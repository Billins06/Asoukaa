import {
  Injectable,
  Logger,
  NotFoundException,
  ConflictException,
  BadRequestException,
  ForbiddenException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, In }   from 'typeorm';
import { isUUID }           from 'class-validator';
import { MailService }      from '../mail/mail.service';

import { VendorProfile, VendorStatus } from '../users/entities/vendor-profile.entity';
import { UserRole, UserRoleEnum }      from '../users/entities/user-role.entity';
import { User }                        from '../users/entities/user.entity';
import { Commission, CommissionStatus } from '../payments/entities/commission.entity';
import { Product, ProductStatus }       from '../products/entities/product.entity';
import { Order, OrderStatus }           from '../orders/entities/order.entity';
import { Review, ReviewStatus }         from '../reviews/entities/review.entity';
import { ShopFollow }                   from './entities/shop-follow.entity';
import { Category }                     from '../categories/entities/category.entity';
import { ProductsService }              from '../products/products.service';
import { toPresence }                   from '../presence/presence.util';

import { SubmitVendorProfileDto }    from './dto/submit-vendor-profile.dto';
import { CompleteVendorDocumentsDto } from './dto/complete-vendor-documents.dto';
import { UpdateShopDto }             from './dto/update-shop.dto';
import { UpdatePaymentSettingsDto }  from './dto/update-payment-settings.dto';
import { UpdateVendorSettingsDto }   from './dto/update-vendor-settings.dto';
import { ReviewVendorDto, VendorReviewAction } from './dto/review-vendor.dto';

import { ActivityLogService } from '../../common/services/activity-log.service';
import { EncryptionService } from '../../common/services/encryption.service';
import {
  ActorType,
  LogAction,
} from '../../common/entities/activity-log.entity';

@Injectable()
export class VendorsService {
  private readonly logger = new Logger(VendorsService.name);

  constructor(
    @InjectRepository(VendorProfile)
    private readonly vendorRepo: Repository<VendorProfile>,

    @InjectRepository(UserRole)
    private readonly userRoleRepo: Repository<UserRole>,

    @InjectRepository(User)
    private readonly userRepo: Repository<User>,

    @InjectRepository(Commission)
    private readonly commissionRepo: Repository<Commission>,

    @InjectRepository(Product)
    private readonly productRepo: Repository<Product>,

    @InjectRepository(Order)
    private readonly orderRepo: Repository<Order>,

    @InjectRepository(Review)
    private readonly reviewRepo: Repository<Review>,

    @InjectRepository(ShopFollow)
    private readonly shopFollowRepo: Repository<ShopFollow>,

    // Catégories de la plateforme choisies par les vendeurs (étiquettes).
    @InjectRepository(Category)
    private readonly categoryRepo: Repository<Category>,

    private readonly mailService:     MailService,
    private readonly logService:      ActivityLogService,
    private readonly encryptionService: EncryptionService,
    // Règle de visibilité produit + résolution des sous-catégories pour
    // l'annuaire des boutiques (getDirectory).
    private readonly productsService: ProductsService,
  ) {}

  // ─────────────────────────────────────────────────────
  // CATÉGORIES DU VENDEUR (étiquettes de la boutique)
  // ─────────────────────────────────────────────────────
  // Le vendeur choisit 1 à 5 catégories de la plateforme. C'est une simple
  // ÉTIQUETTE d'affichage : elle ne restreint PAS les catégories dans
  // lesquelles il peut publier ses produits. activityType reste rempli
  // (noms joints par ", ", 100 caractères max) pour les écrans et les
  // anciens clients qui l'affichent encore.
  private static readonly MAX_VENDOR_CATEGORIES = 5;

  private joinCategoryNames(names: string[]): string {
    const text = names.join(', ');
    return text.length > 100 ? `${text.slice(0, 99).trimEnd()}…` : text;
  }

  // Valide une liste d'ids : dédoublonnage, 1 à 5, UUID, catégories
  // existantes ET actives (racine ou sous-catégorie). Une seule requête.
  private async validateCategoryIds(
    rawIds: string[],
  ): Promise<{ categoryIds: string[]; activityType: string }> {
    // Minuscules AVANT dédoublonnage et requête : un UUID en majuscules est
    // valide mais la base renvoie ses ids en minuscules (byId.get sinon vide).
    const ids = Array.from(
      new Set((rawIds ?? []).map((id) => String(id).trim().toLowerCase())),
    );
    if (!ids.length) {
      throw new BadRequestException('Choisissez au moins une catégorie');
    }
    if (ids.length > VendorsService.MAX_VENDOR_CATEGORIES) {
      throw new BadRequestException(
        `Vous pouvez choisir ${VendorsService.MAX_VENDOR_CATEGORIES} catégories au maximum`,
      );
    }
    if (!ids.every((id) => isUUID(id))) {
      throw new BadRequestException('Identifiant de catégorie invalide');
    }

    const found = await this.categoryRepo.find({
      where:  { id: In(ids), isActive: true },
      select: ['id', 'name'],
    });
    const byId = new Map(found.map((cat) => [cat.id, cat]));
    if (byId.size !== ids.length) {
      throw new BadRequestException(
        'Une ou plusieurs catégories sont introuvables ou désactivées',
      );
    }

    return {
      categoryIds:  ids,
      activityType: this.joinCategoryNames(ids.map((id) => byId.get(id)!.name)),
    };
  }

