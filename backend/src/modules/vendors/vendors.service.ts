import {
  Injectable,
  NotFoundException,
  ConflictException,
  BadRequestException,
  ForbiddenException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository }       from 'typeorm';
import { MailerService }    from '@nestjs-modules/mailer';

import { VendorProfile, VendorStatus } from '../users/entities/vendor-profile.entity';
import { UserRole, UserRoleEnum }      from '../users/entities/user-role.entity';
import { User }                        from '../users/entities/user.entity';

import { SubmitVendorProfileDto }    from './dto/submit-vendor-profile.dto';
import { UpdateShopDto }             from './dto/update-shop.dto';
import { UpdatePaymentSettingsDto }  from './dto/update-payment-settings.dto';
import { ReviewVendorDto, VendorReviewAction } from './dto/review-vendor.dto';

import { ActivityLogService } from '../../common/services/activity-log.service';
import {
  ActorType,
  LogAction,
} from '../../common/entities/activity-log.entity';

@Injectable()
export class VendorsService {

  constructor(
    @InjectRepository(VendorProfile)
    private readonly vendorRepo: Repository<VendorProfile>,

    @InjectRepository(UserRole)
    private readonly userRoleRepo: Repository<UserRole>,

    @InjectRepository(User)
    private readonly userRepo: Repository<User>,

    private readonly mailerService:   MailerService,
    private readonly logService:      ActivityLogService,
  ) {}

  // ─────────────────────────────────────────────────────
  // SOUMETTRE UNE DEMANDE VENDEUR
  // ─────────────────────────────────────────────────────
  async submitProfile(
    userId: string,
    dto:    SubmitVendorProfileDto,
    ip:     string,
  ) {
    // 1. Vérifier qu'une boutique n'existe pas déjà
    const existing = await this.vendorRepo.findOne({
      where: { userId },
    });

    if (existing) {
      // Si déjà approuvé ou en attente → refuser
      if (
        existing.status === VendorStatus.APPROVED ||
        existing.status === VendorStatus.PENDING
      ) {
        throw new ConflictException(
          existing.status === VendorStatus.APPROVED
            ? 'Votre boutique est déjà active'
            : 'Votre demande est déjà en cours de traitement'
        );
      }

      // Si bloqué → ne peut pas re-soumettre
      if (existing.status === VendorStatus.BLOCKED) {
        throw new ForbiddenException(
          'Votre compte vendeur a été bloqué. Contactez le support.'
        );
      }

      // Si rejeté → re-soumission autorisée
      // On met à jour le profil existant
      if (existing.status === VendorStatus.REJECTED) {
        return this.resubmitProfile(existing, dto, ip);
      }
    }

    // 2. Vérifier que le nom de boutique n'est pas déjà pris
    const nameExists = await this.vendorRepo.findOne({
      where: { shopName: dto.shopName },
    });
    if (nameExists) {
      throw new ConflictException('Ce nom de boutique est déjà utilisé');
    }

    // 3. Créer le profil vendeur
    const vendor = this.vendorRepo.create({
      userId,
      shopName:                dto.shopName,
      shopAddress:             dto.shopAddress,
      activityType:            dto.activityType,
      description:             dto.description,
      idDocumentUrl:           dto.idDocumentUrl,
      selfieUrl:               dto.selfieUrl,
      sampleProductUrls:       dto.sampleProductUrls,
      termsAccepted:           dto.termsAccepted,
      fraudPenaltiesAccepted:  dto.fraudPenaltiesAccepted,
      status:                  VendorStatus.PENDING,
      submittedAt:             new Date(),
      submissionCount:         1,
    });

    await this.vendorRepo.save(vendor);

    // 4. Logger
    await this.logService.log({
      actorId:    userId,
      actorType:  ActorType.CLIENT,
      action:     LogAction.VENDOR_SUBMITTED,
      entityType: 'vendor_profile',
      entityId:   vendor.id,
      ipAddress:  ip,
    });

    return {
      message: 'Demande soumise avec succès. '
             + 'Vous serez notifié par email après validation.',
      vendorId: vendor.id,
    };
  }

