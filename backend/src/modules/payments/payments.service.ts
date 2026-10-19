import {
  Injectable,
  Logger,
  NotFoundException,
  BadRequestException,
  ForbiddenException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, DataSource, EntityManager, In, Not } from 'typeorm';
import { MailService } from '../mail/mail.service';
import { NotificationsService } from '../notifications/notifications.service';
import { NotificationType } from '../notifications/entities/notification.entity';
import { VendorWithdrawalsService } from '../vendor-withdrawals/vendor-withdrawals.service';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'crypto';

import { Payment, PaymentStatus, PaymentMethod, PaymentOperator } from './entities/payment.entity';
import { Commission, CommissionStatus }           from './entities/commission.entity';
import { Refund, RefundStatus }                   from './entities/refund.entity';
import { VendorEarningAdjustment }                from './entities/vendor-earning-adjustment.entity';
import { Order, OrderStatus }                     from '../orders/entities/order.entity';
import { ProductVariant }                         from '../products/entities/product-variant.entity';
import { Product }                                from '../products/entities/product.entity';
import { VendorProfile }                          from '../users/entities/vendor-profile.entity';
import { User }                                   from '../users/entities/user.entity';

import { InitiatePaymentDto } from './dto/initiate-payment.dto';
import { RequestRefundDto }   from './dto/request-refund.dto';
import { ActivityLogService } from '../../common/services/activity-log.service';
import { stripSecrets } from '../../common/utils/strip-secrets.util';
import { paymentsToReviewWhere } from './payments-to-review.criteria';
import {
  ActorType,
  LogAction,
  LogResult,
} from '../../common/entities/activity-log.entity';

// Résultat de la reprise sur les gains d'un vendeur (voir
// PaymentsService.approveRefundAndReclaimEarnings).
interface RefundClawback {
  processedAt:       Date;
  adjustmentId:      string;
  vendorId:          string;
  montantVendeur:    number;
  montantCommission: number;
  proportion:        number;
  note:              string | null;
  // true = une reprise existait déjà pour ce remboursement : rien repris de plus.
  dejaRepris:        boolean;
}

// Réponse SIMPLIFIÉE de l'API « statut » de FeexPay (voir fetchFeexPayStatus).
//  - reachable = false : FeexPay n'a pas pu être interrogé (réseau, délai
//    dépassé, HTTP en erreur). On ne sait RIEN du paiement : ne rien changer.
//  - state : 'success' / 'failed' = FeexPay l'a dit explicitement ;
//    'pending' = FeexPay dit « en cours » ; 'unknown' = statut inattendu/absent.
//  - amount : montant renvoyé par FeexPay, s'il est présent.
export interface FeexPayStatusResult {
  reachable: boolean;
  state:     'success' | 'failed' | 'pending' | 'unknown';
  amount?:   number;
}

// Résultat d'une tentative de règlement automatique d'un paiement en attente
// (rattrapage ou webhook, voir settlePendingPayment).
export type SettleOutcome =
  | 'confirmed'        // FeexPay a dit « réussi » → paiement confirmé
  | 'failed'           // FeexPay a dit « échoué » (ou délai de 24 h dépassé) → échoué
  | 'pending'          // toujours en attente chez FeexPay → rien changé
  | 'unreachable'      // FeexPay injoignable → rien changé
  | 'amount_mismatch'  // montant FeexPay ≠ montant attendu → NON confirmé, à examiner
  | 'error'            // confirmation/échec impossible (stock, commande annulée...) → à examiner
  | 'ignored';         // plus en attente ou sans référence FeexPay

// Taux de commission par défaut si non configuré sur le vendeur
const DEFAULT_COMMISSION_RATE = 10; // 10%

// Livre numérique : le gain du vendeur n'est retirable que 24 h après le
// paiement — c'est aussi le délai dont dispose le client pour signaler un
// fichier défectueux (un remboursement ne tombe ainsi presque jamais sur un
// gain déjà retiré).
const DIGITAL_EARNINGS_HOLD_HOURS = 24;
const DIGITAL_REFUND_WINDOW_HOURS = 24;

// Délai maximum d'une interrogation de FeexPay (statut d'un paiement).
const FEEXPAY_STATUS_TIMEOUT_MS = 10_000;

// Statuts FeexPay reconnus (mêmes listes qu'avant l'extraction de
// fetchFeexPayStatus).
const FEEXPAY_SUCCESS_STATUSES = ['SUCCESSFUL', 'SUCCESS', 'APPROVED'];
const FEEXPAY_FAILED_STATUSES  = [
  'FAILED', 'CANCELLED', 'CANCELED', 'ERROR',
  'EXPIRED', 'TIMEOUT', 'REJECTED', 'DECLINED', 'REFUSED',
];
const FEEXPAY_PENDING_STATUSES = ['PENDING', 'PROCESSING', 'INITIATED'];

// Un paiement « en attente » avec référence FeexPay créé il y a moins de
// 15 minutes bloque une nouvelle tentative (risque de double débit).
const RETRY_GUARD_MS = 15 * 60 * 1000;

// Écart de montant toléré (arrondis) entre FeexPay et notre base, en FCFA.
const AMOUNT_TOLERANCE = 1;

// Réponses de PATCH /payments/:id/cancel (contrat avec l'appli : ne pas changer).
const CANCEL_MSG_SUCCESS   = 'Paiement confirmé';
const CANCEL_MSG_FAILED    = 'Paiement annulé, vous pouvez réessayer.';
const CANCEL_MSG_VERIFYING =
  'Paiement en cours de vérification. Vous serez prévenu(e) dès sa confirmation. '
  + 'Ne payez pas une seconde fois.';
const CANCEL_MSG_TO_REVIEW =
  'Votre paiement a bien été reçu, mais votre commande doit être vérifiée par notre équipe. '
  + 'Vous serez prévenu(e). Ne payez pas une seconde fois.';

@Injectable()
export class PaymentsService {
  private readonly logger = new Logger(PaymentsService.name);

  constructor(
    @InjectRepository(Payment)
    private readonly paymentRepo: Repository<Payment>,

    @InjectRepository(Commission)
    private readonly commissionRepo: Repository<Commission>,

    @InjectRepository(Refund)
    private readonly refundRepo: Repository<Refund>,

    @InjectRepository(Order)
    private readonly orderRepo: Repository<Order>,

    @InjectRepository(ProductVariant)
    private readonly variantRepo: Repository<ProductVariant>,

    @InjectRepository(VendorProfile)
    private readonly vendorRepo: Repository<VendorProfile>,

    @InjectRepository(User)
    private readonly userRepo: Repository<User>,

    private readonly dataSource:    DataSource,
    private readonly mailService:   MailService,
    private readonly logService:    ActivityLogService,
    private readonly configService: ConfigService,
    // Sert à prévenir le vendeur d'une nouvelle commande PAYÉE (voir
    // confirmPayment). Le module Notifications ne dépend pas de Payments :
    // pas de dépendance circulaire.
    private readonly notificationsService: NotificationsService,
    // Calcul du solde / de la dette du vendeur après une reprise de gains.
    private readonly vendorWithdrawalsService: VendorWithdrawalsService,
  ) {}

  // ─────────────────────────────────────────────────────
  // INITIER UN PAIEMENT
  // ─────────────────────────────────────────────────────
  async initiatePayment(
    userId: string,
    dto:    InitiatePaymentDto,
    ip:     string,
  ) {
    // Défense en profondeur (le DTO refuse déjà ces cas) : seul Mobile Money
    // est géré de bout en bout pour le moment.
    if (dto.method !== PaymentMethod.MOBILE_MONEY) {
      throw new BadRequestException(
        'Seul le paiement par Mobile Money (MTN ou Moov) est disponible pour le moment.',
      );
    }

    // Panier réparti sur plusieurs boutiques : plusieurs commandes créées
    // ensemble (une par boutique, voir OrdersService.createFromCart), mais
    // le client ne doit payer qu'une seule fois.
    if (dto.orderIds && dto.orderIds.length > 0) {
      return this.initiateGroupPayment(userId, dto, ip);
    }

    // 1. Récupérer la commande
    const order = await this.orderRepo.findOne({
      where:     { id: dto.orderId, userId },
      relations: ['items', 'items.variant'],
    });

    if (!order) throw new NotFoundException('Commande introuvable');

    // 2. Vérifier que la commande est en attente
    if (order.status !== OrderStatus.PENDING) {
      throw new BadRequestException(
        'Cette commande ne peut plus être payée'
      );
    }

    // 2 bis. Livres numériques : jamais deux fois le même livre, et un livre
    // à 0 F ne passe pas par Mobile Money (POST /payments/free).
    await this.assertDigitalOrdersPayable(userId, [order]);

    // 3. Vérifier qu'un paiement n'est pas déjà en cours
    let existingPayment = await this.paymentRepo.findOne({
      where: { orderId: dto.orderId },
    });

    if (existingPayment) {
      if (existingPayment.status === PaymentStatus.SUCCESS) {
        throw new BadRequestException('Cette commande est déjà payée');
      }
      // Paiement encore « en attente » : le client a peut-être DÉJÀ validé son
      // code PIN (ou va le faire). On interroge FeexPay avant de laisser
      // repartir un second prélèvement : réussi → confirmé et refusé ; échoué →
      // marqué échoué et on continue ; sinon → erreur 400 (double débit évité).
      if (existingPayment.status === PaymentStatus.PENDING) {
        await this.refuseRetryWhilePaymentPending([existingPayment], ip, 'order');
        existingPayment = await this.paymentRepo.findOne({
          where: { orderId: dto.orderId },
        });
      }
      // Si paiement échoué → on en crée un nouveau
    }

    // 4. Vérifier le stock une dernière fois avant le paiement
    for (const item of order.items) {
      const variant = item.variant;

      if (variant.stockQuantity < item.quantity) {
        if (variant.stockQuantity === 0) {
          throw new BadRequestException(
            `"${variant.sku}" n'est plus disponible. `
            + `Veuillez retirer cet article de votre commande.`
          );
        }
        throw new BadRequestException(
          `Stock insuffisant pour la référence "${variant.sku}". `
          + `Il reste ${variant.stockQuantity} unité(s).`
        );
      }
    }

    // 5. Créer le paiement en statut PENDING — ou réutiliser la ligne
    //    existante si une tentative précédente a échoué pour cette même
    //    commande (orderId est unique en base : on ne peut pas en
    //    insérer une deuxième).
    //    La réutilisation est ATOMIQUE (UPDATE ... WHERE status = 'échoué') :
    //    si deux requêtes simultanées (double clic) arrivent, une seule
    //    « rouvre » la ligne et appelle FeexPay ; l'autre reçoit une erreur 400.
    //    Elle remet aussi groupRef et providerRef à zéro : la ligne appartient
    //    à une NOUVELLE tentative, sans lien avec un ancien panier groupé ni
    //    avec l'ancienne transaction FeexPay.
    let payment: Payment;
    const previousProviderRef = existingPayment?.providerRef ?? null;
    if (existingPayment) {
      const reopened = await this.reopenFailedPayment(
        this.paymentRepo.manager,
        existingPayment.id,
        {
          method:   dto.method,
          operator: dto.operator ?? null,
          montant:  order.total,
          groupRef: null,
        },
      );
      if (!reopened) {
        throw new BadRequestException(
          'Un paiement est déjà en cours pour cette commande',
        );
      }
      payment = await this.paymentRepo.findOneOrFail({
        where: { id: existingPayment.id },
      });
    } else {
      payment          = this.paymentRepo.create();
      payment.orderId  = dto.orderId!;
      payment.method   = dto.method;
      payment.operator = dto.operator ?? null;
      payment.status   = PaymentStatus.PENDING;
      payment.montant  = order.total;
      try {
        await this.paymentRepo.save(payment);
      } catch (error) {
        // Deux premières demandes simultanées : l'index unique sur orderId
        // refuse la seconde.
        if (this.isUniqueViolation(error)) {
          throw new BadRequestException(
            'Un paiement est déjà en cours pour cette commande',
          );
        }
        throw error;
      }
    }

    await this.logService.log({
      actorId:    userId,
      actorType:  ActorType.CLIENT,
      action:     LogAction.PAYMENT_FAILED, // sera mis à jour à la confirmation
      entityType: 'payment',
      entityId:   payment.id,
      newValue:   {
        method: dto.method,
        amount: order.total,
        ...(previousProviderRef ? { previousProviderRef } : {}),
      },
      ipAddress:  ip,
    });

    // 6. Mobile Money : on demande réellement le paiement à FeexPay
    //    (MTN / Moov). Les autres méthodes (carte, cash) restent en
    //    simulation pour le moment — non branchées côté opérateur.
    if (dto.method === PaymentMethod.MOBILE_MONEY) {
      const reseau =
        dto.operator === PaymentOperator.MTN  ? 'MTN'  :
        dto.operator === PaymentOperator.MOOV ? 'MOOV' : null;

      if (!reseau) {
        await this.paymentRepo.update(
          { id: payment.id, status: PaymentStatus.PENDING },
          { status: PaymentStatus.FAILED },
        );
        throw new BadRequestException(
          `L'opérateur "${dto.operator}" n'est pas encore pris en charge `
          + `via FeexPay (seuls MTN et Moov le sont pour le moment).`
        );
      }

      const user = await this.userRepo.findOne({ where: { id: userId } });

      try {
        const providerRef = await this.callFeexPayRequestToPay({
          phoneNumber: dto.phoneNumber!,
          amount:      Number(order.total),
          reseau,
          firstName:   user?.prenom ?? 'Client',
          email:       user?.email ?? '',
          customId:    payment.id,
          description: `Commande ${order.orderNumber}`,
        });

        payment.providerRef = providerRef;
        await this.paymentRepo.save(payment);
      } catch (err) {
        await this.paymentRepo.update(
          { id: payment.id, status: PaymentStatus.PENDING },
          { status: PaymentStatus.FAILED },
        );
        throw err;
      }

      return {
        message:   'Demande envoyée. Confirmez le paiement sur votre téléphone.',
        paymentId: payment.id,
        amount:    payment.montant,
        method:    payment.method,
        operator:  payment.operator,
      };
    }

    // ⚠️ En production : pour les autres méthodes (carte, Wave, cash...)
    // on appellerait l'API correspondante ici.
    // Pour l'instant on retourne les infos pour simulation.

    return {
      message:   'Paiement initié avec succès',
      paymentId: payment.id,
      amount:    payment.montant,
      method:    payment.method,
      operator:  payment.operator,
      // En production : redirectUrl ou ussdPrompt ici
    };
  }