  // Soumission / re-soumission : categoryIds prioritaire ; sinon ancien
  // comportement (texte libre) pour les anciennes versions de l'appli.
  private async resolveVendorActivity(input: {
    categoryIds?: string[];
    activityType?: string;
  }): Promise<{ categoryIds: string[]; activityType: string }> {
    if (input.categoryIds !== undefined && input.categoryIds !== null) {
      return this.validateCategoryIds(input.categoryIds);
    }
    const text = input.activityType?.trim();
    if (!text) {
      throw new BadRequestException("Choisissez au moins une catégorie d'activité");
    }
    return { categoryIds: [], activityType: text.slice(0, 100) };
  }

  // Charge en UNE requête les catégories de tous les vendeurs d'une page
  // (pas de N+1). activeOnly : vues publiques (une catégorie désactivée
  // ou supprimée disparaît de l'affichage sans toucher au profil).
  private async loadCategoryViews(
    vendors: { categoryIds?: string[] | null }[],
    activeOnly: boolean,
  ): Promise<Map<string, { id: string; name: string; imageUrl: string | null }>> {
    const wanted = new Set<string>();
    for (const v of vendors) {
      for (const id of v.categoryIds ?? []) wanted.add(id);
    }
    const views = new Map<string, { id: string; name: string; imageUrl: string | null }>();
    if (!wanted.size) return views;

    const rows = await this.categoryRepo.find({
      where:  activeOnly
        ? { id: In([...wanted]), isActive: true }
        : { id: In([...wanted]) },
      select: ['id', 'name', 'imageUrl'],
    });
    for (const cat of rows) {
      views.set(cat.id, { id: cat.id, name: cat.name, imageUrl: cat.imageUrl ?? null });
    }
    return views;
  }

  private categoriesOf(
    vendor: { categoryIds?: string[] | null },
    views:  Map<string, { id: string; name: string; imageUrl: string | null }>,
  ) {
    return (vendor.categoryIds ?? [])
      .map((id) => views.get(id))
      .filter((v): v is { id: string; name: string; imageUrl: string | null } => !!v);
  }

  // ─────────────────────────────────────────────────────
  // SOUMETTRE UNE DEMANDE VENDEUR
  // ─────────────────────────────────────────────────────
  async submitProfile(
    userId: string,
    dto:    SubmitVendorProfileDto,
    ip:     string,
  ) {
    // 0. Catégories choisies (ou texte libre des anciennes versions)
    const activity = await this.resolveVendorActivity(dto);

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
        return this.resubmitProfile(existing, dto, ip, activity);
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
      activityType:            activity.activityType,
      categoryIds:             activity.categoryIds,
      description:             dto.description,
      idDocumentUrl:           dto.idDocumentUrl,
      selfieUrl:               dto.selfieUrl,
      sampleProductUrls:       dto.sampleProductUrls ?? [],
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

    // Email "demande reçue, en cours de traitement" — best-effort : un
    // échec d'envoi ne doit pas faire échouer la soumission elle-même.
    // Avant ce correctif, AUCUN email n'était envoyé ici, alors que le
    // message de retour ci-dessous promet "vous serez notifié par email".
    try {
      const submitter = await this.userRepo.findOne({ where: { id: userId } });
      if (submitter) {
        await this.mailService.sendVendorSubmitted(
          submitter.email,
          submitter.prenom,
          vendor.shopName,
        );
      }
    } catch (error) {
      this.logger.error(
        `Échec envoi mail de soumission vendeur → userId=${userId}`,
        error?.message,
      );
    }

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
    activity: { categoryIds: string[]; activityType: string },
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
    existing.activityType           = activity.activityType;
    existing.categoryIds            = activity.categoryIds;
    existing.description            = dto.description;
    existing.idDocumentUrl          = dto.idDocumentUrl ?? existing.idDocumentUrl;
    existing.selfieUrl              = dto.selfieUrl ?? existing.selfieUrl;
    existing.sampleProductUrls      = dto.sampleProductUrls ?? existing.sampleProductUrls ?? [];
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

    // Même email "en cours de traitement" que pour une première soumission
    // — voir submitProfile() ci-dessus.
    try {
      const submitter = await this.userRepo.findOne({ where: { id: existing.userId } });
      if (submitter) {
        await this.mailService.sendVendorSubmitted(
          submitter.email,
          submitter.prenom,
          existing.shopName,
        );
      }
    } catch (error) {
      this.logger.error(
        `Échec envoi mail de re-soumission vendeur → userId=${existing.userId}`,
        error?.message,
      );
    }

    return {
      message:  'Demande re-soumise avec succès. Vous serez notifié par email.',
      vendorId: existing.id,
    };
  }

