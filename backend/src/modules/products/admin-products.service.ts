import {
  Injectable,
  Logger,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';

import { Product, ProductStatus } from './entities/product.entity';
import { NotificationsService } from '../notifications/notifications.service';
import { ActivityLogService } from '../../common/services/activity-log.service';
import { ActorType, LogAction } from '../../common/entities/activity-log.entity';

export interface AdminProductFilters {
  search?:     string;
  status?:     ProductStatus;
  vendorId?:   string;
  categoryId?: string;
  isDigital?:  boolean;
  blocked?:    boolean;
  page:        number;
  limit:       number;
}

@Injectable()
export class AdminProductsService {
  private readonly logger = new Logger(AdminProductsService.name);

  constructor(
    @InjectRepository(Product)
    private readonly productRepo: Repository<Product>,
    private readonly notifications: NotificationsService,
    private readonly logService: ActivityLogService,
  ) {}

  // ─────────────────────────────────────────────────────
  // LISTE (tous statuts confondus) avec filtres
  // ─────────────────────────────────────────────────────
  async list(f: AdminProductFilters) {
    const qb = this.productRepo
      .createQueryBuilder('product')
      .leftJoin('product.vendor', 'vendor')
      .leftJoin('product.images', 'image', 'image.isPrimary = true AND image.isVideo = false')
      .select([
        'product.id', 'product.prod_name', 'product.slug', 'product.basePrice',
        'product.status', 'product.isDigital', 'product.isVedette',
        'product.isBlockedByAdmin', 'product.adminBlockReason', 'product.adminBlockedAt',
        'product.totalVentes', 'product.nombreVues', 'product.noteMoyenne',
        'product.nbreAvis', 'product.author', 'product.createdAt',
        'vendor.id', 'vendor.shopName',
        'image.id', 'image.url',
      ]);

    if (f.search) {
      const like = `%${f.search.replace(/[\\%_]/g, (c) => `\\${c}`)}%`;
      qb.andWhere(
        '(product.prod_name ILIKE :like OR vendor."shopName" ILIKE :like)',
        { like },
      );
    }
    if (f.status)   qb.andWhere('product.status = :status', { status: f.status });
    if (f.vendorId) qb.andWhere('product.vendorId = :vendorId', { vendorId: f.vendorId });
    if (f.isDigital !== undefined) qb.andWhere('product.isDigital = :dg', { dg: f.isDigital });
    if (f.blocked !== undefined)   qb.andWhere('product.isBlockedByAdmin = :bl', { bl: f.blocked });
    if (f.categoryId) {
      qb.andWhere(
        `EXISTS (SELECT 1 FROM product_categories pc WHERE pc."productId" = product.id AND pc."categoryId" = :cat)`,
        { cat: f.categoryId },
      );
    }

    const total = await qb.getCount();
    const items = await qb
      .orderBy('product.createdAt', 'DESC')
      .addOrderBy('product.id', 'ASC')
      .skip((f.page - 1) * f.limit)
      .take(f.limit)
      .getMany();

    return {
      data:  items,
      total,
      page:  f.page,
      pages: Math.max(1, Math.ceil(total / f.limit)),
    };
  }

  // ─────────────────────────────────────────────────────
  // CONSULTATION D'UN PRODUIT (fiche complète, jamais le fichier PDF privé)
  // ─────────────────────────────────────────────────────
  async getOne(id: string) {
    const product = await this.productRepo.findOne({
      where:     { id },
      relations: ['vendor', 'images', 'variants', 'categories'],
      order:     { images: { sortOrder: 'ASC' } },
    });
    if (!product) throw new NotFoundException('Produit introuvable');
    // Le vendeur : seulement ce qui sert à l'administration.
    const v: any = product.vendor;
    (product as any).vendor = v ? { id: v.id, shopName: v.shopName, userId: v.userId } : null;
    return product;
  }

  // ─────────────────────────────────────────────────────
  // DÉSACTIVER / RÉACTIVER
  // ─────────────────────────────────────────────────────
  async setBlocked(
    id:      string,
    blocked: boolean,
    reason:  string | undefined,
    adminId: string,
    ip:      string,
  ) {
    const product = await this.productRepo.findOne({
      where:     { id },
      relations: ['vendor'],
    });
    if (!product) throw new NotFoundException('Produit introuvable');

    const oldStatus = product.status;

    if (blocked) {
      const motif = (reason ?? '').trim();
      if (motif.length < 3) {
        throw new BadRequestException('Indiquez le motif de la désactivation (3 caractères minimum).');
      }
      if (product.isBlockedByAdmin) {
        throw new BadRequestException('Ce produit est déjà désactivé par l\'administration.');
      }
      product.isBlockedByAdmin       = true;
      product.adminBlockReason       = motif.slice(0, 500);
      product.adminBlockedAt         = new Date();
      product.adminBlockedFromStatus = product.status;
      product.status                 = ProductStatus.INACTIVE;
    } else {
      if (!product.isBlockedByAdmin) {
        throw new BadRequestException('Ce produit n\'est pas désactivé par l\'administration.');
      }
      const before = product.adminBlockedFromStatus as ProductStatus | null;
      // Statut d'avant le blocage ; un produit qui était déjà « inactive » le reste.
      product.status = before && Object.values(ProductStatus).includes(before)
        ? before
        : ProductStatus.INACTIVE;
      product.isBlockedByAdmin       = false;
      product.adminBlockReason       = null;
      product.adminBlockedAt         = null;
      product.adminBlockedFromStatus = null;
    }

    await this.productRepo.save(product);

    await this.logService.log({
      actorId:    adminId,
      actorType:  ActorType.ADMIN,
      action:     LogAction.PRODUCT_STATUS_CHANGED,
      entityType: 'product',
      entityId:   id,
      oldValue:   { status: oldStatus },
      newValue:   { status: product.status, blockedByAdmin: blocked, reason: product.adminBlockReason },
      ipAddress:  ip,
    });

    const vendorUserId = (product.vendor as any)?.userId as string | undefined;
    if (vendorUserId) {
      this.notifications
        .notifyProductAdminBlock(vendorUserId, product.prod_name, id, blocked, product.adminBlockReason)
        .catch((e) => this.logger.error(`Notification vendeur (produit ${id}) échouée : ${e?.message}`));
    }

    return {
      message: blocked ? 'Produit désactivé.' : 'Produit réactivé.',
      status:  product.status,
      isBlockedByAdmin: product.isBlockedByAdmin,
    };
  }
}