  // ─────────────────────────────────────────────────────
  // RE-SOUMISSION APRÈS REFUS (méthode privée)
  // ─────────────────────────────────────────────────────
  private async resubmitProfile(
    existing: VendorProfile,
    dto:      SubmitVendorProfileDto,
    ip:       string,
  ) {
    // Vérifier que le nouveau nom de boutique
    // n'est pas déjà pris par quelqu'un d'autre
    if (dto.shopName !== existing.shopName) {
      const nameExists = await this.vendorRepo.findOne({
        where: { shopName: dto.shopName },
      });
      if (nameExists) {
        throw new ConflictException('Ce nom de boutique est déjà utilisé');
      }
    }

    // Mettre à jour avec les nouvelles infos
    existing.shopName               = dto.shopName;
    existing.shopAddress            = dto.shopAddress;
    existing.activityType           = dto.activityType;
    existing.description            = dto.description;
    existing.idDocumentUrl          = dto.idDocumentUrl;
    existing.selfieUrl              = dto.selfieUrl;
    existing.sampleProductUrls      = dto.sampleProductUrls;
    existing.termsAccepted          = dto.termsAccepted;
    existing.fraudPenaltiesAccepted = dto.fraudPenaltiesAccepted;
    existing.status                 = VendorStatus.PENDING;
    existing.motifRefus             = null;
    existing.submittedAt            = new Date();
    existing.submissionCount        += 1;

    await this.vendorRepo.save(existing);

    await this.logService.log({
      actorId:    existing.userId,
      actorType:  ActorType.CLIENT,
      action:     LogAction.VENDOR_SUBMITTED,
      entityType: 'vendor_profile',
      entityId:   existing.id,
      newValue:   { resubmission: true, count: existing.submissionCount },
      ipAddress:  ip,
    });

    return {
      message:  'Demande re-soumise avec succès. Vous serez notifié par email.',
      vendorId: existing.id,
    };
  }

  // ─────────────────────────────────────────────────────
  // VOIR SON PROPRE PROFIL VENDEUR
  // ─────────────────────────────────────────────────────
  async getMyProfile(userId: string) {
    const vendor = await this.vendorRepo.findOne({
      where: { userId },
    });

    if (!vendor) {
      throw new NotFoundException(
        'Aucun profil vendeur trouvé. Soumettez une demande d\'abord.'
      );
    }

    // ⚠️ Ne jamais retourner paymentDetails en clair
    // On retire les données bancaires sensibles
    const { paymentDetails, ...vendorSafe } = vendor;

    return {
      ...vendorSafe,
      hasPaymentConfigured: !!paymentDetails,
    };
  }

  // ─────────────────────────────────────────────────────
  // METTRE À JOUR SA BOUTIQUE (après validation)
  // ─────────────────────────────────────────────────────
  async updateShop(
    userId: string,
    dto:    UpdateShopDto,
    ip:     string,
  ) {
    const vendor = await this.vendorRepo.findOne({
      where: { userId },
    });

    if (!vendor) throw new NotFoundException('Profil vendeur introuvable');

    // ⚠️ Seul un vendeur APPROUVÉ peut modifier sa boutique
    if (vendor.status !== VendorStatus.APPROVED) {
      throw new ForbiddenException(
        'Votre boutique doit être validée avant de pouvoir la modifier'
      );
    }

    // Vérifier le nouveau nom si changé
    if (dto.shopName && dto.shopName !== vendor.shopName) {
      const nameExists = await this.vendorRepo.findOne({
        where: { shopName: dto.shopName },
      });
      if (nameExists) {
        throw new ConflictException('Ce nom de boutique est déjà utilisé');
      }
    }

    const oldValue = {
      shopName:    vendor.shopName,
      shopAddress: vendor.shopAddress,
      description: vendor.description,
    };

    // Mettre à jour uniquement les champs fournis
    if (dto.shopName)    vendor.shopName    = dto.shopName;
    if (dto.shopAddress) vendor.shopAddress = dto.shopAddress;
    if (dto.activityType) vendor.activityType = dto.activityType;
    if (dto.description) vendor.description = dto.description;

    // ⚠️ Logo et bannière — UNIQUEMENT si status = APPROVED
    // Cette vérification est déjà faite ci-dessus donc on est safe
    if (dto.logoUrl)   vendor.logoUrl   = dto.logoUrl;
    if (dto.bannerUrl) vendor.bannerUrl = dto.bannerUrl;

    await this.vendorRepo.save(vendor);

    await this.logService.log({
      actorId:    userId,
      actorType:  ActorType.VENDOR,
      action:     LogAction.VENDOR_SHOP_UPDATED,
      entityType: 'vendor_profile',
      entityId:   vendor.id,
      oldValue,
      newValue: {
        shopName:    vendor.shopName,
        shopAddress: vendor.shopAddress,
        description: vendor.description,
      },
      ipAddress: ip,
    });

    const { paymentDetails, ...vendorSafe } = vendor;
    return {
      ...vendorSafe,
      hasPaymentConfigured: !!paymentDetails,
    };
  }

