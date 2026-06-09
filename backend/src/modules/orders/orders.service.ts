import {
  Injectable,
  NotFoundException,
  BadRequestException,
  ForbiddenException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, DataSource } from 'typeorm';

import { Order, OrderStatus }      from './entities/order.entity';
import { OrderItem }               from './entities/order-item.entity';
import { Cart }                    from '../cart/entities/cart.entity';
import { CartItem }                from '../cart/entities/cart-item.entity';
import { ProductVariant }          from '../products/entities/product-variant.entity';
import { Product, ProductStatus }  from '../products/entities/product.entity';
import { Address }                 from '../users/entities/address.entity';
import { VendorProfile }           from '../users/entities/vendor-profile.entity';
import { Coupon, CouponType }      from '../coupons/entities/coupon.entity';
import { CouponUsage }             from '../coupons/entities/coupon-usage.entity';

import { CreateOrderDto }         from './dto/create-order.dto';
import { UpdateOrderStatusDto }   from './dto/update-order-status.dto';
import { ActivityLogService }     from '../../common/services/activity-log.service';
import {
  ActorType,
  LogAction,
} from '../../common/entities/activity-log.entity';

@Injectable()
export class OrdersService {

  constructor(
    @InjectRepository(Order)
    private readonly orderRepo: Repository<Order>,

    @InjectRepository(OrderItem)
    private readonly orderItemRepo: Repository<OrderItem>,

    @InjectRepository(Cart)
    private readonly cartRepo: Repository<Cart>,

    @InjectRepository(CartItem)
    private readonly cartItemRepo: Repository<CartItem>,

    @InjectRepository(ProductVariant)
    private readonly variantRepo: Repository<ProductVariant>,

    @InjectRepository(Product)
    private readonly productRepo: Repository<Product>,

    @InjectRepository(Address)
    private readonly addressRepo: Repository<Address>,

    @InjectRepository(VendorProfile)
    private readonly vendorRepo: Repository<VendorProfile>,

    @InjectRepository(Coupon)
    private readonly couponRepo: Repository<Coupon>,

    @InjectRepository(CouponUsage)
    private readonly couponUsageRepo: Repository<CouponUsage>,

    private readonly dataSource:  DataSource,
    private readonly logService:  ActivityLogService,
  ) {}

