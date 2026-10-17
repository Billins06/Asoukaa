import {
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, Between, MoreThanOrEqual, DataSource } from 'typeorm';

import { User }                              from '../users/entities/user.entity';
import { VendorProfile, VendorStatus }       from '../users/entities/vendor-profile.entity';
import { DeliveryAgentProfile, AgentStatus } from '../users/entities/delivery-agent-profile.entity';
import { Product, ProductStatus }            from '../products/entities/product.entity';
import { Order, OrderStatus }                from '../orders/entities/order.entity';
import { OrderItem }                         from '../orders/entities/order-item.entity';
import { Payment, PaymentStatus }            from '../payments/entities/payment.entity';
import { Commission }                        from '../payments/entities/commission.entity';
import { Review, ReviewStatus }              from '../reviews/entities/review.entity';
import { Delivery, DeliveryStatus }          from '../delivery/entities/delivery.entity';
import { Refund, RefundStatus }              from '../payments/entities/refund.entity';
import { TicketStatus }                      from '../support-tickets/support-ticket.constants';
import { OrderConfirmationService }          from '../orders/order-confirmation.service';
import { paymentsToReviewWhere }             from '../payments/payments-to-review.criteria';

import {
  DashboardQueryDto,
  DashboardPeriod,
} from './dto/dashboard-query.dto';

@Injectable()
export class DashboardService {

  constructor(
    @InjectRepository(User)
    private readonly userRepo: Repository<User>,

    @InjectRepository(VendorProfile)
    private readonly vendorRepo: Repository<VendorProfile>,

    @InjectRepository(DeliveryAgentProfile)
    private readonly agentRepo: Repository<DeliveryAgentProfile>,

    @InjectRepository(Product)
    private readonly productRepo: Repository<Product>,

    @InjectRepository(Order)
    private readonly orderRepo: Repository<Order>,

    @InjectRepository(OrderItem)
    private readonly orderItemRepo: Repository<OrderItem>,

    @InjectRepository(Payment)
    private readonly paymentRepo: Repository<Payment>,

    @InjectRepository(Commission)
    private readonly commissionRepo: Repository<Commission>,

    @InjectRepository(Review)
    private readonly reviewRepo: Repository<Review>,

    @InjectRepository(Delivery)
    private readonly deliveryRepo: Repository<Delivery>,

    private readonly dataSource: DataSource,

    private readonly orderConfirmation: OrderConfirmationService,
  ) {}

  // ═════════════════════════════════════════════════════
  //          COMPTEURS DU MENU ADMIN
  // GET /api/v1/admin/sidebar-counts
  // ═════════════════════════════════════════════════════
  // Un seul aller-retour pour toutes les pastilles du menu. Chaque compteur
  // reprend EXACTEMENT le critère de la page qu'il annonce :
  //  - vendors / agents    : inscriptions « en attente » (pages « pending » et
  //                          getAdminOverview) ;
  //  - supportTickets      : tickets ouverts OU en cours ;
  //  - refunds             : remboursements « en attente » ;
  //  - ordersToConfirm     : même WHERE que GET /admin/orders/late-confirmation ;
  //  - securityAlerts      : alerte « Ce n'est pas moi » non acquittée
  //                          (securityAlertAt non nul ET acquittement nul ou
  //                          antérieur à l'alerte) ;
  //  - paymentsToReview    : paiements reçus (FeexPay SUCCESS) mais commande
  //                          non validée (stock / annulée) — critère détaillé
  //                          dans payments/payments-to-review.criteria.ts ;
  //                          même filtre que GET /payments?toReview=true.
  async getSidebarCounts() {
    const [
      vendors,
      agents,
      [ticketsRow],
      refunds,
      ordersToConfirm,
      [alertsRow],
      [reviewRow],
    ] = await Promise.all([
      this.vendorRepo.count({ where: { status: VendorStatus.PENDING } }),
      this.agentRepo.count({ where: { status: AgentStatus.PENDING } }),
      this.dataSource.query(
        `SELECT COUNT(*)::int AS "n" FROM "support_tickets" WHERE "status" IN ($1, $2)`,
        [TicketStatus.OUVERT, TicketStatus.EN_COURS],
      ),
      this.dataSource.getRepository(Refund).count({
        where: { status: RefundStatus.PENDING },
      }),
      this.orderConfirmation.countLateConfirmation(),
      this.dataSource.query(
        `SELECT COUNT(*)::int AS "n" FROM "users"
         WHERE "securityAlertAt" IS NOT NULL
           AND ("securityAlertAckedAt" IS NULL OR "securityAlertAckedAt" < "securityAlertAt")`,
      ),
      this.dataSource.query(
        `SELECT COUNT(*)::int AS "n" FROM "payments" "p"
         WHERE ${paymentsToReviewWhere('p')}`,
      ),
    ]);

    return {
      vendors,
      agents,
      supportTickets:  Number(ticketsRow?.n ?? 0),
      refunds,
      ordersToConfirm,
      securityAlerts:  Number(alertsRow?.n ?? 0),
      paymentsToReview: Number(reviewRow?.n ?? 0),
    };
  }