  // ─────────────────────────────────────────────────────
  // CONFIGURER LES PARAMÈTRES DE PAIEMENT
  // ─────────────────────────────────────────────────────
  async updatePaymentSettings(
    userId: string,
    dto:    UpdatePaymentSettingsDto,
  ) {
    const vendor = await this.vendorRepo.findOne({
      where: { userId },
    });

    if (!vendor) throw new NotFoundException('Profil vendeur introuvable');

    // Seul un vendeur approuvé peut configurer son paiement
    if (vendor.status !== VendorStatus.APPROVED) {
      throw new ForbiddenException(
        'Votre boutique doit être validée avant de configurer le paiement'
      );
    }

    // Construire l'objet paymentDetails selon le type
    let paymentDetails: Record<string, any>;

    if (dto.paymentMethod === 'mobile_money') {
      paymentDetails = {
        operator:    dto.operator,
        number:      dto.mobileNumber,
        holderName:  dto.holderName,
      };
    } else {
      paymentDetails = {
        bankName:      dto.bankName,
        accountNumber: dto.accountNumber,
        holderName:    dto.holderName,
      };
    }

    vendor.paymentMethod  = dto.paymentMethod;
    vendor.paymentDetails = paymentDetails;
    await this.vendorRepo.save(vendor);

    return { message: 'Paramètres de paiement mis à jour avec succès' };
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — LISTE DES PROFILS VENDEURS
  // ─────────────────────────────────────────────────────
  async getAllVendors(
    status?: VendorStatus,
    page:    number = 1,
    limit:   number = 20,
  ) {
    // Optimisation : on utilise QueryBuilder pour
    // joindre uniquement les données nécessaires
    const query = this.vendorRepo
      .createQueryBuilder('vendor')
      .leftJoin('vendor.user', 'user')
      .select([
        'vendor.id',
        'vendor.shopName',
        'vendor.activityType',
        'vendor.status',
        'vendor.submittedAt',
        'vendor.submissionCount',
        'user.id',
        'user.prenom',
        'user.name',
        'user.email',
        'user.phone',
      ])
      .orderBy('vendor.submittedAt', 'DESC')
      .skip((page - 1) * limit)
      .take(limit);

    // Filtrer par statut si fourni
    if (status) {
      query.where('vendor.status = :status', { status });
    }

    const [vendors, total] = await query.getManyAndCount();

    return {
      data:  vendors,
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
    };
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — DÉTAILS D'UN PROFIL VENDEUR
  // ─────────────────────────────────────────────────────
  async getVendorById(vendorId: string) {
    const vendor = await this.vendorRepo.findOne({
      where:     { id: vendorId },
      relations: ['user', 'reviewedBy'],
    });

    if (!vendor) throw new NotFoundException('Profil vendeur introuvable');

    // ⚠️ Masquer les données bancaires sensibles
    const { paymentDetails, ...vendorSafe } = vendor;

    return {
      ...vendorSafe,
      hasPaymentConfigured: !!paymentDetails,
    };
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — VALIDER OU REFUSER UN VENDEUR
  // ─────────────────────────────────────────────────────
  async reviewVendor(
    vendorId: string,
    adminId:  string,
    dto:      ReviewVendorDto,
    ip:       string,
  ) {
    const vendor = await this.vendorRepo.findOne({
      where:     { id: vendorId },
      relations: ['user'],
    });

    if (!vendor) throw new NotFoundException('Profil vendeur introuvable');

    // On ne peut traiter que les demandes en attente
    if (vendor.status !== VendorStatus.PENDING) {
      throw new BadRequestException(
        'Seules les demandes en attente peuvent être traitées'
      );
    }

    const oldStatus = vendor.status;

    if (dto.action === VendorReviewAction.APPROVE) {
      vendor.status     = VendorStatus.APPROVED;
      vendor.motifRefus = null;

      // Attribuer le rôle VENDOR à l'utilisateur
      const roleExists = await this.userRoleRepo.findOne({
        where: {
          userId: vendor.userId,
          role:   UserRoleEnum.VENDOR,
        },
      });

      if (!roleExists) {
        const role = this.userRoleRepo.create({
          userId:   vendor.userId,
          role:     UserRoleEnum.VENDOR,
          isActive: true,
        });
        await this.userRoleRepo.save(role);
      } else {
        // Si le rôle existait mais était désactivé → réactiver
        roleExists.isActive = true;
        await this.userRoleRepo.save(roleExists);
      }

      // Envoyer email de validation
      await this.mailerService.sendMail({
        to:      vendor.user.email,
        subject: '🎉 Votre boutique Asoukaa a été validée !',
        html: `
          <p>Bonjour ${vendor.user.prenom},</p>
          <p>Félicitations ! Votre boutique 
             <strong>${vendor.shopName}</strong> 
             a été validée par notre équipe.</p>
          <p>Vous pouvez maintenant :</p>
          <ul>
            <li>Ajouter votre logo et bannière</li>
            <li>Configurer vos paramètres de paiement</li>
            <li>Commencer à ajouter vos produits</li>
          </ul>
          <p>Bienvenue sur Asoukaa !</p>
        `,
      });

    } else {
      // REJECT
      vendor.status     = VendorStatus.REJECTED;
      vendor.motifRefus = dto.rejectionReason ?? null;

      // Envoyer email de refus avec le motif
      await this.mailerService.sendMail({
        to:      vendor.user.email,
        subject: 'Votre demande de boutique Asoukaa',
        html: `
          <p>Bonjour ${vendor.user.prenom},</p>
          <p>Votre demande pour la boutique 
             <strong>${vendor.shopName}</strong> 
             n'a pas pu être validée pour la raison suivante :</p>
          <blockquote style="border-left: 3px solid #ccc; padding-left: 12px;">
            ${dto.rejectionReason}
          </blockquote>
          <p>Vous pouvez corriger ces éléments et 
             re-soumettre votre demande depuis l'application.</p>
        `,
      });
    }

    vendor.reviewedById = adminId;
    vendor.reviewedAt   = new Date();
    await this.vendorRepo.save(vendor);

    await this.logService.log({
      actorId:    adminId,
      actorType:  ActorType.ADMIN,
      action:     dto.action === VendorReviewAction.APPROVE
                    ? LogAction.VENDOR_APPROVED
                    : LogAction.VENDOR_REJECTED,
      entityType: 'vendor_profile',
      entityId:   vendorId,
      oldValue:   { status: oldStatus },
      newValue:   {
        status: vendor.status,
        reason: dto.rejectionReason ?? null,
      },
      ipAddress: ip,
    });

    return {
      message: dto.action === VendorReviewAction.APPROVE
        ? 'Boutique validée avec succès'
        : 'Demande refusée. Le vendeur a été notifié.',
    };
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — BLOQUER UN VENDEUR
  // ─────────────────────────────────────────────────────
  async blockVendor(
    vendorId: string,
    adminId:  string,
    ip:       string,
  ) {
    const vendor = await this.vendorRepo.findOne({
      where:     { id: vendorId },
      relations: ['user'],
    });

    if (!vendor) throw new NotFoundException('Profil vendeur introuvable');

    if (vendor.status === VendorStatus.BLOCKED) {
      throw new BadRequestException('Ce vendeur est déjà bloqué');
    }

    const oldStatus   = vendor.status;
    vendor.status     = VendorStatus.BLOCKED;
    vendor.reviewedById = adminId;
    vendor.reviewedAt   = new Date();

    // Désactiver le rôle VENDOR
    await this.userRoleRepo.update(
      { userId: vendor.userId, role: UserRoleEnum.VENDOR },
      { isActive: false },
    );

    await this.vendorRepo.save(vendor);

    // Notifier le vendeur par email
    await this.mailerService.sendMail({
      to:      vendor.user.email,
      subject: 'Votre boutique Asoukaa a été suspendue',
      html: `
        <p>Bonjour ${vendor.user.prenom},</p>
        <p>Votre boutique <strong>${vendor.shopName}</strong> 
           a été suspendue par notre équipe.</p>
        <p>Pour plus d'informations, contactez notre support.</p>
      `,
    });

    await this.logService.log({
      actorId:    adminId,
      actorType:  ActorType.ADMIN,
      action:     LogAction.VENDOR_BLOCKED,
      entityType: 'vendor_profile',
      entityId:   vendorId,
      oldValue:   { status: oldStatus },
      newValue:   { status: VendorStatus.BLOCKED },
      ipAddress:  ip,
    });

    return { message: 'Boutique bloquée avec succès' };
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — LISTE DES DEMANDES EN ATTENTE
  // (optimisé pour le dashboard)
  // ─────────────────────────────────────────────────────
  async getPendingVendors() {
    return this.vendorRepo
      .createQueryBuilder('vendor')
      .leftJoin('vendor.user', 'user')
      .select([
        'vendor.id',
        'vendor.shopName',
        'vendor.activityType',
        'vendor.submittedAt',
        'vendor.submissionCount',
        'user.id',
        'user.prenom',
        'user.name',
        'user.email',
      ])
      .where('vendor.status = :status', { status: VendorStatus.PENDING })
      .orderBy('vendor.submittedAt', 'ASC') // Les plus anciens d'abord
      .getMany();
  }
}
