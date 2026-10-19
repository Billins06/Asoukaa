import {
  Injectable,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { In, Repository } from 'typeorm';

import { HomeBanner, BannerTargetType } from './entities/home-banner.entity';
import { Category }        from '../categories/entities/category.entity';
import { Product } from '../products/entities/product.entity';
import { VendorStatus }    from '../users/entities/vendor-profile.entity';
import { ProductsService } from '../products/products.service';
import { CreateBannerDto } from './dto/create-banner.dto';
import { UpdateBannerDto, ReorderBannersDto } from './dto/update-banner.dto';

export const BANNER_DEFAULT_DURATION = 4;
// Garde-fou : l'appli ne reçoit jamais plus que ce nombre de bannières.
const PUBLIC_MAX_BANNERS = 50;

// Résultat de la vérification d'une cible (existe-t-elle et est-elle
// visible publiquement ?).
interface ResolvedTarget {
  valid: boolean;
  label: string | null;
  logoUrl?: string | null;
}

@Injectable()
export class BannersService {
  constructor(
    @InjectRepository(HomeBanner)
    private readonly bannerRepo: Repository<HomeBanner>,
    @InjectRepository(Category)
    private readonly categoryRepo: Repository<Category>,
    @InjectRepository(Product)
    private readonly productRepo: Repository<Product>,
    private readonly productsService: ProductsService,
  ) {}

  // ═════════════════════════════════════════════════════
  // PUBLIC — GET /banners
  // ═════════════════════════════════════════════════════
  // Bannières actives, dans leur période, dont la cible est encore valide,
  // dans l'ordre de l'admin. Une bannière dont la cible a disparu (produit
  // supprimé, boutique bloquée…) est simplement omise.
  async getPublic() {
    const now = new Date();
    const rows = await this.bannerRepo
      .createQueryBuilder('b')
      .where('b.isActive = true')
      .andWhere('(b.startsAt IS NULL OR b.startsAt <= :now)', { now })
      .andWhere('(b.endsAt IS NULL OR b.endsAt > :now)', { now })
      .orderBy('b.sortOrder', 'ASC')
      .addOrderBy('b.createdAt', 'ASC')
      .addOrderBy('b.id', 'ASC')
      .limit(PUBLIC_MAX_BANNERS * 4)
      .getMany();

    const resolved = await this.resolveTargets(rows);
    return rows
      .filter((b) => resolved.get(b.id)?.valid)
      .slice(0, PUBLIC_MAX_BANNERS)
      .map((b) => {
        const r = resolved.get(b.id)!;
        return {
          id:              b.id,
          imageUrl:        b.imageUrl,
          titre:           b.titre,
          sousTitre:       b.sousTitre,
          durationSeconds: b.durationSeconds,
          target: {
            type:    b.targetType,
            id:      b.targetId,
            url:     b.targetUrl,
            label:   r.label,
            logoUrl: r.logoUrl ?? null,
          },
        };
      });
  }

  // ═════════════════════════════════════════════════════
  // ADMIN
  // ═════════════════════════════════════════════════════

  async listAdmin() {
    const rows = await this.bannerRepo.find({
      order: { sortOrder: 'ASC', createdAt: 'ASC', id: 'ASC' },
    });
    const resolved = await this.resolveTargets(rows);
    return rows.map((b) => this.toAdmin(b, resolved.get(b.id)));
  }

  async create(dto: CreateBannerDto) {
    const startsAt = this.parseDate(dto.startsAt);
    const endsAt   = this.parseDate(dto.endsAt);
    this.assertPeriod(startsAt, endsAt);

    const banner = this.bannerRepo.create({
      imageUrl:        dto.imageUrl,
      titre:           dto.titre ?? null,
      sousTitre:       dto.sousTitre ?? null,
      targetType:      dto.targetType,
      targetId:        dto.targetId ?? null,
      targetUrl:       dto.targetUrl ?? null,
      durationSeconds: dto.durationSeconds ?? BANNER_DEFAULT_DURATION,
      isActive:        dto.isActive ?? true,
      startsAt,
      endsAt,
    });
    this.normalizeTarget(banner);
    await this.assertTargetExists(banner);

    // Sans ordre explicite : la nouvelle bannière passe en dernier.
    if (dto.sortOrder !== undefined) {
      banner.sortOrder = dto.sortOrder;
    } else {
      const raw = await this.bannerRepo
        .createQueryBuilder('b')
        .select('COALESCE(MAX(b.sortOrder), -1)', 'max')
        .getRawOne();
      banner.sortOrder = Number(raw?.max ?? -1) + 1;
    }

    await this.bannerRepo.save(banner);
    return this.toAdminOne(banner);
  }

  async update(id: string, dto: UpdateBannerDto) {
    const banner = await this.bannerRepo.findOne({ where: { id } });
    if (!banner) throw new NotFoundException('Bannière introuvable');

    const targetTouched =
      dto.targetType !== undefined ||
      dto.targetId   !== undefined ||
      dto.targetUrl  !== undefined;
    const before = {
      type: banner.targetType,
      id:   banner.targetId,
      url:  banner.targetUrl,
    };

    if (dto.imageUrl        !== undefined) banner.imageUrl        = dto.imageUrl;
    if (dto.titre           !== undefined) banner.titre           = dto.titre;
    if (dto.sousTitre       !== undefined) banner.sousTitre       = dto.sousTitre;
    if (dto.durationSeconds !== undefined) banner.durationSeconds = dto.durationSeconds;
    if (dto.sortOrder       !== undefined) banner.sortOrder       = dto.sortOrder;
    if (dto.isActive        !== undefined) banner.isActive        = dto.isActive;
    if (dto.startsAt        !== undefined) banner.startsAt        = this.parseDate(dto.startsAt);
    if (dto.endsAt          !== undefined) banner.endsAt          = this.parseDate(dto.endsAt);

    // Changement de TYPE de cible : l'ancien id / lien n'a plus de sens.
    if (dto.targetType !== undefined && dto.targetType !== banner.targetType) {
      banner.targetType = dto.targetType;
      banner.targetId   = null;
      banner.targetUrl  = null;
    }
    if (dto.targetId  !== undefined) banner.targetId  = dto.targetId;
    if (dto.targetUrl !== undefined) banner.targetUrl = dto.targetUrl;

    // Période : l'ancienne borne est relue, donc modifier seulement endsAt
    // ne doit pas permettre de passer avant startsAt.
    this.assertPeriod(banner.startsAt, banner.endsAt);

    if (targetTouched) {
      // Cohérence type / id / lien : toujours vérifiée.
      this.normalizeTarget(banner);
      // Existence de la cible : seulement si elle a CHANGÉ. Le formulaire
      // renvoie toujours la cible, même inchangée ; sans cette précaution,
      // on ne pourrait plus modifier le titre ou la date d'une bannière
      // dont la boutique/le produit est momentanément indisponible.
      const targetChanged =
        banner.targetType !== before.type ||
        banner.targetId   !== before.id   ||
        banner.targetUrl  !== before.url;
      if (targetChanged) await this.assertTargetExists(banner);
    }

    await this.bannerRepo.save(banner);
    return this.toAdminOne(banner);
  }

  async remove(id: string) {
    const res = await this.bannerRepo.delete({ id });
    if (!res.affected) throw new NotFoundException('Bannière introuvable');
    return { message: 'Bannière supprimée' };
  }

  // Nouvel ordre : sortOrder = position dans la liste reçue (0, 1, 2…).
  async reorder(dto: ReorderBannersDto) {
    const [found, total] = await Promise.all([
      this.bannerRepo.count({ where: { id: In(dto.ids) } }),
      this.bannerRepo.count(),
    ]);
    if (found !== dto.ids.length || total !== dto.ids.length) {
      throw new BadRequestException(
        'La liste des bannières a changé (ajout, suppression ou autre administrateur). Rechargez la page.',
      );
    }
    await this.bannerRepo.manager.transaction(async (manager) => {
      for (let i = 0; i < dto.ids.length; i++) {
        await manager.update(HomeBanner, { id: dto.ids[i] }, { sortOrder: i });
      }
    });
    return this.listAdmin();
  }

  // Sélecteur de cible du formulaire admin (catégories, produits, boutiques).
  async lookup(type: string, search: string | undefined, limit: number) {
    const term = search?.trim();
    // Échappe les jokers LIKE (% et _) saisis par l'admin.
    const like = term ? `%${term.replace(/[\\%_]/g, '\\$&')}%` : null;

    if (type === BannerTargetType.CATEGORY) {
      const qb = this.categoryRepo
        .createQueryBuilder('c')
        .leftJoinAndSelect('c.parent', 'p')
        .where('c.isActive = true')
        .orderBy('c.level', 'ASC')
        .addOrderBy('c.sortOrder', 'ASC')
        .addOrderBy('c.name', 'ASC')
        .take(limit);
      if (like) qb.andWhere('c.name ILIKE :like', { like });
      const cats = await qb.getMany();
      return cats.map((c) => ({
        id:       c.id,
        label:    c.name,
        sublabel: c.parent?.name ?? (c.isDigital ? 'Livres numériques' : 'Catégorie principale'),
        imageUrl: c.imageUrl ?? null,
      }));
    }

    if (type === BannerTargetType.PRODUCT) {
      const qb = this.productRepo
        .createQueryBuilder('product')
        .leftJoinAndSelect('product.vendor', 'vendor')
        .orderBy('product.createdAt', 'DESC')
        .take(limit);
      // Seuls les produits réellement visibles par les acheteurs, filtrés
      // AVANT la limite (sinon des résultats valides seraient écartés).
      this.productsService.applyPublicVisibility(qb, 'product');
      if (like) qb.andWhere('product.prod_name ILIKE :like', { like });
      const products = await qb.getMany();
      return products.map((p) => ({
        id:       p.id,
        label:    p.prod_name,
        sublabel: p.vendor?.shopName ?? null,
        imageUrl: null,
      }));
    }

    if (type === BannerTargetType.SHOP) {
      const params: unknown[] = [VendorStatus.APPROVED];
      let searchSql = '';
      if (like) {
        params.push(like);
        searchSql = `AND vp."shopName" ILIKE $${params.length}`;
      }
      const rows: { id: string; shopName: string; logoUrl: string | null }[] =
        await this.bannerRepo.query(
          `SELECT vp.id, vp."shopName", vp."logoUrl"
             FROM vendor_profiles vp
            INNER JOIN users u ON u.id = vp."userId"
            WHERE vp.status = $1
              AND u."isActive" = true
              AND vp."shopVisible" = true
              ${searchSql}
            ORDER BY vp."shopName" ASC, vp.id ASC
            LIMIT ${Number(limit)}`,
          params,
        );
      return rows.map((r) => ({
        id:       r.id,
        label:    r.shopName,
        sublabel: null,
        imageUrl: r.logoUrl ?? null,
      }));
    }

    throw new BadRequestException('Type invalide (category, product, shop)');
  }

  // ═════════════════════════════════════════════════════
  // OUTILS
  // ═════════════════════════════════════════════════════

  private parseDate(value: string | null | undefined): Date | null {
    if (value === null || value === undefined) return null;
    const d = new Date(value);
    if (Number.isNaN(d.getTime())) {
      throw new BadRequestException('Date invalide');
    }
    return d;
  }

  private assertPeriod(startsAt: Date | null, endsAt: Date | null) {
    if (startsAt && endsAt && endsAt.getTime() <= startsAt.getTime()) {
      throw new BadRequestException('La date de fin doit être après la date de début');
    }
  }

  // Règle : type 'link' => lien https obligatoire et pas d'id ; autres
  // types => id obligatoire et pas de lien.
  private normalizeTarget(banner: HomeBanner) {
    if (banner.targetType === BannerTargetType.LINK) {
      const url = (banner.targetUrl ?? '').trim();
      if (!url) throw new BadRequestException('Indiquez le lien externe');
      let parsed: URL;
      try {
        parsed = new URL(url);
      } catch {
        throw new BadRequestException('Lien externe invalide');
      }
      const host = parsed.hostname.toLowerCase();
      if (parsed.protocol !== 'https:' || !host.includes('.')) {
        throw new BadRequestException('Le lien externe doit commencer par https:// et avoir un nom de domaine');
      }
      if (parsed.username || parsed.password) {
        throw new BadRequestException('Le lien externe ne doit pas contenir d\'identifiant ni de mot de passe');
      }
      if (/^\d{1,3}(\.\d{1,3}){3}$/.test(host) || host.startsWith('[') ||
          host.endsWith('.local') || host.endsWith('.internal') || host.endsWith('.localhost')) {
        throw new BadRequestException('Le lien externe doit pointer vers un vrai site web (pas une adresse interne)');
      }
      // Forme normalisée par URL (espaces et caractères parasites retirés).
      banner.targetUrl = parsed.href.slice(0, 500);
      banner.targetId  = null;
      return;
    }
    if (!banner.targetId) {
      throw new BadRequestException('Choisissez la catégorie, le produit ou la boutique visé');
    }
    banner.targetUrl = null;
  }

  private async assertTargetExists(banner: HomeBanner) {
    if (banner.targetType === BannerTargetType.LINK) return;
    // À la création la bannière n'a pas encore d'id : on résout via une copie.
    const probe = Object.assign(new HomeBanner(), banner, { id: '__probe__' });
    const resolved = await this.resolveTargets([probe]);
    if (!resolved.get('__probe__')?.valid) {
      const what =
        banner.targetType === BannerTargetType.CATEGORY ? 'Catégorie' :
        banner.targetType === BannerTargetType.PRODUCT  ? 'Produit' : 'Boutique';
      throw new BadRequestException(`${what} introuvable ou non visible par les acheteurs`);
    }
  }

  // Résout en lot les cibles de plusieurs bannières : existe-t-elle, est-elle
  // visible par le public, quel nom afficher. 3 requêtes au maximum.
  private async resolveTargets(rows: HomeBanner[]): Promise<Map<string, ResolvedTarget>> {
    const out = new Map<string, ResolvedTarget>();
    const idsOf = (t: BannerTargetType) => [
      ...new Set(rows.filter((r) => r.targetType === t && r.targetId).map((r) => r.targetId as string)),
    ];

    const catIds  = idsOf(BannerTargetType.CATEGORY);
    const prodIds = idsOf(BannerTargetType.PRODUCT);
    const shopIds = idsOf(BannerTargetType.SHOP);

    const cats = catIds.length
      ? new Map((await this.categoryRepo.find({ where: { id: In(catIds) } })).map((c) => [c.id, c]))
      : new Map<string, Category>();

    let prodNames = new Map<string, string>();
    let prodVisible = new Set<string>();
    if (prodIds.length) {
      const prods = await this.productRepo.find({
        select: { id: true, prod_name: true },
        where: { id: In(prodIds) },
      });
      prodNames   = new Map(prods.map((p) => [p.id, p.prod_name]));
      prodVisible = new Set(await this.productsService.filterPublicVisibleIds(prods.map((p) => p.id)));
    }

    const shops = new Map<string, { shopName: string; logoUrl: string | null; valid: boolean }>();
    if (shopIds.length) {
      const shopRows: { id: string; shopName: string; logoUrl: string | null; valid: boolean }[] =
        await this.bannerRepo.query(
          `SELECT vp.id, vp."shopName", vp."logoUrl",
                  (vp.status = $1 AND u."isActive" = true AND vp."shopVisible" = true) AS valid
             FROM vendor_profiles vp
             INNER JOIN users u ON u.id = vp."userId"
            WHERE vp.id = ANY($2::uuid[])`,
          [VendorStatus.APPROVED, shopIds],
        );
      for (const s of shopRows) shops.set(s.id, s);
    }

    for (const r of rows) {
      switch (r.targetType) {
        case BannerTargetType.CATEGORY: {
          const c = r.targetId ? cats.get(r.targetId) : undefined;
          out.set(r.id, { valid: !!c && c.isActive, label: c?.name ?? null });
          break;
        }
        case BannerTargetType.PRODUCT: {
          const id = r.targetId ?? '';
          out.set(r.id, { valid: prodVisible.has(id), label: prodNames.get(id) ?? null });
          break;
        }
        case BannerTargetType.SHOP: {
          const s = r.targetId ? shops.get(r.targetId) : undefined;
          out.set(r.id, {
            valid: !!s && s.valid,
            label: s?.shopName ?? null,
            logoUrl: s?.logoUrl ?? null,
          });
          break;
        }
        default:
          out.set(r.id, { valid: !!r.targetUrl, label: r.targetUrl });
      }
    }
    return out;
  }

  private async toAdminOne(banner: HomeBanner) {
    const resolved = await this.resolveTargets([banner]);
    return this.toAdmin(banner, resolved.get(banner.id));
  }

  private toAdmin(b: HomeBanner, target?: ResolvedTarget) {
    const now = Date.now();
    const started = !b.startsAt || b.startsAt.getTime() <= now;
    const notEnded = !b.endsAt || b.endsAt.getTime() > now;
    const targetValid = target?.valid ?? false;
    // Statut lisible pour la liste du back-office.
    let status: 'visible' | 'inactive' | 'programmee' | 'expiree' | 'cible_invalide';
    if (!b.isActive) status = 'inactive';
    else if (!started) status = 'programmee';
    else if (!notEnded) status = 'expiree';
    else if (!targetValid) status = 'cible_invalide';
    else status = 'visible';

    return {
      id:              b.id,
      imageUrl:        b.imageUrl,
      titre:           b.titre,
      sousTitre:       b.sousTitre,
      targetType:      b.targetType,
      targetId:        b.targetId,
      targetUrl:       b.targetUrl,
      targetLabel:     target?.label ?? null,
      targetValid,
      durationSeconds: b.durationSeconds,
      sortOrder:       b.sortOrder,
      isActive:        b.isActive,
      startsAt:        b.startsAt,
      endsAt:          b.endsAt,
      status,
      createdAt:       b.createdAt,
      updatedAt:       b.updatedAt,
    };
  }
}