  // ─────────────────────────────────────────────────────
  // CRÉER UNE COMMANDE DEPUIS LE PANIER
  // ─────────────────────────────────────────────────────
  async createFromCart(
    userId: string,
    dto:    CreateOrderDto,
    ip:     string,
  ) {
    // 1. Récupérer le panier avec tous ses articles
    const cart = await this.cartRepo.findOne({
      where:     { userId },
      relations: [
        'items',
        'items.variant',
        'items.variant.product',
        'items.variant.product.vendor',
      ],
    });

    if (!cart || !cart.items.length) {
      throw new BadRequestException('Votre panier est vide');
    }

    // 2. Vérifier l'adresse
    const address = await this.addressRepo.findOne({
      where: { id: dto.addressId, userId },
    });

    if (!address) {
      throw new NotFoundException('Adresse introuvable');
    }

    // 3. Vérifier le stock de chaque article
    // et regrouper les articles par boutique
    const vendorGroups = new Map<string, CartItem[]>();

    for (const item of cart.items) {
      const variant = item.variant;

      // Vérifier stock disponible
      if (variant.stockQuantity < item.quantity) {
        if (variant.stockQuantity === 0) {
          // Rupture totale → retirer du panier
          await this.cartItemRepo.remove(item);
          throw new BadRequestException(
            `"${variant.product.prod_name}" n'est plus disponible `
            + `et a été retiré de votre panier`
          );
        } else {
          // Stock insuffisant → proposer d'ajuster
          throw new BadRequestException(
            `Stock insuffisant pour "${variant.product.prod_name}". `
            + `Il reste ${variant.stockQuantity} unité(s). `
            + `Veuillez ajuster la quantité dans votre panier.`
          );
        }
      }

      // Regrouper par vendeur
      const vendorId = variant.product.vendorId;
      if (!vendorGroups.has(vendorId)) {
        vendorGroups.set(vendorId, []);
      }
      vendorGroups.get(vendorId)!.push(item);
    }

    // 4. Vérifier le coupon si fourni
    let coupon: Coupon | null = null;
    if (dto.couponCode) {
      coupon = await this.validateCoupon(dto.couponCode, userId);
    }

    // 5. Créer une commande par boutique dans une transaction
    // ⚠️ Transaction = si une commande échoue, tout est annulé
    const createdOrders = await this.dataSource.transaction(
      async (manager) => {
        const orders: Order[] = [];

        for (const [vendorId, items] of vendorGroups) {
          // Calculer le sous-total de cette boutique
          const subtotal = items.reduce(
            (sum, item) =>
              sum + Number(item.unitPrice) * item.quantity,
            0
          );

          // Calculer la remise coupon (uniquement sur la première boutique)
          let discount = 0;
          if (coupon && orders.length === 0) {
            discount = this.calculateDiscount(coupon, subtotal);
          }

          const total = subtotal - discount;

          // Générer le numéro de commande unique
          const orderNumber = await this.generateOrderNumber();

          // Créer la commande
          const order               = manager.create(Order);
          order.orderNumber         = orderNumber;
          order.userId              = userId;
          order.vendorId            = vendorId;
          order.addressId           = dto.addressId;
          order.couponId            = coupon?.id ?? null;
          order.status              = OrderStatus.PENDING;
          order.instructions        = dto.instructions ?? null;
          order.subtotal            = Number(subtotal.toFixed(2));
          order.fraisLivraison      = 0; // calculé à l'affectation du livreur
          order.rabais              = Number(discount.toFixed(2));
          order.montantCommission   = 0; // calculé au paiement
          order.total               = Number(total.toFixed(2));

          await manager.save(order);

          // Créer les lignes de commande
          for (const item of items) {
            const orderItem         = manager.create(OrderItem);
            orderItem.orderId       = order.id;
            orderItem.variantId     = item.variantId;
            orderItem.quantity      = item.quantity;
            orderItem.unitPrice     = Number(item.unitPrice);
            await manager.save(orderItem);

            // ⚠️ Décrémenter le stock UNIQUEMENT
            // quand le paiement sera confirmé
            // Ici on réserve simplement
          }

          orders.push(order);
        }

        // 6. Marquer le coupon comme utilisé
        if (coupon) {
          coupon.usedCount += 1;
          await manager.save(coupon);

          const usage         = manager.create(CouponUsage);
          usage.couponId      = coupon.id;
          usage.userId        = userId;
          usage.orderId       = orders[0].id; // première commande
          await manager.save(usage);
        }

        // 7. Vider le panier après commande réussie
        await manager.delete(CartItem, { cartId: cart.id });

        return orders;
      }
    );

    // 8. Logger
    for (const order of createdOrders) {
      await this.logService.log({
        actorId:    userId,
        actorType:  ActorType.CLIENT,
        action:     LogAction.ORDER_CREATED,
        entityType: 'order',
        entityId:   order.id,
        newValue:   {
          orderNumber: order.orderNumber,
          total:       order.total,
        },
        ipAddress: ip,
      });
    }

    return {
      message: `${createdOrders.length} commande(s) créée(s) avec succès`,
      orders:  createdOrders.map(o => ({
        id:          o.id,
        orderNumber: o.orderNumber,
        total:       o.total,
        status:      o.status,
      })),
    };
  }

  // ─────────────────────────────────────────────────────
  // CLIENT — MES COMMANDES
  // ─────────────────────────────────────────────────────
  async getMyOrders(
    userId: string,
    page:   number = 1,
    limit:  number = 10,
  ) {
    const [orders, total] = await this.orderRepo.findAndCount({
      where:     { userId },
      relations: [
        'items',
        'items.variant',
        'items.variant.product',
        'items.variant.product.images',
        'vendor',
        'address',
      ],
      order:  { createdAt: 'DESC' },
      skip:   (page - 1) * limit,
      take:   limit,
    });

    return {
      data:  orders,
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
    };
  }

