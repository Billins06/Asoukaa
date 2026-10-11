import {
  Injectable,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, In } from 'typeorm';

import { VitrineRayon, VitrineRayonType } from './entities/vitrine-rayon.entity';
import { VitrineRayonProduit }            from './entities/vitrine-rayon-produit.entity';
import { VitrineBandeau }                 from './entities/vitrine-bandeau.entity';
import { Product, ProductStatus }         from '../products/entities/product.entity';
import { ProductsService }                from '../products/products.service';

import { CreateRayonDto }      from './dto/create-rayon.dto';
import { UpdateRayonDto }      from './dto/update-rayon.dto';
import { SetRayonProductsDto } from './dto/set-rayon-products.dto';
import { UpsertBandeauDto }    from './dto/upsert-bandeau.dto';

// Ligne produit simplifiée pour le back-office (détail d'un rayon et
// sélecteur de produits) — pas la forme complète de GET /products.
export interface VitrineAdminProduct {
  id:       string;
  name:     string;
  imageUrl: string | null;
  price:    number;
  shopName: string | null;
  isActive: boolean;
  status:   ProductStatus;
}

@Injectable()
export class VitrineService {

  constructor(
    @InjectRepository(VitrineRayon)
    private readonly rayonRepo: Repository<VitrineRayon>,

    @InjectRepository(VitrineRayonProduit)
    private readonly rayonProduitRepo: Repository<VitrineRayonProduit>,

    @InjectRepository(VitrineBandeau)
    private readonly bandeauRepo: Repository<VitrineBandeau>,

    @InjectRepository(Product)
    private readonly productRepo: Repository<Product>,

    // Source unique des règles de visibilité et de la forme JSON des
    // produits publics (voir ProductsService.createPublicListQuery).
    private readonly productsService: ProductsService,
  ) {}

  // ═════════════════════════════════════════════════════
  // PUBLIC
  // ═════════════════════════════════════════════════════

  // ─────────────────────────────────────────────────────
  // GET /vitrine — bandeau actif + rayons visibles maintenant
  // ─────────────────────────────────────────────────────
  async getVitrine() {
    const [bandeau, rayons] = await Promise.all([
      this.findBandeauRow(),
      this.activeRayonsQuery().getMany(),
    ]);

    const counts = await this.countProducts(rayons.map((r) => r.id), true);

    return {
      bandeau: bandeau && bandeau.isActive
        ? {
            titre:     bandeau.titre,
            sousTitre: bandeau.sousTitre,
            imageUrl:  bandeau.imageUrl,
          }
        : null,
      // Un rayon sans aucun produit visible ne s'affiche pas dans l'appli
      // (sa pastille ouvrirait une page vide).
      rayons: rayons
        .filter((r) => (counts.get(r.id) ?? 0) > 0)
        .map((r) => this.toPublicRayon(r, counts.get(r.id) ?? 0)),
    };
  }

  // ─────────────────────────────────────────────────────
  // GET /vitrine/rayons/:id/products — produits d'un rayon, paginés,
  // dans l'ordre choisi par l'admin
  // ─────────────────────────────────────────────────────
  async getRayonProducts(rayonId: string, page: number, limit: number) {
    const rayon = await this.activeRayonsQuery()
      .andWhere('rayon.id = :rayonId', { rayonId })
      .getOne();

    if (!rayon) throw new NotFoundException('Rayon introuvable');

    // Pagination sur les produits VISIBLES uniquement (un produit
    // désactivé entre-temps ne laisse pas de trou dans la page).
    const visibleIds = await this.productsService.filterPublicVisibleIds(
      await this.orderedProductIds(rayonId),
    );
    const total   = visibleIds.length;
    const pageIds = visibleIds.slice((page - 1) * limit, page * limit);

    return {
      data: await this.productsService.findPublicByIds(pageIds),
      meta: {
        total,
        page,
        limit,
        totalPages: Math.ceil(total / limit),
      },
    };
  }

