import {
  Injectable,
  NotFoundException,
  BadRequestException,
  ConflictException,
  ForbiddenException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository }       from 'typeorm';

import { Coupon, CouponType }  from './entities/coupon.entity';
import { CouponUsage }         from './entities/coupon-usage.entity';
import { VendorProfile, VendorStatus } from '../users/entities/vendor-profile.entity';
import { AdminAccount }        from '../auth/entities/admin-account.entity';

import { CreateCouponDto }   from './dto/create-coupon.dto';
import { ApplyCouponDto }    from './dto/apply-coupon.dto';
import { ActivityLogService } from '../../common/services/activity-log.service';
import { stripSecrets } from '../../common/utils/strip-secrets.util';
import {
  ActorType,
  LogAction,
} from '../../common/entities/activity-log.entity';

@Injectable()
export class CouponsService {

  constructor(
    @InjectRepository(Coupon)
    private readonly couponRepo: Repository<Coupon>,

    @InjectRepository(CouponUsage)
    private readonly usageRepo: Repository<CouponUsage>,

    @InjectRepository(VendorProfile)
    private readonly vendorRepo: Repository<VendorProfile>,

    private readonly logService: ActivityLogService,
  ) {}

  // ─────────────────────────────────────────────────────
  // CRÉER UN COUPON (admin ou vendeur)
  // ─────────────────────────────────────────────────────
  async create(
    dto:       CreateCouponDto,
    creatorId: string,
    isAdmin:   boolean,
    ip:        string,
  ) {
    // 1. Vérifier l'unicité du code
    const existing = await this.couponRepo.findOne({
      where: { code: dto.code },
    });

    if (existing) {
      throw new ConflictException(
        `Le code coupon "${dto.code}" est déjà utilisé`
      );
    }

    // 2. Vérifier valeur percentage ≤ 100
    if (
      dto.type === CouponType.PERCENTAGE &&
      Number(dto.value) > 100
    ) {
      throw new BadRequestException(
        'Une réduction en pourcentage ne peut pas dépasser 100%'
      );
    }

    // 3. Si c'est un vendeur → vérifier sa boutique
    let vendorId: string | null = null;

    if (!isAdmin) {
      const vendor = await this.vendorRepo.findOne({
        where: { userId: creatorId },
      });

      if (!vendor) {
        throw new ForbiddenException('Boutique introuvable');
      }

      if (vendor.status !== VendorStatus.APPROVED) {
        throw new ForbiddenException(
          'Votre boutique doit être validée pour créer des coupons'
        );
      }

      // Un vendeur ne peut créer des coupons que pour sa propre boutique
      vendorId = vendor.id;
    } else {
      // Un admin peut créer un coupon limité à une boutique spécifique
      vendorId = dto.vendorId ?? null;
    }

    // 4. Créer le coupon
    const coupon                  = this.couponRepo.create();
    coupon.code                   = dto.code;
    coupon.type                   = dto.type;
    coupon.value                  = dto.value;
    coupon.minOrderAmount         = dto.minOrderAmount ?? null;
    coupon.maxUses                = dto.maxUses        ?? null;
    coupon.usedCount              = 0;
    coupon.expiresAt              = dto.expiresAt
                                    ? new Date(dto.expiresAt)
                                    : null;
    coupon.isActive               = true;
    coupon.vendorId               = vendorId;
    coupon.createdByAdminId       = isAdmin  ? creatorId : null;
    // ⚠️ createdByVendorId référence vendor_profiles.id (clé étrangère), PAS
    // l'id de l'utilisateur : y mettre creatorId (userId) faisait échouer la
    // création (violation de clé étrangère) et empêchait de retrouver ses coupons.
    coupon.createdByVendorId      = !isAdmin ? vendorId : null;

    await this.couponRepo.save(coupon);

    await this.logService.log({
      actorId:    creatorId,
      actorType:  isAdmin ? ActorType.ADMIN : ActorType.VENDOR,
      action:     LogAction.COUPON_CREATED,
      entityType: 'coupon',
      entityId:   coupon.id,
      newValue:   { code: coupon.code, type: coupon.type, value: coupon.value },
      ipAddress:  ip,
    });

    return coupon;
  }