  // ─────────────────────────────────────────────────────
  // CLIENT — DÉTAILS D'UNE COMMANDE
  // ─────────────────────────────────────────────────────
  async getOrderById(orderId: string, userId: string) {
    const order = await this.orderRepo.findOne({
      where:     { id: orderId, userId },
      relations: [
        'items',
        'items.variant',
        'items.variant.product',
        'items.variant.product.images',
        'vendor',
        'vendor.user',
        'address',
        'coupon',
      ],
    });

    if (!order) throw new NotFoundException('Commande introuvable');

    // Masquer les données sensibles du vendeur
    if (order.vendor?.user) {
      const { passwordHash, ...userSafe } = order.vendor.user as any;
      (order.vendor as any).user = userSafe;
    }

    return order;
  }

  // ─────────────────────────────────────────────────────
  // VENDEUR — COMMANDES DE SA BOUTIQUE
  // ─────────────────────────────────────────────────────
  async getVendorOrders(
    userId: string,
    status?: OrderStatus,
    page:   number = 1,
    limit:  number = 20,
  ) {
    const vendor = await this.vendorRepo.findOne({
      where: { userId },
    });

    if (!vendor) throw new NotFoundException('Boutique introuvable');

    const query = this.orderRepo
      .createQueryBuilder('order')
      .leftJoinAndSelect('order.items',           'item')
      .leftJoinAndSelect('item.variant',          'variant')
      .leftJoinAndSelect('variant.product',       'product')
      .leftJoinAndSelect('product.images',        'image',
        'image.isPrimary = true')
      .leftJoinAndSelect('order.address',         'address')
      .where('order.vendorId = :vendorId', { vendorId: vendor.id })
      .orderBy('order.createdAt', 'DESC')
      .skip((page - 1) * limit)
      .take(limit);

    if (status) {
      query.andWhere('order.status = :status', { status });
    }

    const [orders, total] = await query.getManyAndCount();

    return {
      data:  orders,
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
    };
  }

