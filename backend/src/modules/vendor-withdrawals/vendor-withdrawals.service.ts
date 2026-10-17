import {
  Injectable,
  Logger,
  NotFoundException,
  BadRequestException,
  ForbiddenException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import {
  Repository,
  FindOptionsWhere,
  FindManyOptions,
  DataSource,
  EntityManager,
} from 'typeorm';
import {
  VendorWithdrawal,
  VendorWithdrawalStatus,
} from './entities/vendor-withdrawal.entity';
import {
  VendorProfile,
  VendorStatus,
  PaymentMethod as VendorPaymentMethod,
} from '../users/entities/vendor-profile.entity';
import { User } from '../users/entities/user.entity';
import { Order, OrderStatus } from '../orders/entities/order.entity';
import {
  Commission,
  CommissionStatus,
} from '../payments/entities/commission.entity';
import { VendorEarningAdjustment } from '../payments/entities/vendor-earning-adjustment.entity';
import { CreateWithdrawalDto } from './dto/create-withdrawal.dto';
import { MarkWithdrawalPaidDto } from './dto/mark-withdrawal-paid.dto';
import { RejectWithdrawalDto } from './dto/reject-withdrawal.dto';
import { ActivityLogService } from '../../common/services/activity-log.service';
import { EncryptionService } from '../../common/services/encryption.service';
import { MailService } from '../mail/mail.service';
import {
  ActorType,
  LogAction,
  LogResult,
} from '../../common/entities/activity-log.entity';
import { clampLimit, clampPage } from '../../common/utils/pagination.util';
import { stripSecrets } from '../../common/utils/strip-secrets.util';

export interface VendorWithdrawalFilters {
  vendorId?: string;
  status?: VendorWithdrawalStatus;
  page?: number;
  limit?: number;
}

// Solde retirable d'un vendeur, recalcule a chaque appel.
export interface VendorBalance {
  gainsBruts:      number; // (total - montantCommission) sur les commandes LIVREES
  totalPaye:       number; // retraits deja verses par l'admin
  totalEnAttente:  number; // retraits demandes mais pas encore verses
  soldeDisponible: number; // gainsBruts - totalPaye - totalEnAttente
  minWithdrawalAmount: number; // quota minimum fixe par l'admin (0 = aucun)
  aUneDemandeEnAttente: boolean;
  // ── Reprises liées aux remboursements clients (ajoutés, rien de renommé) ──
  // Total repris sur les gains du vendeur suite à des remboursements clients
  // approuvés (voir PaymentsService.processRefund / vendor_earning_adjustments).
  reprisesRemboursements: number;
  // Dette envers la plateforme (>= 0) : positive quand les reprises dépassent
  // ce que le vendeur avait encore en caisse (il avait déjà retiré l'argent).
  // soldeDisponible reste TOUJOURS >= 0 ; la dette est exposée à part et
  // se rembourse toute seule sur les prochains gains. Tant qu'elle est > 0,
  // aucun nouveau retrait n'est possible.
  dette: number;
  // Phrase française prête à afficher (null quand dette = 0).
  messageDette: string | null;
}

// Meme esprit que DeliveryEarningsService (delivery-earnings/) cote livreur :
// un montant du, un statut payé/non payé, et une action admin
// "marquer comme payé (virement effectue)".
//
// Difference majeure : le solde du vendeur n'est PAS une somme de lignes
// deja calculees en base, il est recalcule a partir des commandes. Voir
// getBalance() ci-dessous pour la formule exacte.
@Injectable()
export class VendorWithdrawalsService {
  private readonly logger = new Logger(VendorWithdrawalsService.name);

  constructor(
    @InjectRepository(VendorWithdrawal)
    private withdrawalRepo: Repository<VendorWithdrawal>,
    @InjectRepository(VendorProfile)
    private vendorRepo: Repository<VendorProfile>,
    @InjectRepository(Commission)
    private readonly commissionRepo: Repository<Commission>,

    @InjectRepository(Order)
    private orderRepo: Repository<Order>,
    @InjectRepository(VendorEarningAdjustment)
    private readonly adjustmentRepo: Repository<VendorEarningAdjustment>,
    private logService: ActivityLogService,
    private readonly dataSource: DataSource,
    private readonly encryptionService: EncryptionService,
    private readonly mailService: MailService,
  ) {}

  // ─────────────────────────────────────────────────────
  // Resolution du vendeur connecte
  // ─────────────────────────────────────────────────────
  // On ne fait JAMAIS confiance a un vendorId envoye par le client : on part
  // de l'id utilisateur du token et on retrouve SON profil vendeur.
  private async getVendorByUserId(userId: string): Promise<VendorProfile> {
    const vendor = await this.vendorRepo.findOne({ where: { userId } });

    if (!vendor) {
      throw new NotFoundException(
        'Aucun profil vendeur trouvé. Soumettez une demande d\'abord.',
      );
    }

    return vendor;
  }

  // ─────────────────────────────────────────────────────
  // CALCUL DU SOLDE — le coeur de la fonctionnalite
  // ─────────────────────────────────────────────────────
  //   gainsBruts      = SUM(total - montantCommission) sur les commandes de
  //                     ce vendeur au statut OrderStatus.DELIVERED ('livré')
  //   - totalPaye     = SUM(montant) des retraits deja payés
  //   - totalEnAttente= SUM(montant) des retraits encore en attente
  //   = soldeDisponible
  //
  // Pourquoi deduire aussi les demandes EN ATTENTE : sans ca, un vendeur
  // pourrait demander deux fois le meme argent avant que l'admin ait eu le
  // temps de virer la premiere demande.
  // Les retraits rejetés ne sont PAS deduits : l'argent n'est jamais parti.
  //
  // Une commande payée mais pas encore livrée ne compte pas : elle peut
  // encore etre annulée ou remboursée.
  //
  // ATTENTION : Postgres renvoie les colonnes `decimal` sous forme de
  // CHAINES via TypeORM ("4.50"), d'ou les Number(...) systematiques.
  async getBalance(userId: string): Promise<VendorBalance> {
    const vendor = await this.getVendorByUserId(userId);
    return this.computeBalance(vendor);
  }

  // Même calcul à partir de l'id de la FICHE vendeur (utilisé par
  // PaymentsService après un remboursement, pour savoir si le vendeur est
  // en dette). Renvoie null si la fiche n'existe pas.
  async getBalanceByVendorId(
    vendorId: string,
    manager?: EntityManager,
  ): Promise<VendorBalance | null> {
    const vendor = manager
      ? await manager.findOne(VendorProfile, { where: { id: vendorId } })
      : await this.vendorRepo.findOne({ where: { id: vendorId } });
    if (!vendor) return null;
    return this.computeBalance(vendor, manager);
  }

  // `manager` : à passer quand le calcul se fait DANS une transaction (création
  // d'une demande de retrait, sous verrou) pour lire avec la même connexion.
  private async computeBalance(
    vendor: VendorProfile,
    manager?: EntityManager,
  ): Promise<VendorBalance> {
    const commissionRepo = manager
      ? manager.getRepository(Commission)
      : this.commissionRepo;
    const withdrawalRepo = manager
      ? manager.getRepository(VendorWithdrawal)
      : this.withdrawalRepo;
    const adjustmentRepo = manager
      ? manager.getRepository(VendorEarningAdjustment)
      : this.adjustmentRepo;

    // ⚠️ SOURCE DE VERITE DES GAINS : la table `commissions`, PAS
    // `orders.total - orders.montantCommission`.
    //
    // `orders.montantCommission` est ecrit en dur a 0 a la creation de la
    // commande (voir OrdersService, « calculé au paiement ») et n'est JAMAIS
    // renseigne ensuite : la vraie commission vit dans l'entite Commission,
    // creee au paiement par PaymentsService.createCommission(), ou
    // `commissionVendor` = ce qui revient au vendeur, commission deduite.
    // Partir de `orders` revenait donc a ne rien deduire du tout et a
    // promettre au vendeur 100 % du montant de la commande.
    //
    // C'est aussi la source utilisee par VendorsService.getMyEarnings
    // (ecran profil vendeur), qui lui DELEGUE soldeDisponible, dette,
    // messageDette et reprisesRemboursements via getBalance() : les deux
    // ecrans affichent le meme chiffre.
    const [brutRow, reverseRow, paidRow, pendingRow, pendingCount, repriseRow] = await Promise.all([
      commissionRepo
        .createQueryBuilder('c')
        .innerJoin('c.order', 'o')
        .select('COALESCE(SUM(c.commissionVendor), 0)', 'sum')
        .where('c.vendorId = :vendorId', { vendorId: vendor.id })
        .andWhere('o.status = :status', { status: OrderStatus.DELIVERED })
        .getRawOne<{ sum: string }>(),
      // Montants deja reverses par l'ancien circuit « Commissions » de
      // l'admin (CommissionStatus.PAID = « montant reversé au vendeur »).
      // Sans cette soustraction, un vendeur deja paye par ce circuit
      // pourrait redemander le meme argent en retrait : on paierait deux
      // fois. Tant que les deux circuits coexistent, on retranche les deux.
      commissionRepo
        .createQueryBuilder('c')
        .innerJoin('c.order', 'o')
        .select('COALESCE(SUM(c.commissionVendor), 0)', 'sum')
        .where('c.vendorId = :vendorId', { vendorId: vendor.id })
        .andWhere('o.status = :status', { status: OrderStatus.DELIVERED })
        .andWhere('c.status = :cstatus', { cstatus: CommissionStatus.PAID })
        .getRawOne<{ sum: string }>(),
      withdrawalRepo
        .createQueryBuilder('w')
        .select('COALESCE(SUM(w.montant), 0)', 'sum')
        .where('w.vendorId = :vendorId', { vendorId: vendor.id })
        .andWhere('w.status = :status', {
          status: VendorWithdrawalStatus.PAID,
        })
        .getRawOne<{ sum: string }>(),
      withdrawalRepo
        .createQueryBuilder('w')
        .select('COALESCE(SUM(w.montant), 0)', 'sum')
        .where('w.vendorId = :vendorId', { vendorId: vendor.id })
        .andWhere('w.status = :status', {
          status: VendorWithdrawalStatus.PENDING,
        })
        .getRawOne<{ sum: string }>(),
      withdrawalRepo.count({
        where: {
          vendorId: vendor.id,
          status: VendorWithdrawalStatus.PENDING,
        },
      }),
      // Reprises sur gains suite à un remboursement client approuvé : une
      // ligne par remboursement dans vendor_earning_adjustments (0 pour une
      // commande qui n'avait jamais été livrée : rien à reprendre).
      adjustmentRepo
        .createQueryBuilder('a')
        .select('COALESCE(SUM(a.montantVendeur), 0)', 'sum')
        .where('a.vendorId = :vendorId', { vendorId: vendor.id })
        .getRawOne<{ sum: string }>(),
    ]);

    const gainsBruts     = this.round2(Number(brutRow?.sum ?? 0));
    const dejaReverse    = this.round2(Number(reverseRow?.sum ?? 0));
    const totalPaye      = this.round2(
      Number(paidRow?.sum ?? 0) + dejaReverse,
    );
    const totalEnAttente = this.round2(Number(pendingRow?.sum ?? 0));

    const reprises = this.round2(Number(repriseRow?.sum ?? 0));

    // Valeur INTERNE, qui peut etre negative : gains - reprises - deja verse
    // - en attente. Negative = le vendeur a deja retire de l'argent qui a
    // ensuite ete rendu au client (une « dette » envers la plateforme).
    const soldeInterne = this.round2(
      gainsBruts - reprises - totalPaye - totalEnAttente,
    );

    // Jamais de solde negatif brut expose au vendeur : `soldeDisponible` est
    // borne a 0 et la dette est donnee a part (`dette` >= 0, avec un message
    // explicatif). Elle diminue toute seule quand de nouveaux gains arrivent.
    const soldeDisponible = this.round2(Math.max(0, soldeInterne));
    const dette           = this.round2(Math.max(0, -soldeInterne));

    return {
      gainsBruts,
      totalPaye,
      totalEnAttente,
      soldeDisponible,
      minWithdrawalAmount: this.round2(
        Number(vendor.minWithdrawalAmount ?? 0),
      ),
      aUneDemandeEnAttente: pendingCount > 0,
      reprisesRemboursements: reprises,
      dette,
      messageDette: dette > 0 ? this.debtMessage(dette) : null,
    };
  }

  private debtMessage(dette: number): string {
    const montant = dette
      .toLocaleString('fr-FR', { maximumFractionDigits: 2 })
      .replace(/[\u202f\u00a0]/g, ' ');
    return (
      `Un remboursement client a été déduit de vos gains alors que vous aviez `
      + `déjà retiré cet argent : vous avez une dette de ${montant} FCFA envers `
      + `la plateforme. Elle sera déduite automatiquement de vos prochains `
      + `gains. Les retraits sont suspendus tant qu'elle n'est pas couverte.`
    );
  }

  private round2(value: number): number {
    if (!Number.isFinite(value)) return 0;
    return Math.round(value * 100) / 100;
  }

  // ─────────────────────────────────────────────────────
  // VENDEUR : creer une demande de retrait
  // ─────────────────────────────────────────────────────
  async createWithdrawal(
    userId: string,
    dto: CreateWithdrawalDto,
    ipAddress?: string,
  ) {
    const montant = this.round2(Number(dto.montant));

    if (!Number.isFinite(montant) || montant <= 0) {
      throw new BadRequestException('Le montant doit être supérieur à 0');
    }

    const paymentMethod = dto.paymentMethod.trim();
    const mobileNumber  = dto.mobileNumber.trim();

    const vendorLookup = await this.getVendorByUserId(userId);

    // ⚠️ Tout se passe dans UNE transaction, sous verrou sur la fiche vendeur :
    // deux demandes simultanées (double clic, renvoi réseau) font la queue ;
    // la seconde relit le solde et voit la demande de la première.
    // Avant : lecture du solde puis écriture sans verrou -> deux demandes
    // pouvaient être créées pour le même argent.
    let created: {
      withdrawal: VendorWithdrawal;
      vendor: VendorProfile;
      previousNumber: string | null;
    };
    try {
      created = await this.dataSource.transaction(async (manager) => {
        // Verrou de ligne (SELECT ... FOR UPDATE) sur la fiche vendeur.
        await manager.query(
          'SELECT "id" FROM "vendor_profiles" WHERE "id" = $1 FOR UPDATE',
          [vendorLookup.id],
        );

        // Relire la fiche SOUS verrou (statut, minimum, coordonnées à jour).
        const vendor = await manager.findOne(VendorProfile, {
          where: { id: vendorLookup.id },
        });
        if (!vendor) {
          throw new NotFoundException('Aucun profil vendeur trouvé.');
        }

        // Seul un vendeur approuvé peut retirer de l'argent (un vendeur
        // bloqué, rejeté ou en attente de validation ne le peut pas).
        if (vendor.status !== VendorStatus.APPROVED) {
          throw new ForbiddenException(
            'Votre boutique doit être approuvée pour demander un retrait.',
          );
        }

        // Le solde disponible déduit déjà les retraits payés ET les demandes
        // en attente (voir computeBalance).
        const balance = await this.computeBalance(vendor, manager);

        // Dette suite a un remboursement client : aucun nouveau retrait tant
        // qu'elle n'est pas couverte par de nouveaux gains.
        if (balance.dette > 0) {
          throw new BadRequestException(
            balance.messageDette ?? 'Retrait impossible : vous avez une dette.',
          );
        }

        // Une seule demande en attente a la fois : plus simple a suivre pour
        // l'admin, et ca evite les doubles demandes sur le meme solde.
        if (balance.aUneDemandeEnAttente) {
          throw new BadRequestException(this.PENDING_EXISTS_MESSAGE);
        }

        // Quota minimum propre a CE vendeur (0 = aucun minimum)
        if (
          balance.minWithdrawalAmount > 0
          && montant < balance.minWithdrawalAmount
        ) {
          throw new BadRequestException(
            `Le montant minimum de retrait fixé pour votre boutique est de `
            + `${balance.minWithdrawalAmount} FCFA.`,
          );
        }

        if (montant > balance.soldeDisponible) {
          throw new BadRequestException(
            `Montant supérieur à votre solde disponible `
            + `(${balance.soldeDisponible} FCFA).`,
          );
        }

        // Numéro du dernier retrait (avant celui-ci), pour l'alerte de changement.
        const last = await manager.findOne(VendorWithdrawal, {
          where: { vendorId: vendor.id },
          order: { createdAt: 'DESC' },
        });

        const withdrawal = manager.create(VendorWithdrawal, {
          vendorId:      vendor.id,
          montant,
          status:        VendorWithdrawalStatus.PENDING,
          paymentMethod,
          mobileNumber,
          noteAdmin:     null,
          paidAt:        null,
          processedById: null,
        });
        const saved = await manager.save(withdrawal);

        return {
          withdrawal: saved,
          vendor,
          previousNumber: last?.mobileNumber ?? null,
        };
      });
    } catch (err: any) {
      // Filet de sécurité : l'index unique « une seule demande en attente »
      // (UQ_vendor_withdrawals_one_pending) a refusé l'insertion.
      if (
        err?.code === '23505'
        || err?.driverError?.code === '23505'
      ) {
        throw new BadRequestException(this.PENDING_EXISTS_MESSAGE);
      }
      throw err;
    }

    // Alerte « numéro inhabituel » : jamais bloquante, jamais attendue.
    void this.alertIfUnusualNumber({
      userId,
      vendor:         created.vendor,
      withdrawal:     created.withdrawal,
      previousNumber: created.previousNumber,
      ipAddress,
    }).catch((e) =>
      this.logger.error(`Alerte numéro de retrait impossible : ${e?.message}`),
    );

    // Pas de ligne ActivityLog "demande de retrait" : la ligne
    // vendor_withdrawals porte vendorId + createdAt. Seules les DECISIONS
    // admin et les ALERTES (numéro inhabituel) sont loguées.
    return {
      demande: created.withdrawal,
      solde:   await this.computeBalance(created.vendor),
    };
  }

  private readonly PENDING_EXISTS_MESSAGE =
    'Vous avez déjà une demande de retrait en attente. '
    + 'Attendez son traitement avant d\'en créer une nouvelle.';

  // ─────────────────────────────────────────────────────
  // ALERTE : retrait vers un numéro Mobile Money inhabituel
  // ─────────────────────────────────────────────────────
  // Protège contre le vol de compte (le numéro est libre à chaque demande :
  // on ne bloque PAS le flux, on prévient). Un numéro est « inhabituel » s'il
  // diffère du numéro du dernier retrait OU de celui enregistré sur la fiche
  // (quand ils existent). Action : ligne dans le journal d'activité + e-mail
  // d'information au vendeur, numéro masqué sauf ses 4 derniers chiffres.
  private async alertIfUnusualNumber(args: {
    userId: string;
    vendor: VendorProfile;
    withdrawal: VendorWithdrawal;
    previousNumber: string | null;
    ipAddress?: string;
  }): Promise<void> {
    const { userId, vendor, withdrawal, previousNumber, ipAddress } = args;

    let profileNumber: string | null = null;
    if (
      vendor.paymentMethod === VendorPaymentMethod.MOBILE_MONEY
      && vendor.paymentDetails
    ) {
      try {
        const details = this.encryptionService.decrypt(vendor.paymentDetails);
        if (details?.number) profileNumber = String(details.number);
      } catch {
        profileNumber = null; // fiche illisible : on compare seulement au dernier retrait
      }
    }

    const newKey = this.phoneKey(withdrawal.mobileNumber);
    const differsFromLast =
      !!previousNumber && this.phoneKey(previousNumber) !== newKey;
    const differsFromProfile =
      !!profileNumber && this.phoneKey(profileNumber) !== newKey;

    if (!differsFromLast && !differsFromProfile) return;

    const maskedNew = this.maskPhone(withdrawal.mobileNumber);

    await this.logService.log({
      actorId:    userId,
      actorType:  ActorType.VENDOR,
      action:     LogAction.VENDOR_WITHDRAWAL_NUMBER_ALERT,
      entityType: 'VendorWithdrawal',
      entityId:   withdrawal.id,
      oldValue:   {
        numeroDernierRetrait: previousNumber ? this.maskPhone(previousNumber) : null,
        numeroFiche:          profileNumber ? this.maskPhone(profileNumber) : null,
      },
      newValue:   {
        nouveauNumero: maskedNew,
        operateur:     withdrawal.paymentMethod,
        montant:       Number(withdrawal.montant),
        differeDuDernierRetrait: differsFromLast,
        differeDeLaFiche:        differsFromProfile,
      },
      ipAddress,
    });

    const user = await this.dataSource
      .getRepository(User)
      .findOne({ where: { id: userId }, select: ['id', 'email', 'prenom'] });
    if (!user?.email) return;

    await this.mailService.sendWithdrawalNumberAlert(user.email, {
      prenom:           user.prenom ?? '',
      montant:          Number(withdrawal.montant),
      operateur:        withdrawal.paymentMethod,
      maskedNumber:     maskedNew,
      requestedAtLabel: new Date().toLocaleString('fr-FR', {
        timeZone: 'Africa/Porto-Novo',
        dateStyle: 'long',
        timeStyle: 'short',
      }),
    });
  }

  // Clé de comparaison de numéros : chiffres seulement, 8 derniers chiffres
  // (« +229 01 96 78 20 26 », « 0196782026 » et « 96782026 » = même numéro).
  private phoneKey(value: string): string {
    const digits = String(value ?? '').replace(/\D/g, '');
    return digits.length > 8 ? digits.slice(-8) : digits;
  }

  // Masque tout sauf les 4 derniers chiffres : « 0196782026 » -> « ******2026 ».
  private maskPhone(value: string): string {
    const digits = String(value ?? '').replace(/\D/g, '');
    if (digits.length <= 4) return '****';
    return '*'.repeat(digits.length - 4) + digits.slice(-4);
  }

  // ─────────────────────────────────────────────────────
  // VENDEUR : mon solde + mes gains
  // ─────────────────────────────────────────────────────
  async getMyEarnings(userId: string) {
    const vendor  = await this.getVendorByUserId(userId);
    const balance = await this.computeBalance(vendor);

    const nbCommandesLivrees = await this.orderRepo.count({
      where: { vendorId: vendor.id, status: OrderStatus.DELIVERED },
    });

    return {
      vendorId:  vendor.id,
      shopName:  vendor.shopName,
      ...balance,
      nbCommandesLivrees,
    };
  }

  // ─────────────────────────────────────────────────────
  // VENDEUR : historique de MES demandes
  // ─────────────────────────────────────────────────────
  async getMyWithdrawals(
    userId: string,
    page?: number | string,
    limit?: number | string,
  ) {
    const vendor     = await this.getVendorByUserId(userId);
    const safePage   = clampPage(page);
    const safeLimit  = clampLimit(limit);

    const [rows, total] = await this.withdrawalRepo.findAndCount({
      where: { vendorId: vendor.id },
      order: { createdAt: 'DESC' },
      skip:  (safePage - 1) * safeLimit,
      take:  safeLimit,
    });

    return {
      data: rows.map((w) => ({
        id:            w.id,
        montant:       Number(w.montant),
        status:        w.status,
        paymentMethod: w.paymentMethod,
        mobileNumber:  w.mobileNumber,
        noteAdmin:     w.noteAdmin,
        createdAt:     w.createdAt,
        paidAt:        w.paidAt,
      })),
      pagination: {
        total,
        page:  safePage,
        limit: safeLimit,
        pages: Math.ceil(total / safeLimit),
      },
    };
  }

  // ─────────────────────────────────────────────────────
  // ADMIN : lister / consulter
  // ─────────────────────────────────────────────────────
  async getAll(filters: VendorWithdrawalFilters = {}) {
    const { vendorId, status } = filters;
    const page  = clampPage(filters.page);
    const limit = clampLimit(filters.limit);

    const where: FindOptionsWhere<VendorWithdrawal> = {};
    if (vendorId) where.vendorId = vendorId;
    if (status)   where.status   = status;

    const options: FindManyOptions<VendorWithdrawal> = {
      where,
      relations: ['vendor', 'vendor.user', 'processedBy'],
      order: { createdAt: 'DESC' },
      skip: (page - 1) * limit,
      take: limit,
    };

    const [rows, total] = await this.withdrawalRepo.findAndCount(options);

    return {
      data: stripSecrets(rows),
      pagination: {
        total,
        page,
        limit,
        pages: Math.ceil(total / limit),
      },
    };
  }

  private async findOrFail(id: string) {
    const withdrawal = await this.withdrawalRepo.findOne({
      where: { id },
      relations: ['vendor', 'vendor.user', 'processedBy'],
    });

    if (!withdrawal) {
      throw new NotFoundException(`Demande de retrait ${id} introuvable`);
    }

    return withdrawal;
  }

  // ─────────────────────────────────────────────────────
  // ADMIN : marquer comme payé (virement deja effectue a la main)
  // ─────────────────────────────────────────────────────
  // ⚠️ AUCUN appel a une API de paiement sortant ici : l'admin a fait le
  // virement Mobile Money par ses propres moyens, on ne fait qu'enregistrer
  // la confirmation. Exactement le fonctionnement de
  // DeliveryEarningsService.markAsPaid.
  // Version destinée à l'API (route admin) : sans champs secrets des comptes
  // chargés en relation (user, processedBy...). Les méthodes internes qui
  // modifient puis ENREGISTRENT l'entité utilisent findOrFail (entité brute).
  async getById(id: string) {
    return stripSecrets(await this.findOrFail(id));
  }

  async markAsPaid(
    id: string,
    dto: MarkWithdrawalPaidDto,
    processedById: string,
    ipAddress?: string,
  ) {
    const withdrawal = await this.findOrFail(id);

    if (withdrawal.status !== VendorWithdrawalStatus.PENDING) {
      throw new BadRequestException(
        `Cette demande est déjà au statut "${withdrawal.status}"`,
      );
    }

    const ancienStatut = withdrawal.status;

    withdrawal.status        = VendorWithdrawalStatus.PAID;
    withdrawal.paidAt        = new Date();
    withdrawal.processedById = processedById;
    withdrawal.noteAdmin     = dto?.noteAdmin?.trim() || null;

    const updated = await this.withdrawalRepo.save(withdrawal);

    await this.logService.log({
      actorId:    processedById,
      actorType:  ActorType.ADMIN,
      action:     LogAction.PAYMENT_SUCCESS,
      entityType: 'VendorWithdrawal',
      entityId:   id,
      oldValue:   { status: ancienStatut, paidAt: null },
      newValue:   {
        status:  VendorWithdrawalStatus.PAID,
        paidAt:  updated.paidAt,
        montant: Number(updated.montant),
      },
      ipAddress,
    });

    // Information pour l'admin : si, une fois ce retrait versé, les reprises
    // pour remboursements clients dépassent le solde du vendeur, il est en
    // dette (champ AJOUTÉ à la réponse ; 0 dans le cas normal).
    let detteVendeur = 0;
    try {
      const vendorForBalance = withdrawal.vendor
        ?? (await this.vendorRepo.findOne({ where: { id: withdrawal.vendorId } }));
      if (vendorForBalance) {
        detteVendeur = (await this.computeBalance(vendorForBalance)).dette;
      }
    } catch (e: any) {
      this.logger.warn(`Calcul de dette impossible après paiement : ${e?.message}`);
    }

    return { ...stripSecrets(updated), detteVendeur };
  }

  // ─────────────────────────────────────────────────────
  // ADMIN : rejeter une demande (motif obligatoire)
  // ─────────────────────────────────────────────────────
  // Le montant retourne automatiquement dans le solde disponible du
  // vendeur, puisque seuls les retraits "en attente" et "payé" sont deduits
  // dans computeBalance().
  async reject(
    id: string,
    dto: RejectWithdrawalDto,
    processedById: string,
    ipAddress?: string,
  ) {
    const withdrawal = await this.findOrFail(id);

    if (withdrawal.status !== VendorWithdrawalStatus.PENDING) {
      throw new BadRequestException(
        `Cette demande est déjà au statut "${withdrawal.status}"`,
      );
    }

    const ancienStatut = withdrawal.status;

    withdrawal.status        = VendorWithdrawalStatus.REJECTED;
    withdrawal.noteAdmin     = dto.motif.trim();
    withdrawal.processedById = processedById;
    withdrawal.paidAt        = null;

    const updated = await this.withdrawalRepo.save(withdrawal);

    // ⚠️ LogAction n'a pas (encore) de valeur dediee aux retraits vendeurs,
    // et en ajouter une imposerait un ALTER TYPE sur l'enum Postgres de
    // activity_logs. On reutilise donc PAYMENT_FAILED + result FAILURE :
    // du point de vue du vendeur, le versement n'a pas eu lieu. Le detail
    // reel est dans entityType / newValue.
    await this.logService.log({
      actorId:    processedById,
      actorType:  ActorType.ADMIN,
      action:     LogAction.PAYMENT_FAILED,
      entityType: 'VendorWithdrawal',
      entityId:   id,
      oldValue:   { status: ancienStatut },
      newValue:   {
        status:  VendorWithdrawalStatus.REJECTED,
        motif:   updated.noteAdmin,
        montant: Number(updated.montant),
      },
      result:       LogResult.FAILURE,
      errorMessage: updated.noteAdmin ?? undefined,
      ipAddress,
    });

    return stripSecrets(updated);
  }

  // ─────────────────────────────────────────────────────
  // ADMIN : fixer le quota minimum de retrait d'UN vendeur
  // ─────────────────────────────────────────────────────
  async setMinWithdrawalAmount(
    vendorId: string,
    minWithdrawalAmount: number,
    processedById: string,
    ipAddress?: string,
  ) {
    const vendor = await this.vendorRepo.findOne({ where: { id: vendorId } });

    if (!vendor) {
      throw new NotFoundException(`Vendeur ${vendorId} introuvable`);
    }

    const ancienMinimum = this.round2(Number(vendor.minWithdrawalAmount ?? 0));
    const nouveauMinimum = this.round2(Number(minWithdrawalAmount));

    if (!Number.isFinite(nouveauMinimum) || nouveauMinimum < 0) {
      throw new BadRequestException('Le minimum ne peut pas être négatif');
    }

    vendor.minWithdrawalAmount = nouveauMinimum;
    await this.vendorRepo.save(vendor);

    await this.logService.log({
      actorId:    processedById,
      actorType:  ActorType.ADMIN,
      action:     LogAction.USER_UPDATED_BY_ADMIN,
      entityType: 'VendorProfile',
      entityId:   vendorId,
      oldValue:   { minWithdrawalAmount: ancienMinimum },
      newValue:   { minWithdrawalAmount: nouveauMinimum },
      ipAddress,
    });

    return {
      vendorId:            vendor.id,
      shopName:            vendor.shopName,
      minWithdrawalAmount: nouveauMinimum,
    };
  }

  // ─────────────────────────────────────────────────────
  // ADMIN : vue d'ensemble (meme forme que delivery-earnings)
  // ─────────────────────────────────────────────────────
  async getStatistics() {
    const sumFor = (status: VendorWithdrawalStatus) =>
      this.withdrawalRepo
        .createQueryBuilder('w')
        .select('COALESCE(SUM(w.montant), 0)', 'sum')
        .where('w.status = :status', { status })
        .getRawOne<{ sum: string }>();

    const [
      countPending, countPaid, countRejected,
      sumPending,   sumPaid,   sumRejected,
    ] = await Promise.all([
      this.withdrawalRepo.count({ where: { status: VendorWithdrawalStatus.PENDING } }),
      this.withdrawalRepo.count({ where: { status: VendorWithdrawalStatus.PAID } }),
      this.withdrawalRepo.count({ where: { status: VendorWithdrawalStatus.REJECTED } }),
      sumFor(VendorWithdrawalStatus.PENDING),
      sumFor(VendorWithdrawalStatus.PAID),
      sumFor(VendorWithdrawalStatus.REJECTED),
    ]);

    return {
      pending:  { count: countPending,  amount: Number(sumPending?.sum ?? 0) },
      paid:     { count: countPaid,     amount: Number(sumPaid?.sum ?? 0) },
      rejected: { count: countRejected, amount: Number(sumRejected?.sum ?? 0) },
    };
  }
}