  // ─────────────────────────────────────────────────────
  // GET /vitrine/by-type/:type — premier rayon visible de ce type
  // ─────────────────────────────────────────────────────
  async getByType(type: string, limit: number) {
    if (!Object.values(VitrineRayonType).includes(type as VitrineRayonType)) {
      throw new BadRequestException(
        `Type de rayon invalide. Valeurs acceptées : ${Object.values(VitrineRayonType).join(', ')}`
      );
    }

    const candidats = await this.activeRayonsQuery()
      .andWhere('rayon.type = :type', { type })
      .getMany();

    // Premier rayon de ce type qui a au moins un produit visible : un rayon
    // vide ne doit pas masquer un autre rayon du même type bien rempli.
    for (const rayon of candidats) {
      const visibleIds = await this.productsService.filterPublicVisibleIds(
        await this.orderedProductIds(rayon.id),
      );
      if (!visibleIds.length) continue;
      return {
        rayon:    this.toPublicRayon(rayon, visibleIds.length),
        products: await this.productsService.findPublicByIds(visibleIds.slice(0, limit)),
      };
    }

    return { rayon: null, products: [] };
  }

  // ═════════════════════════════════════════════════════
  // ADMIN — RAYONS
  // ═════════════════════════════════════════════════════

  // Tous les rayons (actifs ou non, en période ou non).
  // productCount = produits placés dans le rayon (tous statuts) ;
  // visibleProductCount = ceux réellement affichés aux acheteurs.
  async listRayonsAdmin() {
    const rayons = await this.rayonRepo.find({
      order: { sortOrder: 'ASC', createdAt: 'ASC' },
    });
    const ids = rayons.map((r) => r.id);
    const [counts, visibleCounts] = await Promise.all([
      this.countProducts(ids, false),
      this.countProducts(ids, true),
    ]);

    return rayons.map((r) =>
      this.toAdminRayon(r, counts.get(r.id) ?? 0, visibleCounts.get(r.id) ?? 0),
    );
  }

  async getRayonAdmin(id: string) {
    const rayon = await this.rayonRepo.findOne({ where: { id } });
    if (!rayon) throw new NotFoundException('Rayon introuvable');

    const rows = await this.rayonProduitRepo
      .createQueryBuilder('rp')
      .innerJoinAndSelect('rp.product', 'product')
      .leftJoinAndSelect('product.vendor', 'vendor')
      .leftJoinAndSelect('product.images', 'image')
      .where('rp.rayonId = :id', { id })
      .orderBy('rp.sortOrder', 'ASC')
      .getMany();

    const products = rows.map((rp) => this.toAdminProduct(rp.product));
    const visibleCount = products.filter((p) => p.isActive).length;

    return {
      ...this.toAdminRayon(rayon, products.length, visibleCount),
      products,
    };
  }

  async createRayon(dto: CreateRayonDto) {
    const startsAt = this.parseDate(dto.startsAt);
    const endsAt   = this.parseDate(dto.endsAt);
    this.assertPeriod(startsAt, endsAt);

    const rayon     = this.rayonRepo.create();
    rayon.nom       = dto.nom;
    rayon.type      = dto.type      ?? VitrineRayonType.LIBRE;
    rayon.imageUrl  = dto.imageUrl  ?? null;
    rayon.sortOrder = dto.sortOrder ?? 0;
    rayon.isActive  = dto.isActive  ?? true;
    rayon.startsAt  = startsAt;
    rayon.endsAt    = endsAt;

    await this.rayonRepo.save(rayon);
    return this.toAdminRayon(rayon, 0, 0);
  }

  async updateRayon(id: string, dto: UpdateRayonDto) {
    const rayon = await this.rayonRepo.findOne({ where: { id } });
    if (!rayon) throw new NotFoundException('Rayon introuvable');

    if (dto.nom       !== undefined) rayon.nom       = dto.nom;
    if (dto.type      !== undefined) rayon.type      = dto.type;
    if (dto.imageUrl  !== undefined) rayon.imageUrl  = dto.imageUrl;   // null = vider
    if (dto.sortOrder !== undefined) rayon.sortOrder = dto.sortOrder;
    if (dto.isActive  !== undefined) rayon.isActive  = dto.isActive;
    if (dto.startsAt  !== undefined) rayon.startsAt  = this.parseDate(dto.startsAt);
    if (dto.endsAt    !== undefined) rayon.endsAt    = this.parseDate(dto.endsAt);

    // Contrôle sur l'état FINAL (valeur modifiée ou valeur déjà en base) :
    // ne changer que endsAt ne doit pas permettre de passer avant startsAt.
    this.assertPeriod(rayon.startsAt, rayon.endsAt);

    await this.rayonRepo.save(rayon);

    const ids = [rayon.id];
    const [counts, visibleCounts] = await Promise.all([
      this.countProducts(ids, false),
      this.countProducts(ids, true),
    ]);
    return this.toAdminRayon(rayon, counts.get(rayon.id) ?? 0, visibleCounts.get(rayon.id) ?? 0);
  }