  // ─────────────────────────────────────────────────────
  // PANIER MULTI-BOUTIQUES — UN SEUL PAIEMENT POUR PLUSIEURS COMMANDES
  // Même schéma que initiatePayment() (commande unique) mais appliqué à
  // un groupe de commandes créées ensemble par OrdersService.createFromCart
  // (une commande par boutique). On crée une ligne Payment par commande
  // (orderId reste unique en base — impossible de n'en créer qu'une seule
  // pour plusieurs commandes), mais toutes partagent le même groupRef et
  // le même providerRef FeexPay : un seul montant est réellement demandé
  // au client. checkPaymentStatus() confirmera ensuite TOUTES les lignes
  // du groupe d'un coup dès que FeexPay confirme.
  // ─────────────────────────────────────────────────────
  private async initiateGroupPayment(
    userId: string,
    dto:    InitiatePaymentDto,
    ip:     string,
  ) {
    const orderIds = dto.orderIds!;

    const orders = await this.orderRepo.find({
      where:     { id: In(orderIds), userId },
      relations: ['items', 'items.variant'],
    });

    if (orders.length !== orderIds.length) {
      throw new NotFoundException(
        'Une ou plusieurs commandes de ce paiement sont introuvables'
      );
    }

    for (const order of orders) {
      if (order.status !== OrderStatus.PENDING) {
        throw new BadRequestException(
          `La commande ${order.orderNumber} ne peut plus être payée`
        );
      }
    }

    await this.assertDigitalOrdersPayable(userId, orders);

    let existingPayments = await this.paymentRepo.find({
      where: { orderId: In(orderIds) },
    });

    for (const existing of existingPayments) {
      if (existing.status === PaymentStatus.SUCCESS) {
        throw new BadRequestException(
          'Une des commandes de ce paiement est déjà payée'
        );
      }
    }

    // Paiement encore « en attente » pour une des commandes : même protection
    // contre le double débit que pour une commande seule (voir plus haut).
    const pendingExisting = existingPayments.filter(
      p => p.status === PaymentStatus.PENDING,
    );
    if (pendingExisting.length > 0) {
      await this.refuseRetryWhilePaymentPending(pendingExisting, ip, 'group');
      existingPayments = await this.paymentRepo.find({
        where: { orderId: In(orderIds) },
      });
    }

    // Vérifier le stock une dernière fois avant le paiement
    for (const order of orders) {
      for (const item of order.items) {
        const variant = item.variant;
        if (variant.stockQuantity < item.quantity) {
          if (variant.stockQuantity === 0) {
            throw new BadRequestException(
              `"${variant.sku}" n'est plus disponible. `
              + `Veuillez retirer cet article de votre commande.`
            );
          }
          throw new BadRequestException(
            `Stock insuffisant pour la référence "${variant.sku}". `
            + `Il reste ${variant.stockQuantity} unité(s).`
          );
        }
      }
    }

    const totalAmount = orders.reduce((sum, o) => sum + Number(o.total), 0);
    const groupRef     = randomUUID();

    const existingByOrderId = new Map(
      existingPayments.map(p => [p.orderId, p]),
    );

    // Création / réutilisation des lignes dans UNE transaction : réutiliser une
    // ligne « échouée » est atomique (UPDATE ... WHERE status = 'échoué'). Si une
    // requête simultanée (double clic) a déjà rouvert une ligne, on annule tout
    // et on répond 400 AVANT d'appeler FeexPay. Ligne réutilisée = nouvelle
    // tentative : groupRef est réaffecté, providerRef remis à zéro et la date
    // de création repart de maintenant (le rattrapage se base sur l'âge).
    const alreadyRunning = new BadRequestException(
      'Un paiement est déjà en cours pour une des commandes',
    );
    try {
      await this.paymentRepo.manager.transaction(async (manager) => {
        // Ordre fixe (par id) : évite les blocages mutuels entre deux
        // requêtes simultanées sur les mêmes commandes.
        const ordered = [...orders].sort((a, b) => a.id.localeCompare(b.id));
        for (const order of ordered) {
          const existing = existingByOrderId.get(order.id);
          if (existing) {
            const reopened = await this.reopenFailedPayment(manager, existing.id, {
              method:   dto.method,
              operator: dto.operator ?? null,
              montant:  order.total,
              groupRef,
            });
            if (!reopened) throw alreadyRunning;
          } else {
            const created = manager.create(Payment, {
              orderId:  order.id,
              method:   dto.method,
              operator: dto.operator ?? null,
              status:   PaymentStatus.PENDING,
              montant:  order.total,
              groupRef,
            });
            await manager.save(created);
          }
        }
      });
    } catch (error) {
      if (this.isUniqueViolation(error)) throw alreadyRunning;
      throw error;
    }

    const savedByOrderId = new Map(
      (await this.paymentRepo.find({ where: { orderId: In(orderIds) } }))
        .map(p => [p.orderId, p] as const),
    );
    const payments = orders.map(order => savedByOrderId.get(order.id)!);

    void Promise.all(
      payments.map(payment =>
        this.logService.log({
          actorId:    userId,
          actorType:  ActorType.CLIENT,
          action:     LogAction.PAYMENT_FAILED, // mis à jour à la confirmation
          entityType: 'payment',
          entityId:   payment.id,
          newValue:   { method: dto.method, amount: payment.montant, groupRef },
          ipAddress:  ip,
        }),
      ),
    );

    const primaryPayment = payments[0];

    if (dto.method === PaymentMethod.MOBILE_MONEY) {
      const reseau =
        dto.operator === PaymentOperator.MTN  ? 'MTN'  :
        dto.operator === PaymentOperator.MOOV ? 'MOOV' : null;

      if (!reseau) {
        await this.paymentRepo.update({ groupRef, status: PaymentStatus.PENDING }, { status: PaymentStatus.FAILED });
        throw new BadRequestException(
          `L'opérateur "${dto.operator}" n'est pas encore pris en charge `
          + `via FeexPay (seuls MTN et Moov le sont pour le moment).`
        );
      }

      const user = await this.userRepo.findOne({ where: { id: userId } });

      try {
        const providerRef = await this.callFeexPayRequestToPay({
          phoneNumber: dto.phoneNumber!,
          amount:      totalAmount,
          reseau,
          firstName:   user?.prenom ?? 'Client',
          email:       user?.email ?? '',
          customId:    groupRef,
          description: `${orders.length} commandes (`
            + `${orders.map(o => o.orderNumber).join(', ')})`,
        });

        await this.paymentRepo.update({ groupRef }, { providerRef });
      } catch (err) {
        await this.paymentRepo.update({ groupRef, status: PaymentStatus.PENDING }, { status: PaymentStatus.FAILED });
        throw err;
      }

      return {
        message:         'Demande envoyée. Confirmez le paiement sur votre téléphone.',
        paymentId:       primaryPayment.id,
        groupPaymentIds: payments.map(p => p.id),
        amount:          totalAmount,
        method:          dto.method,
        operator:        dto.operator,
      };
    }

    return {
      message:         'Paiement initié avec succès',
      paymentId:       primaryPayment.id,
      groupPaymentIds: payments.map(p => p.id),
      amount:          totalAmount,
      method:          dto.method,
      operator:        dto.operator,
    };
  }

  // Rouvre ATOMIQUEMENT une ligne de paiement « échouée » pour une nouvelle
  // tentative (UPDATE ... WHERE status = 'échoué'). Renvoie false si la ligne
  // n'est plus « échouée » (une autre requête l'a déjà rouverte, ou elle a été
  // payée entre-temps) : l'appelant doit alors refuser, SANS appeler FeexPay.
  // Remet providerRef à NULL (l'ancienne transaction FeexPay n'a aucun lien avec
  // la nouvelle) et repart la date de création de maintenant.
  private async reopenFailedPayment(
    manager:   EntityManager,
    paymentId: string,
    fields: {
      method:   PaymentMethod;
      operator: PaymentOperator | null;
      montant:  number;
      groupRef: string | null;
    },
  ): Promise<boolean> {
    const result = await manager
      .createQueryBuilder()
      .update(Payment)
      .set({
        status:      PaymentStatus.PENDING,
        method:      fields.method,
        operator:    fields.operator,
        montant:     fields.montant,
        groupRef:    fields.groupRef,
        providerRef: () => 'NULL',
        createdAt:   new Date(),
      })
      .where('"id" = :id AND "status" = :failed', {
        id:     paymentId,
        failed: PaymentStatus.FAILED,
      })
      .execute();
    return (result.affected ?? 0) > 0;
  }

  // Violation de contrainte unique PostgreSQL (code 23505).
  private isUniqueViolation(error: unknown): boolean {
    const e = error as { code?: string; driverError?: { code?: string } };
    return e?.code === '23505' || e?.driverError?.code === '23505';
  }

  // ─────────────────────────────────────────────────────
  // APPEL RÉEL À L'API FEEXPAY (requesttopay mobile money)
  // Référence API confirmée via le SDK PHP officiel de FeexPay :
  // POST {base}/api/transactions/requesttopay/integration
  // Corps : phoneNumber, amount, reseau, token, shop, first_name, email
  // ─────────────────────────────────────────────────────
  // Récupère l'IP publique sortante du serveur : certains champs FeexPay
  // (merchant_ip) attendent l'IP réelle du serveur marchand, pas celle du
  // client. Best-effort : si indisponible, on continue sans (chaîne vide).
  private async getMerchantPublicIp(): Promise<string> {
    try {
      const res = await fetch('https://api.ipify.org?format=json');
      if (!res.ok) return '';
      const data: any = await res.json();
      return data?.ip ?? '';
    } catch {
      return '';
    }
  }

  // FeexPay attend le numéro au format international SANS "+" : l'indicatif
  // 229 collé devant le numéro local tel quel (avec son 0 initial).
  // Ex. confirmé en conditions réelles : "0196782026" -> "2290196782026".
  // C'est le seul champ qui empêchait le USSD de partir — le reste du
  // corps/endpoint fonctionne déjà tel quel.
  private toFeexPayPhoneFormat(phoneNumber: string): string {
    const digitsOnly = phoneNumber.replace(/[^\d]/g, '');
    if (digitsOnly.startsWith('229')) return digitsOnly;
    return `229${digitsOnly}`;
  }

  async callFeexPayRequestToPay(params: {
    phoneNumber: string;
    amount:      number;
    reseau:      string;
    firstName:   string;
    email:       string;
    customId:    string;
    description: string;
  }): Promise<string> {
    const token   = this.configService.get<string>('FEEXPAY_API_KEY');
    const shop    = this.configService.get<string>('FEEXPAY_SHOP_ID');
    const baseUrl =
      this.configService.get<string>('FEEXPAY_BASE_URL')
      ?? 'https://api-v2.feexpay.me';

    if (!token || !shop) {
      throw new BadRequestException(
        'FeexPay non configuré côté serveur '
        + '(FEEXPAY_API_KEY / FEEXPAY_SHOP_ID manquants dans .env)'
      );
    }

    const merchantIp = await this.getMerchantPublicIp();

    // ⚠️ Le SDK PHP officiel (plus ancien) envoie ce corps en
    // x-www-form-urlencoded, mais le SDK React officiel, plus récent,
    // envoie du JSON ET ajoute un en-tête Authorization: Bearer <token>
    // en plus du champ "token" dans le corps — c'est ce dernier format
    // que l'API v2 (api-v2.feexpay.me) attend réellement (confirmé par
    // la source du SDK @feexpay/react-sdk).
    // On aligne aussi le corps sur TOUS les champs envoyés par ce SDK :
    // certains champs qu'on omettait (currency, payment_interface,
    // merchant_ip, merchant_domain, callback_info, otp, customId,
    // description) pourraient expliquer pourquoi FeexPay accepte la
    // demande (HTTP 201) sans jamais déclencher le USSD chez l'opérateur.
    const body = {
      phoneNumber:       this.toFeexPayPhoneFormat(params.phoneNumber),
      amount:            params.amount,
      reseau:            params.reseau,
      token,
      shop,
      first_name:        params.firstName,
      email:             params.email,
      description:       params.description,
      customId:          params.customId,
      currency:          'XOF',
      payment_interface: 'API',
      callback_info:     {},
      otp:               '',
      merchant_domain:
        this.configService.get<string>('FEEXPAY_MERCHANT_DOMAIN')
        ?? 'asoukaa.com',
      merchant_ip:       merchantIp,
    };

    let response: Response;
    try {
      response = await fetch(
        `${baseUrl}/api/transactions/requesttopay/integration`,
        {
          method:  'POST',
          headers: {
            'Content-Type':  'application/json',
            'Authorization': `Bearer ${token}`,
          },
          body: JSON.stringify(body),
        },
      );
    } catch (err) {
      throw new BadRequestException(
        'Impossible de joindre FeexPay. Vérifiez la connexion internet du serveur.'
      );
    }

    // On lit d'abord le texte brut (le corps ne peut être lu qu'une
    // fois) : si FeexPay ne renvoie pas du JSON valide (page HTML,
    // texte brut, corps vide...), response.json() planterait sans
    // qu'on sache jamais ce qui a été réellement reçu.
    const rawText = await response.text().catch(() => '');
    let data: any = null;
    try {
      data = rawText ? JSON.parse(rawText) : null;
    } catch {
      data = null;
    }

    // ⚠️ logger.debug et non console.log : la réponse brute contient le
    // numéro de téléphone du client et les références de transaction.
    // debug n'est pas émis avec les niveaux de log de production.
    this.logger.debug(
      `[FeexPay] Statut HTTP : ${response.status}`
      + ` | Content-Type : ${response.headers.get('content-type')}`
      + ` | Corps brut : ${rawText}`,
    );

    if (!response.ok) {
      const feexpayMessage =
        data?.message ?? data?.error ?? data?.error_message
        ?? data?.errorMessage ?? data?.msg ?? data?.detail;
      throw new BadRequestException(
        feexpayMessage
          ? `FeexPay a refusé la demande de paiement : ${
              typeof feexpayMessage === 'string' ? feexpayMessage : JSON.stringify(feexpayMessage)
            }`
          : `FeexPay a refusé la demande de paiement (HTTP ${response.status}, réponse brute : ${
              rawText || '(corps vide)'
            })`
      );
    }

    // ⚠️ Le nom exact du champ de référence renvoyé n'a pas encore été
    // vérifié en conditions réelles (doc FeexPay non accessible) — on
    // couvre les variantes les plus probables. À ajuster après premier
    // test réel si nécessaire (voir la réponse brute dans les logs).
    const reference = data?.reference ?? data?.trans_id ?? data?.id ?? data?._id;

    if (!reference) {
      throw new BadRequestException(
        "FeexPay n'a pas renvoyé de référence de transaction exploitable"
      );
    }

    return String(reference);
  }