  // ─────────────────────────────────────────────────────
  // COMPLÉTER LES DOCUMENTS MANQUANTS (dossier EN ATTENTE)
  // ─────────────────────────────────────────────────────
  async completeDocuments(
    userId: string,
    dto:    CompleteVendorDocumentsDto,
    ip:     string,
  ) {
    const vendor = await this.vendorRepo.findOne({ where: { userId } });
    if (!vendor) throw new NotFoundException('Profil vendeur introuvable');

    if (vendor.status !== VendorStatus.PENDING) {
      throw new BadRequestException(
        "Cette action n'est possible que pour un dossier en attente de validation"
      );
    }

    if (dto.idDocumentUrl)     vendor.idDocumentUrl = dto.idDocumentUrl;
    if (dto.selfieUrl)         vendor.selfieUrl = dto.selfieUrl;
    if (dto.sampleProductUrls && dto.sampleProductUrls.length > 0) {
      vendor.sampleProductUrls = dto.sampleProductUrls;
    }

    await this.vendorRepo.save(vendor);

    await this.logService.log({
      actorId:    userId,
      actorType:  ActorType.CLIENT,
      action:     LogAction.VENDOR_SUBMITTED,
      entityType: 'vendor_profile',
      entityId:   vendor.id,
      ipAddress:  ip,
    });

    return { message: 'Documents mis à jour.' };
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

    const myViews = await this.loadCategoryViews([vendor], false);

    return {
      ...vendorSafe,
      categoryIds:          vendor.categoryIds ?? [],
      categories:           this.categoriesOf(vendor, myViews),
      // « Boutique visible » (réglage PATCH /vendors/me/settings).
      shopVisible:          vendor.shopVisible !== false,
      hasPaymentConfigured: !!paymentDetails,
      // Vraies statistiques (remplacent les chiffres figés "4.8 / 342 /
      // 128" affichés en dur dans le profil vendeur côté Flutter).
      stats: await this.getShopStats(vendor.id),
    };
  }

  // ─────────────────────────────────────────────────────
  // RÉGLAGES DU VENDEUR (PATCH /vendors/me/settings)
  // ─────────────────────────────────────────────────────
  // « Boutique visible » : false = la boutique et ses produits disparaissent
  // des listes publiques (annuaire, fiche publique, produits, panier,
  // commandes futures) ; le propriétaire garde l'accès à tout et les
  // commandes déjà passées continuent normalement.
  async updateSettings(userId: string, dto: UpdateVendorSettingsDto) {
    const vendor = await this.vendorRepo.findOne({
      where:  { userId },
      select: { id: true },
    });

    if (!vendor) {
      throw new NotFoundException(
        'Aucun profil vendeur trouvé. Soumettez une demande d\'abord.'
      );
    }

    await this.vendorRepo.update({ id: vendor.id }, { shopVisible: dto.shopVisible });

    return { shopVisible: dto.shopVisible };
  }

  // ─────────────────────────────────────────────────────
  // STATISTIQUES RÉELLES D'UNE BOUTIQUE
  // ─────────────────────────────────────────────────────
  // Utilisé par getMyProfile (GET /vendors/me) et getPublicShop
  // (GET /vendors/:id/public). Trois requêtes COUNT/AVG en parallèle,
  // aucune ligne chargée en mémoire.
  //  - salesCount    : commandes au statut "livré" uniquement. "en attente",
  //    "en cours", "livreur affecté", "expedié" et "en transit" ne sont
  //    pas encore des ventes abouties (elles peuvent encore être annulées
  //    ou contestées) ; "annulé" n'en est évidemment pas une.
  //  - productsCount : produits publiés ("active"), c.-à-d. visibles des
  //    acheteurs (même règle que dashboard.service → activeProducts).
  //  - rating / reviewsCount : moyenne et nombre des avis APPROUVÉS sur
  //    les produits de la boutique (même calcul que la réputation du
  //    dashboard vendeur). 0 s'il n'y a encore aucun avis.
  //  - ratingBreakdown : nombre d'avis approuvés par note (1 à 5), pour
  //    les barres de répartition de la fiche boutique. Calculé dans la
  //    même requête GROUP BY que la moyenne.
  //  - followersCount : nombre d'abonnés réels (table shop_follows,
  //    voir followShop / unfollowShop plus bas).
  private async getShopStats(vendorId: string) {
    const [salesCount, productsCount, ratingRows, followersCount] = await Promise.all([
      this.orderRepo.count({
        where: { vendorId, status: OrderStatus.DELIVERED },
      }),
      this.productRepo.count({
        where: { vendorId, status: ProductStatus.ACTIVE },
      }),
      this.reviewRepo
        .createQueryBuilder('review')
        .innerJoin('review.product', 'product')
        .select('review.notation', 'notation')
        .addSelect('COUNT(review.id)', 'count')
        .where('product.vendorId = :vendorId', { vendorId })
        .andWhere('review.status = :status', { status: ReviewStatus.APPROVED })
        .groupBy('review.notation')
        .getRawMany(),
      this.shopFollowRepo.count({ where: { vendorId } }),
    ]);

    const ratingBreakdown: Record<string, number> = { '1': 0, '2': 0, '3': 0, '4': 0, '5': 0 };
    let reviewsCount = 0;
    let ratingSum    = 0;
    for (const row of ratingRows) {
      const notation = Number(row.notation);
      const count    = Number(row.count) || 0;
      if (!Number.isFinite(notation)) continue;
      reviewsCount += count;
      ratingSum    += notation * count;
      const key = String(notation);
      if (key in ratingBreakdown) ratingBreakdown[key] += count;
    }

    return {
      salesCount,
      productsCount,
      rating: reviewsCount > 0
        ? Math.round((ratingSum / reviewsCount) * 10) / 10
        : 0,
      reviewsCount,
      ratingBreakdown,
      followersCount,
    };
  }