  async deleteRayon(id: string) {
    // Les lignes vitrine_rayon_produits partent avec (ON DELETE CASCADE).
    const result = await this.rayonRepo.delete({ id });
    if (!result.affected) throw new NotFoundException('Rayon introuvable');
    return { success: true };
  }

  // Remplace TOUTE la liste des produits du rayon ; l'ordre du tableau
  // devient sortOrder (0, 1, 2…).
  async setRayonProducts(id: string, dto: SetRayonProductsDto) {
    const rayon = await this.rayonRepo.findOne({ where: { id } });
    if (!rayon) throw new NotFoundException('Rayon introuvable');

    // Postgres renvoie les uuid en minuscules : on normalise pour que la
    // comparaison (ids inconnus) et l'unicité tiennent même si le client
    // envoie des majuscules (que @ArrayUnique ne voit pas comme doublons).
    const productIds = dto.productIds.map((pid) => pid.toLowerCase());
    if (new Set(productIds).size !== productIds.length) {
      throw new BadRequestException('La liste contient des produits en double');
    }

    if (productIds.length) {
      const found = await this.productRepo.find({
        where:  { id: In(productIds) },
        select: { id: true },
      });
      const foundIds = new Set(found.map((p) => p.id));
      const unknownIds = productIds.filter((pid) => !foundIds.has(pid));
      if (unknownIds.length) {
        // ⚠️ Le filtre global d'exceptions ne renvoie que "message" : la
        // liste des ids inconnus est donc incluse dans le message.
        throw new BadRequestException(
          `Produits introuvables : ${unknownIds.join(', ')}`
        );
      }
    }

    // Suppression + réinsertion dans une transaction : jamais de rayon à
    // moitié rempli si l'insertion échoue.
    await this.rayonProduitRepo.manager.transaction(async (manager) => {
      await manager.delete(VitrineRayonProduit, { rayonId: id });
      if (productIds.length) {
        await manager.insert(
          VitrineRayonProduit,
          productIds.map((productId, index) => ({
            rayonId:   id,
            productId,
            sortOrder: index,
          })),
        );
      }
    });

    return this.getRayonAdmin(id);
  }

  // ─────────────────────────────────────────────────────
  // Sélecteur de produits du back-office : TOUS les produits (quel que
  // soit leur statut), recherche ILIKE sur le nom.
  // ─────────────────────────────────────────────────────
  async searchProductsAdmin(search: string | undefined, limit: number) {
    const qb = this.productRepo
      .createQueryBuilder('product')
      .leftJoinAndSelect('product.vendor', 'vendor')
      .leftJoinAndSelect('product.images', 'image')
      .orderBy('product.createdAt', 'DESC')
      .take(limit);

    const term = search?.trim();
    if (term) {
      // Échappe les jokers LIKE (% et _) saisis par l'admin.
      const escaped = term.replace(/[\\%_]/g, '\\$&');
      qb.where('product.prod_name ILIKE :search', { search: `%${escaped}%` });
    }

    const products = await qb.getMany();
    return products.map((p) => this.toAdminProduct(p));
  }

  // ═════════════════════════════════════════════════════
  // ADMIN — BANDEAU
  // ═════════════════════════════════════════════════════

  async getBandeauAdmin() {
    const row = await this.findBandeauRow();
    return row ? this.toAdminBandeau(row) : null;
  }

  async upsertBandeau(dto: UpsertBandeauDto) {
    const row = (await this.findBandeauRow()) ?? this.bandeauRepo.create({
      sousTitre: null,
      imageUrl:  null,
      isActive:  true,
    });

    row.titre = dto.titre;
    if (dto.sousTitre !== undefined) row.sousTitre = dto.sousTitre || null;
    if (dto.imageUrl  !== undefined) row.imageUrl  = dto.imageUrl;
    if (dto.isActive  !== undefined) row.isActive  = dto.isActive;

    await this.bandeauRepo.save(row);
    return this.toAdminBandeau(row);
  }

  // ═════════════════════════════════════════════════════
  // OUTILS
  // ═════════════════════════════════════════════════════

  // Rayons visibles publiquement maintenant : actifs ET dans leur période
  // (startsAt/endsAt null = pas de borne). Triés sortOrder puis createdAt.
  private activeRayonsQuery() {
    const now = new Date();
    return this.rayonRepo
      .createQueryBuilder('rayon')
      .where('rayon.isActive = true')
      .andWhere('(rayon.startsAt IS NULL OR rayon.startsAt <= :now)', { now })
      .andWhere('(rayon.endsAt IS NULL OR rayon.endsAt > :now)', { now })
      .orderBy('rayon.sortOrder', 'ASC')
      .addOrderBy('rayon.createdAt', 'ASC');
  }

