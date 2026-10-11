import {
  Injectable,
  NotFoundException,
  BadRequestException,
  ConflictException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';

import { FeaturedShop }          from './entities/featured-shop.entity';
import { Product }               from '../products/entities/product.entity';
import { ProductsService }       from '../products/products.service';
import { toPublicVendor }        from '../products/public-vendor.util';
import { VendorStatus }          from '../users/entities/vendor-profile.entity';
import {
  AddFeaturedShopDto,
  UpdateFeaturedShopDto,
  ReorderFeaturedShopsDto,
} from './dto/featured-shop.dto';

// Nombre maximal de boutiques dans « Meilleures boutiques ».
export const MAX_FEATURED_SHOPS = 20;
// Nombre de produits montrés par boutique sur l'accueil.
export const FEATURED_PRODUCTS_PER_SHOP = 6;

// Verrou applicatif (pg_advisory_xact_lock) qui sérialise les écritures sur
// la liste (ajout / réordonnancement / suppression) : deux admins
// simultanés ne peuvent ni dépasser le maximum ni désordonner les positions.
const LOCK_SQL = `SELECT pg_advisory_xact_lock(hashtext('featured_shops'))`;

@Injectable()
export class FeaturedShopsService {

  constructor(
    @InjectRepository(FeaturedShop)
    private readonly featuredRepo: Repository<FeaturedShop>,

    @InjectRepository(Product)
    private readonly productRepo: Repository<Product>,

    // Source unique des règles de visibilité et de la forme des cartes
    // produit publiques.
    private readonly productsService: ProductsService,
  ) {}

  // ═════════════════════════════════════════════════════
  // PUBLIC — GET /vitrine/best-shops
  // ═════════════════════════════════════════════════════
  // Boutiques actives dans la liste, vendeur approuvé, compte actif,
  // boutique visible (vendor_profiles."shopVisible") ET au moins un produit
  // visible. Aucun repli : une boutique sans produit visible disparaît.
  async getBestShops() {
    const shops = await this.featuredRepo
      .createQueryBuilder('fs')
      .innerJoin('fs.vendor', 'vendor')
      .innerJoin('vendor.user', 'vuser')
      .select([
        'fs.id',
        'fs.position',
        'fs.vendorId',
        'vendor.id',
        'vendor.userId',
        'vendor.shopName',
        'vendor.logoUrl',
        'vendor.bannerUrl',
      ])
      .where('fs.isActive = true')
      .andWhere('vendor.status = :approved', { approved: VendorStatus.APPROVED })
      .andWhere('vuser.isActive = true')
      .andWhere('vendor."shopVisible" = true')
      .orderBy('fs.position', 'ASC')
      .addOrderBy('fs.createdAt', 'ASC')
      .addOrderBy('fs.id', 'ASC')
      .getMany();

    if (!shops.length) return [];

    const vendorIds = shops.map((s) => s.vendorId);
    const [counts, idsByVendor] = await Promise.all([
      this.countVisibleProducts(vendorIds),
      this.topProductIdsByVendor(vendorIds, FEATURED_PRODUCTS_PER_SHOP),
    ]);

    // Une seule requête pour charger toutes les cartes produit (même forme
    // que GET /products), puis répartition par boutique.
    const allIds = [...new Set([...idsByVendor.values()].flat())];
    const cards  = await this.productsService.findPublicByIds(allIds);
    const byId   = new Map(cards.map((p) => [p.id, p]));

    const result: any[] = [];
    for (const shop of shops) {
      const products = (idsByVendor.get(shop.vendorId) ?? [])
        .map((id) => byId.get(id))
        .filter((p): p is Product => !!p);
      const productCount = counts.get(shop.vendorId) ?? 0;

      if (!products.length || productCount === 0) continue;

      // Liste blanche existante, réduite aux 4 champs de l'accueil.
      const pub = toPublicVendor(shop.vendor);
      result.push({
        id:       shop.id,
        position: shop.position,
        vendor: {
          id:        pub.id,
          shopName:  pub.shopName,
          logoUrl:   pub.logoUrl,
          bannerUrl: pub.bannerUrl,
        },
        products,
        productCount,
      });
    }
    return result;
  }

  // ═════════════════════════════════════════════════════
  // ADMIN
  // ═════════════════════════════════════════════════════

  // Liste complète (actives ou non, affichables ou non).
  async listAdmin() {
    const rows: any[] = await this.featuredRepo.query(
      `SELECT fs.id, fs."vendorId", fs."position", fs."isActive",
              fs."createdAt", fs."updatedAt",
              vp."shopName", vp."logoUrl", vp.status AS "vendorStatus",
              vp."shopVisible", u."isActive" AS "accountActive"
         FROM featured_shops fs
         INNER JOIN vendor_profiles vp ON vp.id = fs."vendorId"
         LEFT JOIN users u ON u.id = vp."userId"
        ORDER BY fs."position" ASC, fs."createdAt" ASC, fs.id ASC`,
    );

    const counts = await this.countVisibleProducts(rows.map((r) => r.vendorId));

    return rows.map((r) => {
      const visibleProductCount = counts.get(r.vendorId) ?? 0;
      const approved = r.vendorStatus === VendorStatus.APPROVED;
      return {
        id:        r.id,
        vendorId:  r.vendorId,
        position:  Number(r.position),
        isActive:  r.isActive,
        createdAt: r.createdAt,
        updatedAt: r.updatedAt,
        vendor: {
          id:            r.vendorId,
          shopName:      r.shopName,
          logoUrl:       r.logoUrl ?? null,
          status:        r.vendorStatus,
          shopVisible:   r.shopVisible,
          accountActive: r.accountActive !== false,
        },
        visibleProductCount,
        // true = la boutique apparaît réellement sur l'accueil
        isDisplayed:
          r.isActive && approved && r.accountActive !== false
          && r.shopVisible === true && visibleProductCount > 0,
      };
    });
  }

  // Vendeurs approuvés (compte actif) pas encore dans la liste, recherche
  // ILIKE sur le nom de la boutique, paginés.
  async listCandidates(search: string | undefined, page: number, limit: number) {
    const params: any[] = [VendorStatus.APPROVED];
    let searchSql = '';
    const term = search?.trim();
    if (term) {
      // Échappe les jokers LIKE (% et _) saisis par l'admin.
      params.push(`%${term.replace(/[\\%_]/g, '\\$&')}%`);
      searchSql = `AND vp."shopName" ILIKE $${params.length}`;
    }

    const base = `FROM vendor_profiles vp
         INNER JOIN users u ON u.id = vp."userId"
        WHERE vp.status = $1
          AND u."isActive" = true
          AND NOT EXISTS (SELECT 1 FROM featured_shops fs WHERE fs."vendorId" = vp.id)
          ${searchSql}`;

    const [{ total }] = await this.featuredRepo.query(
      `SELECT COUNT(*)::int AS total ${base}`,
      params,
    );

    const rows: any[] = await this.featuredRepo.query(
      `SELECT vp.id, vp."shopName", vp."logoUrl", vp."shopVisible"
         ${base}
        ORDER BY vp."shopName" ASC, vp.id ASC
        LIMIT ${Number(limit)} OFFSET ${Number((page - 1) * limit)}`,
      params,
    );

    const counts = await this.countVisibleProducts(rows.map((r) => r.id));

    return {
      data: rows.map((r) => ({
        id:                  r.id,
        shopName:            r.shopName,
        logoUrl:             r.logoUrl ?? null,
        shopVisible:         r.shopVisible,
        visibleProductCount: counts.get(r.id) ?? 0,
      })),
      meta: {
        total,
        page,
        limit,
        totalPages: Math.ceil(total / limit),
      },
    };
  }

  // Ajoute une boutique EN FIN de liste.
  async add(dto: AddFeaturedShopDto) {
    const vendorId = dto.vendorId.toLowerCase();

    let createdId: string;
    try {
      createdId = await this.featuredRepo.manager.transaction(async (manager) => {
        await manager.query(LOCK_SQL);

        const [vendor] = await manager.query(
          `SELECT vp.id, vp.status, u."isActive" AS "accountActive"
             FROM vendor_profiles vp
             LEFT JOIN users u ON u.id = vp."userId"
            WHERE vp.id = $1`,
          [vendorId],
        );
        if (!vendor) throw new NotFoundException('Vendeur introuvable');
        if (vendor.status !== VendorStatus.APPROVED) {
          throw new BadRequestException(
            'Seul un vendeur approuvé peut être ajouté aux meilleures boutiques',
          );
        }
        if (vendor.accountActive === false) {
          throw new BadRequestException('Le compte de ce vendeur est désactivé');
        }

        const [{ count, maxPos }] = await manager.query(
          `SELECT COUNT(*)::int AS count, COALESCE(MAX("position"), -1)::int AS "maxPos"
             FROM featured_shops`,
        );
        const [{ exists }] = await manager.query(
          `SELECT EXISTS (SELECT 1 FROM featured_shops WHERE "vendorId" = $1) AS exists`,
          [vendorId],
        );
        if (exists) {
          throw new ConflictException('Cette boutique est déjà dans la liste');
        }
        if (count >= MAX_FEATURED_SHOPS) {
          throw new BadRequestException(
            `La liste est limitée à ${MAX_FEATURED_SHOPS} boutiques`,
          );
        }

        const row = manager.create(FeaturedShop, {
          vendorId,
          position: maxPos + 1,
          isActive: true,
        });
        await manager.save(row);
        return row.id;
      });
    } catch (err: any) {
      // Filet de sécurité : violation de l'unicité vendorId (23505).
      if (err?.code === '23505') {
        throw new ConflictException('Cette boutique est déjà dans la liste');
      }
      throw err;
    }

    return this.getAdminRow(createdId);
  }

  async update(id: string, dto: UpdateFeaturedShopDto) {
    const row = await this.featuredRepo.findOne({ where: { id } });
    if (!row) throw new NotFoundException('Boutique introuvable dans la liste');

    row.isActive = dto.isActive;
    await this.featuredRepo.save(row);
    return this.getAdminRow(id);
  }

  // Réordonne : `ids` doit contenir EXACTEMENT les ids actuellement dans la
  // liste (ni plus, ni moins), dans le nouvel ordre.
  async reorder(dto: ReorderFeaturedShopsDto) {
    const ids = dto.ids.map((i) => i.toLowerCase());
    if (new Set(ids).size !== ids.length) {
      throw new BadRequestException('La liste contient des identifiants en double');
    }

    await this.featuredRepo.manager.transaction(async (manager) => {
      await manager.query(LOCK_SQL);

      const existing: { id: string }[] = await manager.query(
        `SELECT id FROM featured_shops`,
      );
      const existingIds = new Set(existing.map((r) => r.id));

      const unknown = ids.filter((i) => !existingIds.has(i));
      if (unknown.length) {
        // Le filtre global d'exceptions ne renvoie que « message ».
        throw new BadRequestException(
          `Boutiques introuvables dans la liste : ${unknown.join(', ')}`,
        );
      }
      if (ids.length !== existingIds.size) {
        throw new BadRequestException(
          'La liste doit contenir toutes les boutiques actuellement enregistrées',
        );
      }
      if (!ids.length) return;

      await manager.query(
        `UPDATE featured_shops f
            SET "position" = t.ord - 1, "updatedAt" = now()
           FROM unnest($1::uuid[]) WITH ORDINALITY AS t(id, ord)
          WHERE f.id = t.id`,
        [ids],
      );
    });

    return this.listAdmin();
  }

  async remove(id: string) {
    await this.featuredRepo.manager.transaction(async (manager) => {
      await manager.query(LOCK_SQL);

      const result = await manager.delete(FeaturedShop, { id });
      if (!result.affected) {
        throw new NotFoundException('Boutique introuvable dans la liste');
      }

      // Recompacte les positions (0, 1, 2…) sans changer l'ordre.
      await manager.query(
        `UPDATE featured_shops f
            SET "position" = r.rn - 1
           FROM (SELECT id, ROW_NUMBER() OVER (ORDER BY "position", "createdAt", id) AS rn
                   FROM featured_shops) r
          WHERE f.id = r.id AND f."position" <> r.rn - 1`,
      );
    });
    return { success: true };
  }

  // ═════════════════════════════════════════════════════
  // OUTILS
  // ═════════════════════════════════════════════════════

  private async getAdminRow(id: string) {
    const rows = await this.listAdmin();
    const row = rows.find((r) => r.id === id);
    if (!row) throw new NotFoundException('Boutique introuvable dans la liste');
    return row;
  }

  // Nombre de produits VISIBLES publiquement par vendeur (même règle que
  // GET /products, via ProductsService), en une seule requête GROUP BY.
  private async countVisibleProducts(vendorIds: string[]): Promise<Map<string, number>> {
    const counts = new Map<string, number>();
    if (!vendorIds.length) return counts;

    const qb = this.productRepo
      .createQueryBuilder('product')
      .select('product.vendorId', 'vendorId')
      .addSelect('COUNT(product.id)', 'count')
      .where('product.vendorId IN (:...vendorIds)', { vendorIds });
    this.productsService.applyPublicVisibility(qb, 'product');

    const rows: { vendorId: string; count: string }[] = await qb
      .groupBy('product.vendorId')
      .getRawMany();

    for (const row of rows) counts.set(row.vendorId, Number(row.count) || 0);
    return counts;
  }

  // Les `perShop` produits visibles les plus vus (nombreVues) puis les plus
  // récents de chaque vendeur, en UNE requête (fonction de fenêtre).
  // Départage final par id pour un ordre déterministe.
  private async topProductIdsByVendor(
    vendorIds: string[],
    perShop:   number,
  ): Promise<Map<string, string[]>> {
    const result = new Map<string, string[]>();
    if (!vendorIds.length) return result;

    const inner = this.productRepo
      .createQueryBuilder('product')
      .select('product.id', 'id')
      .addSelect('product."vendorId"', 'vendorId')
      .addSelect(
        'ROW_NUMBER() OVER (PARTITION BY product."vendorId" '
        + 'ORDER BY product."nombreVues" DESC, product."createdAt" DESC, product.id DESC)',
        'rn',
      )
      .where('product.vendorId IN (:...vendorIds)', { vendorIds });
    this.productsService.applyPublicVisibility(inner, 'product');

    const rows: { id: string; vendorId: string; rn: string }[] = await this.productRepo.manager
      .createQueryBuilder()
      .select('ranked.id', 'id')
      .addSelect('ranked."vendorId"', 'vendorId')
      .from(`(${inner.getQuery()})`, 'ranked')
      .where('ranked.rn <= :perShop', { perShop })
      .orderBy('ranked.rn', 'ASC')
      .setParameters(inner.getParameters())
      .getRawMany();

    for (const row of rows) {
      const list = result.get(row.vendorId) ?? [];
      list.push(row.id);
      result.set(row.vendorId, list);
    }
    return result;
  }
}