  // ─────────────────────────────────────────────────────
  // MES GAINS (vendeur) — solde réel basé sur les commissions
  // calculées à chaque commande payée (voir payments.service.ts
  // → createCommission). "En attente" = Asoukaa doit encore reverser
  // ce montant au vendeur (virement/mobile money fait manuellement
  // par un admin) ; "Total retiré" = déjà reversé (commission
  // marquée "payé" par un admin, voir admin/commissions).
  // Il n'existe pas encore de retrait auto-déclenché par le vendeur
  // depuis l'appli : c'est un processus encore piloté côté back-office.
  async getMyEarnings(userId: string) {
    const vendor = await this.vendorRepo.findOne({ where: { userId } });

    if (!vendor) {
      throw new NotFoundException(
        'Aucun profil vendeur trouvé. Soumettez une demande d\'abord.'
      );
    }

    const commissions = await this.commissionRepo.find({
      where:     { vendorId: vendor.id },
      relations: ['order'],
      order:     { createdAt: 'DESC' },
    });

    const pendingAmount = commissions
      .filter((c) => c.status === CommissionStatus.PENDING)
      .reduce((sum, c) => sum + Number(c.commissionVendor), 0);

    const paidAmount = commissions
      .filter((c) => c.status === CommissionStatus.PAID)
      .reduce((sum, c) => sum + Number(c.commissionVendor), 0);

    return {
      soldeDisponible: pendingAmount,
      enAttente:       pendingAmount,
      totalRetire:     paidAmount,
      historique: commissions.slice(0, 30).map((c) => ({
        id:          c.id,
        orderNumber: c.order?.orderNumber ?? '—',
        montant:     Number(c.commissionVendor),
        statut:      c.status,
        date:        c.paidAt ?? c.createdAt,
      })),
    };
  }

  // ─────────────────────────────────────────────────────
  // FICHE BOUTIQUE PUBLIQUE (vue par un acheteur)
  // ─────────────────────────────────────────────────────
  // Remplace les anciens appels Flutter vers /api/v1/shops/:id, qui ne
  // correspondaient à AUCUNE route existante côté serveur (404
  // silencieux, rattrapé uniquement par le fallback sur les données déjà
  // en mémoire côté appli). On ne renvoie que des champs publics — ni
  // paymentDetails, ni les documents de vérification (idDocumentUrl,
  // selfieUrl), qui n'ont rien à faire devant un acheteur.
  // viewerId : utilisateur connecté qui consulte la fiche (la route est
  // protégée par JwtAuthGuard) → sert à calculer isFollowing.
  async getPublicShop(vendorId: string, viewerId?: string) {
    const vendor = await this.vendorRepo.findOne({
      where:     { id: vendorId },
      relations: ['user'],
    });

    if (
      !vendor
      || vendor.status !== VendorStatus.APPROVED
      || vendor.user?.isActive === false
    ) {
      throw new NotFoundException('Boutique introuvable');
    }

    // Boutique masquée par son vendeur (« Boutique visible » désactivé) :
    // introuvable pour tout le monde SAUF son propriétaire.
    if (vendor.shopVisible === false && vendor.userId !== viewerId) {
      throw new NotFoundException('Boutique introuvable');
    }

    // Le propriétaire qui consulte sa propre boutique ne fausse pas les
    // statistiques : pas d'incrément pour lui.
    const isOwner = !!viewerId && vendor.userId === viewerId;

    // Best-effort : un compteur de visite qui échoue à s'incrémenter ne
    // doit jamais empêcher l'affichage de la boutique.
    if (!isOwner) {
      try {
        await this.vendorRepo.increment({ id: vendorId }, 'visitCount', 1);
      } catch (error) {
        this.logger.warn(`Échec incrément visitCount vendeur ${vendorId}`, error?.message);
      }
    }

    const shopViews = await this.loadCategoryViews([vendor], true);

    return {
      id:            vendor.id,
      // ownerId : nécessaire côté app pour le bouton "Message" (créer une
      // conversation avec le vendeur) — pas de donnée sensible exposée ici,
      // juste l'id utilisateur qui sert de destinataire.
      ownerId:       vendor.userId,
      shopName:      vendor.shopName,
      shopAddress:   vendor.shopAddress,
      activityType:  vendor.activityType,
      // Catégories choisies (étiquettes) ; [] pour les anciens vendeurs.
      categoryIds:   this.categoriesOf(vendor, shopViews).map((cat) => cat.id),
      categories:    this.categoriesOf(vendor, shopViews),
      description:   vendor.description,
      logoUrl:       vendor.logoUrl,
      bannerUrl:     vendor.bannerUrl,
      visitCount:    vendor.visitCount + (isOwner ? 0 : 1),
      createdAt:     vendor.createdAt,
      // Boutique forcément approuvée ici (voir le contrôle plus haut).
      status:        vendor.status,
      // Présence du vendeur : { lastSeenAt, isOnline } uniquement.
      ...toPresence(vendor.user?.lastSeenAt),
      stats:         await this.getShopStats(vendor.id),
      // true si l'utilisateur connecté suit déjà cette boutique
      isFollowing:   viewerId
        ? await this.shopFollowRepo.exists({ where: { userId: viewerId, vendorId: vendor.id } })
        : false,
    };
  }

  // ─────────────────────────────────────────────────────
  // PRÉSENCE D'UN VENDEUR (léger, sans incrément de visite)
  // ─────────────────────────────────────────────────────
  // Mêmes règles de visibilité que getPublicShop : introuvable si le vendeur
  // n'est pas approuvé, si son compte est inactif, ou si la boutique est
  // masquée (sauf pour son propriétaire). Ne renvoie QUE
  // { lastSeenAt, isOnline }.
  async getVendorPresence(vendorId: string, viewerId?: string) {
    const vendor = await this.vendorRepo.findOne({
      where:     { id: vendorId },
      relations: ['user'],
    });

    if (
      !vendor
      || vendor.status !== VendorStatus.APPROVED
      || vendor.user?.isActive === false
    ) {
      throw new NotFoundException('Boutique introuvable');
    }

    if (vendor.shopVisible === false && vendor.userId !== viewerId) {
      throw new NotFoundException('Boutique introuvable');
    }

    return toPresence(vendor.user?.lastSeenAt);
  }

