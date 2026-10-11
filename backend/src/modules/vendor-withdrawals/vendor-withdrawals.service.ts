import {
  Injectable,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, FindOptionsWhere, FindManyOptions } from 'typeorm';
import {
  VendorWithdrawal,
  VendorWithdrawalStatus,
} from './entities/vendor-withdrawal.entity';
import { VendorProfile } from '../users/entities/vendor-profile.entity';
import { Order, OrderStatus } from '../orders/entities/order.entity';
import {
  Commission,
  CommissionStatus,
} from '../payments/entities/commission.entity';
import { CreateWithdrawalDto } from './dto/create-withdrawal.dto';
import { MarkWithdrawalPaidDto } from './dto/mark-withdrawal-paid.dto';
import { RejectWithdrawalDto } from './dto/reject-withdrawal.dto';
import { ActivityLogService } from '../../common/services/activity-log.service';
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
  constructor(
    @InjectRepository(VendorWithdrawal)
    private withdrawalRepo: Repository<VendorWithdrawal>,
    @InjectRepository(VendorProfile)
    private vendorRepo: Repository<VendorProfile>,
    @InjectRepository(Commission)
    private readonly commissionRepo: Repository<Commission>,

    @InjectRepository(Order)
    private orderRepo: Repository<Order>,
    private logService: ActivityLogService,
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

  private async computeBalance(vendor: VendorProfile): Promise<VendorBalance> {
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
    // (ecran profil vendeur) : les deux ecrans affichent enfin le meme
    // chiffre.
    const [brutRow, reverseRow, paidRow, pendingRow, pendingCount] = await Promise.all([
      this.commissionRepo
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
      this.commissionRepo
        .createQueryBuilder('c')
        .innerJoin('c.order', 'o')
        .select('COALESCE(SUM(c.commissionVendor), 0)', 'sum')
        .where('c.vendorId = :vendorId', { vendorId: vendor.id })
        .andWhere('o.status = :status', { status: OrderStatus.DELIVERED })
        .andWhere('c.status = :cstatus', { cstatus: CommissionStatus.PAID })
        .getRawOne<{ sum: string }>(),
      this.withdrawalRepo
        .createQueryBuilder('w')
        .select('COALESCE(SUM(w.montant), 0)', 'sum')
        .where('w.vendorId = :vendorId', { vendorId: vendor.id })
        .andWhere('w.status = :status', {
          status: VendorWithdrawalStatus.PAID,
        })
        .getRawOne<{ sum: string }>(),
      this.withdrawalRepo
        .createQueryBuilder('w')
        .select('COALESCE(SUM(w.montant), 0)', 'sum')
        .where('w.vendorId = :vendorId', { vendorId: vendor.id })
        .andWhere('w.status = :status', {
          status: VendorWithdrawalStatus.PENDING,
        })
        .getRawOne<{ sum: string }>(),
      this.withdrawalRepo.count({
        where: {
          vendorId: vendor.id,
          status: VendorWithdrawalStatus.PENDING,
        },
      }),
    ]);

    const gainsBruts     = this.round2(Number(brutRow?.sum ?? 0));
    const dejaReverse    = this.round2(Number(reverseRow?.sum ?? 0));
    const totalPaye      = this.round2(
      Number(paidRow?.sum ?? 0) + dejaReverse,
    );
    const totalEnAttente = this.round2(Number(pendingRow?.sum ?? 0));

    // Jamais de solde negatif affiche au vendeur : si une commande livrée
    // est annulée a posteriori apres un virement deja fait, le solde est
    // borne a 0 (la dette eventuelle se regle hors application).
    const soldeDisponible = this.round2(
      Math.max(0, gainsBruts - totalPaye - totalEnAttente),
    );

    return {
      gainsBruts,
      totalPaye,
      totalEnAttente,
      soldeDisponible,
      minWithdrawalAmount: this.round2(
        Number(vendor.minWithdrawalAmount ?? 0),
      ),
      aUneDemandeEnAttente: pendingCount > 0,
    };
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
  ) {
    const vendor  = await this.getVendorByUserId(userId);
    const balance = await this.computeBalance(vendor);

    const montant = this.round2(Number(dto.montant));

    if (!Number.isFinite(montant) || montant <= 0) {
      throw new BadRequestException('Le montant doit être supérieur à 0');
    }

    // Une seule demande en attente a la fois : plus simple a suivre pour
    // l'admin, et ca evite les doubles demandes sur le meme solde.
    if (balance.aUneDemandeEnAttente) {
      throw new BadRequestException(
        'Vous avez déjà une demande de retrait en attente. '
        + 'Attendez son traitement avant d\'en créer une nouvelle.',
      );
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

    const withdrawal = this.withdrawalRepo.create({
      vendorId:      vendor.id,
      montant,
      status:        VendorWithdrawalStatus.PENDING,
      paymentMethod: dto.paymentMethod.trim(),
      mobileNumber:  dto.mobileNumber.trim(),
      noteAdmin:     null,
      paidAt:        null,
      processedById: null,
    });

    // Pas de ligne ActivityLog a la creation : aucune valeur de LogAction ne
    // decrit honnetement "demande de retrait vendeur" (y en ajouter une
    // imposerait un ALTER TYPE sur l'enum Postgres de activity_logs). La
    // trace existe de toute facon : la ligne vendor_withdrawals porte
    // vendorId + createdAt. Seules les DECISIONS admin sont loguees.
    const saved = await this.withdrawalRepo.save(withdrawal);

    return {
      demande: saved,
      solde:   await this.computeBalance(vendor),
    };
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

    return stripSecrets(updated);
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