  // ═════════════════════════════════════════════════════
  //          DASHBOARD ADMIN
  // ═════════════════════════════════════════════════════

  // ─────────────────────────────────────────────────────
  // VUE D'ENSEMBLE ADMIN
  // ─────────────────────────────────────────────────────
  async getAdminOverview(query: DashboardQueryDto) {
    const { startDate, endDate } = this.parsePeriod(query);

    // Compteurs globaux
    const [
      totalUsers,
      totalVendors,
      totalAgents,
      totalProducts,
      pendingVendors,
      pendingAgents,
      pendingReviews,
    ] = await Promise.all([
      this.userRepo.count(),
      this.vendorRepo.count({ where: { status: VendorStatus.APPROVED } }),
      this.agentRepo.count({ where: { status: AgentStatus.APPROVED } }),
      this.productRepo.count({ where: { status: ProductStatus.ACTIVE } }),
      this.vendorRepo.count({ where: { status: VendorStatus.PENDING } }),
      this.agentRepo.count({ where: { status: AgentStatus.PENDING } }),
      this.reviewRepo.count({ where: { status: ReviewStatus.PENDING } }),
    ]);

    // Stats commandes sur la période
    const ordersStats = await this.orderRepo
      .createQueryBuilder('order')
      .select('COUNT(order.id)',    'totalOrders')
      .addSelect('SUM(order.total)', 'totalRevenue')
      .where('order.createdAt BETWEEN :start AND :end', {
        start: startDate,
        end:   endDate,
      })
      .getRawOne();

    // Commandes par statut
    const ordersByStatus = await this.orderRepo
      .createQueryBuilder('order')
      .select('order.status', 'status')
      .addSelect('COUNT(order.id)', 'count')
      .where('order.createdAt BETWEEN :start AND :end', {
        start: startDate,
        end:   endDate,
      })
      .groupBy('order.status')
      .getRawMany();

    // Total commissions Asoukaa
    const commissionsStats = await this.commissionRepo
      .createQueryBuilder('commission')
      .select('SUM(commission.montantCommission)', 'totalCommissions')
      .where('commission.createdAt BETWEEN :start AND :end', {
        start: startDate,
        end:   endDate,
      })
      .getRawOne();

    return {
      counters: {
        totalUsers,
        totalVendors,
        totalAgents,
        totalProducts,
        pendingVendors,
        pendingAgents,
        pendingReviews,
      },
      period: {
        start: startDate,
        end:   endDate,
        totalOrders:      Number(ordersStats?.totalOrders)     || 0,
        totalRevenue:     Number(ordersStats?.totalRevenue)    || 0,
        totalCommissions: Number(commissionsStats?.totalCommissions) || 0,
        ordersByStatus,
      },
    };
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — REVENUS PAR JOUR (pour graphique)
  // ─────────────────────────────────────────────────────
  async getAdminRevenueChart(query: DashboardQueryDto) {
    const { startDate, endDate } = this.parsePeriod(query);

    const result = await this.orderRepo
      .createQueryBuilder('order')
      .select(`DATE(order.createdAt)`, 'date')
      .addSelect('SUM(order.total)',    'revenue')
      .addSelect('COUNT(order.id)',     'orderCount')
      .where('order.createdAt BETWEEN :start AND :end', {
        start: startDate,
        end:   endDate,
      })
      .andWhere('order.status != :cancelled', {
        cancelled: OrderStatus.CANCELLED,
      })
      .groupBy('DATE(order.createdAt)')
      .orderBy('date', 'ASC')
      .getRawMany();

    return result.map(r => ({
      date:       r.date,
      revenue:    Number(r.revenue) || 0,
      orderCount: Number(r.orderCount) || 0,
    }));
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — TOP PRODUITS LES PLUS VENDUS
  // ─────────────────────────────────────────────────────
  async getAdminTopProducts(query: DashboardQueryDto, limit = 10) {
    const { startDate, endDate } = this.parsePeriod(query);

    const result = await this.orderItemRepo
      .createQueryBuilder('item')
      .leftJoin('item.variant',           'variant')
      .leftJoin('variant.product',        'product')
      .leftJoin('item.order',             'order')
      .select('product.id',               'productId')
      .addSelect('product.prod_name',     'productName')
      .addSelect('SUM(item.quantity)',    'totalSold')
      .addSelect('SUM(item.quantity * item.unitPrice)', 'totalRevenue')
      .where('order.createdAt BETWEEN :start AND :end', {
        start: startDate,
        end:   endDate,
      })
      .andWhere('order.status != :cancelled', {
        cancelled: OrderStatus.CANCELLED,
      })
      .groupBy('product.id, product.prod_name')
      .orderBy('"totalSold"', 'DESC')
      .limit(limit)
      .getRawMany();

    return result.map(r => ({
      productId:    r.productId,
      productName:  r.productName,
      totalSold:    Number(r.totalSold) || 0,
      totalRevenue: Number(r.totalRevenue) || 0,
    }));
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — TOP VENDEURS
  // ─────────────────────────────────────────────────────
  async getAdminTopVendors(query: DashboardQueryDto, limit = 10) {
    const { startDate, endDate } = this.parsePeriod(query);

    const result = await this.orderRepo
      .createQueryBuilder('order')
      .leftJoin('order.vendor',           'vendor')
      .select('vendor.id',                'vendorId')
      .addSelect('vendor.shopName',       'shopName')
      .addSelect('COUNT(order.id)',       'totalOrders')
      .addSelect('SUM(order.total)',      'totalRevenue')
      .where('order.createdAt BETWEEN :start AND :end', {
        start: startDate,
        end:   endDate,
      })
      .andWhere('order.status != :cancelled', {
        cancelled: OrderStatus.CANCELLED,
      })
      .groupBy('vendor.id, vendor.shopName')
      .orderBy('"totalRevenue"', 'DESC')
      .limit(limit)
      .getRawMany();

    return result.map(r => ({
      vendorId:     r.vendorId,
      shopName:     r.shopName,
      totalOrders:  Number(r.totalOrders) || 0,
      totalRevenue: Number(r.totalRevenue) || 0,
    }));
  }

  // ═════════════════════════════════════════════════════
  //          DASHBOARD VENDEUR
  // ═════════════════════════════════════════════════════

  // ─────────────────────────────────────────────────────
  // VENDEUR — VUE D'ENSEMBLE
  // ─────────────────────────────────────────────────────
  async getVendorOverview(userId: string, query: DashboardQueryDto) {
    const vendor = await this.vendorRepo.findOne({
      where: { userId },
    });

    if (!vendor) throw new NotFoundException('Boutique introuvable');

    const { startDate, endDate } = this.parsePeriod(query);

    // Compteurs spécifiques à la boutique
    const [
      totalProducts,
      activeProducts,
      pendingOrders,
      processingOrders,
    ] = await Promise.all([
      this.productRepo.count({ where: { vendorId: vendor.id } }),
      this.productRepo.count({
        where: { vendorId: vendor.id, status: ProductStatus.ACTIVE },
      }),
      this.orderRepo.count({
        where: { vendorId: vendor.id, status: OrderStatus.PENDING },
      }),
      this.orderRepo.count({
        where: { vendorId: vendor.id, status: OrderStatus.PREPARING },
      }),
    ]);

    // Revenus de la période
    // ⚠️ RÈGLE MÉTIER : le vendeur ne touche RIEN des frais de livraison
    // (livreur 80 % + plateforme). Son chiffre d'affaires = ses PRODUITS après
    // remise (subtotal − rabais), PAS order.total. Le net déduit la vraie
    // commission (table commissions, créée au paiement) : la colonne
    // orders.montantCommission est toujours 0 et ne sert à rien ici.
    const revenueStats = await this.orderRepo
      .createQueryBuilder('order')
      .leftJoin(Commission, 'comm', 'comm.orderId = order.id')
      .select('COUNT(order.id)',     'totalOrders')
      .addSelect('SUM(order.subtotal - order.rabais)', 'grossRevenue')
      // Net vendeur = produits après remise − commission − reprises pour
      // remboursement client approuvé (vendor_earning_adjustments ; sous-requête
      // plutôt que jointure pour ne jamais dupliquer une commande).
      .addSelect(
        'SUM(order.subtotal - order.rabais - COALESCE(comm.montantCommission, 0)'
        + ' - COALESCE((SELECT SUM(adj."montantVendeur") FROM "vendor_earning_adjustments" adj WHERE adj."orderId" = order.id), 0))',
        'netRevenue',
      )
      .addSelect(
        'COALESCE(SUM((SELECT SUM(adj2."montantVendeur") FROM "vendor_earning_adjustments" adj2 WHERE adj2."orderId" = order.id)), 0)',
        'reprisesRemboursements',
      )
      .where('order.vendorId = :vendorId', { vendorId: vendor.id })
      .andWhere('order.createdAt BETWEEN :start AND :end', {
        start: startDate,
        end:   endDate,
      })
      .andWhere('order.status != :cancelled', {
        cancelled: OrderStatus.CANCELLED,
      })
      .getRawOne();

    // Note moyenne globale de la boutique
    const reviewStats = await this.reviewRepo
      .createQueryBuilder('review')
      .leftJoin('review.product', 'product')
      .select('AVG(review.notation)', 'avgRating')
      .addSelect('COUNT(review.id)',  'reviewCount')
      .where('product.vendorId = :vendorId', { vendorId: vendor.id })
      .andWhere('review.status = :status', { status: ReviewStatus.APPROVED })
      .getRawOne();

    return {
      shopName:         vendor.shopName,
      counters: {
        totalProducts,
        activeProducts,
        pendingOrders,
        processingOrders,
      },
      period: {
        start:         startDate,
        end:           endDate,
        totalOrders:   Number(revenueStats?.totalOrders) || 0,
        grossRevenue:  Number(revenueStats?.grossRevenue) || 0,
        netRevenue:    Number(revenueStats?.netRevenue) || 0,
        // Champ AJOUTÉ : total repris sur ces commandes (remboursements clients).
        reprisesRemboursements: Number(revenueStats?.reprisesRemboursements) || 0,
      },
      reputation: {
        avgRating:   Number(reviewStats?.avgRating)?.toFixed(2) || 0,
        reviewCount: Number(reviewStats?.reviewCount) || 0,
      },
    };
  }

  // ─────────────────────────────────────────────────────
  // VENDEUR — REVENUS PAR JOUR
  // ─────────────────────────────────────────────────────
  async getVendorRevenueChart(userId: string, query: DashboardQueryDto) {
    const vendor = await this.vendorRepo.findOne({
      where: { userId },
    });

    if (!vendor) throw new NotFoundException('Boutique introuvable');

    const { startDate, endDate } = this.parsePeriod(query);

    const result = await this.orderRepo
      .createQueryBuilder('order')
      .select('DATE(order.createdAt)', 'date')
      // Produits après remise, hors frais de livraison (jamais pour le vendeur)
      .addSelect('SUM(order.subtotal - order.rabais)', 'revenue')
      .addSelect('COUNT(order.id)',    'orderCount')
      .where('order.vendorId = :vendorId', { vendorId: vendor.id })
      .andWhere('order.createdAt BETWEEN :start AND :end', {
        start: startDate,
        end:   endDate,
      })
      .andWhere('order.status != :cancelled', {
        cancelled: OrderStatus.CANCELLED,
      })
      .groupBy('DATE(order.createdAt)')
      .orderBy('date', 'ASC')
      .getRawMany();

    return result.map(r => ({
      date:       r.date,
      revenue:    Number(r.revenue) || 0,
      orderCount: Number(r.orderCount) || 0,
    }));
  }

  // ─────────────────────────────────────────────────────
  // VENDEUR — TOP PRODUITS DE MA BOUTIQUE
  // ─────────────────────────────────────────────────────
  async getVendorTopProducts(
    userId: string,
    query:  DashboardQueryDto,
    limit:  number = 10,
  ) {
    const vendor = await this.vendorRepo.findOne({
      where: { userId },
    });

    if (!vendor) throw new NotFoundException('Boutique introuvable');

    const { startDate, endDate } = this.parsePeriod(query);

    const result = await this.orderItemRepo
      .createQueryBuilder('item')
      .leftJoin('item.variant',           'variant')
      .leftJoin('variant.product',        'product')
      .leftJoin('item.order',             'order')
      .select('product.id',               'productId')
      .addSelect('product.prod_name',     'productName')
      .addSelect('SUM(item.quantity)',    'totalSold')
      .addSelect('SUM(item.quantity * item.unitPrice)', 'totalRevenue')
      .where('product.vendorId = :vendorId', { vendorId: vendor.id })
      .andWhere('order.createdAt BETWEEN :start AND :end', {
        start: startDate,
        end:   endDate,
      })
      .andWhere('order.status != :cancelled', {
        cancelled: OrderStatus.CANCELLED,
      })
      .groupBy('product.id, product.prod_name')
      .orderBy('"totalSold"', 'DESC')
      .limit(limit)
      .getRawMany();

    return result.map(r => ({
      productId:    r.productId,
      productName:  r.productName,
      totalSold:    Number(r.totalSold) || 0,
      totalRevenue: Number(r.totalRevenue) || 0,
    }));
  }

  // ═════════════════════════════════════════════════════
  //          MÉTHODE PRIVÉE — CALCUL DE PÉRIODE
  // ═════════════════════════════════════════════════════
  private parsePeriod(query: DashboardQueryDto): {
    startDate: Date;
    endDate:   Date;
  } {
    const now = new Date();

    // Si dates custom fournies → on les utilise
    if (query.startDate && query.endDate) {
      return {
        startDate: new Date(query.startDate),
        endDate:   new Date(query.endDate),
      };
    }

    // Sinon, période prédéfinie
    const period = query.period ?? DashboardPeriod.MONTH;

    const endDate   = new Date(now);
    let   startDate = new Date(now);

    switch (period) {
      case DashboardPeriod.TODAY:
        startDate.setHours(0, 0, 0, 0);
        break;
      case DashboardPeriod.WEEK:
        startDate.setDate(startDate.getDate() - 7);
        break;
      case DashboardPeriod.MONTH:
        startDate.setMonth(startDate.getMonth() - 1);
        break;
      case DashboardPeriod.YEAR:
        startDate.setFullYear(startDate.getFullYear() - 1);
        break;
    }

    return { startDate, endDate };
  }
}