  // ─────────────────────────────────────────────────────
  // ABONNEMENTS AUX BOUTIQUES ("Suivre la boutique")
  // ─────────────────────────────────────────────────────
  // Seules les boutiques APPROUVÉES peuvent être suivies (même règle que
  // la fiche publique : une boutique en attente/rejetée/bloquée n'existe
  // pas pour un acheteur).
  private async findFollowableShop(vendorId: string, userId?: string) {
    const vendor = await this.vendorRepo.findOne({ where: { id: vendorId } });
    if (!vendor || vendor.status !== VendorStatus.APPROVED) {
      throw new NotFoundException('Boutique introuvable');
    }
    // Boutique masquée (« Boutique visible » désactivé) : introuvable,
    // sauf pour son propriétaire.
    if (vendor.shopVisible === false && vendor.userId !== userId) {
      throw new NotFoundException('Boutique introuvable');
    }
    return vendor;
  }

  private countFollowers(vendorId: string) {
    return this.shopFollowRepo.count({ where: { vendorId } });
  }

  // Statut d'abonnement de l'utilisateur courant pour une boutique.
  async getFollowStatus(userId: string, vendorId: string) {
    await this.findFollowableShop(vendorId, userId);
    const [following, followersCount] = await Promise.all([
      this.shopFollowRepo.exists({ where: { userId, vendorId } }),
      this.countFollowers(vendorId),
    ]);
    return { following, followersCount };
  }

  // Suivre une boutique — idempotent : suivre deux fois ne crée pas de
  // doublon (ON CONFLICT DO NOTHING sur la contrainte UNIQUE userId +
  // vendorId, sûr même en cas de double tap simultané).
  async followShop(userId: string, vendorId: string) {
    const vendor = await this.findFollowableShop(vendorId, userId);

    if (vendor.userId === userId) {
      throw new BadRequestException(
        'Vous ne pouvez pas suivre votre propre boutique'
      );
    }

    // Un token admin (req.user = AdminAccount) n'a pas de ligne dans
    // "users" → la clé étrangère échouerait en 500. On refuse proprement.
    const isUser = await this.userRepo.exists({ where: { id: userId } });
    if (!isUser) {
      throw new ForbiddenException(
        'Seuls les comptes utilisateurs peuvent suivre une boutique'
      );
    }

    await this.shopFollowRepo
      .createQueryBuilder()
      .insert()
      .into(ShopFollow)
      .values({ userId, vendorId })
      .orIgnore()
      .execute();

    return { following: true, followersCount: await this.countFollowers(vendorId) };
  }

  // Ne plus suivre une boutique — idempotent : aucune erreur si
  // l'utilisateur ne la suivait pas. Pas de contrôle du statut de la
  // boutique : on doit pouvoir se désabonner d'une boutique bloquée.
  async unfollowShop(userId: string, vendorId: string) {
    await this.shopFollowRepo.delete({ userId, vendorId });
    return { following: false, followersCount: await this.countFollowers(vendorId) };
  }

  // Boutiques suivies par l'utilisateur courant, plus récentes d'abord.
  // Les boutiques qui ne sont plus approuvées (bloquées…) sont masquées,
  // comme les produits inactifs dans la wishlist.
  async getFollowedShops(userId: string, page: number = 1, limit: number = 20) {
    const [follows, total] = await this.shopFollowRepo
      .createQueryBuilder('follow')
      .innerJoinAndSelect('follow.vendor', 'vendor')
      .where('follow.userId = :userId', { userId })
      .andWhere('vendor.status = :status', { status: VendorStatus.APPROVED })
      // Boutique masquée par son vendeur : n'apparaît plus.
      .andWhere('vendor.shopVisible = true')
      .orderBy('follow.createdAt', 'DESC')
      .skip((page - 1) * limit)
      .take(limit)
      .getManyAndCount();

    return {
      data: follows.map((f) => ({
        id:          f.vendor.id,
        shopName:    f.vendor.shopName,
        logoUrl:     f.vendor.logoUrl,
        bannerUrl:   f.vendor.bannerUrl,
        shopAddress: f.vendor.shopAddress,
        followedAt:  f.createdAt,
      })),
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
    };
  }