  // ─────────────────────────────────────────────────────
  // VÉRIFIER LE STATUT D'UN PAIEMENT (interrogé par l'appli en
  // attendant que le client confirme sur son téléphone). Filet de sécurité si
  // l'appli abandonne : webhook FeexPay (PaymentsWebhookController) et
  // rattrapage automatique (PaymentReconciliationService).
  // ─────────────────────────────────────────────────────
  async checkPaymentStatus(paymentId: string, userId: string, ip: string) {
    const payment = await this.paymentRepo.findOne({
      where:     { id: paymentId },
      relations: ['order'],
    });

    if (!payment) throw new NotFoundException('Paiement introuvable');
    if (payment.order.userId !== userId) {
      throw new ForbiddenException('Accès refusé');
    }

    // Panier groupé déjà payé : une commande « sœur » peut être restée
    // « en attente » (stock insuffisant, annulée...) alors que le paiement
    // principal est réussi. On la retente (tant qu'elle peut l'être) et on
    // rend l'état visible au lieu de répondre « success » sans rien dire.
    if (payment.status === PaymentStatus.SUCCESS && payment.groupRef) {
      return this.retryGroupSiblings(payment, ip);
    }

    // Déjà finalisé : on renvoie l'état actuel sans rappeler FeexPay
    if (payment.status !== PaymentStatus.PENDING || !payment.providerRef) {
      return { status: payment.status };
    }

    // L'interrogation de FeexPay est faite par fetchFeexPayStatus() (partagée
    // avec l'annulation, le rattrapage automatique et le webhook).
    const feex = await this.fetchFeexPayStatus(payment.providerRef);

    if (!feex.reachable) {
      // ⚠️ Ce n'est PAS un vrai statut "en attente" renvoyé par FeexPay :
      // l'appel HTTP lui-même a échoué. On le distingue clairement pour ne
      // plus confondre "vérification impossible" et "vraiment en attente" :
      // le statut renvoyé est notre dernière valeur connue, PAS une
      // confirmation de FeexPay.
      return { status: payment.status, statusCheckFailed: true };
    }

    if (feex.state === 'success') {
      return this.confirmPaymentOrGroup(payment, ip);
    }

    if (feex.state === 'failed') {
      return this.failPaymentOrGroup(payment, ip);
    }

    return { status: payment.status }; // toujours en attente
  }

  // ─────────────────────────────────────────────────────
  // INTERROGER FEEXPAY (statut d'une transaction)
  // ⚠️ Route confirmée en conditions réelles (une autre intégration FeexPay
  // fonctionnelle utilisant les mêmes clés) : sur l'API v2 la vérification
  // est /api/transactions/public/single/status/{ref}, avec le même en-tête
  // Authorization: Bearer que l'appel de paiement (l'ancienne route du SDK PHP,
  // sans authentification, renvoyait un 404 "Cannot GET" sur ce domaine).
  //
  // Ne lève JAMAIS d'exception : une panne réseau, un délai dépassé (10 s) ou
  // un HTTP en erreur donnent { reachable: false } — "vérification
  // impossible", à ne jamais confondre avec un paiement échoué.
  // ─────────────────────────────────────────────────────
  async fetchFeexPayStatus(providerRef: string): Promise<FeexPayStatusResult> {
    const baseUrl =
      this.configService.get<string>('FEEXPAY_BASE_URL')
      ?? 'https://api-v2.feexpay.me';
    const token = this.configService.get<string>('FEEXPAY_API_KEY');

    let response: Response;
    let rawText = '';
    try {
      response = await fetch(
        `${baseUrl}/api/transactions/public/single/status/${encodeURIComponent(providerRef)}`,
        {
          headers: { Authorization: `Bearer ${token}` },
          signal:  AbortSignal.timeout(FEEXPAY_STATUS_TIMEOUT_MS),
        },
      );
      rawText = await response.text().catch(() => '');
    } catch (error) {
      this.logger.warn(
        `[FeexPay] ⚠️ Vérification de statut impossible pour la référence ${providerRef} `
        + `(FeexPay injoignable ou trop lent) : ${(error as Error)?.message}`,
      );
      return { reachable: false, state: 'unknown' };
    }

    let data: any = null;
    try {
      data = rawText ? JSON.parse(rawText) : null;
    } catch {
      data = null;
    }
    this.logger.debug(
      `[FeexPay] Statut — HTTP : ${response.status} | Corps brut : ${rawText}`,
    );

    if (!response.ok) {
      // ⚠️ Ce n'est PAS un vrai statut "en attente" renvoyé par FeexPay :
      // l'appel HTTP lui-même a échoué (ex. HTTP 404).
      this.logger.warn(
        `[FeexPay] ⚠️ Vérification de statut impossible (HTTP ${response.status}) `
        + `pour la référence ${providerRef} — ce n'est PAS une confirmation de FeexPay.`,
      );
      return { reachable: false, state: 'unknown' };
    }

    const feexStatus = (data?.status ?? data?.statut ?? '').toString().toUpperCase();

    const rawAmount = data?.amount ?? data?.montant;
    const parsedAmount =
      rawAmount === undefined || rawAmount === null || rawAmount === ''
        ? NaN
        : Number(rawAmount);
    const amount =
      Number.isFinite(parsedAmount) && parsedAmount > 0 ? parsedAmount : undefined;

    let state: FeexPayStatusResult['state'] = 'unknown';
    if (FEEXPAY_SUCCESS_STATUSES.includes(feexStatus))      state = 'success';
    else if (FEEXPAY_FAILED_STATUSES.includes(feexStatus))  state = 'failed';
    else if (FEEXPAY_PENDING_STATUSES.includes(feexStatus)) state = 'pending';

    return { reachable: true, state, amount };
  }

  // ─────────────────────────────────────────────────────
  // RÈGLEMENT AUTOMATIQUE D'UN PAIEMENT « EN ATTENTE » (hors passage où
  // l'appli attend) — utilisé par le rattrapage (PaymentReconciliationService)
  // et par le webhook FeexPay (PaymentsWebhookController).
  //
  // Interroge FeexPay (jamais de confiance au contenu d'un webhook) puis :
  //  - réussi  → confirme le paiement (ou tout le groupe), SAUF si le montant
  //              renvoyé par FeexPay diffère du montant attendu : alors on ne
  //              confirme PAS, on avertit dans les logs et on ajoute la ligne
  //              « Échec du paiement » du journal, ce qui fait apparaître le
  //              paiement dans « paiements à examiner » ;
  //  - échoué  → marque échoué ;
  //  - en cours → rien, sauf failIfNotSuccess (délai de 24 h dépassé) → échoué ;
  //  - statut inconnu → rien (même après 24 h) ;
  //  - injoignable → rien du tout.
  // Ne lève jamais d'exception.
  // ─────────────────────────────────────────────────────
  async settlePendingPayment(
    payment: Payment,
    ip:      string,
    options: { source: 'rattrapage' | 'webhook'; failIfNotSuccess?: boolean },
  ): Promise<SettleOutcome> {
    if (payment.status !== PaymentStatus.PENDING || !payment.providerRef) {
      return 'ignored';
    }
    const tag = `[${options.source}] paiement ${payment.id} (réf. ${payment.providerRef})`;

    try {
      const feex = await this.fetchFeexPayStatus(payment.providerRef);
      if (!feex.reachable) return 'unreachable';

      if (feex.state === 'success') {
        const group    = await this.groupPaymentsOf(payment);
        const expected = group.reduce((sum, p) => sum + Number(p.montant), 0);

        // Les frais FeexPay sont payés PAR-DESSUS par le client : un montant
        // supérieur au montant attendu est normal. On ne bloque que si FeexPay
        // annonce MOINS que prévu (paiement incomplet).
        if (
          feex.amount !== undefined
          && feex.amount < expected - AMOUNT_TOLERANCE
        ) {
          const message =
            `Montant FeexPay (${feex.amount}) inférieur au montant attendu (${expected}) : `
            + `paiement NON confirmé automatiquement.`;
          this.logger.warn(`${tag} : ${message} À examiner par un administrateur.`);
          for (const p of group) {
            if (p.status === PaymentStatus.PENDING) {
              await this.logConfirmationFailureOnce(p.id, ip, message);
            }
          }
          return 'amount_mismatch';
        }

        const result = await this.confirmPaymentOrGroup(payment, ip);
        this.logger.log(`${tag} : confirmé.`);
        await this.notifyClientPaymentConfirmed(payment, result);
        return 'confirmed';
      }

      if (feex.state === 'failed') {
        await this.failPaymentOrGroup(payment, ip);
        this.logger.log(`${tag} : FeexPay dit « échoué » → marqué échoué.`);
        return 'failed';
      }

      // Après 24 h, on ne marque « échoué » que si FeexPay a répondu clairement
      // « en cours » (pending). Un statut inattendu/absent (unknown) ne prouve
      // rien : on laisse le paiement « en attente » (à examiner).
      if (options.failIfNotSuccess && feex.state === 'pending') {
        await this.failPaymentOrGroup(payment, ip);
        this.logger.warn(
          `${tag} : toujours pas de succès après 24 h (FeexPay : ${feex.state}) → marqué échoué.`,
        );
        return 'failed';
      }
      if (options.failIfNotSuccess) {
        this.logger.warn(
          `${tag} : plus de 24 h et FeexPay répond un statut inconnu → laissé « en attente » (à examiner).`,
        );
      }

      return 'pending';
    } catch (error) {
      // Typiquement : stock insuffisant / commande annulée au moment de
      // confirmer (le paiement reste « en attente » et apparaît dans
      // « paiements à examiner »), ou paiement modifié en parallèle.
      this.logger.warn(`${tag} : règlement impossible : ${(error as Error)?.message}`);
      return 'error';
    }
  }

  // ─────────────────────────────────────────────────────
  // WEBHOOK FEEXPAY : retrouve les paiements en attente correspondant aux
  // références candidates extraites du corps, puis les règle via
  // settlePendingPayment (FeexPay est de toute façon re-interrogé : le corps
  // du webhook ne sert QU'À retrouver la référence). Référence inconnue ou
  // déjà traitée : on ne fait rien (et on ne révèle rien à l'appelant).
  // Ne lève jamais d'exception.
  // ─────────────────────────────────────────────────────
  async handleFeexPayWebhook(candidateRefs: string[], ip: string): Promise<void> {
    try {
      const refs = [...new Set(candidateRefs)].filter(r => r.length > 0 && r.length <= 255);
      if (refs.length === 0) return;

      const payments = await this.paymentRepo.find({
        where:     { providerRef: In(refs) },
        relations: ['order'],
      });
      if (payments.length === 0) {
        this.logger.log('Webhook FeexPay : aucune référence connue dans le corps reçu.');
        return;
      }

      const seen = new Set<string>();
      for (const payment of payments) {
        if (payment.status !== PaymentStatus.PENDING) continue; // déjà traité
        const key = payment.groupRef ?? payment.id;
        if (seen.has(key)) continue;
        seen.add(key);
        const outcome = await this.settlePendingPayment(payment, ip, { source: 'webhook' });
        this.logger.log(`Webhook FeexPay : paiement ${payment.id} → ${outcome}.`);
      }
    } catch (error) {
      this.logger.error(`Webhook FeexPay : traitement en échec : ${(error as Error)?.message}`);
    }
  }

  // Les lignes de paiement d'un même panier groupé (ou le seul paiement).
  private async groupPaymentsOf(payment: Payment): Promise<Payment[]> {
    if (!payment.groupRef) return [payment];
    // On écarte les lignes « échouées » : une ancienne tentative de panier dont
    // la ligne n'a pas été rouverte garde son groupRef mais ne fait plus partie
    // du paiement en cours (elle fausserait le contrôle de montant).
    const rows = await this.paymentRepo.find({
      where: { groupRef: payment.groupRef, status: Not(PaymentStatus.FAILED) },
    });
    return rows.length > 0 ? rows : [payment];
  }

  // ─────────────────────────────────────────────────────
  // Prévient le client (notification dans l'appli) qu'un paiement a été
  // confirmé HORS d'un passage où l'appli attendait (rattrapage / webhook).
  // L'e-mail de confirmation est déjà envoyé par confirmPayment() : on n'en
  // envoie donc pas un second ici (sendEmail: false). Best-effort : une
  // erreur ici ne remet jamais en cause le paiement. La préférence
  // « paiements » du client est appliquée par NotificationsService.create.
  // ─────────────────────────────────────────────────────
  private async notifyClientPaymentConfirmed(payment: Payment, result: unknown): Promise<void> {
    try {
      const order = payment.order
        ?? (await this.orderRepo.findOne({ where: { id: payment.orderId } }));
      if (!order?.userId) return;

      const r = (result ?? {}) as { orders?: unknown; orderNumber?: string };
      const numeros: string[] = (Array.isArray(r.orders)
        ? r.orders.map(String)
        : [r.orderNumber ?? order.orderNumber]
      ).filter(n => !!n && n !== 'undefined' && n !== 'null');
      // Rien à annoncer (liste vide) : on n'envoie pas « N°undefined ».
      if (numeros.length === 0) return;

      const body = numeros.length > 1
        ? `Votre paiement est confirmé, vos commandes N°${numeros.join(', N°')} sont enregistrées.`
        : `Votre paiement est confirmé, votre commande N°${numeros[0]} est enregistrée.`;

      await this.notificationsService.create({
        userId:        order.userId,
        title:         'Paiement confirmé',
        body,
        type:          NotificationType.PAYMENT,
        referenceId:   order.id,
        referenceType: 'order',
        sendEmail:     false,
      });
    } catch (error) {
      this.logger.error(
        `Échec notification « paiement confirmé » (paiement ${payment.id}) : ${(error as Error)?.message}`,
      );
    }
  }

  // ─────────────────────────────────────────────────────
  // Empêche le DOUBLE DÉBIT : appelée quand le client relance un paiement
  // alors qu'un paiement « en attente » existe déjà pour la commande (ou le
  // panier). Interroge FeexPay UNE fois par paiement :
  //  - réussi  → on confirme et on refuse la relance (« déjà payée ») ;
  //  - échoué  → on le marque échoué et on RETOURNE (le client peut réessayer) ;
  //  - sinon / injoignable / sans référence FeexPay → on lève une erreur 400 :
  //    message « en cours de vérification » si le paiement a une référence
  //    FeexPay et moins de 15 minutes, message habituel sinon.
  // ─────────────────────────────────────────────────────
  private async refuseRetryWhilePaymentPending(
    pendings: Payment[],
    ip:       string,
    scope:    'order' | 'group',
  ): Promise<void> {
    const stillPending: Payment[] = [];
    let confirmedOne = false;
    const handled = new Set<string>();

    for (const payment of pendings) {
      if (payment.status !== PaymentStatus.PENDING) continue;

      if (!payment.providerRef) {
        stillPending.push(payment);
        continue;
      }

      const key = payment.groupRef ?? payment.id;
      if (handled.has(key)) continue;
      handled.add(key);

      const feex = await this.fetchFeexPayStatus(payment.providerRef);
      if (!feex.reachable) {
        stillPending.push(payment);
        continue;
      }

      try {
        if (feex.state === 'success') {
          await this.confirmPaymentOrGroup(payment, ip);
          confirmedOne = true;
          continue;
        }
        if (feex.state === 'failed') {
          await this.failPaymentOrGroup(payment, ip);
          continue;
        }
      } catch (error) {
        this.logger.warn(
          `Relance de paiement : règlement impossible du paiement ${payment.id} : ${(error as Error)?.message}`,
        );
      }
      stillPending.push(payment);
    }

    if (confirmedOne) {
      throw new BadRequestException(
        scope === 'order'
          ? 'Cette commande est déjà payée'
          : 'Une des commandes de ce paiement est déjà payée',
      );
    }

    if (stillPending.length > 0) {
      const recent = stillPending.some(
        p => !!p.providerRef
          && Date.now() - new Date(p.createdAt).getTime() < RETRY_GUARD_MS,
      );
      if (recent) {
        throw new BadRequestException(
          scope === 'order'
            ? 'Un paiement est déjà en cours de vérification pour cette commande, patientez quelques minutes.'
            : 'Un paiement est déjà en cours de vérification pour ce panier, patientez quelques minutes.',
        );
      }
      throw new BadRequestException(
        scope === 'order'
          ? 'Un paiement est déjà en cours pour cette commande'
          : 'Un paiement est déjà en cours pour une des commandes',
      );
    }
  }

