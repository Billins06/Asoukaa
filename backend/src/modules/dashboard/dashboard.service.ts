import {
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, Between, MoreThanOrEqual } from 'typeorm';

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
  ) {}

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
    const revenueStats = await this.orderRepo
      .createQueryBuilder('order')
      .select('COUNT(order.id)',     'totalOrders')
      .addSelect('SUM(order.total)', 'grossRevenue')
      .addSelect('SUM(order.total - order.montantCommission)', 'netRevenue')
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
      .addSelect('SUM(order.total)',   'revenue')
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