  // ─────────────────────────────────────────────────────
  // ANNUAIRE DES BOUTIQUES (GET /vendors/directory)
  // ─────────────────────────────────────────────────────
  // Uniquement les boutiques APPROUVÉES (même règle que la fiche publique :
  // en attente / rejetée / bloquée = n'existe pas pour un acheteur).
  //  - search     : ILIKE sur le nom de la boutique ;
  //  - filter     : 'verified' = boutiques dont les pièces KYC (pièce
  //                 d'identité + selfie) sont au dossier, voir
  //                 isVerifiedShop() ; 'new' = créées depuis 30 jours,
  //                 plus récentes d'abord ; 'all' = toutes ;
  //  - categoryId : boutiques ayant au moins un produit visible dans cette
  //                 catégorie OU l'une de ses sous-catégories.
  // Tri par défaut : ordre alphabétique du nom (un annuaire se parcourt
  // par nom, et l'ordre reste stable d'une page à l'autre).
  // id renvoyé = VendorProfile.id, celui qu'attendent GET
  // /vendors/:id/public et POST/DELETE /vendors/:id/follow.
  async getDirectory(
    viewerId: string | undefined,
    params: {
      search?:     string;
      filter?:     string;
      categoryId?: string;
      page:        number;
      limit:       number;
    },
  ) {
    const { page, limit } = params;
    const filter = params.filter?.trim() || 'all';

    if (!['all', 'verified', 'new'].includes(filter)) {
      throw new BadRequestException(
        'Filtre invalide. Valeurs acceptées : all, verified, new'
      );
    }

    const categoryId = params.categoryId?.trim();
    if (categoryId && !isUUID(categoryId)) {
      throw new BadRequestException('categoryId doit être un UUID');
    }

    const qb = this.vendorRepo
      .createQueryBuilder('vendor')
      // Compte désactivé par l'admin : la boutique n'est plus listée.
      .innerJoin('vendor.user', 'dirOwner', 'dirOwner.isActive = true')
      .where('vendor.status = :approved', { approved: VendorStatus.APPROVED })
      // Boutique masquée par son vendeur (« Boutique visible » désactivé) :
      // absente de l'annuaire et de sa recherche, même pour son propriétaire
      // (l'annuaire est une liste publique ; il garde sa fiche et ses produits).
      .andWhere('vendor.shopVisible = true');

    const search = params.search?.trim();
    if (search) {
      // Échappe les jokers LIKE (% et _) saisis par l'utilisateur.
      const escaped = search.replace(/[\\%_]/g, '\\$&');
      qb.andWhere('vendor.shopName ILIKE :search', { search: `%${escaped}%` });
    }

    if (filter === 'verified') {
      qb.andWhere(
        `vendor.idDocumentUrl IS NOT NULL AND vendor.idDocumentUrl <> ''`
        + ` AND vendor.selfieUrl IS NOT NULL AND vendor.selfieUrl <> ''`,
      );
    }

    if (filter === 'new') {
      const since = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
      qb.andWhere('vendor.createdAt >= :since', { since })
        .orderBy('vendor.createdAt', 'DESC');
    } else {
      qb.orderBy('vendor.shopName', 'ASC');
    }
    qb.addOrderBy('vendor.id', 'ASC'); // départage stable pour la pagination

    if (categoryId) {
      const categoryIds =
        await this.productsService.resolveCategoryIdsWithDescendants(categoryId);
      // Sous-requête EXISTS construite avec la règle de visibilité de
      // ProductsService (une seule définition de "produit visible").
      const sub = this.productRepo
        .createQueryBuilder('dirProduct')
        .select('1')
        .innerJoin('dirProduct.categories', 'dirCategory')
        .where('dirProduct.vendorId = "vendor"."id"')
        .andWhere('dirCategory.id IN (:...dirCategoryIds)', { dirCategoryIds: categoryIds });
      this.productsService.applyPublicVisibility(sub, 'dirProduct');
      qb.andWhere(`EXISTS (${sub.getQuery()})`)
        .setParameters(sub.getParameters());
    }

    const [vendors, total] = await qb
      .skip((page - 1) * limit)
      .take(limit)
      .getManyAndCount();

    const vendorIds = vendors.map((v) => v.id);
    const [previews, ratings, followed, catViews, owners] = await Promise.all([
      this.getDirectoryPreviews(vendorIds),
      this.getDirectoryRatings(vendorIds),
      viewerId && vendorIds.length
        ? this.shopFollowRepo.find({
            where:  { userId: viewerId, vendorId: In(vendorIds) },
            select: { id: true, vendorId: true },
          })
        : Promise.resolve([] as ShopFollow[]),
      // Catégories de toutes les boutiques de la page, en UNE requête.
      this.loadCategoryViews(vendors, true),
      // Dernière activité des propriétaires (présence) : UNE requête,
      // uniquement id + lastSeenAt.
      vendors.length
        ? this.userRepo.find({
            where:  { id: In(vendors.map((v) => v.userId)) },
            select: { id: true, lastSeenAt: true },
          })
        : Promise.resolve([] as User[]),
    ]);
    const followedIds = new Set(followed.map((f) => f.vendorId));
    const lastSeenByUser = new Map(owners.map((u) => [u.id, u.lastSeenAt]));

    return {
      data: vendors.map((v) => {
        const r = ratings.get(v.id);
        return {
          id:              v.id,
          shopName:        v.shopName,
          logoUrl:         v.logoUrl || null,
          zone:            this.shortZone(v.shopAddress),
          categoryIds:     this.categoriesOf(v, catViews).map((cat) => cat.id),
          categories:      this.categoriesOf(v, catViews),
          isVerified:      this.isVerifiedShop(v),
          rating:          r ? r.rating : null,
          reviewCount:     r ? r.count : 0,
          createdAt:       v.createdAt,
          isFollowing:     followedIds.has(v.id),
          // Présence du vendeur : { lastSeenAt, isOnline } uniquement.
          ...toPresence(lastSeenByUser.get(v.userId)),
          previewProducts: previews.get(v.id) ?? [],
        };
      }),
      meta: {
        total,
        page,
        limit,
        totalPages: Math.ceil(total / limit),
      },
    };
  }

  // Boutique "vérifiée" : approuvée (toujours vrai dans l'annuaire) ET
  // pièce d'identité + selfie présents au dossier. Il n'existe pas de
  // colonne dédiée de vérification KYC : ce sont ces deux pièces que
  // reviewVendor() exige avant toute approbation. Une boutique créée
  // avant cette exigence (documents rendus facultatifs par la migration
  // 1790500000000) peut être approuvée sans eux → non vérifiée.
  // ⚠️ Même définition que le filtre SQL filter=verified ci-dessus.
  private isVerifiedShop(vendor: VendorProfile): boolean {
    return !!vendor.idDocumentUrl && !!vendor.selfieUrl;
  }