  // ─────────────────────────────────────────────────────
  // Confirme un paiement, ET tous ses "frères" de même groupRef s'il en a
  // (panier multi-boutiques réglé en un seul paiement — voir
  // initiateGroupPayment). Chaque commande garde sa propre logique de
  // confirmation (stock, commission, email) via confirmPayment(), on
  // l'applique juste à tout le groupe d'un coup.
  // ─────────────────────────────────────────────────────
  private async confirmPaymentOrGroup(payment: Payment, ip: string) {
    if (!payment.groupRef) {
      return this.confirmPayment(payment.id, payment.providerRef, ip);
    }

    const siblings = await this.paymentRepo.find({
      where:     { groupRef: payment.groupRef, status: PaymentStatus.PENDING },
      relations: ['order'],
    });

    const results: Array<{ message: string; orderNumber: string; status: PaymentStatus }> = [];
    const unconfirmedOrders: string[] = [];
    // ⚠️ Une commande du groupe qui ne peut pas être confirmée (ex. annulée
    // entre-temps par l'admin → confirmPayment refuse de la ressusciter) ne
    // doit pas empêcher les AUTRES commandes du groupe, déjà payées par le
    // client, d'être confirmées : sinon elles resteraient bloquées à chaque
    // nouvelle vérification du statut. On traite donc chaque commande
    // isolément, puis on remonte la première erreur à la fin si AUCUNE
    // commande n'a pu être confirmée.
    let premiereErreur: unknown = null;
    for (const sibling of siblings) {
      try {
        results.push(
          await this.confirmPayment(sibling.id, payment.providerRef, ip),
        );
      } catch (error) {
        premiereErreur = premiereErreur ?? error;
        unconfirmedOrders.push(sibling.order?.orderNumber ?? sibling.orderId);
        this.logger.error(
          `Confirmation impossible pour le paiement ${sibling.id} du groupe ${payment.groupRef} : ${(error as Error)?.message}`,
        );
      }
    }
    if (results.length === 0 && premiereErreur) throw premiereErreur;

    return {
      message: `${results.length} commande(s) confirmée(s)`,
      status:  PaymentStatus.SUCCESS,
      orders:  results.map(r => r.orderNumber),
      // Clés additives : présentes seulement si une commande du panier n'a pas
      // pu être validée (paiement reçu mais commande à examiner par l'admin).
      ...(unconfirmedOrders.length > 0
        ? { partial: true, unconfirmedOrders }
        : {}),
    };
  }

  // ─────────────────────────────────────────────────────
  // Panier groupé dont le paiement principal est déjà « success » : retente
  // les commandes sœurs restées « en attente » (la référence FeexPay est
  // partagée, le client a déjà payé pour tout le panier). Aucune règle
  // métier changée : c'est le même confirmPayment() qu'au premier passage.
  // Un échec persistant n'est journalisé qu'une fois (voir
  // logConfirmationFailureOnce) et reste visible dans la réponse.
  // ─────────────────────────────────────────────────────
  private async retryGroupSiblings(payment: Payment, ip: string) {
    const pendings = await this.paymentRepo.find({
      where:     { groupRef: payment.groupRef!, status: PaymentStatus.PENDING },
      relations: ['order'],
    });

    const unconfirmedOrders: string[] = [];
    for (const sibling of pendings) {
      const ref = sibling.providerRef || payment.providerRef;
      const numero = sibling.order?.orderNumber ?? sibling.orderId;
      if (!ref) {
        unconfirmedOrders.push(numero);
        continue;
      }
      try {
        await this.confirmPayment(sibling.id, ref, ip);
      } catch (error) {
        unconfirmedOrders.push(numero);
        this.logger.warn(
          `Rejeu impossible pour le paiement ${sibling.id} du groupe ${payment.groupRef} : ${(error as Error)?.message}`,
        );
      }
    }

    return unconfirmedOrders.length > 0
      ? { status: payment.status, partial: true, unconfirmedOrders }
      : { status: payment.status };
  }

  // ─────────────────────────────────────────────────────
  // Symétrique de confirmPaymentOrGroup() pour un échec.
  // ─────────────────────────────────────────────────────
  private async failPaymentOrGroup(payment: Payment, ip: string) {
    if (!payment.groupRef) {
      return this.failPayment(payment.id, ip);
    }

    const siblings = await this.paymentRepo.find({
      where: { groupRef: payment.groupRef, status: PaymentStatus.PENDING },
    });

    for (const sibling of siblings) {
      await this.failPayment(sibling.id, ip);
    }

    return { message: 'Paiement marqué comme échoué' };
  }

  // ⚠️ confirmCodPayment() (le vendeur marquait lui-même une commande
  // "payée en espèces") a été retirée : un vendeur ne doit plus pouvoir
  // marquer unilatéralement une commande comme payée. Les commandes
  // initiées par un vendeur ne créent plus de paiement "cash_on_delivery"
  // (voir OrdersService.createVendorInitiated) — le client paie via le
  // flux Mobile Money normal (initiatePayment ci-dessus), confirmé comme
  // n'importe quel autre paiement par confirmPayment() ci-dessous.

  // ─────────────────────────────────────────────────────
  // CONFIRMER UN PAIEMENT
  // ⚠️ PRIVÉE : jamais exposée en HTTP directement. Appelée par
  // checkPaymentStatus() après confirmation FeexPay (Mobile Money) — seul
  // chemin restant depuis la suppression de confirmCodPayment() (voir
  // commentaire ci-dessus : les commandes initiées par un vendeur ne créent
  // plus de paiement "cash_on_delivery").
  // ─────────────────────────────────────────────────────
  private async confirmPayment(
    paymentId:   string,
    providerRef: string,
    ip:          string,
  ) {
    const payment = await this.paymentRepo.findOne({
      where:     { id: paymentId },
      relations: ['order', 'order.items', 'order.items.variant', 'order.user'],
    });

    if (!payment) throw new NotFoundException('Paiement introuvable');

    if (payment.status !== PaymentStatus.PENDING) {
      throw new BadRequestException(
        'Ce paiement ne peut plus être confirmé'
      );
    }

    // ⚠️ En production : vérifier providerRef côté opérateur
    // avant d'accepter le paiement
    // Ne jamais faire confiance uniquement au callback

    // ⚠️ Une commande qui n'est plus « en attente » (annulée par l'admin,
    // déjà confirmée...) ne doit JAMAIS être retraitée : sinon on
    // décrémenterait le stock et on créerait une commission pour une
    // commande annulée (elle « ressusciterait »). Contrôle rapide ici ; il est
    // refait plus bas sous verrou, car l'admin peut annuler entre-temps.
    // (Dans le try : tout refus est journalisé par le catch ci-dessous.)

    // Titres des livres numériques de la commande (remplis dans la transaction).
    let bookTitles: string[] = [];

    // Transaction atomique : tout réussit ou tout échoue
    try {
      if (payment.order.status !== OrderStatus.PENDING) {
        this.refuserConfirmation(payment.order.status);
      }
      const dejaConfirme = await this.dataSource.transaction(async (manager) => {

        // 0. Verrouiller la commande puis revérifier son statut (course
        // possible avec une annulation admin simultanée).
        const lockedOrder = await manager.findOne(Order, {
          where: { id: payment.orderId },
          lock:  { mode: 'pessimistic_write' },
        });
        if (!lockedOrder || lockedOrder.status !== OrderStatus.PENDING) {
          this.refuserConfirmation(lockedOrder?.status ?? 'introuvable');
        }

        // 0 bis. Relire le PAIEMENT sous verrou. Deux vérifications de statut
        // simultanées passent toutes deux le contrôle « paiement en attente »
        // fait avant la transaction ; la commande reste « en attente » après
        // confirmation (règle métier), donc le verrou de commande ne suffit
        // pas à détecter que l'autre a déjà tout traité. Sans cette relecture,
        // la seconde retraiterait stock et commission et plantait sur la
        // contrainte unique commissions.orderId (erreur 500). Déjà confirmé
        // par l'autre → on s'arrête proprement, sans rien refaire.
        const lockedPayment = await manager.findOne(Payment, {
          where: { id: paymentId },
          lock:  { mode: 'pessimistic_write' },
        });
        if (!lockedPayment) {
          throw new NotFoundException('Paiement introuvable');
        }
        if (lockedPayment.status === PaymentStatus.SUCCESS) {
          return true;
        }
        if (lockedPayment.status !== PaymentStatus.PENDING) {
          throw new BadRequestException(
            'Ce paiement ne peut plus être confirmé'
          );
        }

        // 1. Marquer le paiement comme réussi
        payment.status      = PaymentStatus.SUCCESS;
        payment.providerRef = providerRef;
        payment.paidAt      = new Date();
        await manager.save(payment);

        // 2. La commande RESTE « en attente » (règle métier) : une commande
        // payée par Mobile Money ne passe pas toute seule « en cours ». C'est
        // le bouton « Confirmer » du vendeur (OrdersService.updateStatus, qui
        // exige un paiement réussi) qui la fait passer « en cours » ; sans
        // réponse, OrderConfirmationService relance le vendeur (24 h) puis
        // alerte l'admin (48 h) — il sélectionne justement les commandes
        // « en attente » dont le paiement est réussi.
        const order = payment.order;

        // 3. Décrémenter le stock de chaque variante
        // ⚠️ Verrou pessimiste (SELECT ... FOR UPDATE) sur chaque variante :
        // le stock n'est pas réservé à la création de la commande, donc N
        // clients peuvent commander le dernier exemplaire. Sans ce verrou,
        // deux paiements confirmés en parallèle lisaient le même stock et le
        // décrémentaient tous les deux → stock négatif et survente.
        // Le verrou sérialise les confirmations concurrentes ; la vérification
        // qui suit fait échouer (et annule) celle qui arrive trop tard.
        // Livre numérique : pas de stock à décrémenter (stock fictif jamais épuisé).
        for (const item of (order.isDigital ? [] : order.items)) {
          const variant = await manager.findOne(ProductVariant, {
            where: { id: item.variantId },
            lock: { mode: 'pessimistic_write' },
          });

          if (!variant) {
            throw new NotFoundException(
              `Variante ${item.variantId} introuvable`,
            );
          }

          if (variant.stockQuantity < item.quantity) {
            throw new BadRequestException(
              `Stock insuffisant pour la référence "${variant.sku}" : `
              + `${variant.stockQuantity} unité(s) restante(s) pour `
              + `${item.quantity} commandée(s). Le paiement n'a pas été validé.`
            );
          }

          await manager.decrement(
            ProductVariant,
            { id: item.variantId },
            'stockQuantity',
            item.quantity,
          );

          // Vérifier si le stock est sous le seuil d'alerte
          // (on recalcule sans relire : le verrou garantit la valeur)
          const remaining = variant.stockQuantity - item.quantity;
          if (remaining <= variant.lowStockAlert) {
            // ⚠️ Notifier le vendeur (sera géré dans le module notifications)
            this.logger.warn(
              `[STOCK ALERT] Variante ${variant.sku} : `
              + `${remaining} unité(s) restante(s)`
            );
          }
        }

        // 4. Calculer et créer la commission
        await this.createCommission(manager, order);

        // 5. Livre numérique : la commande passe directement « livrée » et le
        // livre entre dans la Bibliothèque du client, dans la MÊME transaction
        // que le paiement (jamais l'un sans l'autre).
        if (order.isDigital) {
          bookTitles = await this.completeDigitalOrder(manager, order);
        }

        return false;
      });

      // Paiement déjà confirmé par une vérification concurrente : tout (stock,
      // commission, email, notification vendeur) a déjà été fait par elle.
      if (dejaConfirme) {
        return {
          message:     'Paiement confirmé',
          orderNumber: payment.order.orderNumber,
          status:      PaymentStatus.SUCCESS,
        };
      }
    } catch (error) {
      // On journalise tout refus de confirmation (stock insuffisant, commande
      // annulée...) pour que l'admin puisse traiter un paiement reçu mais non
      // validé ; l'erreur est ensuite renvoyée telle quelle.
      if (error instanceof BadRequestException || error instanceof NotFoundException) {
        await this.logConfirmationFailureOnce(paymentId, ip, error.message);
      }
      throw error;
    }

    // 5. Envoyer email de confirmation au client (best-effort)
    const user = payment.order.user;
    // Livre à 0 F : aucun paiement à confirmer par e-mail.
    const skipPaymentMail = payment.order.isDigital && Number(payment.montant) === 0;
    try {
      if (!skipPaymentMail) await this.mailService.sendPaymentConfirmed(
        user.email,
        user.prenom,
        payment.order.orderNumber,
        Number(payment.montant),
        payment.order.id,
        !!payment.order.isDigital,
      );
    } catch (error) {
      this.logger.error(`Échec envoi mail confirmation paiement → ${user.email}`, error?.message);
    }

    // 6. Prévenir le vendeur d'une nouvelle commande PAYÉE à confirmer
    // (best-effort, APRÈS la transaction, une fois par commande : si la
    // notification échoue, le paiement et le stock restent valides). La
    // préférence « newOrders » du vendeur est appliquée par
    // NotificationsService.create.
    try {
      const vendor = await this.vendorRepo.findOne({
        where:  { id: payment.order.vendorId },
        select: ['id', 'userId'],
      });
      if (vendor?.userId) {
        if (payment.order.isDigital) {
          // Livre : rien à « confirmer » ni à expédier — simple info de vente.
          await this.notificationsService.notifyNewBookSale(
            vendor.userId,
            bookTitles.join(', '),
            payment.order.orderNumber,
            payment.order.id,
          );
        } else {
          await this.notificationsService.notifyNewOrder(
            vendor.userId,
            payment.order.orderNumber,
            payment.order.id,
          );
        }
      }
    } catch (error) {
      this.logger.error(
        `Échec notification nouvelle commande → vendeur de la commande ${payment.order.id}`,
        error?.message,
      );
    }

    // Livre numérique : prévenir le client que son livre est dans la Bibliothèque.
    if (payment.order.isDigital) {
      try {
        await this.notificationsService.notifyBookAvailable(
          payment.order.userId,
          bookTitles.join(', '),
          payment.order.id,
        );
      } catch (error) {
        this.logger.error(
          `Échec notification « livre disponible » (commande ${payment.order.id}) : ${(error as Error)?.message}`,
        );
      }
    }

    await this.logService.log({
      actorType:  ActorType.SYSTEM,
      action:     LogAction.PAYMENT_SUCCESS,
      entityType: 'payment',
      entityId:   paymentId,
      newValue:   { providerRef, amount: payment.montant },
      ipAddress:  ip,
    });

    return {
      message:     'Paiement confirmé',
      orderNumber: payment.order.orderNumber,
      status:      payment.status,
    };
  }