  // ─────────────────────────────────────────────────────
  // VÉRIFIER UN COUPON AVANT APPLICATION
  // (POST /coupons/validate — aperçu de la remise dans le panier)
  // ─────────────────────────────────────────────────────
  // Réponse volontairement UNIFORME : code inconnu, désactivé, expiré,
  // épuisé, non applicable à ce panier ou montant minimum non atteint →
  // toujours « Code invalide ». Un message différent selon le cas
  // permettrait de deviner quels codes existent. (« Vous avez déjà utilisé
  // ce code » reste distinct : seul un client qui l'a réellement utilisé peut
  // le recevoir.)
  // On ne renvoie jamais l'objet coupon : seulement { valid, code, discount,
  // message, scope }. L'application lit `discount` et `message`.
  async validateCoupon(
    code:      string,
    userId:    string,
    subtotal?: number,
  ) {
    const invalid = () => new BadRequestException('Code invalide');

    const normalized = typeof code === 'string' ? code.trim().toUpperCase() : '';
    if (!normalized || normalized.length > 50) throw invalid();

    const coupon = await this.couponRepo.findOne({
      where: { code: normalized, isActive: true },
    });

    if (!coupon) throw invalid();

    // Expiré
    if (coupon.expiresAt && new Date() > coupon.expiresAt) throw invalid();

    // Épuisé
    if (
      coupon.maxUses !== null &&
      coupon.usedCount >= coupon.maxUses
    ) {
      throw invalid();
    }

    // Usage unique par client
    const alreadyUsed = await this.usageRepo.findOne({
      where: { couponId: coupon.id, userId },
    });

    if (alreadyUsed) {
      throw new BadRequestException('Vous avez déjà utilisé ce code');
    }

    // Base de calcul de la remise :
    //  - coupon d'une boutique → sous-total des seules lignes de CETTE boutique
    //    dans le panier du client (les autres boutiques n'ont rien offert) ;
    //  - coupon plateforme → sous-total du panier (celui fourni par
    //    l'application, sinon calculé ici).
    const scopeVendorId = coupon.vendorId ?? coupon.createdByVendorId ?? null;
    let base: number;
    if (scopeVendorId) {
      base = await this.cartSubtotal(userId, scopeVendorId);
      if (base <= 0) throw invalid(); // aucun article de cette boutique
    } else if (typeof subtotal === 'number' && Number.isFinite(subtotal)) {
      base = subtotal;
    } else {
      base = await this.cartSubtotal(userId, null);
    }

    // Montant minimum non atteint
    if (coupon.minOrderAmount && base < Number(coupon.minOrderAmount)) {
      throw invalid();
    }

    const discount = this.calculateDiscount(coupon, base);

    return {
      valid:    true,
      code:     coupon.code,
      discount,
      message:  `Coupon appliqué : -${discount} FCFA`,
      scope:    scopeVendorId ? 'boutique' : 'plateforme',
    };
  }

  // Sous-total du panier du client (toutes boutiques, ou seulement celles du
  // vendeur donné) à partir des prix enregistrés dans le panier.
  private async cartSubtotal(
    userId:   string,
    vendorId: string | null,
  ): Promise<number> {
    const rows = await this.usageRepo.manager.query(
      `
      SELECT COALESCE(SUM(ci."unitPrice" * ci."quantity"), 0)::float8 AS "subtotal"
      FROM "carts" c
      JOIN "cart_items" ci      ON ci."cartId" = c."id"
      JOIN "product_variants" v ON v."id" = ci."variantId"
      JOIN "products" p         ON p."id" = v."productId"
      WHERE c."userId" = $1
        AND ($2::uuid IS NULL OR p."vendorId" = $2::uuid)
      `,
      [userId, vendorId],
    );
    return Number(rows?.[0]?.subtotal ?? 0);
  }

  // ─────────────────────────────────────────────────────
  // APPLIQUER UN COUPON (vérification avant commande)
  // ─────────────────────────────────────────────────────
  async apply(
    userId:   string,
    dto:      ApplyCouponDto,
    subtotal: number,
  ) {
    return this.validateCoupon(dto.code, userId, subtotal);
  }