  // VendorProfile n'a ni ville ni quartier : seule l'adresse libre
  // (shopAddress) existe. On la renvoie nettoyée et tronquée à 60
  // caractères pour l'affichage en carte.
  private shortZone(address: string | null | undefined): string | null {
    const clean = (address ?? '').replace(/\s+/g, ' ').trim();
    if (!clean) return null;
    return clean.length > 60 ? `${clean.slice(0, 57).trimEnd()}…` : clean;
  }

  // 3 produits visibles les plus récents par boutique, en UNE requête
  // (ROW_NUMBER par vendeur). Image = image principale, sinon la première
  // image (hors vidéo) de la galerie.
  private async getDirectoryPreviews(
    vendorIds: string[],
  ): Promise<Map<string, { id: string; name: string; imageUrl: string | null }[]>> {
    const previews = new Map<string, { id: string; name: string; imageUrl: string | null }[]>();
    if (!vendorIds.length) return previews;

    const inner = this.productRepo
      .createQueryBuilder('p')
      .select('p.id', 'id')
      .addSelect('p.vendorId', 'vendorId')
      .addSelect('p.prod_name', 'name')
      .addSelect(
        `(SELECT pi."url" FROM "product_images" pi`
        + ` WHERE pi."productId" = "p"."id" AND pi."isVideo" = false`
        + ` ORDER BY pi."isPrimary" DESC, pi."sortOrder" ASC LIMIT 1)`,
        'imageUrl',
      )
      .addSelect(
        'ROW_NUMBER() OVER (PARTITION BY "p"."vendorId" ORDER BY "p"."createdAt" DESC)',
        'rn',
      )
      .where('p.vendorId IN (:...vendorIds)', { vendorIds });
    this.productsService.applyPublicVisibility(inner, 'p');

    const [sql, sqlParams] = inner.getQueryAndParameters();
    const rows: { id: string; vendorId: string; name: string; imageUrl: string | null; rn: string }[] =
      await this.productRepo.manager.query(
        `SELECT * FROM (${sql}) "ranked" WHERE "ranked"."rn" <= 3 ORDER BY "ranked"."rn" ASC`,
        sqlParams,
      );

    for (const row of rows) {
      const list = previews.get(row.vendorId) ?? [];
      list.push({ id: row.id, name: row.name, imageUrl: row.imageUrl ?? null });
      previews.set(row.vendorId, list);
    }
    return previews;
  }