  // ─────────────────────────────────────────────────────
  // Journalise l'échec de validation d'un paiement reçu UNE SEULE FOIS par
  // paiement : l'application interroge le statut en boucle, sans cette
  // vérification chaque sondage ajouterait la même ligne PAYMENT_FAILED.
  // (Les lignes d'initiation / d'annulation ont result = success : elles ne
  // comptent pas ici.) Cette ligne alimente aussi `paymentsToReview` (voir
  // payments-to-review.criteria.ts).
  // ─────────────────────────────────────────────────────
  private async logConfirmationFailureOnce(
    paymentId: string,
    ip:        string,
    message:   string,
  ): Promise<void> {
    try {
      const deja = await this.dataSource.query(
        `SELECT 1 FROM "activity_logs"
         WHERE "entityType" = 'payment' AND "entityId" = $1
           AND "action" = $2 AND "result" = $3
         LIMIT 1`,
        [paymentId, LogAction.PAYMENT_FAILED, LogResult.FAILURE],
      );
      if (deja.length > 0) return;
    } catch {
      // Vérification impossible : mieux vaut une ligne de trop que pas de trace.
    }

    await this.logService.log({
      actorType:    ActorType.SYSTEM,
      action:       LogAction.PAYMENT_FAILED,
      entityType:   'payment',
      entityId:     paymentId,
      ipAddress:    ip,
      result:       LogResult.FAILURE,
      errorMessage: String(message).slice(0, 500),
    });
  }

  // ─────────────────────────────────────────────────────
  // Refus de confirmer un paiement dont la commande n'est plus « en attente »
  // (annulée, déjà confirmée...). Lève toujours une exception claire ; le
  // journal d'activité est écrit par le catch de confirmPayment.
  // Type `never` : l'appelant sait que l'exécution s'arrête là.
  // ─────────────────────────────────────────────────────
  private refuserConfirmation(statutCommande: string): never {
    const message =
      `Ce paiement ne peut pas être validé : la commande est « ${statutCommande} » `
      + `et non « en attente ». Si le client a réellement été débité, un `
      + `remboursement manuel est à étudier.`;
    throw new BadRequestException(message);
  }

  // ─────────────────────────────────────────────────────
  // ABANDON DE L'ATTENTE PAR L'APPLI (PATCH /payments/:id/cancel)
  //
  // ⚠️ Un abandon ou un délai dépassé côté appli ne prouve PAS que le client
  // n'a pas payé : il peut valider son code PIN après. On interroge donc
  // FeexPay AVANT de toucher au statut :
  //  - réussi  → on confirme le paiement ;
  //  - échoué  → on le marque échoué (le client peut réessayer) ;
  //  - en cours / statut inconnu / FeexPay injoignable → on NE marque PAS
  //    échoué : le paiement reste « en attente » et le rattrapage automatique
  //    (PaymentReconciliationService) ou le webhook le règlera plus tard.
  // Sans référence FeexPay (la demande n'est jamais partie chez FeexPay), il
  // n'y a rien à vérifier ni à débiter : on le marque échoué comme avant.
  // Réponse : toujours HTTP 200 { status, message, verificationEnCours? }.
  // ─────────────────────────────────────────────────────
  async cancelMyPendingPayment(paymentId: string, userId: string, ip: string) {
    const payment = await this.paymentRepo.findOne({
      where:     { id: paymentId },
      relations: ['order'],
    });

    if (!payment) throw new NotFoundException('Paiement introuvable');
    if (payment.order.userId !== userId) {
      throw new ForbiddenException('Accès refusé');
    }

    // Déjà réglé entre-temps (rattrapage / webhook / autre vérification) :
    // on répond l'état réel plutôt qu'une erreur, l'appli doit le savoir.
    if (payment.status === PaymentStatus.SUCCESS) {
      return { status: PaymentStatus.SUCCESS, message: CANCEL_MSG_SUCCESS };
    }
    if (payment.status === PaymentStatus.FAILED) {
      return { status: PaymentStatus.FAILED, message: CANCEL_MSG_FAILED };
    }
    if (payment.status !== PaymentStatus.PENDING) {
      throw new BadRequestException('Ce paiement ne peut plus être annulé');
    }

    // Jamais parti chez FeexPay : aucun débit possible, rien à vérifier.
    if (!payment.providerRef) {
      try {
        await this.failPaymentOrGroup(payment, ip);
      } catch (error) {
        return this.cancelAnswerAfterError(paymentId, error);
      }
      return { status: PaymentStatus.FAILED, message: CANCEL_MSG_FAILED };
    }

    const feex = await this.fetchFeexPayStatus(payment.providerRef);

    try {
      if (feex.reachable && feex.state === 'success') {
        const result = await this.confirmPaymentOrGroup(payment, ip);
        const extra  = result as { partial?: boolean; unconfirmedOrders?: string[] };
        return {
          status:  PaymentStatus.SUCCESS,
          message: CANCEL_MSG_SUCCESS,
          // Additifs, seulement si une commande du panier n'a pas pu être validée.
          ...(extra.partial
            ? { partial: true, unconfirmedOrders: extra.unconfirmedOrders }
            : {}),
        };
      }

      if (feex.reachable && feex.state === 'failed') {
        await this.failPaymentOrGroup(payment, ip);
        return { status: PaymentStatus.FAILED, message: CANCEL_MSG_FAILED };
      }
    } catch (error) {
      return this.cancelAnswerAfterError(paymentId, error);
    }

    this.logger.log(
      `Abandon de l'attente du paiement ${paymentId} : FeexPay `
      + (feex.reachable ? `répond « ${feex.state} »` : 'injoignable')
      + ' → le paiement reste « en attente » (vérification automatique).',
    );
    return {
      status:              PaymentStatus.PENDING,
      verificationEnCours: true,
      message:             CANCEL_MSG_VERIFYING,
    };
  }

  // Réponse de cancelMyPendingPayment quand la confirmation / l'échec a levé
  // une erreur (stock insuffisant, commande annulée, paiement modifié en
  // parallèle...). On relit l'état réel ; jamais d'erreur HTTP vers l'appli.
  private async cancelAnswerAfterError(paymentId: string, error: unknown) {
    this.logger.warn(
      `Annulation du paiement ${paymentId} : traitement impossible : ${(error as Error)?.message}`,
    );
    const fresh = await this.paymentRepo
      .findOne({ where: { id: paymentId } })
      .catch(() => null);

    if (fresh?.status === PaymentStatus.SUCCESS) {
      return { status: PaymentStatus.SUCCESS, message: CANCEL_MSG_SUCCESS };
    }
    if (fresh?.status === PaymentStatus.FAILED) {
      return { status: PaymentStatus.FAILED, message: CANCEL_MSG_FAILED };
    }
    // Typiquement FeexPay a dit « réussi » mais la commande ne peut pas être
    // validée (stock...) : le paiement reste « en attente » et apparaît dans
    // « paiements à examiner ».
    return {
      status:              PaymentStatus.PENDING,
      verificationEnCours: true,
      message:             CANCEL_MSG_TO_REVIEW,
    };
  }

  // ─────────────────────────────────────────────────────
  // ÉCHEC D'UN PAIEMENT
  // ─────────────────────────────────────────────────────
  private async failPayment(paymentId: string, ip: string) {
    const payment = await this.paymentRepo.findOne({
      where: { id: paymentId },
    });

    if (!payment) throw new NotFoundException('Paiement introuvable');

    if (payment.status !== PaymentStatus.PENDING) {
      throw new BadRequestException('Statut de paiement invalide');
    }

    // Écriture CONDITIONNELLE : si le paiement a été confirmé (success) entre
    // la lecture ci-dessus et maintenant, on ne l'écrase surtout pas.
    const updated = await this.paymentRepo.update(
      { id: paymentId, status: PaymentStatus.PENDING },
      { status: PaymentStatus.FAILED },
    );
    if (!updated.affected) {
      throw new BadRequestException('Statut de paiement invalide');
    }

    await this.logService.log({
      actorType:  ActorType.SYSTEM,
      action:     LogAction.PAYMENT_FAILED,
      entityType: 'payment',
      entityId:   paymentId,
      ipAddress:  ip,
    });

    return { message: 'Paiement marqué comme échoué' };
  }

  // Paiement « en attente » SANS référence FeexPay (la demande n'est jamais
  // partie chez FeexPay : rien n'a pu être débité). Utilisé par le rattrapage
  // automatique après un délai. Écriture conditionnelle (ne touche pas un
  // paiement qui aurait reçu une référence ou été réglé entre-temps).
  // Renvoie true si la ligne a bien été marquée échouée.
  async failUnsentPayment(paymentId: string, ip: string): Promise<boolean> {
    const result = await this.paymentRepo
      .createQueryBuilder()
      .update(Payment)
      .set({ status: PaymentStatus.FAILED })
      .where(
        '"id" = :id AND "status" = :pending '
        + 'AND ("providerRef" IS NULL OR "providerRef" = \'\')',
        { id: paymentId, pending: PaymentStatus.PENDING },
      )
      .execute();
    if (!result.affected) return false;

    await this.logService.log({
      actorType:  ActorType.SYSTEM,
      action:     LogAction.PAYMENT_FAILED,
      entityType: 'payment',
      entityId:   paymentId,
      ipAddress:  ip,
    });
    return true;
  }

  // ─────────────────────────────────────────────────────
  // REMBOURSEMENT D'UNE COMMANDE LIVRÉE : montant fixe = part du vendeur
  // (commissionVendor). Renvoie null s'il n'y a pas de commission.
  // ─────────────────────────────────────────────────────
  private async getFixedRefundAmount(orderId: string): Promise<number | null> {
    const commission = await this.commissionRepo.findOne({ where: { orderId } });
    if (!commission) return null;
    return this.round2(Number(commission.commissionVendor));
  }

  // Délai de remboursement (heures après la livraison) — à changer ici si besoin.
  private readonly DELAI_REMBOURSEMENT_HEURES = 24;

  // Commande ANNULÉE : remboursement = total payé − frais de livraison.
  private getCancelledRefundAmount(order: Order, payment: Payment): number {
    const total = Number(payment.montant);
    const livraison = Number(order.fraisLivraison ?? 0);
    return this.round2(Math.max(0, total - livraison));
  }

  // Vrai si la commande est LIVRÉE depuis plus de DELAI_REMBOURSEMENT_HEURES.
  private async isRefundDelayExceeded(order: Order): Promise<boolean> {
    if (order.status !== OrderStatus.DELIVERED) return false;
    const rows: Array<{ deliveredAt: Date | string | null }> =
      await this.dataSource.query(
        `SELECT "deliveredAt" FROM deliveries
          WHERE "orderId" = $1 AND "deliveredAt" IS NOT NULL
          ORDER BY "deliveredAt" DESC LIMIT 1`,
        [order.id],
      );
    const livreeLe = rows[0]?.deliveredAt
      ? new Date(rows[0].deliveredAt)
      : order.updatedAt;
    const limite = new Date(
      livreeLe.getTime() + this.DELAI_REMBOURSEMENT_HEURES * 60 * 60 * 1000,
    );
    return new Date() > limite;
  }

  // Aperçu pour l'appli : montant fixe (commande livrée) ou saisie libre
  // jusqu'au total payé (commande annulée). Mêmes contrôles que requestRefund.
  async getRefundQuote(userId: string, orderId: string) {
    const order = await this.orderRepo.findOne({ where: { id: orderId, userId } });
    if (!order) throw new NotFoundException('Commande introuvable');
    this.assertNotDigitalForClientRefund(order);

    if (
      order.status !== OrderStatus.CANCELLED &&
      order.status !== OrderStatus.DELIVERED
    ) {
      throw new BadRequestException(
        'Le remboursement n\'est possible que pour une commande annulée ou livrée',
      );
    }

    const payment = await this.paymentRepo.findOne({ where: { orderId } });
    if (!payment || payment.status !== PaymentStatus.SUCCESS) {
      throw new BadRequestException('Aucun paiement confirmé trouvé pour cette commande');
    }
    const existing = await this.refundRepo.findOne({ where: { orderId } });
    if (existing) {
      throw new BadRequestException(
        'Une demande de remboursement existe déjà pour cette commande',
      );
    }
    const totalPaye = Number(payment.montant);

    if (order.status === OrderStatus.DELIVERED) {
      const fixe = await this.getFixedRefundAmount(orderId);
      if (fixe === null || fixe <= 0) {
        throw new BadRequestException(
          'Aucun montant remboursable pour cette commande. Contactez le support.',
        );
      }
      return {
        orderId,
        orderStatus:  order.status,
        montantFixe:  true,
        montant:      fixe,
        totalPaye,
        delaiDepasse: await this.isRefundDelayExceeded(order),
        message:
          'Le remboursement d\'une commande livrée correspond à la part du vendeur '
          + '(la commission de la plateforme et les frais de livraison ne sont pas remboursés).',
      };
    }
    const fixeAnnulee = this.getCancelledRefundAmount(order, payment);
    if (fixeAnnulee <= 0) {
      throw new BadRequestException(
        'Aucun montant remboursable pour cette commande. Contactez le support.',
      );
    }
    return {
      orderId,
      orderStatus:  order.status,
      montantFixe:  true,
      montant:      fixeAnnulee,
      totalPaye,
      delaiDepasse: false,
      message:
        'Votre commande a été annulée : vous êtes remboursé(e) du montant payé, '
        + 'hors frais de livraison.',
    };
  }