  // ─────────────────────────────────────────────────────
  // DÉSACTIVER UN COUPON
  // ─────────────────────────────────────────────────────
  async deactivate(
    couponId:  string,
    requesterId: string,
    isAdmin:   boolean,
    ip:        string,
  ) {
    const coupon = await this.couponRepo.findOne({
      where: { id: couponId },
    });

    if (!coupon) throw new NotFoundException('Coupon introuvable');

    // Un vendeur ne peut désactiver que ses propres coupons
    if (!isAdmin) {
      const vendor = await this.vendorRepo.findOne({
        where: { userId: requesterId },
      });

      if (!vendor || coupon.createdByVendorId !== vendor.id) {
        throw new ForbiddenException(
          'Vous n\'êtes pas autorisé à désactiver ce coupon'
        );
      }
    }

    if (!coupon.isActive) {
      throw new BadRequestException('Ce coupon est déjà inactif');
    }

    coupon.isActive = false;
    await this.couponRepo.save(coupon);

    await this.logService.log({
      actorId:    requesterId,
      actorType:  isAdmin ? ActorType.ADMIN : ActorType.VENDOR,
      action:     LogAction.COUPON_DEACTIVATED,
      entityType: 'coupon',
      entityId:   couponId,
      oldValue:   { isActive: true },
      newValue:   { isActive: false },
      ipAddress:  ip,
    });

    return { message: 'Coupon désactivé avec succès' };
  }

  // ─────────────────────────────────────────────────────
  // LISTE DES COUPONS DU VENDEUR CONNECTÉ
  // ─────────────────────────────────────────────────────
  async getMyVendorCoupons(
    userId: string,
    page:   number = 1,
    limit:  number = 20,
  ) {
    const vendor = await this.vendorRepo.findOne({
      where: { userId },
    });

    if (!vendor) throw new NotFoundException('Boutique introuvable');

    const [coupons, total] = await this.couponRepo.findAndCount({
      where:  { createdByVendorId: vendor.id },
      order:  { createdAt: 'DESC' },
      skip:   (page - 1) * limit,
      take:   limit,
    });

    return {
      data:  coupons,
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
    };
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — TOUS LES COUPONS
  // ─────────────────────────────────────────────────────
  async getAllCoupons(
    isActive?: boolean,
    page:      number = 1,
    limit:     number = 20,
  ) {
    const query = this.couponRepo
      .createQueryBuilder('coupon')
      .leftJoinAndSelect('coupon.createdByAdmin',  'admin')
      .leftJoinAndSelect('coupon.createdByVendor', 'vendor')
      .orderBy('coupon.createdAt', 'DESC')
      .skip((page - 1) * limit)
      .take(limit);

    if (isActive !== undefined) {
      query.where('coupon.isActive = :isActive', { isActive });
    }

    const [coupons, total] = await query.getManyAndCount();

    return {
      // createdByAdmin / createdByVendor sont chargés en entier : on retire
      // les champs secrets (hash, jeton d'invitation...) avant de répondre.
      data:  stripSecrets(coupons),
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
    };
  }

  // ─────────────────────────────────────────────────────
  // DÉTAILS D'UN COUPON
  // ─────────────────────────────────────────────────────
  async findOne(couponId: string) {
    const coupon = await this.couponRepo.findOne({
      where:     { id: couponId },
      relations: ['createdByAdmin', 'createdByVendor', 'vendor'],
    });

    if (!coupon) throw new NotFoundException('Coupon introuvable');

    // Statistiques d'utilisation
    const usageCount = await this.usageRepo.count({
      where: { couponId },
    });

    return { ...stripSecrets(coupon), usageCount };
  }

  // ─────────────────────────────────────────────────────
  // MÉTHODE PRIVÉE — CALCULER LA REMISE
  // ─────────────────────────────────────────────────────
  calculateDiscount(coupon: Coupon, subtotal: number): number {
    if (coupon.type === CouponType.PERCENTAGE) {
      const discount = (subtotal * Number(coupon.value)) / 100;
      // La remise ne peut jamais dépasser le sous-total
      return Number(Math.min(discount, subtotal).toFixed(2));
    } else {
      return Number(Math.min(Number(coupon.value), subtotal).toFixed(2));
    }
  }
}