  // Note moyenne des avis APPROUVÉS sur les produits de chaque boutique
  // (même calcul que getShopStats → fiche boutique), arrondie à 0,1.
  private async getDirectoryRatings(
    vendorIds: string[],
  ): Promise<Map<string, { rating: number; count: number }>> {
    const ratings = new Map<string, { rating: number; count: number }>();
    if (!vendorIds.length) return ratings;

    const rows: { vendorId: string; avg: string; count: string }[] = await this.reviewRepo
      .createQueryBuilder('review')
      .innerJoin('review.product', 'product')
      .select('product.vendorId', 'vendorId')
      .addSelect('AVG(review.notation)', 'avg')
      .addSelect('COUNT(review.id)', 'count')
      .where('product.vendorId IN (:...vendorIds)', { vendorIds })
      .andWhere('review.status = :reviewStatus', { reviewStatus: ReviewStatus.APPROVED })
      .groupBy('product.vendorId')
      .getRawMany();

    for (const row of rows) {
      const count = Number(row.count) || 0;
      const avg   = Number(row.avg);
      if (count > 0 && Number.isFinite(avg)) {
        ratings.set(row.vendorId, { rating: Math.round(avg * 10) / 10, count });
      }
    }
    return ratings;
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
    if (dto.categoryIds !== undefined) {
      // Catégories de la plateforme : prioritaires, activityType re-dérivé.
      const activity = await this.validateCategoryIds(dto.categoryIds);
      vendor.categoryIds  = activity.categoryIds;
      vendor.activityType = activity.activityType;
    } else if (dto.activityType && dto.activityType !== vendor.activityType) {
      // Ancien client : texte libre modifié → il devient la référence.
      // (Texte inchangé = on garde les catégories choisies.)
      vendor.activityType = dto.activityType.slice(0, 100);
      vendor.categoryIds  = [];
    }
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
    const updViews = await this.loadCategoryViews([vendor], false);
    return {
      ...vendorSafe,
      categoryIds:          vendor.categoryIds ?? [],
      categories:           this.categoriesOf(vendor, updViews),
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
    // 🔒 Chiffrer les données bancaires sensibles
    vendor.paymentDetails = this.encryptionService.encrypt(paymentDetails);
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
        'vendor.categoryIds',
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
    const listViews = await this.loadCategoryViews(vendors, false);

    return {
      data:  vendors.map((v) => ({ ...v, categories: this.categoriesOf(v, listViews) })),
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
    const detailViews = await this.loadCategoryViews([vendor], false);

    // ⚠️ Liste blanche : ni passwordHash, ni jetons de sécurité, ni
    // invitationToken de l'admin relecteur ne doivent sortir d'ici.
    const u = vendor.user;
    const r = vendor.reviewedBy;

    return {
      ...vendorSafe,
      user: u
        ? {
            id:         u.id,
            prenom:     u.prenom,
            name:       u.name,
            email:      u.email,
            phone:      u.phone,
            avatarUrl:  u.avatarUrl,
            isVerified: u.isVerified,
            isActive:   u.isActive,
            createdAt:  u.createdAt,
          }
        : null,
      reviewedBy: r
        ? { id: r.id, prenom: r.prenom, name: r.name, email: r.email }
        : null,
      categories:           this.categoriesOf(vendor, detailViews),
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
      if (!vendor.idDocumentUrl || !vendor.selfieUrl || !vendor.sampleProductUrls?.length) {
        throw new BadRequestException(
          "Impossible d'approuver : il manque des documents (pièce d'identité, selfie ou photos produits)"
        );
      }

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
    } else {
      // REJECT
      vendor.status     = VendorStatus.REJECTED;
      vendor.motifRefus = dto.rejectionReason ?? null;
    }

    // ⚠️ On persiste le statut AVANT l'envoi de l'email : un échec SMTP ne
    // doit jamais laisser le vendeur dans un état incohérent (rôle attribué
    // mais statut resté "en attente").
    vendor.reviewedById = adminId;
    vendor.reviewedAt   = new Date();
    await this.vendorRepo.save(vendor);

    // Email de notification — best-effort : une erreur d'envoi ne doit pas
    // faire échouer l'action d'approbation/refus elle-même.
    //
    // ⚠️ Avant ce correctif, ces deux emails étaient envoyés en HTML brut,
    // fait main, sans passer par MailService / renderEmailLayout comme
    // TOUS les autres emails de l'app (commande, livraison, OTP...). Résultat :
    // un email sans le moindre habillage, affiché comme du texte simple par
    // les clients mail. vendorApprovedTemplate/vendorRejectedTemplate
    // existaient déjà tous les deux dans templates/ mais n'étaient jamais
    // appelés depuis ici — seul mail.service.ts les utilisait, et rien
    // n'appelait mail.service.ts pour ce cas précis.
    try {
      if (dto.action === VendorReviewAction.APPROVE) {
        await this.mailService.sendVendorApproved(
          vendor.user.email,
          vendor.user.prenom,
          vendor.shopName,
        );
      } else {
        await this.mailService.sendVendorRejected(
          vendor.user.email,
          vendor.user.prenom,
          vendor.shopName,
          dto.rejectionReason ?? '',
        );
      }
    } catch (error) {
      this.logger.error(
        `Échec envoi mail de revue vendeur → ${vendor.user.email}`,
        error?.message,
      );
    }

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

    // Notifier le vendeur par email (best-effort)
    try {
      await this.mailService.sendVendorBlocked(
        vendor.user.email,
        vendor.user.prenom,
        vendor.shopName,
      );
    } catch (error) {
      this.logger.error(
        `Échec envoi mail de blocage vendeur → ${vendor.user.email}`,
        error?.message,
      );
    }

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
  // ADMIN — DÉBLOQUER UN VENDEUR
  // ─────────────────────────────────────────────────────
  async unblockVendor(
    vendorId: string,
    adminId:  string,
    ip:       string,
  ) {
    const vendor = await this.vendorRepo.findOne({
      where:     { id: vendorId },
      relations: ['user'],
    });

    if (!vendor) throw new NotFoundException('Profil vendeur introuvable');

    if (vendor.status !== VendorStatus.BLOCKED) {
      throw new BadRequestException("Ce vendeur n'est pas bloqué");
    }

    const oldStatus     = vendor.status;
    // Un vendeur ne pouvait être bloqué que s'il avait déjà été approuvé
    // (seul un compte VENDOR actif peut opérer) — le débloquer le restaure
    // donc dans l'état APPROUVÉ, prêt à reprendre son activité.
    vendor.status        = VendorStatus.APPROVED;
    vendor.reviewedById  = adminId;
    vendor.reviewedAt    = new Date();

    // Réactiver le rôle VENDOR
    await this.userRoleRepo.update(
      { userId: vendor.userId, role: UserRoleEnum.VENDOR },
      { isActive: true },
    );

    await this.vendorRepo.save(vendor);

    try {
      await this.mailService.sendVendorUnblocked(
        vendor.user.email,
        vendor.user.prenom,
        vendor.shopName,
      );
    } catch (error) {
      this.logger.error(
        `Échec envoi mail de déblocage vendeur → ${vendor.user.email}`,
        error?.message,
      );
    }

    await this.logService.log({
      actorId:    adminId,
      actorType:  ActorType.ADMIN,
      action:     LogAction.VENDOR_UNBLOCKED,
      entityType: 'vendor_profile',
      entityId:   vendorId,
      oldValue:   { status: oldStatus },
      newValue:   { status: VendorStatus.APPROVED },
      ipAddress:  ip,
    });

    return { message: 'Boutique débloquée avec succès' };
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — LISTE DES DEMANDES EN ATTENTE
  // (optimisé pour le dashboard)
  // ─────────────────────────────────────────────────────
  async getPendingVendors() {
    const pending = await this.vendorRepo
      .createQueryBuilder('vendor')
      .leftJoin('vendor.user', 'user')
      .select([
        'vendor.id',
        'vendor.shopName',
        'vendor.activityType',
        'vendor.categoryIds',
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

    const pendingViews = await this.loadCategoryViews(pending, false);
    return pending.map((v) => ({ ...v, categories: this.categoriesOf(v, pendingViews) }));
  }
}