  // ─────────────────────────────────────────────────────
  // DEMANDE DE REMBOURSEMENT
  // ─────────────────────────────────────────────────────
  async requestRefund(
    userId: string,
    dto:    RequestRefundDto,
    ip:     string,
  ) {
    // 1. Récupérer la commande
    const order = await this.orderRepo.findOne({
      where: { id: dto.orderId, userId },
    });

    if (!order) throw new NotFoundException('Commande introuvable');
    this.assertNotDigitalForClientRefund(order);

    // 2. Vérifier que la commande est annulée ou livrée
    if (
      order.status !== OrderStatus.CANCELLED &&
      order.status !== OrderStatus.DELIVERED
    ) {
      throw new BadRequestException(
        'Le remboursement n\'est possible que pour une commande '
        + 'annulée ou livrée'
      );
    }

    // 2 bis. Délai : une commande LIVRÉE ne se rembourse que dans les 24 h
    // qui suivent la livraison (une commande annulée n'est pas concernée).
    if (await this.isRefundDelayExceeded(order)) {
      throw new BadRequestException(
        `Le délai de ${this.DELAI_REMBOURSEMENT_HEURES} h après la livraison est dépassé : `
        + 'la demande de remboursement n\'est plus possible.',
      );
    }

    // 3. Récupérer le paiement
    const payment = await this.paymentRepo.findOne({
      where: { orderId: dto.orderId },
    });

    if (!payment || payment.status !== PaymentStatus.SUCCESS) {
      throw new BadRequestException(
        'Aucun paiement confirmé trouvé pour cette commande'
      );
    }

    // 4. Vérifier qu'un remboursement n'existe pas déjà
    const existing = await this.refundRepo.findOne({
      where: { orderId: dto.orderId },
    });

    if (existing) {
      throw new BadRequestException(
        'Une demande de remboursement existe déjà pour cette commande'
      );
    }

    // 5. Montant du remboursement
    //  - commande LIVRÉE : montant FIXE = part du vendeur (la commission de la
    //    plateforme et la livraison ne sont pas remboursées) ; toute valeur
    //    envoyée par le client est ignorée ;
    //  - commande ANNULÉE : le client indique le montant (jusqu'au total payé).
    let montantRemb: number;
    if (order.status === OrderStatus.DELIVERED) {
      const fixe = await this.getFixedRefundAmount(order.id);
      if (fixe === null || fixe <= 0) {
        throw new BadRequestException(
          'Aucun montant remboursable pour cette commande. Contactez le support.'
        );
      }
      montantRemb = fixe;
    } else {
      // Commande ANNULÉE : montant FIXE = tout ce qui a été payé SAUF la
      // livraison ; toute valeur envoyée par le client est ignorée.
      const fixe = this.getCancelledRefundAmount(order, payment);
      if (fixe <= 0) {
        throw new BadRequestException(
          'Aucun montant remboursable pour cette commande. Contactez le support.'
        );
      }
      montantRemb = fixe;
    }
    if (montantRemb > Number(payment.montant)) {
      throw new BadRequestException(
        `Le montant du remboursement ne peut pas dépasser `
        + `${payment.montant} FCFA`
      );
    }

    // 6. Créer la demande
    const refund          = this.refundRepo.create();
    refund.paymentId      = payment.id;
    refund.orderId        = dto.orderId;
    refund.montantRemb    = montantRemb;
    refund.motif          = dto.motif;
    refund.status         = RefundStatus.PENDING;

    await this.refundRepo.save(refund);

    await this.logService.log({
      actorId:    userId,
      actorType:  ActorType.CLIENT,
      action:     LogAction.REFUND_REQUESTED,
      entityType: 'refund',
      entityId:   refund.id,
      newValue:   { amount: montantRemb, motif: dto.motif },
      ipAddress:  ip,
    });

    return {
      message:  'Demande de remboursement soumise avec succès',
      refundId: refund.id,
    };
  }