  // ─────────────────────────────────────────────────────
  // VENDEUR — METTRE À JOUR LE STATUT
  // ─────────────────────────────────────────────────────
  async updateStatus(
    orderId:  string,
    userId:   string,
    dto:      UpdateOrderStatusDto,
    ip:       string,
    isAdmin:  boolean = false,
  ) {
    const order = await this.orderRepo.findOne({
      where:     { id: orderId },
      relations: ['vendor', 'items', 'items.variant'],
    });

    if (!order) throw new NotFoundException('Commande introuvable');

    // Si c'est un vendeur → vérifier qu'il est propriétaire
    if (!isAdmin) {
      const vendor = await this.vendorRepo.findOne({
        where: { userId },
      });

      if (!vendor || order.vendorId !== vendor.id) {
        throw new ForbiddenException(
          'Vous n\'êtes pas autorisé à modifier cette commande'
        );
      }
    }

    // ⚠️ Vérifier les transitions de statut autorisées
    this.validateStatusTransition(order.status, dto.status);

    const oldStatus = order.status;
    order.status    = dto.status;

    // Si annulation → remettre le stock
    if (dto.status === OrderStatus.CANCELLED) {
      order.motifAnnulation = dto.motifAnnulation ?? null;

      // Remettre le stock si le paiement avait été fait
      // (ce check sera renforcé avec le module payments)
      for (const item of order.items) {
        await this.variantRepo.increment(
          { id: item.variantId },
          'stockQuantity',
          item.quantity,
        );
      }
    }

    await this.orderRepo.save(order);

    await this.logService.log({
      actorId:    userId,
      actorType:  isAdmin ? ActorType.ADMIN : ActorType.VENDOR,
      action:     dto.status === OrderStatus.CANCELLED
                    ? LogAction.ORDER_CANCELLED
                    : LogAction.ORDER_STATUS_CHANGED,
      entityType: 'order',
      entityId:   orderId,
      oldValue:   { status: oldStatus },
      newValue:   { status: dto.status, reason: dto.motifAnnulation },
      ipAddress:  ip,
    });

    return {
      message:     'Statut mis à jour',
      orderNumber: order.orderNumber,
      status:      order.status,
    };
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — TOUTES LES COMMANDES
  // ─────────────────────────────────────────────────────
  async getAllOrders(params: {
    status?:   OrderStatus;
    vendorId?: string;
    userId?:   string;
    page?:     number;
    limit?:    number;
  }) {
    const { status, vendorId, userId, page = 1, limit = 20 } = params;

    const query = this.orderRepo
      .createQueryBuilder('order')
      .leftJoinAndSelect('order.vendor',  'vendor')
      .leftJoinAndSelect('order.address', 'address')
      .orderBy('order.createdAt', 'DESC')
      .skip((page - 1) * limit)
      .take(limit);

    if (status)   query.andWhere('order.status = :status',     { status });
    if (vendorId) query.andWhere('order.vendorId = :vendorId', { vendorId });
    if (userId)   query.andWhere('order.userId = :userId',     { userId });

    const [orders, total] = await query.getManyAndCount();

    return {
      data:  orders,
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
    };
  }

  // ─────────────────────────────────────────────────────
  // MÉTHODES PRIVÉES
  // ─────────────────────────────────────────────────────

  // Génère un numéro de commande unique
  private async generateOrderNumber(): Promise<string> {
    const year  = new Date().getFullYear();
    const count = await this.orderRepo.count();
    const seq   = String(count + 1).padStart(5, '0');
    return `ASK-${year}-${seq}`;
  }

  // Valide les transitions de statut autorisées
  private validateStatusTransition(
    current: OrderStatus,
    next:    OrderStatus,
  ): void {
    const allowed: Record<OrderStatus, OrderStatus[]> = {
      [OrderStatus.PENDING]:    [OrderStatus.PREPARING, OrderStatus.CANCELLED],
      [OrderStatus.PREPARING]:  [OrderStatus.SHIPPED,   OrderStatus.CANCELLED],
      [OrderStatus.SHIPPED]:    [OrderStatus.DELIVERED],
      [OrderStatus.DELIVERED]:  [],
      [OrderStatus.CANCELLED]:  [],
    };

    if (!allowed[current].includes(next)) {
      throw new BadRequestException(
        `Transition de statut invalide : `
        + `${current} → ${next} n'est pas autorisée`
      );
    }
  }

  // Valide et retourne le coupon
  private async validateCoupon(
    code:   string,
    userId: string,
  ): Promise<Coupon> {
    const coupon = await this.couponRepo.findOne({
      where: { code, isActive: true },
    });

    if (!coupon) {
      throw new BadRequestException('Code coupon invalide ou inactif');
    }

    // Vérifier l'expiration
    if (coupon.expiresAt && new Date() > coupon.expiresAt) {
      throw new BadRequestException('Ce code coupon a expiré');
    }

    // Vérifier le nombre max d'utilisations
    if (
      coupon.maxUses !== null &&
      coupon.usedCount >= coupon.maxUses
    ) {
      throw new BadRequestException(
        'Ce code coupon a atteint son nombre maximum d\'utilisations'
      );
    }

    // Vérifier si ce client l'a déjà utilisé
    const alreadyUsed = await this.couponUsageRepo.findOne({
      where: { couponId: coupon.id, userId },
    });

    if (alreadyUsed) {
      throw new BadRequestException(
        'Vous avez déjà utilisé ce code coupon'
      );
    }

    return coupon;
  }

  // Calcule le montant de la remise
  private calculateDiscount(
    coupon:   Coupon,
    subtotal: number,
  ): number {
    // Vérifier le montant minimum si défini
    if (
      coupon.minOrderAmount &&
      subtotal < Number(coupon.minOrderAmount)
    ) {
      throw new BadRequestException(
        `Commande minimum de ${coupon.minOrderAmount} FCFA `
        + `requise pour ce coupon`
      );
    }

    if (coupon.type === CouponType.PERCENTAGE) {
      // ⚠️ La réduction ne peut pas dépasser le sous-total
      const discount = (subtotal * Number(coupon.value)) / 100;
      return Math.min(discount, subtotal);
    } else {
      // Montant fixe — ne peut pas dépasser le sous-total
      return Math.min(Number(coupon.value), subtotal);
    }
  }
}