import {
  Injectable,
  NotFoundException,
  BadRequestException,
  ForbiddenException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, DataSource } from 'typeorm';
import { MailerService } from '@nestjs-modules/mailer';

import { Payment, PaymentStatus, PaymentMethod } from './entities/payment.entity';
import { Commission, CommissionStatus }           from './entities/commission.entity';
import { Refund, RefundStatus }                   from './entities/refund.entity';
import { Order, OrderStatus }                     from '../orders/entities/order.entity';
import { ProductVariant }                         from '../products/entities/product-variant.entity';
import { VendorProfile }                          from '../users/entities/vendor-profile.entity';
import { User }                                   from '../users/entities/user.entity';

import { InitiatePaymentDto } from './dto/initiate-payment.dto';
import { RequestRefundDto }   from './dto/request-refund.dto';
import { ActivityLogService } from '../../common/services/activity-log.service';
import {
  ActorType,
  LogAction,
} from '../../common/entities/activity-log.entity';

// Taux de commission par défaut si non configuré sur le vendeur
const DEFAULT_COMMISSION_RATE = 10; // 10%

@Injectable()
export class PaymentsService {

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
    private readonly mailerService: MailerService,
    private readonly logService:    ActivityLogService,
  ) {}

  // ─────────────────────────────────────────────────────
  // INITIER UN PAIEMENT
  // ─────────────────────────────────────────────────────
  async initiatePayment(
    userId: string,
    dto:    InitiatePaymentDto,
    ip:     string,
  ) {
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

    // 3. Vérifier qu'un paiement n'est pas déjà en cours
    const existingPayment = await this.paymentRepo.findOne({
      where: { orderId: dto.orderId },
    });

    if (existingPayment) {
      if (existingPayment.status === PaymentStatus.SUCCESS) {
        throw new BadRequestException('Cette commande est déjà payée');
      }
      // Si paiement échoué → on en crée un nouveau
      if (existingPayment.status === PaymentStatus.PENDING) {
        throw new BadRequestException(
          'Un paiement est déjà en cours pour cette commande'
        );
      }
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

    // 5. Créer le paiement en statut PENDING
    const payment         = this.paymentRepo.create();
    payment.orderId       = dto.orderId;
    payment.method        = dto.method;
    payment.operator      = dto.operator ?? null;
    payment.status        = PaymentStatus.PENDING;
    payment.montant        = order.total;

    await this.paymentRepo.save(payment);

    await this.logService.log({
      actorId:    userId,
      actorType:  ActorType.CLIENT,
      action:     LogAction.PAYMENT_FAILED, // sera mis à jour à la confirmation
      entityType: 'payment',
      entityId:   payment.id,
      newValue:   { method: dto.method, amount: order.total },
      ipAddress:  ip,
    });

    // ⚠️ En production : ici on appellerait l'API de l'opérateur
    // (MTN MoMo, Moov Money, Wave, Stripe...)
    // et on retournerait l'URL de paiement ou le prompt USSD
    // Pour l'instant on retourne les infos pour simulation

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
  // CONFIRMER UN PAIEMENT (callback opérateur)
  // ─────────────────────────────────────────────────────
  async confirmPayment(
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

    // Transaction atomique : tout réussit ou tout échoue
    await this.dataSource.transaction(async (manager) => {

      // 1. Marquer le paiement comme réussi
      payment.status      = PaymentStatus.SUCCESS;
      payment.providerRef = providerRef;
      payment.paidAt      = new Date();
      await manager.save(payment);

      // 2. Passer la commande en PREPARING
      const order        = payment.order;
      order.status       = OrderStatus.PREPARING;
      await manager.save(order);

      // 3. Décrémenter le stock de chaque variante
      for (const item of order.items) {
        await manager.decrement(
          ProductVariant,
          { id: item.variantId },
          'stockQuantity',
          item.quantity,
        );

        // Vérifier si le stock est sous le seuil d'alerte
        const variant = await manager.findOne(ProductVariant, {
          where: { id: item.variantId },
        });

        if (
          variant &&
          variant.stockQuantity <= variant.lowStockAlert
        ) {
          // ⚠️ Notifier le vendeur (sera géré dans le module notifications)
          console.log(
            `[STOCK ALERT] Variante ${variant.sku} : `
            + `${variant.stockQuantity} unité(s) restante(s)`
          );
        }
      }

      // 4. Calculer et créer la commission
      await this.createCommission(manager, order);
    });

    // 5. Envoyer email de confirmation au client
    const user = payment.order.user;
    await this.mailerService.sendMail({
      to:      user.email,
      subject: `✅ Paiement confirmé — Commande ${payment.order.orderNumber}`,
      html: `
        <p>Bonjour ${user.prenom},</p>
        <p>Votre paiement de <strong>${payment.montant} FCFA</strong> 
           a été confirmé pour la commande 
           <strong>${payment.order.orderNumber}</strong>.</p>
        <p>Votre commande est maintenant en préparation.</p>
      `,
    });

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
  // ÉCHEC D'UN PAIEMENT
  // ─────────────────────────────────────────────────────
  async failPayment(paymentId: string, ip: string) {
    const payment = await this.paymentRepo.findOne({
      where: { id: paymentId },
    });

    if (!payment) throw new NotFoundException('Paiement introuvable');

    if (payment.status !== PaymentStatus.PENDING) {
      throw new BadRequestException('Statut de paiement invalide');
    }

    payment.status = PaymentStatus.FAILED;
    await this.paymentRepo.save(payment);

    await this.logService.log({
      actorType:  ActorType.SYSTEM,
      action:     LogAction.PAYMENT_FAILED,
      entityType: 'payment',
      entityId:   paymentId,
      ipAddress:  ip,
    });

    return { message: 'Paiement marqué comme échoué' };
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

    // 5. Vérifier que le montant ne dépasse pas le paiement
    if (Number(dto.montantRemb) > Number(payment.montant)) {
      throw new BadRequestException(
        `Le montant du remboursement ne peut pas dépasser `
        + `${payment.montant} FCFA`
      );
    }

    // 6. Créer la demande
    const refund          = this.refundRepo.create();
    refund.paymentId      = payment.id;
    refund.orderId        = dto.orderId;
    refund.montantRemb    = dto.montantRemb;
    refund.motif          = dto.motif;
    refund.status         = RefundStatus.PENDING;

    await this.refundRepo.save(refund);

    await this.logService.log({
      actorId:    userId,
      actorType:  ActorType.CLIENT,
      action:     LogAction.REFUND_REQUESTED,
      entityType: 'refund',
      entityId:   refund.id,
      newValue:   { amount: dto.montantRemb, motif: dto.motif },
      ipAddress:  ip,
    });

    return {
      message:  'Demande de remboursement soumise avec succès',
      refundId: refund.id,
    };
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — TRAITER UN REMBOURSEMENT
  // ─────────────────────────────────────────────────────
  async processRefund(
    refundId: string,
    adminId:  string,
    action:   'approve' | 'reject',
    ip:       string,
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

    refund.processedById = adminId;
    refund.processedAt   = new Date();

    if (action === 'approve') {
      refund.status = RefundStatus.APPROVED;

      // Marquer le paiement comme remboursé
      refund.payment.status = PaymentStatus.REFUNDED;
      await this.paymentRepo.save(refund.payment);

      // Notifier le client
      await this.mailerService.sendMail({
        to:      refund.order.user.email,
        subject: '✅ Remboursement approuvé',
        html: `
          <p>Bonjour ${refund.order.user.prenom},</p>
          <p>Votre demande de remboursement de 
             <strong>${refund.montantRemb} FCFA</strong> 
             pour la commande 
             <strong>${refund.order.orderNumber}</strong> 
             a été approuvée.</p>
          <p>Le montant sera crédité sous 3 à 5 jours ouvrables.</p>
        `,
      });

    } else {
      refund.status = RefundStatus.REJECTED;

      // Notifier le client du refus
      await this.mailerService.sendMail({
        to:      refund.order.user.email,
        subject: 'Demande de remboursement',
        html: `
          <p>Bonjour ${refund.order.user.prenom},</p>
          <p>Votre demande de remboursement pour la commande 
             <strong>${refund.order.orderNumber}</strong> 
             n'a pas pu être approuvée.</p>
          <p>Pour plus d'informations, contactez notre support.</p>
        `,
      });
    }

    await this.refundRepo.save(refund);

    await this.logService.log({
      actorId:    adminId,
      actorType:  ActorType.ADMIN,
      action:     LogAction.REFUND_PROCESSED,
      entityType: 'refund',
      entityId:   refundId,
      newValue:   { action, status: refund.status },
      ipAddress:  ip,
    });

    return {
      message: action === 'approve'
        ? 'Remboursement approuvé'
        : 'Demande de remboursement refusée',
      status: refund.status,
    };
  }

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
      .orderBy('refund.requestedAt', 'DESC')
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

    // Taux de commission (par défaut 10% si non configuré)
    const rate             = DEFAULT_COMMISSION_RATE;
    const orderTotal       = Number(order.total);
    const commissionAmount = Number(
      ((orderTotal * rate) / 100).toFixed(2)
    );
    const vendorAmount     = Number(
      (orderTotal - commissionAmount).toFixed(2)
    );

    const commission              = manager.create(Commission);
    commission.orderId            = order.id;
    commission.vendorId           = order.vendorId;
    commission.totalCommande      = orderTotal;
    commission.taux               = rate;
    commission.montantCommission  = commissionAmount;
    commission.commissionVendor   = vendorAmount;
    commission.status             = CommissionStatus.PENDING;

    await manager.save(commission);
  }
}