  // ─────────────────────────────────────────────────────
  // CLIENT — MES DEMANDES DE REMBOURSEMENT
  // (statut : en attente / approuvé / rejetté / traité)
  // ─────────────────────────────────────────────────────
  async getMyRefunds(userId: string, page = 1, limit = 10) {
    const query = this.refundRepo
      .createQueryBuilder('refund')
      .innerJoin('refund.order', 'order')
      .leftJoinAndSelect('refund.order',   'ord')
      .leftJoinAndSelect('refund.payment', 'payment')
      .where('order.userId = :userId', { userId })
      .orderBy('refund.dateDemande', 'DESC')
      .skip((page - 1) * limit)
      .take(limit);

    const [refunds, total] = await query.getManyAndCount();

    return {
      data:  refunds,
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
    };
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — TRAITER UN REMBOURSEMENT
  // ─────────────────────────────────────────────────────
  // Ce que « remboursement » veut dire ici :
  //  - `refund.montantRemb` est choisi par le client à sa demande ; il peut
  //    être PARTIEL et va jusqu'au TOTAL PAYÉ de la commande (`payment.montant`
  //    = `order.total`, donc livraison comprise, après remise) ;
  //  - l'argent est rendu AU CLIENT À LA MAIN (aucun appel FeexPay ici).
  //
  // Image : le vendeur a une « tirelire » (ses gains). À l'APPROBATION, on
  // reprend dans la tirelire la part du vendeur correspondant à la fraction
  // remboursée, sinon il pourrait retirer de l'argent déjà rendu au client et
  // c'est la plateforme qui paierait. La reprise est faite dès l'approbation
  // (et non au statut « traité ») : à partir du moment où la plateforme
  // s'engage à rembourser, l'argent ne doit plus pouvoir être retiré.
  // Un remboursement REFUSÉ ne reprend rien.
  async processRefund(
    refundId: string,
    adminId:  string,
    action:   'approve' | 'reject',
    ip:       string,
    // Motif du refus saisi par l'admin (facultatif, rejet uniquement).
    motifRejet?: string,
  ) {
    const refund = await this.refundRepo.findOne({
      where:     { id: refundId },
      relations: ['payment', 'order', 'order.user'],
    });

    if (!refund) throw new NotFoundException('Demande de remboursement introuvable');

    if (refund.status !== RefundStatus.PENDING) {
      throw new BadRequestException(
        'Cette demande a déjà été traitée'
      );
    }

    let clawback: RefundClawback | null = null;

    if (action === 'approve') {
      // Transaction : paiement « remboursé » + remboursement « approuvé » +
      // reprise sur les gains du vendeur, tout ensemble ou rien.
      clawback = await this.approveRefundAndReclaimEarnings(
        refundId,
        refund.order.vendorId,
        adminId,
      );
      refund.status        = RefundStatus.APPROVED;
      refund.processedById = adminId;
      refund.processedAt   = clawback.processedAt;
    } else {
      refund.processedById = adminId;
      refund.processedAt   = new Date();
      refund.status        = RefundStatus.REJECTED;
      // Colonne dédiée (et non `motif`, qui contient la raison donnée par le
      // CLIENT : l'écraser ferait perdre sa demande d'origine).
      refund.motifRejet = motifRejet?.trim() || null;

      // ⚠️ On persiste le statut AVANT l'envoi de l'email : un échec SMTP ne
      // doit jamais laisser le remboursement dans un état incohérent.
      // Écriture CONDITIONNELLE (WHERE status = 'en attente') : si un autre
      // administrateur vient d'approuver (ou de refuser) cette demande, on
      // n'écrase rien et on répond 400.
      const rejected = await this.refundRepo.update(
        { id: refundId, status: RefundStatus.PENDING },
        {
          status:        RefundStatus.REJECTED,
          processedById: adminId,
          processedAt:   refund.processedAt,
          motifRejet:    refund.motifRejet,
        },
      );
      if (!rejected.affected) {
        throw new BadRequestException('Cette demande a déjà été traitée');
      }
    }

    // Prévenir le vendeur (best-effort) et savoir s'il est en dette.
    let detteVendeur = 0;
    if (clawback && !clawback.dejaRepris) {
      detteVendeur = await this.notifyVendorOfClawback(
        refund,
        clawback,
      );
    }

    // Notifier le client (best-effort)
    try {
      if (action === 'approve') {
        await this.mailService.sendRefundApproved(
          refund.order.user.email,
          refund.order.user.prenom,
          refund.order.orderNumber,
          Number(refund.montantRemb),
          refund.order.id,
        );
      } else {
        await this.mailService.sendRefundRejected(
          refund.order.user.email,
          refund.order.user.prenom,
          refund.order.orderNumber,
          refund.motifRejet,
        );
      }
    } catch (error) {
      this.logger.error(`Échec envoi mail remboursement → ${refund.order.user.email}`, error?.message);
    }

    await this.logService.log({
      actorId:    adminId,
      actorType:  ActorType.ADMIN,
      action:     LogAction.REFUND_PROCESSED,
      entityType: 'refund',
      entityId:   refundId,
      newValue:   {
        action,
        status: refund.status,
        ...(action === 'reject' && refund.motifRejet ? { motifRejet: refund.motifRejet } : {}),
        ...(clawback
          ? {
              repriseGains: {
                adjustmentId:      clawback.adjustmentId,
                vendorId:          clawback.vendorId,
                montantVendeur:    clawback.montantVendeur,
                montantCommission: clawback.montantCommission,
                proportion:        clawback.proportion,
                dejaRepris:        clawback.dejaRepris,
                note:              clawback.note,
                detteVendeur,
              },
            }
          : {}),
      },
      ipAddress:  ip,
    });

    return {
      message: action === 'approve'
        ? 'Remboursement approuvé'
        : 'Demande de remboursement refusée',
      status: refund.status,
      // Champs AJOUTÉS (approbation uniquement) : ce qui a été repris au
      // vendeur. `detteVendeur` > 0 = le vendeur avait déjà retiré l'argent.
      ...(clawback
        ? {
            repriseGains: {
              montantVendeur:    clawback.montantVendeur,
              montantCommission: clawback.montantCommission,
              proportion:        clawback.proportion,
              dejaRepris:        clawback.dejaRepris,
              note:              clawback.note,
            },
            detteVendeur,
          }
        : {}),
    };
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — MARQUER UN REMBOURSEMENT « TRAITÉ »
  // (l'argent a été rendu au client À LA MAIN : aucun appel FeexPay)
  // ─────────────────────────────────────────────────────
  // approuvé → traité, rien d'autre. La reprise sur les gains du vendeur a
  // déjà été faite à l'approbation : ce statut ne change aucun montant.
  // processedAt / processedById gardent la date et l'admin de l'APPROBATION ;
  // la date de passage à « traité » est `updatedAt`, et l'admin + la note sont
  // dans le journal d'activité.
  async markRefundProcessed(
    refundId: string,
    adminId:  string,
    ip:       string,
    note?:    string,
  ) {
    const refund = await this.refundRepo.findOne({ where: { id: refundId } });

    if (!refund) throw new NotFoundException('Demande de remboursement introuvable');

    if (refund.status !== RefundStatus.APPROVED) {
      throw new BadRequestException(
        'Seul un remboursement approuvé peut être marqué comme traité '
        + `(statut actuel : « ${refund.status} »)`,
      );
    }

    // Mise à jour conditionnelle : deux clics simultanés ne passent qu'une fois.
    const result = await this.refundRepo
      .createQueryBuilder()
      .update(Refund)
      .set({ status: RefundStatus.PROCESSED })
      .where('id = :id AND status = :status', {
        id:     refundId,
        status: RefundStatus.APPROVED,
      })
      .execute();

    if (!result.affected) {
      throw new BadRequestException(
        'Ce remboursement n\'est plus au statut « approuvé »',
      );
    }

    const cleanNote = note?.trim() || null;

    await this.logService.log({
      actorId:    adminId,
      actorType:  ActorType.ADMIN,
      action:     LogAction.REFUND_PROCESSED,
      entityType: 'refund',
      entityId:   refundId,
      oldValue:   { status: RefundStatus.APPROVED },
      newValue:   {
        action:  'processed',
        status:  RefundStatus.PROCESSED,
        montant: Number(refund.montantRemb),
        ...(cleanNote ? { note: cleanNote } : {}),
      },
      ipAddress:  ip,
    });

    return {
      message:  'Remboursement marqué comme traité',
      refundId,
      status:   RefundStatus.PROCESSED,
      note:     cleanNote,
    };
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — MARQUER UN « PAIEMENT À EXAMINER » COMME TRAITÉ
  // ─────────────────────────────────────────────────────
  // L'admin a tranché à la main (client remboursé, commande rejouée...).
  // Aucun appel FeexPay, le statut du paiement ne change pas : il sort juste de
  // la liste « à examiner » et du compteur du menu (colonne reviewedAt).
  async markPaymentReviewed(
    paymentId: string,
    adminId:   string,
    ip:        string,
    note?:     string,
  ) {
    const inList = await this.paymentRepo
      .createQueryBuilder('payment')
      .select('payment.id', 'id')
      .where('payment.id = :id', { id: paymentId })
      .andWhere(paymentsToReviewWhere('payment'))
      .getRawMany();

    if (!inList.length) {
      throw new BadRequestException(
        'Ce paiement n\'est pas (ou plus) dans la liste « à examiner »',
      );
    }

    const cleanNote = note?.trim() || null;

    // Conditionnel : deux clics simultanés ne passent qu'une fois.
    const result = await this.paymentRepo
      .createQueryBuilder()
      .update(Payment)
      .set({ reviewedAt: new Date(), reviewedBy: adminId, reviewNote: cleanNote })
      .where('id = :id AND "reviewedAt" IS NULL AND "status" = :pending', {
        id: paymentId,
        pending: PaymentStatus.PENDING,
      })
      .execute();

    if (!result.affected) {
      throw new BadRequestException('Ce paiement a déjà été marqué comme traité');
    }

    await this.logService.log({
      actorId:    adminId,
      actorType:  ActorType.ADMIN,
      action:     LogAction.PAYMENT_REVIEWED,
      entityType: 'payment',
      entityId:   paymentId,
      newValue:   { action: 'reviewed', ...(cleanNote ? { note: cleanNote } : {}) },
      ipAddress:  ip,
    });

    return {
      message:   'Paiement marqué comme traité',
      paymentId,
      note:      cleanNote,
    };
  }

  // ─────────────────────────────────────────────────────
  // MÉTHODE PRIVÉE — APPROUVER + REPRENDRE LE GAIN DU VENDEUR
  // ─────────────────────────────────────────────────────
  // Ordre des verrous (toujours le même, pour éviter les blocages croisés) :
  //   1. la fiche vendeur — le MÊME verrou que la création d'un retrait
  //      (VendorWithdrawalsService.createWithdrawal) : un retrait et un
  //      remboursement simultanés passent l'un après l'autre ;
  //   2. la demande de remboursement ;
  //   3. la commission de la commande.
  //
  // Montants : proportion = montantRemb / total payé (plafonnée à 1), appliquée
  // à la part vendeur (`commissionVendor`) ET à la commission plateforme
  // (`montantCommission`) — la plateforme rend aussi sa part sur les produits
  // remboursés. Ces deux montants sont calculés sur les PRODUITS seulement : les
  // frais de livraison n'en font jamais partie, ils ne sont donc jamais repris
  // au vendeur. Les gains du LIVREUR (80 % de la livraison) ne sont PAS touchés.
  private async approveRefundAndReclaimEarnings(
    refundId: string,
    vendorId: string,
    adminId:  string,
  ): Promise<RefundClawback> {
    return this.dataSource.transaction(async (manager) => {
      await manager.query(
        'SELECT "id" FROM "vendor_profiles" WHERE "id" = $1 FOR UPDATE',
        [vendorId],
      );
      await manager.query(
        'SELECT "id" FROM "refunds" WHERE "id" = $1 FOR UPDATE',
        [refundId],
      );

      // Relecture SOUS verrou : deux approbations simultanées ne passent pas.
      const refund = await manager.findOne(Refund, {
        where:     { id: refundId },
        relations: ['payment', 'order'],
      });
      if (!refund) throw new NotFoundException('Demande de remboursement introuvable');
      if (refund.status !== RefundStatus.PENDING) {
        throw new BadRequestException('Cette demande a déjà été traitée');
      }

      await manager.query(
        'SELECT "id" FROM "commissions" WHERE "orderId" = $1 FOR UPDATE',
        [refund.orderId],
      );
      const commission = await manager.findOne(Commission, {
        where: { orderId: refund.orderId },
      });

      const processedAt = new Date();

      // Statuts (comme avant : paiement « remboursé », remboursement « approuvé »).
      await manager.update(Payment, { id: refund.paymentId }, {
        status: PaymentStatus.REFUNDED,
      });
      await manager.update(Refund, { id: refundId }, {
        status:        RefundStatus.APPROVED,
        processedById: adminId,
        processedAt,
      });

      // Livre numérique remboursé : l'accès à la Bibliothèque est retiré dans
      // la MÊME transaction (jamais « remboursé mais encore possédé »).
      if (refund.order.isDigital) {
        await manager.query(
          `UPDATE "library_items"
              SET "revokedAt" = now(), "revokedReason" = $2
            WHERE "orderId" = $1 AND "revokedAt" IS NULL`,
          [refund.orderId, `Remboursé : ${refund.motif ?? ''}`.slice(0, 300)],
        );
      }

      // Idempotence : un remboursement ne reprend qu'UNE fois (index unique
      // sur refundId en plus de ce contrôle).
      const existing = await manager.findOne(VendorEarningAdjustment, {
        where: { refundId },
      });
      if (existing) {
        return {
          processedAt,
          adjustmentId:      existing.id,
          vendorId,
          montantVendeur:    Number(existing.montantVendeur),
          montantCommission: Number(existing.montantCommission),
          proportion:        Number(existing.proportion),
          note:              existing.note,
          dejaRepris:        true,
        };
      }

      const totalPaye   = Number(refund.payment?.montant ?? 0);
      const montantRemb = Number(refund.montantRemb);

      // Règle : le vendeur perd exactement ce qui est remboursé au client,
      // plafonné à sa part (commissionVendor). La commission de la plateforme
      // n'est jamais rendue ; la livraison n'est jamais reprise.
      let proportion        = 0;
      let montantVendeur    = 0;
      const montantCommission = 0;
      let note: string | null = null;

      if (!commission) {
        note = 'Aucune commission trouvée pour cette commande : rien à reprendre.';
      } else if (refund.order.status !== OrderStatus.DELIVERED) {
        // Les gains ne comptent que les commandes LIVRÉES : une commande
        // annulée n'a jamais rien crédité au vendeur, donc rien à reprendre.
        note = 'Commande non livrée : aucun gain vendeur à reprendre.';
      } else if (
        commission.availableAt
        && new Date(commission.availableAt).getTime() > processedAt.getTime()
      ) {
        // Livre numérique remboursé PENDANT la retenue de 24 h : le gain n'a
        // jamais été retirable (il ne compte pas encore dans le solde), donc
        // rien à reprendre — on annule simplement ce gain pour qu'il n'apparaisse
        // pas plus tard.
        montantVendeur = 0;
        proportion     = 0;
        note = 'Livre remboursé pendant la retenue de 24 h : gain du vendeur annulé avant tout versement.';
        await manager.update(Commission, { id: commission.id }, { commissionVendor: 0 });
      } else {
        const cv = Number(commission.commissionVendor);
        montantVendeur = this.round2(Math.min(Math.max(montantRemb, 0), cv));
        proportion = cv > 0
          ? Number(Math.min(1, montantVendeur / cv).toFixed(6))
          : 0;
        note = proportion >= 1
          ? 'Part du vendeur reprise en totalité (commission plateforme non rendue).'
          : 'Part du vendeur reprise à hauteur du montant remboursé.';
      }

      const adjustment = await manager.save(
        manager.create(VendorEarningAdjustment, {
          refundId,
          orderId:          refund.orderId,
          commissionId:     commission?.id ?? null,
          vendorId,
          montantRembourse: this.round2(montantRemb),
          totalPaye:        this.round2(totalPaye),
          proportion,
          montantVendeur,
          montantCommission,
          note,
        }),
      );

      return {
        processedAt,
        adjustmentId: adjustment.id,
        vendorId,
        montantVendeur,
        montantCommission,
        proportion,
        note,
        dejaRepris: false,
      };
    });
  }

  // Prévient le vendeur (notification dans l'application) et renvoie sa dette
  // éventuelle (0 si aucune). Best-effort : ne fait jamais échouer le
  // remboursement.
  private async notifyVendorOfClawback(
    refund:   Refund,
    clawback: RefundClawback,
  ): Promise<number> {
    let dette = 0;
    try {
      const balance = await this.vendorWithdrawalsService
        .getBalanceByVendorId(clawback.vendorId);
      dette = balance?.dette ?? 0;
    } catch (error) {
      this.logger.warn(`Calcul de dette vendeur impossible : ${error?.message}`);
    }

    if (clawback.montantVendeur <= 0) return dette;

    try {
      const vendor = await this.vendorRepo.findOne({
        where: { id: clawback.vendorId },
      });
      if (!vendor?.userId) return dette;

      let body =
        `Un remboursement client a été validé : `
        + `${this.formatFcfa(clawback.montantVendeur)} FCFA ont été déduits `
        + `de vos gains pour la commande N°${refund.order.orderNumber}.`;
      if (dette > 0) {
        body +=
          ` Cet argent ayant déjà été retiré, vous avez une dette de `
          + `${this.formatFcfa(dette)} FCFA : elle sera déduite de vos `
          + `prochains gains, et les retraits sont suspendus tant qu'elle `
          + `n'est pas couverte.`;
      }

      await this.notificationsService.create({
        userId:        vendor.userId,
        title:         'Remboursement client : déduction sur vos gains',
        body,
        type:          NotificationType.PAYMENT,
        referenceId:   refund.orderId,
        referenceType: 'order',
        sendEmail:     false,
      });
    } catch (error) {
      this.logger.error(
        `Notification de reprise impossible (vendeur ${clawback.vendorId})`,
        error?.message,
      );
    }
    return dette;
  }

  private round2(value: number): number {
    if (!Number.isFinite(value)) return 0;
    return Math.round(value * 100) / 100;
  }

  private formatFcfa(value: number): string {
    return Number(value)
      .toLocaleString('fr-FR', { maximumFractionDigits: 2 })
      .replace(/[  ]/g, ' ');
  }

  // ─────────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────
  // CLIENT — MES PAIEMENTS
  // ─────────────────────────────────────────────────────
  async getMyPayments(userId: string, page = 1, limit = 10) {
    const query = this.paymentRepo
      .createQueryBuilder('payment')
      .innerJoin('payment.order', 'order')
      .leftJoinAndSelect('payment.order', 'ord')
      .where('order.userId = :userId', { userId })
      .orderBy('payment.createdAt', 'DESC')
      .skip((page - 1) * limit)
      .take(limit);

    const [payments, total] = await query.getManyAndCount();

    return {
      data:  payments,
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
    };
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — TOUS LES PAIEMENTS
  // ─────────────────────────────────────────────────────
  async getAllPayments(
    status?: PaymentStatus,
    page = 1,
    limit = 20,
    toReview = false,
  ) {
    const query = this.paymentRepo
      .createQueryBuilder('payment')
      .leftJoinAndSelect('payment.order', 'order')
      .leftJoinAndSelect('order.vendor',  'vendor')
      .orderBy('payment.createdAt', 'DESC')
      .skip((page - 1) * limit)
      .take(limit);

    if (status) {
      query.where('payment.status = :status', { status });
    }

    // Paiements reçus mais non validés (même critère que le compteur
    // `paymentsToReview` du menu admin).
    if (toReview) {
      query.andWhere(paymentsToReviewWhere('payment'));
    }

    const [payments, total] = await query.getManyAndCount();

    return {
      data:  stripSecrets(payments),
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
    };
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — TOUTES LES DEMANDES DE REMBOURSEMENT
  // ─────────────────────────────────────────────────────
  async getAllRefunds(
    status?: RefundStatus,
    page = 1,
    limit = 20,
  ) {
    const query = this.refundRepo
      .createQueryBuilder('refund')
      .leftJoinAndSelect('refund.order',   'order')
      .leftJoinAndSelect('order.user',     'user')
      .leftJoinAndSelect('refund.payment', 'payment')
      // La colonne s'appelle dateDemande (Refund.dateDemande) : l'ancien
      // « requestedAt » n'existait pas et faisait planter la liste admin.
      .orderBy('refund.dateDemande', 'DESC')
      .skip((page - 1) * limit)
      .take(limit);

    if (status) {
      query.where('refund.status = :status', { status });
    }

    const [refunds, total] = await query.getManyAndCount();

    // Masquer les passwordHash
    const safeRefunds = refunds.map(r => {
      if (r.order?.user) {
        const { passwordHash, ...userSafe } = r.order.user as any;
        (r.order as any).user = userSafe;
      }
      return r;
    });

    return {
      data:  safeRefunds,
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
    };
  }

  // ─────────────────────────────────────────────────────
  // MÉTHODE PRIVÉE — CRÉER LA COMMISSION
  // ─────────────────────────────────────────────────────
  private async createCommission(
    manager: any,
    order:   Order,
  ): Promise<void> {
    const vendor = await manager.findOne(VendorProfile, {
      where: { id: order.vendorId },
    });

    if (!vendor) return;

    // ⚠️ RÈGLE MÉTIER (décidée par le propriétaire) :
    //  - la commission de la plateforme (10 % par défaut) se calcule sur les
    //    PRODUITS SEULEMENT, APRÈS remise : base = subtotal − rabais ;
    //  - les frais de livraison (order.fraisLivraison) n'entrent JAMAIS dans
    //    cette base et le vendeur n'en touche RIEN : ils reviennent au livreur
    //    (80 %) et à la plateforme (le reste), partage calculé dans
    //    DeliveryService.createDeliveryEarning (à ne pas changer ici).
    // Avant : la base était order.total (produits + livraison), ce qui
    // faisait payer au vendeur une commission sur la livraison ET lui en
    // reversait 90 % — d'où des gains surévalués.
    // `commission.totalCommande` contient donc désormais la base de calcul
    // (produits après remise), pas le total payé par le client.
    // Tous les lecteurs (gains vendeur, solde de retrait, tableaux de bord)
    // lisent commissionVendor / montantCommission : ils restent cohérents.
    // Commission propre au vendeur (fixée par l'admin) : pourcentage ou montant
    // fixe par commande ; sans réglage, 10 % comme avant.
    const fixedMode = vendor.commissionType === 'fixed' && vendor.commissionValue != null;
    const customRate = !fixedMode && vendor.commissionType === 'percent' && vendor.commissionValue != null
      ? Number(vendor.commissionValue)
      : NaN;
    // Garde-fou : une valeur incohérente retombe sur la commission par défaut.
    const rate      = Number.isFinite(customRate) && customRate >= 0 && customRate <= 100
      ? customRate
      : DEFAULT_COMMISSION_RATE;
    let baseProduits       = Math.max(
      0,
      Number(order.subtotal) - Number(order.rabais ?? 0),
    );
    // Livre numérique + code promo de la PLATEFORME (non créé par un vendeur) :
    // la remise est financée par Asoukaa, le vendeur est calculé sur le prix
    // plein. Un code créé par le vendeur lui-même reste à sa charge.
    if (order.isDigital && order.couponId && Number(order.rabais ?? 0) > 0) {
      const rows: Array<{ vendorId: string | null }> = await manager.query(
        'SELECT "vendorId" FROM "coupons" WHERE "id" = $1',
        [order.couponId],
      );
      if (rows[0] && !rows[0].vendorId) {
        baseProduits = Math.max(0, Number(order.subtotal));
      }
    }
    // Montant fixe : jamais plus que la base (le vendeur ne paie pas plus que ses ventes).
    const commissionAmount = fixedMode
      ? Number(Math.min(Number(vendor.commissionValue), baseProduits).toFixed(2))
      : Number(((baseProduits * rate) / 100).toFixed(2));
    const vendorAmount     = Number(
      (baseProduits - commissionAmount).toFixed(2)
    );

    const commission              = manager.create(Commission);
    commission.orderId            = order.id;
    commission.vendorId           = order.vendorId;
    commission.totalCommande      = Number(baseProduits.toFixed(2));
    commission.typeCommission     = fixedMode ? 'fixed' : 'percent';
    // Montant fixe : on garde le pourcentage équivalent pour les statistiques.
    commission.taux               = fixedMode
      ? (baseProduits > 0 ? Number(((commissionAmount / baseProduits) * 100).toFixed(2)) : 0)
      : rate;
    commission.montantCommission  = commissionAmount;
    commission.commissionVendor   = vendorAmount;
    commission.status             = CommissionStatus.PENDING;
    // Livre numérique : gain retirable 24 h après le paiement ; produit
    // physique : null = disponible dès que la commande est « livrée ».
    commission.availableAt        = order.isDigital
      ? new Date(Date.now() + DIGITAL_EARNINGS_HOLD_HOURS * 60 * 60 * 1000)
      : null;

    await manager.save(commission);
  }

  // ═════════════════════════════════════════════════════
  // LIVRES NUMÉRIQUES
  // ═════════════════════════════════════════════════════

  // Refus d'un remboursement client « classique » pour un livre : il passe par
  // un ticket d'assistance traité par un administrateur.
  private assertNotDigitalForClientRefund(order: Order): void {
    if (order.isDigital) {
      throw new BadRequestException(
        'Un livre numérique ne se rembourse pas depuis l\'application. Si le fichier est '
        + 'défectueux ou ne s\'ouvre pas, ouvrez un ticket d\'assistance dans les '
        + `${DIGITAL_REFUND_WINDOW_HOURS} heures qui suivent l'achat.`,
      );
    }
  }

  // Avant paiement : un livre déjà possédé ne se rachète pas, et un livre à
  // 0 F ne passe pas par Mobile Money.
  private async assertDigitalOrdersPayable(userId: string, orders: Order[]): Promise<void> {
    // Le même livre ne doit pas figurer deux fois dans le lot payé.
    const seen = new Set<string>();
    for (const order of orders) {
      if (!order.isDigital) continue;
      for (const item of order.items ?? []) {
        const pid = item.variant?.productId;
        if (!pid) continue;
        if (seen.has(pid)) {
          throw new BadRequestException(
            'Le même livre apparaît deux fois dans cette commande : retirez le doublon de votre panier.',
          );
        }
        seen.add(pid);
      }
    }
    for (const order of orders) {
      if (!order.isDigital) continue;
      if (Number(order.total) <= 0) {
        throw new BadRequestException(
          'Ce livre est gratuit : aucun paiement n\'est nécessaire (validation gratuite).',
        );
      }
      const productIds = (order.items ?? [])
        .map(i => i.variant?.productId)
        .filter((id): id is string => !!id);
      if (productIds.length === 0) continue;
      const owned = await this.dataSource.query(
        `SELECT 1 FROM "library_items"
          WHERE "userId" = $1 AND "productId" = ANY($2::uuid[]) AND "revokedAt" IS NULL LIMIT 1`,
        [userId, productIds],
      );
      if (Array.isArray(owned) && owned.length > 0) {
        throw new BadRequestException(
          'Vous possédez déjà un des livres de cette commande : retrouvez-le dans votre Bibliothèque.',
        );
      }
      // Autre commande du même client pour ce livre, avec un paiement déjà
      // réussi ou encore en cours (moins de 20 min) : on évite le double débit.
      const others = await this.dataSource.query(
        `SELECT 1
           FROM "orders" o
           JOIN "order_items" oi ON oi."orderId" = o."id"
           JOIN "product_variants" v ON v."id" = oi."variantId"
           JOIN "payments" pay ON pay."orderId" = o."id"
          WHERE o."userId" = $1
            AND o."id" <> ALL($3::uuid[])
            AND v."productId" = ANY($2::uuid[])
            AND o."status" <> 'annulé'
            AND (pay."status" = 'success'
                 OR (pay."status" = 'en attente' AND pay."createdAt" > now() - interval '20 minutes'))
          LIMIT 1`,
        [userId, productIds, orders.map(o => o.id)],
      );
      if (Array.isArray(others) && others.length > 0) {
        throw new BadRequestException(
          'Un paiement est déjà en cours pour ce livre. Terminez-le ou patientez 20 minutes avant de réessayer.',
        );
      }
    }
  }

  // Finalise une commande de livres payée : statut « livré », entrée dans la
  // Bibliothèque, compteur de ventes. Appelée DANS la transaction de
  // confirmPayment. Renvoie les titres (pour les notifications).
  private async completeDigitalOrder(manager: EntityManager, order: Order): Promise<string[]> {
    await manager.update(Order, { id: order.id }, { status: OrderStatus.DELIVERED });
    order.status = OrderStatus.DELIVERED;

    const titles: string[] = [];
    for (const item of order.items) {
      const productId = item.variant?.productId;
      if (!productId) continue;

      const rows: Array<{ prod_name: string }> = await manager.query(
        `SELECT "prod_name" FROM "products" WHERE "id" = $1`,
        [productId],
      );
      if (rows[0]?.prod_name) titles.push(rows[0].prod_name);

      // Un livre par client : si le client le possède déjà (ligne active), on ne
      // touche à rien (WHERE ... IS NOT NULL) ; s'il avait été remboursé avant
      // (ligne révoquée), l'accès est rouvert à zéro.
      const inserted = await manager.query(
        `INSERT INTO "library_items" ("userId", "productId", "orderId")
         VALUES ($1, $2, $3)
         ON CONFLICT ("userId", "productId") DO UPDATE SET
           "orderId" = EXCLUDED."orderId",
           "revokedAt" = NULL, "revokedReason" = NULL,
           "downloadCount" = 0, "firstDownloadedAt" = NULL, "lastDownloadedAt" = NULL,
           "createdAt" = now()
         WHERE "library_items"."revokedAt" IS NOT NULL
         RETURNING "id"`,
        [order.userId, productId, order.id],
      );
      if (!Array.isArray(inserted) || inserted.length === 0) {
        this.logger.warn(
          `[LIVRE] Le client ${order.userId} possédait déjà le livre ${productId} `
          + `(commande ${order.orderNumber}) : double achat à examiner.`,
        );
      }

      await manager.increment(Product, { id: productId }, 'totalVentes', item.quantity);
    }
    return titles;
  }

  // POST /payments/free — valide des livres numériques à 0 F : même chemin que
  // le paiement (commission à 0, Bibliothèque, notifications), sans FeexPay.
  async claimFreeOrders(userId: string, orderIds: string[], ip: string) {
    const orders = await this.orderRepo.find({
      where:     { id: In(orderIds), userId },
      relations: ['items', 'items.variant'],
    });
    if (orders.length !== new Set(orderIds).size) {
      throw new NotFoundException('Une ou plusieurs commandes sont introuvables');
    }
    for (const order of orders) {
      if (!order.isDigital || Number(order.total) !== 0) {
        throw new BadRequestException(
          `La commande ${order.orderNumber} n'est pas un livre gratuit.`,
        );
      }
      // Déjà validée (réponse perdue lors d'un essai précédent) : on la saute
      // plus bas sans erreur.
      if (order.status !== OrderStatus.PENDING && order.status !== OrderStatus.DELIVERED) {
        throw new BadRequestException(
          `La commande ${order.orderNumber} ne peut plus être validée.`,
        );
      }
    }
    // Déjà possédé ? (les commandes à 0 F sont exclues du contrôle « payable »)
    for (const order of orders) {
      if (order.status === OrderStatus.DELIVERED) continue;
      const productIds = order.items.map(i => i.variant?.productId).filter((id): id is string => !!id);
      const owned = await this.dataSource.query(
        `SELECT 1 FROM "library_items"
          WHERE "userId" = $1 AND "productId" = ANY($2::uuid[]) AND "revokedAt" IS NULL LIMIT 1`,
        [userId, productIds],
      );
      if (Array.isArray(owned) && owned.length > 0) {
        throw new BadRequestException(
          'Vous possédez déjà un de ces livres : retrouvez-le dans votre Bibliothèque.',
        );
      }
    }

    const done: string[] = [];
    for (const order of orders) {
      let payment = await this.paymentRepo.findOne({ where: { orderId: order.id } });
      if (!payment) {
        try {
          payment          = this.paymentRepo.create();
          payment.orderId  = order.id;
          payment.method   = PaymentMethod.FREE;
          payment.operator = null;
          payment.status   = PaymentStatus.PENDING;
          payment.montant  = 0;
          await this.paymentRepo.save(payment);
        } catch {
          // Course (double clic) : la ligne existe déjà, on la relit.
          payment = await this.paymentRepo.findOne({ where: { orderId: order.id } });
        }
      }
      if (!payment) throw new BadRequestException('Validation impossible, réessayez.');
      if (payment.status === PaymentStatus.SUCCESS) {
        done.push(order.orderNumber);
        continue;
      }
      if (order.status === OrderStatus.DELIVERED) continue;
      // Un essai précédent a pu laisser ce paiement gratuit « échoué » : on le rouvre.
      if (payment.status === PaymentStatus.FAILED && payment.method === PaymentMethod.FREE) {
        await this.paymentRepo.update({ id: payment.id }, { status: PaymentStatus.PENDING });
      }
      await this.confirmPayment(payment.id, `FREE-${order.orderNumber}`, ip);
      done.push(order.orderNumber);
    }
    return {
      message: done.length > 1
        ? 'Vos livres sont disponibles dans votre Bibliothèque'
        : 'Votre livre est disponible dans votre Bibliothèque',
      orders: done,
    };
  }

  // ADMIN — aperçu avant de rembourser un livre depuis un ticket : le livre
  // a-t-il été téléchargé ? le délai de 24 h est-il respecté ?
  async getDigitalRefundPreview(orderId: string, ticketId?: string) {
    const order = await this.orderRepo.findOne({ where: { id: orderId } });
    if (!order) throw new NotFoundException('Commande introuvable');
    if (!order.isDigital) {
      throw new BadRequestException('Cette commande ne contient pas de livre numérique');
    }
    const payment = await this.paymentRepo.findOne({ where: { orderId } });
    const existing = await this.refundRepo.findOne({ where: { orderId } });
    const books: Array<{
      productId: string; title: string; downloadCount: number;
      firstDownloadedAt: Date | null; revokedAt: Date | null;
    }> = await this.dataSource.query(
      `SELECT l."productId", p."prod_name" AS "title", l."downloadCount",
              l."firstDownloadedAt", l."revokedAt"
         FROM "library_items" l
         JOIN "products" p ON p."id" = l."productId"
        WHERE l."orderId" = $1`,
      [orderId],
    );
    const fixed   = await this.getFixedRefundAmount(orderId);
    const montant = fixed === null ? null : this.round2(Math.min(fixed, Number(payment?.montant ?? 0)));
    const { windowOpen, windowEndsAt, reason } = await this.digitalRefundWindow(order, payment, ticketId);
    return {
      orderId,
      orderNumber:   order.orderNumber,
      paymentStatus: payment?.status ?? null,
      paidAt:        payment?.paidAt ?? null,
      totalPaye:     payment ? Number(payment.montant) : 0,
      montantRemboursable: montant ?? 0,
      dejaRembourse: !!existing,
      fenetreOuverte: windowOpen,
      fenetreJusquau: windowEndsAt,
      fenetreMotif:   reason,
      livres:        books,
      jamaisTelecharge: books.length > 0 && books.every(b => (b.downloadCount ?? 0) === 0),
    };
  }

  // Le client a 24 h après l'achat pour SIGNALER le problème. Si un ticket (de
  // CE client, pour CETTE commande) a été ouvert dans ce délai, l'admin peut
  // traiter plus tard : le délai porte sur le signalement, pas sur le traitement.
  private async digitalRefundWindow(
    order: Order,
    payment: Payment | null,
    ticketId?: string,
  ): Promise<{ windowOpen: boolean; windowEndsAt: Date | null; reason: string }> {
    if (!payment?.paidAt) {
      return { windowOpen: false, windowEndsAt: null, reason: 'Aucun paiement confirmé' };
    }
    const endsAt = new Date(
      new Date(payment.paidAt).getTime() + DIGITAL_REFUND_WINDOW_HOURS * 60 * 60 * 1000,
    );
    if (Date.now() <= endsAt.getTime()) {
      return { windowOpen: true, windowEndsAt: endsAt, reason: 'Dans les 24 h après l\'achat' };
    }
    if (ticketId) {
      const rows: Array<{ createdAt: Date }> = await this.dataSource.query(
        `SELECT "createdAt" FROM "support_tickets"
          WHERE "id" = $1 AND "orderId" = $2 AND "userId" = $3 LIMIT 1`,
        [ticketId, order.id, order.userId],
      );
      const paidMs = new Date(payment.paidAt).getTime();
      const createdMs = rows[0] ? new Date(rows[0].createdAt).getTime() : 0;
      if (rows[0] && createdMs >= paidMs && createdMs <= endsAt.getTime()) {
        return { windowOpen: true, windowEndsAt: endsAt, reason: 'Ticket ouvert par le client dans les 24 h' };
      }
    }
    return {
      windowOpen: false,
      windowEndsAt: endsAt,
      reason: 'Délai de 24 h dépassé et aucun ticket ouvert dans ce délai',
    };
  }

  // ADMIN — rembourse un livre numérique (fichier défectueux ou jamais
  // téléchargé, constaté via un ticket). Réutilise le circuit habituel
  // (montant = part du vendeur, commission plateforme non rendue), puis retire
  // l'accès à la Bibliothèque.
  async adminRefundDigitalOrder(
    adminId: string,
    dto: { orderId: string; motif: string; ticketId?: string },
    ip: string,
  ) {
    const order = await this.orderRepo.findOne({ where: { id: dto.orderId } });
    if (!order) throw new NotFoundException('Commande introuvable');
    if (!order.isDigital) {
      throw new BadRequestException('Cette commande ne contient pas de livre numérique');
    }
    const payment = await this.paymentRepo.findOne({ where: { orderId: dto.orderId } });
    if (!payment || payment.status !== PaymentStatus.SUCCESS) {
      throw new BadRequestException('Aucun paiement confirmé trouvé pour cette commande');
    }
    if (Number(payment.montant) <= 0) {
      throw new BadRequestException('Livre gratuit : rien à rembourser.');
    }
    const win = await this.digitalRefundWindow(order, payment, dto.ticketId);
    if (!win.windowOpen) {
      throw new BadRequestException(win.reason + ' : remboursement impossible.');
    }
    // Jamais plus que ce que le client a réellement payé (cas d'un code promo
    // financé par la plateforme : la part du vendeur peut dépasser le payé).
    const fixed   = await this.getFixedRefundAmount(order.id);
    const montant = fixed === null ? null : this.round2(Math.min(fixed, Number(payment.montant)));
    if (montant === null || montant <= 0) {
      throw new BadRequestException('Aucun montant remboursable pour cette commande.');
    }

    // Création SOUS verrou de la commande : deux clics (ou deux admins) en
    // même temps ne créent pas deux remboursements.
    const refund = await this.dataSource.transaction(async (manager) => {
      await manager.query('SELECT "id" FROM "orders" WHERE "id" = $1 FOR UPDATE', [order.id]);
      const dup = await manager.findOne(Refund, { where: { orderId: order.id } });
      if (dup) {
        throw new BadRequestException('Un remboursement existe déjà pour cette commande');
      }
      const created       = manager.create(Refund, {
        paymentId:   payment.id,
        orderId:     order.id,
        montantRemb: montant,
        motif:       `[Livre numérique] ${dto.motif}`,
        status:      RefundStatus.PENDING,
      });
      return manager.save(created);
    });

    await this.logService.log({
      actorId:    adminId,
      actorType:  ActorType.ADMIN,
      action:     LogAction.REFUND_REQUESTED,
      entityType: 'refund',
      entityId:   refund.id,
      newValue:   { amount: montant, motif: dto.motif, ticketId: dto.ticketId ?? null, digital: true },
      ipAddress:  ip,
    });

    // L'approbation retire aussi l'accès au livre (même transaction, voir
    // approveRefundAndReclaimEarnings). Si elle échoue, on supprime la demande
    // « en attente » pour que l'admin puisse réessayer proprement.
    let result: unknown;
    try {
      result = await this.processRefund(refund.id, adminId, 'approve', ip);
    } catch (err) {
      await this.refundRepo.delete({ id: refund.id, status: RefundStatus.PENDING }).catch(() => undefined);
      throw err;
    }
    await this.logService.log({
      actorId:    adminId,
      actorType:  ActorType.ADMIN,
      action:     LogAction.EBOOK_REFUNDED,
      entityType: 'order',
      entityId:   order.id,
      newValue:   { refundId: refund.id, ticketId: dto.ticketId ?? null },
      ipAddress:  ip,
    });

    return { ...(result as object), refundId: refund.id, accesRetire: true };
  }
}