  // Ids produits d'un rayon dans l'ordre choisi par l'admin.
  private async orderedProductIds(rayonId: string): Promise<string[]> {
    const rows = await this.rayonProduitRepo.find({
      where:  { rayonId },
      select: { id: true, productId: true },
      order:  { sortOrder: 'ASC' },
    });
    return rows.map((r) => r.productId);
  }

  // Nombre de produits par rayon, en une seule requête GROUP BY.
  // onlyVisible = true : uniquement les produits visibles publiquement
  // (même règle que GET /products, via ProductsService).
  private async countProducts(
    rayonIds:    string[],
    onlyVisible: boolean,
  ): Promise<Map<string, number>> {
    const counts = new Map<string, number>();
    if (!rayonIds.length) return counts;

    const qb = this.rayonProduitRepo
      .createQueryBuilder('rp')
      .innerJoin('rp.product', 'product')
      .select('rp.rayonId', 'rayonId')
      .addSelect('COUNT(rp.id)', 'count')
      .where('rp.rayonId IN (:...rayonIds)', { rayonIds });

    if (onlyVisible) this.productsService.applyPublicVisibility(qb, 'product');

    const rows: { rayonId: string; count: string }[] = await qb
      .groupBy('rp.rayonId')
      .getRawMany();

    for (const row of rows) counts.set(row.rayonId, Number(row.count) || 0);
    return counts;
  }

  private async findBandeauRow(): Promise<VitrineBandeau | null> {
    const rows = await this.bandeauRepo.find({
      order: { updatedAt: 'DESC' },
      take:  1,
    });
    return rows[0] ?? null;
  }

  private parseDate(value: string | null | undefined): Date | null {
    if (value === undefined || value === null) return null;
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) {
      throw new BadRequestException('Date invalide');
    }
    return date;
  }

  private assertPeriod(startsAt: Date | null, endsAt: Date | null) {
    if (startsAt && endsAt && endsAt.getTime() <= startsAt.getTime()) {
      throw new BadRequestException(
        'La date de fin doit être postérieure à la date de début'
      );
    }
  }

  // Image principale : isPrimary d'abord, sinon la première image (hors
  // vidéo) de la galerie.
  private primaryImageUrl(product: Product): string | null {
    const images = (product.images ?? []).filter((i) => !i.isVideo);
    const primary = images.find((i) => i.isPrimary)
      ?? [...images].sort((a, b) => a.sortOrder - b.sortOrder)[0];
    return primary?.url ?? null;
  }

  private toAdminProduct(product: Product): VitrineAdminProduct {
    return {
      id:       product.id,
      name:     product.prod_name,
      imageUrl: this.primaryImageUrl(product),
      price:    Number(product.basePrice),
      shopName: product.vendor?.shopName ?? null,
      // true = visible par les acheteurs (même règle que GET /products)
      isActive: product.status === ProductStatus.ACTIVE,
      status:   product.status,
    };
  }

  private toPublicRayon(rayon: VitrineRayon, productCount: number) {
    return {
      id:        rayon.id,
      nom:       rayon.nom,
      type:      rayon.type,
      imageUrl:  rayon.imageUrl,
      sortOrder: rayon.sortOrder,
      startsAt:  rayon.startsAt,
      endsAt:    rayon.endsAt,
      productCount,
    };
  }

  private toAdminRayon(
    rayon:               VitrineRayon,
    productCount:        number,
    visibleProductCount: number,
  ) {
    return {
      id:        rayon.id,
      nom:       rayon.nom,
      type:      rayon.type,
      imageUrl:  rayon.imageUrl,
      sortOrder: rayon.sortOrder,
      isActive:  rayon.isActive,
      startsAt:  rayon.startsAt,
      endsAt:    rayon.endsAt,
      createdAt: rayon.createdAt,
      updatedAt: rayon.updatedAt,
      productCount,
      visibleProductCount,
    };
  }

  private toAdminBandeau(row: VitrineBandeau) {
    return {
      id:        row.id,
      titre:     row.titre,
      sousTitre: row.sousTitre,
      imageUrl:  row.imageUrl,
      isActive:  row.isActive,
      updatedAt: row.updatedAt,
    };
  }
}
