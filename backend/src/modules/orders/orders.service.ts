import { toPublicVendor } from '../products/public-vendor.util';
import {
  Injectable,
  Logger,
  NotFoundException,
  BadRequestException,
  ForbiddenException,
  OnModuleInit,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, DataSource, EntityManager, In, LessThanOrEqual, IsNull, Not } from 'typeorm';
import { Cron, CronExpression } from '@nestjs/schedule';

import { Order, OrderStatus, OrderDeliveryMode } from './entities/order.entity';
import { OrderItem }               from './entities/order-item.entity';
import { Cart }                    from '../cart/entities/cart.entity';
import { CartItem }                from '../cart/entities/cart-item.entity';
import { ProductVariant }          from '../products/entities/product-variant.entity';
import { Product, ProductStatus }  from '../products/entities/product.entity';
import { Address }                 from '../users/entities/address.entity';
import { VendorProfile, VendorStatus } from '../users/entities/vendor-profile.entity';
import { Coupon, CouponType }      from '../coupons/entities/coupon.entity';
import { CouponUsage }             from '../coupons/entities/coupon-usage.entity';
import { DeliveryZone }            from '../delivery-zones/entities/delivery-zone.entity';
import { Payment, PaymentStatus, PaymentMethod }  from '../payments/entities/payment.entity';
import { User }                    from '../users/entities/user.entity';
import { DeliveryProof, ProofRole, ProofStage } from '../delivery/entities/delivery-proof.entity';
import { UploadService, UploadType } from '../upload/upload.service';
import { resolveTierUnitPrice }    from '../../common/utils/tier-pricing.util';

import { CreateOrderDto }         from './dto/create-order.dto';
import { UpdateOrderStatusDto }   from './dto/update-order-status.dto';
import { CreateVendorOrderDto }   from './dto/create-vendor-order.dto';
import { SubmitStorePickupProofDto } from './dto/submit-store-pickup-proof.dto';
import { SubmitDispatchProofDto }    from './dto/submit-dispatch-proof.dto';
import { SubmitReceptionProofDto }   from './dto/submit-reception-proof.dto';
import { OpenDisputeDto }            from './dto/open-dispute.dto';
import { ActivityLogService }     from '../../common/services/activity-log.service';
import { MailService }            from '../mail/mail.service';
import { DeliveryService }        from '../delivery/delivery.service';
import { NotificationsService }   from '../notifications/notifications.service';
import { NotificationType }       from '../notifications/entities/notification.entity';
import { OrderConfirmationService } from './order-confirmation.service';
import {
  ActorType,
  LogAction,
} from '../../common/entities/activity-log.entity';

@Injectable()
export class OrdersService implements OnModuleInit {

  private readonly logger = new Logger(OrdersService.name);

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

    @InjectRepository(User)
    private readonly userRepo: Repository<User>,

    @InjectRepository(Coupon)
    private readonly couponRepo: Repository<Coupon>,

    @InjectRepository(CouponUsage)
    private readonly couponUsageRepo: Repository<CouponUsage>,

    @InjectRepository(DeliveryZone)
    private readonly deliveryZoneRepo: Repository<DeliveryZone>,

    @InjectRepository(Payment)
    private readonly paymentRepo: Repository<Payment>,

    @InjectRepository(DeliveryProof)
    private readonly proofRepo: Repository<DeliveryProof>,

    private readonly dataSource:      DataSource,
    private readonly logService:      ActivityLogService,
    private readonly mailService:     MailService,
    private readonly deliveryService: DeliveryService,
    private readonly uploadService:   UploadService,
    private readonly notificationsService: NotificationsService,
    private readonly orderConfirmation: OrderConfirmationService,
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
        'items.variant.product.vendor.user',
        // Paliers de prix dégressifs (voir recalcul du prix unitaire plus bas)
        'items.variant.product.tierPrices',
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

    // 2bis. Mode de livraison choisi par le client : livraison a domicile
    // (defaut) ou retrait en boutique. En retrait, pas de frais de
    // livraison et pas de fiche Delivery a creer.
    const deliveryMode = dto.deliveryMode ?? OrderDeliveryMode.LIVRAISON;

    // Frais de livraison de la commune de destination (table
    // delivery_zones, paramétrée par l'admin). Même frais appliqué à chaque
    // commande (une par boutique) puisque chacune est livrée séparément à
    // cette même adresse. Nul en mode retrait.
    const fraisLivraisonCommune =
      deliveryMode === OrderDeliveryMode.RETRAIT
        ? 0
        : await this.getFraisLivraisonForCommune(address.ville, dto.transportMode);

    // 3. Vérifier le stock de chaque article
    // et regrouper les articles par boutique
    const vendorGroups = new Map<string, CartItem[]>();

    for (const item of cart.items) {
      const variant = item.variant;

      // Produit d'un vendeur bloqué / non approuvé / désactivé depuis son
      // ajout au panier : on ne le vend plus.
      const articleVendor = variant.product?.vendor;
      if (
        !articleVendor
        || articleVendor.status !== VendorStatus.APPROVED
        || articleVendor.user?.isActive === false
      ) {
        throw new BadRequestException(
          `"${variant.product?.prod_name ?? 'Un article'}" n'est plus disponible. `
          + `Veuillez le retirer de votre panier.`
        );
      }

      // Boutique masquée par son vendeur (« Boutique visible » désactivé) :
      // plus de nouvelle commande. Les commandes déjà passées continuent
      // normalement (cette règle ne s'applique qu'à la création).
      if (articleVendor.shopVisible === false) {
        throw new BadRequestException(
          `Cette boutique est momentanément indisponible ("${articleVendor.shopName}"). `
          + `Veuillez retirer ses articles de votre panier.`
        );
      }

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

      // ⚠️ Prix unitaire recalculé par le serveur (il fait foi) : prix
      // dégressif du palier atteint par la quantité, sinon prix normal de la
      // variante (voir common/utils/tier-pricing.util.ts). Modifié en mémoire
      // uniquement (le panier n'est pas réenregistré ici) : le sous-total et
      // les lignes de commande ci-dessous lisent item.unitPrice.
      item.unitPrice = resolveTierUnitPrice(
        variant.price,
        variant.product?.tierPrices,
        item.quantity,
      );

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
    // Adresse de retrait/livraison de chaque boutique concernee, capturee
    // pendant la transaction pour creer les fiches Delivery juste apres.
    const pickupAddressByOrderId = new Map<string, string>();

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

          // Générer le numéro de commande unique (séquence Postgres)
          const orderNumber = await this.generateOrderNumber(manager);

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
          order.fraisLivraison      = fraisLivraisonCommune;
          order.rabais              = Number(discount.toFixed(2));
          order.montantCommission   = 0; // calculé au paiement
          order.total               = Number((total + fraisLivraisonCommune).toFixed(2));
          order.deliveryMode        = deliveryMode;
          order.transportMode       = dto.transportMode ?? null;

          await manager.save(order);

          pickupAddressByOrderId.set(
            order.id,
            items[0].variant.product.vendor.shopAddress ?? '',
          );

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
        // ⚠️ increment() atomique + re-vérification du plafond DANS la
        // transaction. Avec `coupon.usedCount += 1; save()` (lecture puis
        // écriture), deux commandes simultanées lisaient la même valeur et
        // un coupon limité à N usages passait N+1 fois.
        if (coupon) {
          await manager.increment(Coupon, { id: coupon.id }, 'usedCount', 1);

          if (coupon.maxUses !== null) {
            const updated = await manager.findOne(Coupon, {
              where: { id: coupon.id },
            });
            if (
              updated?.maxUses != null &&
              updated.usedCount > updated.maxUses
            ) {
              throw new BadRequestException(
                'Ce code coupon a atteint son nombre maximum d\'utilisations',
              );
            }
          }

          const usage         = manager.create(CouponUsage);
          usage.couponId      = coupon.id;
          usage.userId        = userId;
          usage.orderId       = orders[0].id; // première commande
          await manager.save(usage);
        }

        // 7. NE PAS vider le panier ici : la commande est encore PENDING,
        // le paiement n'est pas confirmé. Le panier est vidé uniquement
        // après confirmation du paiement (voir FeexpayResultScreen /
        // DELETE /api/v1/cart côté frontend), pour que le client ne perde
        // pas ses articles en cas d'échec ou d'interruption du paiement.

        return orders;
      }
    );

    // 7bis. Créer la fiche Delivery pour chaque commande livrée (pas en
    // mode retrait). C'est cette étape qui manquait jusqu'ici : aucune
    // commande ne generait de fiche de livraison, meme en mode livraison.
    if (deliveryMode === OrderDeliveryMode.LIVRAISON) {
      const adresseLivraison =
        `${address.quartier}, ${address.ville}, ${address.country}`;

      for (const order of createdOrders) {
        await this.deliveryService.createForOrder(
          order.id,
          pickupAddressByOrderId.get(order.id) ?? '',
          adresseLivraison,
          address.latitude,
          address.longitude,
        );
      }
    }

    // 8. Logger
    // ⚠️ Les écritures d'audit ne sont plus attendues une par une dans le
    // chemin de réponse : sur un panier réparti entre 4 boutiques, c'étaient
    // 4 INSERT séquentiels ajoutés à la latence perçue par le client.
    // ActivityLogService.log() n'échoue jamais (try/catch interne), donc on
    // peut les lancer en parallèle sans bloquer la réponse.
    void Promise.all(
      createdOrders.map((order) =>
        this.logService.log({
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
        }),
      ),
    );

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
  // VENDEUR — RECHERCHER DES CLIENTS (téléphone, nom/prénom ou email)
  // Étape 1 de "Initier une commande pour un client" : le client doit
  // déjà avoir un compte sur l'application. Recherche large (contient,
  // insensible à la casse) sur téléphone/prénom/nom/email — peut renvoyer
  // plusieurs correspondances, à charge pour le vendeur de choisir le bon
  // client dans la liste (voir getClientAddresses pour l'étape suivante).
  // ─────────────────────────────────────────────────────
  async findClients(vendorUserId: string, query: string) {
    const vendor = await this.vendorRepo.findOne({
      where: { userId: vendorUserId },
    });
    if (!vendor) {
      throw new ForbiddenException('Profil vendeur introuvable');
    }
    if (vendor.status !== VendorStatus.APPROVED) {
      throw new ForbiddenException(
        'Votre boutique doit être approuvée pour rechercher des clients.'
      );
    }

    const q = query?.trim();
    if (!q) {
      throw new BadRequestException('Veuillez saisir une recherche');
    }
    if (q.length < 3) {
      throw new BadRequestException(
        'Saisissez au moins 3 caractères pour rechercher un client.'
      );
    }
    // Échappe les jokers LIKE (% et _) : on cherche le texte tel quel.
    const likeQ = q.replace(/[\\%_]/g, '\\$&');

    const clients = await this.userRepo
      .createQueryBuilder('user')
      .where('user.isActive = true')
      .andWhere(
        '(user.phone ILIKE :q OR user.email ILIKE :q '
        + 'OR user.prenom ILIKE :q OR user.name ILIKE :q)',
        { q: `%${likeQ}%` },
      )
      .orderBy('user.prenom', 'ASC')
      .take(10)
      .getMany();

    if (!clients.length) {
      throw new NotFoundException(
        'Aucun client trouvé. Le client doit d\'abord '
        + 'créer un compte sur l\'application.'
      );
    }

    return clients.map((c) => ({
      id:     c.id,
      prenom: c.prenom,
      name:   c.name,
      phone:  c.phone,
      email:  c.email,
    }));
  }

  // ─────────────────────────────────────────────────────
  // VENDEUR — ADRESSES D'UN CLIENT (étape 2, une fois choisi dans la
  // liste renvoyée par findClients).
  // ─────────────────────────────────────────────────────
  async getClientAddresses(vendorUserId: string, clientId: string) {
    const vendor = await this.vendorRepo.findOne({
      where: { userId: vendorUserId },
    });
    if (!vendor) {
      throw new ForbiddenException('Profil vendeur introuvable');
    }
    if (vendor.status !== VendorStatus.APPROVED) {
      throw new ForbiddenException(
        'Votre boutique doit être approuvée pour consulter les adresses d\'un client.'
      );
    }

    const client = await this.userRepo.findOne({ where: { id: clientId } });
    if (!client) {
      throw new NotFoundException('Client introuvable');
    }

    const addresses = await this.addressRepo.find({
      where: { userId: client.id },
    });

    return {
      id:      client.id,
      prenom:  client.prenom,
      name:    client.name,
      phone:   client.phone,
      addresses,
    };
  }

  // ─────────────────────────────────────────────────────
  // VENDEUR — INITIER UNE COMMANDE POUR UN CLIENT
  // Vente téléphonique / en boutique : le vendeur saisit lui-même la
  // commande pour un client déjà inscrit (cf. findClientByPhone). La
  // commande est créée en statut PENDING, SANS paiement — exactement
  // comme une commande créée depuis le panier (createFromCart) : c'est
  // au CLIENT de payer ensuite via le bouton "Payer la commande" (app
  // mobile), qui appelle POST /payments/initiate comme un paiement
  // normal (Mobile Money). Le vendeur ne peut plus marquer une commande
  // "payée en espèces" lui-même (voir suppression de
  // PaymentsService.confirmCodPayment) : seul le client peut déclencher
  // et confirmer le paiement.
  // ─────────────────────────────────────────────────────
  async createVendorInitiated(
    vendorUserId: string,
    dto:          CreateVendorOrderDto,
    ip:           string,
  ) {
    const vendor = await this.vendorRepo.findOne({
      where: { userId: vendorUserId },
    });
    if (!vendor) {
      throw new ForbiddenException('Profil vendeur introuvable');
    }
    if (vendor.status !== VendorStatus.APPROVED) {
      throw new ForbiddenException(
        'Votre boutique doit être approuvée pour initier une commande.'
      );
    }

    const client = await this.userRepo.findOne({
      where: { phone: dto.clientPhone },
    });
    if (!client) {
      throw new NotFoundException(
        'Aucun client trouvé avec ce numéro. Le client doit d\'abord '
        + 'créer un compte sur l\'application.'
      );
    }

    // Résoudre l'adresse : une adresse existante du client, ou une
    // nouvelle qu'on crée pour lui à la volée.
    let address: Address;
    if (dto.addressId) {
      const existing = await this.addressRepo.findOne({
        where: { id: dto.addressId, userId: client.id },
      });
      if (!existing) {
        throw new NotFoundException('Adresse introuvable pour ce client');
      }
      address = existing;
    } else if (dto.newAddressVille && dto.newAddressQuartier) {
      address = this.addressRepo.create({
        userId:             client.id,
        label:              dto.newAddressLabel?.trim() || 'Adresse vendeur',
        nom_destinataire:   `${client.prenom} ${client.name}`,
        phone_destinataire: client.phone,
        quartier:           dto.newAddressQuartier.trim(),
        ville:              dto.newAddressVille.trim(),
        isDefault:          false,
      });
      address = await this.addressRepo.save(address);
    } else {
      throw new BadRequestException(
        'Adresse de livraison requise (addressId ou newAddressVille/newAddressQuartier)'
      );
    }

    const deliveryMode = dto.deliveryMode ?? OrderDeliveryMode.LIVRAISON;
    const fraisLivraison =
      deliveryMode === OrderDeliveryMode.RETRAIT
        ? 0
        : await this.getFraisLivraisonForCommune(address.ville, dto.transportMode);

    // Charger et vérifier chaque variante (doit appartenir à ce vendeur).
    const lines: { variant: ProductVariant; quantity: number; unitPrice: number }[] = [];
    let subtotal = 0;

    for (const item of dto.items) {
      const variant = await this.variantRepo.findOne({
        where:     { id: item.variantId },
        relations: ['product', 'product.tierPrices'],
      });

      if (!variant) {
        throw new NotFoundException(`Variante ${item.variantId} introuvable`);
      }
      if (variant.product.vendorId !== vendor.id) {
        throw new ForbiddenException(
          `Le produit "${variant.product.prod_name}" n'appartient pas à votre boutique`
        );
      }
      if (variant.stockQuantity < item.quantity) {
        throw new BadRequestException(
          `Stock insuffisant pour "${variant.product.prod_name}" : `
          + `${variant.stockQuantity} unité(s) restante(s)`
        );
      }

      // Prix dégressif du palier atteint (même règle que le panier)
      const unitPrice = resolveTierUnitPrice(
        variant.price,
        variant.product?.tierPrices,
        item.quantity,
      );
      subtotal += unitPrice * item.quantity;
      lines.push({ variant, quantity: item.quantity, unitPrice });
    }

    subtotal = Number(subtotal.toFixed(2));
    const total = Number((subtotal + fraisLivraison).toFixed(2));

    const { order, pickupAddress } = await this.dataSource.transaction(
      async (manager) => {
        const orderNumber = await this.generateOrderNumber(manager);

        const order               = manager.create(Order);
        order.orderNumber         = orderNumber;
        order.userId              = client.id;
        order.vendorId            = vendor.id;
        order.addressId           = address.id;
        order.couponId            = null;
        order.status              = OrderStatus.PENDING;
        order.instructions        = dto.instructions ?? null;
        order.subtotal            = subtotal;
        order.fraisLivraison      = fraisLivraison;
        order.rabais              = 0;
        order.montantCommission   = 0; // calculé à la confirmation du paiement
        order.total               = total;
        order.deliveryMode        = deliveryMode;
        order.transportMode       = dto.transportMode ?? null;
        await manager.save(order);

        for (const { variant, quantity, unitPrice } of lines) {
          const orderItem     = manager.create(OrderItem);
          orderItem.orderId   = order.id;
          orderItem.variantId = variant.id;
          orderItem.quantity  = quantity;
          orderItem.unitPrice = unitPrice;
          await manager.save(orderItem);
        }

        // Pas de paiement créé ici : la commande reste PENDING sans
        // ligne Payment, exactement comme une commande créée depuis le
        // panier avant que le client ne paie (voir createFromCart /
        // PaymentsService.initiatePayment). C'est le client qui, via le
        // bouton "Payer la commande" côté app, initiera le paiement
        // Mobile Money normal pour cette commande.
        return {
          order,
          pickupAddress: vendor.shopAddress ?? '',
        };
      },
    );

    if (deliveryMode === OrderDeliveryMode.LIVRAISON) {
      const adresseLivraison =
        `${address.quartier}, ${address.ville}, ${address.country}`;
      await this.deliveryService.createForOrder(
        order.id,
        pickupAddress,
        adresseLivraison,
      );
    }

    void this.logService.log({
      actorId:    vendorUserId,
      actorType:  ActorType.VENDOR,
      action:     LogAction.ORDER_CREATED,
      entityType: 'order',
      entityId:   order.id,
      newValue:   {
        orderNumber: order.orderNumber,
        total:       order.total,
        source:      'vendeur',
        clientId:    client.id,
      },
      ipAddress: ip,
    });

    return {
      message: `Commande ${order.orderNumber} créée avec succès`,
      order: {
        id:          order.id,
        orderNumber: order.orderNumber,
        total:       order.total,
        status:      order.status,
      },
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

    // Comme pour getVendorOrders : pas de relation inverse Payment sur
    // Order, on va chercher les paiements séparément et on les rattache
    // manuellement. Nécessaire côté client pour savoir si une commande
    // (notamment une commande initiée par le vendeur, sans paiement créé
    // à la création) est encore en attente de paiement et doit afficher
    // le bouton "Payer la commande".
    const orderIds = orders.map(o => o.id);
    const payments = orderIds.length
      ? await this.paymentRepo.find({ where: { orderId: In(orderIds) } })
      : [];
    const paymentByOrderId = new Map(payments.map(p => [p.orderId, p]));

    const data = orders.map(o => ({
      ...o,
      // Le client ne voit que la fiche publique de la boutique.
      vendor:  toPublicVendor(o.vendor),
      payment: paymentByOrderId.get(o.id) ?? null,
    }));

    return {
      data,
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

    // Masquer les données sensibles du vendeur : le client ne reçoit que la
    // fiche publique de la boutique (pas de documents, ni de paiement, ni
    // l'e-mail ou le téléphone du compte).
    if (order.vendor) {
      (order as any).vendor = toPublicVendor(order.vendor);
    }

    // Livraison + livreur assigné (peut être null tant que personne n'est
    // encore affecté) — utilisé par l'écran "Suivi de commande" du client
    // pour remplacer le bloc "Transporteur" fictif par les vraies infos.
    // Projection PUBLIQUE du livreur (id, prénom, nom, téléphone, photo,
    // type de véhicule) : jamais ses documents, son e-mail, son taux de
    // gain ni aucun champ de sécurité du compte.
    (order as any).delivery =
      await this.deliveryService.getPublicDeliveryForOrder(orderId);

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

    // Le paiement n'a pas de relation inverse sur Order dans le schéma
    // (Payment.order est un OneToOne côté Payment uniquement) : on va le
    // chercher séparément et on le rattache manuellement. Utile côté
    // vendeur pour afficher le statut de paiement réel de chaque
    // commande (ex: mobileMoneyUnpaid côté app) — le vendeur ne peut
    // plus confirmer lui-même un paiement (route confirm-cod retirée).
    const orderIds = orders.map(o => o.id);
    const payments = orderIds.length
      ? await this.paymentRepo.find({ where: { orderId: In(orderIds) } })
      : [];
    const paymentByOrderId = new Map(payments.map(p => [p.orderId, p]));

    const data = orders.map(o => {
      const payment = paymentByOrderId.get(o.id) ?? null;
      return {
        ...o,
        payment,
        // Date limite théorique de confirmation (référence + délai de rappel) ;
        // null si la commande n'attend pas la confirmation du vendeur.
        confirmBy: this.orderConfirmation.computeConfirmBy(o, payment),
      };
    });

    return {
      data,
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
      relations: ['vendor', 'items', 'items.variant', 'user'],
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

      // ⚠️ Faille fermée : un vendeur ne peut plus passer directement
      // à "Livreur affecté" / "Expédiée" / "En transit" / "Livrée" via
      // cette route générique — ces statuts exigent désormais une
      // preuve concrète (photo, scan QR, GPS, signature selon le cas)
      // et passent par les routes dédiées ci-dessous. Avant ce
      // correctif, rien n'empêchait un vendeur de se déclarer "Livré"
      // sans qu'aucune preuve n'existe.
      //
      // ⚠️ RÈGLE MÉTIER : un vendeur ne peut JAMAIS annuler une commande
      // (seuls l'admin, via la route admin-status, et les flux système
      // — ex. paiement échoué — peuvent l'annuler). Le refus est explicite
      // et passe avant toute autre vérification.
      if (dto.status === OrderStatus.CANCELLED) {
        throw new ForbiddenException(
          'Un vendeur ne peut pas annuler une commande. Contactez le support.'
        );
      }

      const VENDOR_ALLOWED_DIRECT_STATUSES = [
        OrderStatus.PREPARING,
      ];
      if (!VENDOR_ALLOWED_DIRECT_STATUSES.includes(dto.status)) {
        throw new ForbiddenException(
          'Ce changement de statut doit passer par une preuve de livraison'
        );
      }

      // ⚠️ Un vendeur ne peut confirmer ("En cours") une commande que si
      // le paiement a réellement abouti. Avant ce correctif, rien ne
      // vérifiait le paiement ici : un client qui annulait/faisait
      // échouer son paiement mobile money voyait quand même sa commande
      // rester "en attente", en tout point identique à une commande
      // valide — et le vendeur pouvait la confirmer normalement, sans
      // aucune indication que le client n'avait jamais payé.
      // Le paiement à la livraison (cash_on_delivery) n'est pas concerné :
      // il n'y a jamais de paiement "réussi" avant la livraison effective.
      if (dto.status === OrderStatus.PREPARING) {
        const payment = await this.paymentRepo.findOne({
          where: { orderId: order.id },
        });
        const isCashOnDelivery =
          payment?.method === PaymentMethod.CASH_ON_DELIVERY;

        if (!isCashOnDelivery && payment?.status !== PaymentStatus.SUCCESS) {
          throw new ForbiddenException(
            'Le paiement de cette commande n\'a pas encore été confirmé — impossible de la valider pour le moment.'
          );
        }
      }
    }

    // ⚠️ Vérifier les transitions de statut autorisées
    this.validateStatusTransition(order.status, dto.status);

    const oldStatus = order.status;
    order.status    = dto.status;

    // (Annulation : atteignable ici uniquement par l'ADMIN — le vendeur est
    // bloqué plus haut. Le code ci-dessous reste donc nécessaire côté admin.)
    // Si annulation → remettre le stock, MAIS uniquement s'il avait
    // réellement été décrémenté.
    // ⚠️ Le stock n'est décrémenté qu'à la confirmation du paiement
    // (PaymentsService.confirmPayment). Avant ce correctif, on le
    // réincrémentait à chaque annulation sans vérifier : annuler une
    // commande PENDING jamais payée créait du stock qui n'a jamais existé,
    // et l'inventaire dérivait à chaque cycle commande → annulation.
    if (dto.status === OrderStatus.CANCELLED) {
      order.motifAnnulation = dto.motifAnnulation ?? null;

      const payment = await this.paymentRepo.findOne({
        where: { orderId: order.id },
      });
      const stockWasDecremented =
        payment?.status === PaymentStatus.SUCCESS;

      if (stockWasDecremented) {
        for (const item of order.items) {
          await this.variantRepo.increment(
            { id: item.variantId },
            'stockQuantity',
            item.quantity,
          );
        }
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

    // Si la commande est annulée alors qu'un livreur avait déjà été
    // affecté, il doit être prévenu dans l'app : il ne doit plus aller
    // récupérer ni livrer ce colis. Best-effort — l'annulation doit
    // aboutir même si la notification plante (même logique que
    // chat.service.ts et que l'email ci-dessous).
    if (dto.status === OrderStatus.CANCELLED) {
      try {
        const delivery = await this.deliveryService.getDeliveryForOrderRaw(
          order.id,
        );
        if (delivery?.agent?.userId) {
          await this.notificationsService.notifyDeliveryCancelled(
            delivery.agent.userId,
            delivery.id,
            order.orderNumber,
          );
        }
      } catch (error) {
        this.logger.error(`Échec notification annulation livraison — commande ${order.id}`, error?.message);
      }
    }

    // Email au client — sendOrderStatusUpdate logue l'erreur en interne
    // sans jamais bloquer la mise a jour du statut si l'envoi echoue.
    // ⚠️ Volontairement NON attendu : un aller-retour SMTP prend plusieurs
    // centaines de ms et le vendeur n'a aucune raison d'attendre l'envoi du
    // mail pour voir son statut mis à jour.
    // Préférence « Commandes & livraisons » de l'acheteur : l'e-mail de suivi
    // est coupé, SAUF l'annulation (information importante, toujours envoyée).
    if (
      order.user?.email
      && (
        order.status === OrderStatus.CANCELLED
        || (await this.notificationsService.isAllowed(order.userId, NotificationType.ORDER, 'orders'))
      )
    ) {
      void this.mailService.sendOrderStatusUpdate(order.user.email, {
        prenom:      order.user.prenom,
        orderNumber: order.orderNumber,
        status:      order.status,
        motif:       dto.motifAnnulation,
        orderId:     order.id,
      });
    }

    return {
      message:     'Statut mis à jour',
      orderNumber: order.orderNumber,
      status:      order.status,
    };
  }

  // ─────────────────────────────────────────────────────
  // CAS B — RETRAIT EN BOUTIQUE : le vendeur scanne le QR code
  // affiché sur le téléphone du client venu récupérer sa commande.
  // ─────────────────────────────────────────────────────
  async submitStorePickupProof(
    orderId: string,
    userId:  string,
    dto:     SubmitStorePickupProofDto,
    ip:      string,
  ) {
    const order = await this.orderRepo.findOne({
      where:     { id: orderId },
      relations: ['vendor', 'user'],
    });

    if (!order) throw new NotFoundException('Commande introuvable');

    const vendor = await this.vendorRepo.findOne({ where: { userId } });

    if (!vendor || order.vendorId !== vendor.id) {
      throw new ForbiddenException(
        'Vous n\'êtes pas autorisé à modifier cette commande'
      );
    }

    if (order.deliveryMode !== OrderDeliveryMode.RETRAIT) {
      throw new BadRequestException(
        'Cette commande n\'est pas en mode retrait en boutique'
      );
    }

    this.validateStatusTransition(order.status, OrderStatus.DELIVERED);

    // Le QR scanné doit correspondre à CETTE commande.
    const expected = order.orderNumber.replace(/^ASK-/, '');
    const scanned  = dto.qrScanValue.replace(/^ASK-/, '');
    if (scanned !== expected) {
      throw new BadRequestException(
        'Le QR code scanné ne correspond pas à cette commande'
      );
    }

    const oldStatus = order.status;
    order.status = OrderStatus.DELIVERED;
    await this.orderRepo.save(order);
    await this.incrementProductSales(order.id);

    await this.proofRepo.save(this.proofRepo.create({
      orderId:         order.id,
      role:            ProofRole.VENDEUR,
      stage:           ProofStage.RETRAIT_BOUTIQUE,
      qrScanValue:     dto.qrScanValue,
      createdByUserId: userId,
    }));

    await this.logService.log({
      actorId:    userId,
      actorType:  ActorType.VENDOR,
      action:     LogAction.DELIVERY_PROOF_SUBMITTED,
      entityType: 'order',
      entityId:   orderId,
      oldValue:   { status: oldStatus },
      newValue:   { status: order.status },
      ipAddress:  ip,
    });

    // Préférence « Commandes & livraisons » de l'acheteur (e-mail de suivi).
    if (order.user?.email && (await this.notificationsService.isAllowed(order.userId, NotificationType.ORDER, 'orders'))) {
      void this.mailService.sendOrderStatusUpdate(order.user.email, {
        prenom:      order.user.prenom,
        orderNumber: order.orderNumber,
        status:      order.status,
        orderId:     order.id,
      });
    }

    return {
      message:     'Retrait confirmé',
      orderNumber: order.orderNumber,
      status:      order.status,
    };
  }

  // ─────────────────────────────────────────────────────
  // CAS C — BUS/TAXI, ÉTAPE 1 : le vendeur remet le colis au
  // transporteur (photo + état). Démarre le délai de 3 jours.
  // ─────────────────────────────────────────────────────
  async submitDispatchProof(
    orderId: string,
    userId:  string,
    dto:     SubmitDispatchProofDto,
    ip:      string,
  ) {
    const order = await this.orderRepo.findOne({
      where:     { id: orderId },
      relations: ['vendor', 'user'],
    });

    if (!order) throw new NotFoundException('Commande introuvable');

    const vendor = await this.vendorRepo.findOne({ where: { userId } });

    if (!vendor || order.vendorId !== vendor.id) {
      throw new ForbiddenException(
        'Vous n\'êtes pas autorisé à modifier cette commande'
      );
    }

    if (
      order.deliveryMode !== OrderDeliveryMode.LIVRAISON ||
      !order.transportMode
    ) {
      throw new BadRequestException(
        'Cette commande n\'est pas une livraison par bus/taxi'
      );
    }

    this.validateStatusTransition(order.status, OrderStatus.SHIPPED);
    this.assertOwnProofPhoto(dto.photoUrl);

    const oldStatus = order.status;
    order.status    = OrderStatus.SHIPPED;
    // Horodatage posé par le serveur, jamais par le client — point de
    // départ du délai de 3 jours (voir checkAutoConfirmBusTaxiOrders).
    order.expedieAt = new Date();
    await this.orderRepo.save(order);

    await this.proofRepo.save(this.proofRepo.create({
      orderId:         order.id,
      role:            ProofRole.VENDEUR,
      stage:           ProofStage.REMISE_TRANSPORTEUR,
      photoUrl:        dto.photoUrl,
      etatColis:       dto.etatColis,
      createdByUserId: userId,
    }));

    await this.logService.log({
      actorId:    userId,
      actorType:  ActorType.VENDOR,
      action:     LogAction.DELIVERY_PROOF_SUBMITTED,
      entityType: 'order',
      entityId:   orderId,
      oldValue:   { status: oldStatus },
      newValue:   { status: order.status },
      ipAddress:  ip,
    });

    // Préférence « Commandes & livraisons » de l'acheteur (e-mail de suivi).
    if (order.user?.email && (await this.notificationsService.isAllowed(order.userId, NotificationType.ORDER, 'orders'))) {
      void this.mailService.sendOrderStatusUpdate(order.user.email, {
        prenom:      order.user.prenom,
        orderNumber: order.orderNumber,
        status:      order.status,
        orderId:     order.id,
      });
    }

    return {
      message:     'Remise au transporteur enregistrée',
      orderNumber: order.orderNumber,
      status:      order.status,
    };
  }

  // ─────────────────────────────────────────────────────
  // CAS C — ÉTAPE 2a : le client confirme lui-même avoir reçu le
  // colis (photo).
  // ─────────────────────────────────────────────────────
  async submitReceptionProof(
    orderId: string,
    userId:  string,
    dto:     SubmitReceptionProofDto,
    ip:      string,
  ) {
    const order = await this.orderRepo.findOne({ where: { id: orderId } });

    if (!order) throw new NotFoundException('Commande introuvable');

    if (order.userId !== userId) {
      throw new ForbiddenException(
        'Vous n\'êtes pas autorisé à confirmer cette commande'
      );
    }

    if (!order.transportMode) {
      throw new BadRequestException(
        'Cette confirmation n\'est disponible que pour une livraison par bus/taxi'
      );
    }

    if (order.disputeOuverte) {
      throw new BadRequestException(
        'Un litige est en cours sur cette commande'
      );
    }

    this.validateStatusTransition(order.status, OrderStatus.DELIVERED);
    this.assertOwnProofPhoto(dto.photoUrl);

    const oldStatus = order.status;
    order.status = OrderStatus.DELIVERED;
    // Confirmation réelle du client, pas automatique.
    order.confirmationAutomatique = false;
    await this.orderRepo.save(order);
    await this.incrementProductSales(order.id);

    await this.proofRepo.save(this.proofRepo.create({
      orderId:         order.id,
      role:            ProofRole.CLIENT,
      stage:           ProofStage.RECEPTION_CLIENT,
      photoUrl:        dto.photoUrl,
      createdByUserId: userId,
    }));

    await this.logService.log({
      actorId:    userId,
      actorType:  ActorType.CLIENT,
      action:     LogAction.DELIVERY_PROOF_SUBMITTED,
      entityType: 'order',
      entityId:   orderId,
      oldValue:   { status: oldStatus },
      newValue:   { status: order.status },
      ipAddress:  ip,
    });

    return {
      message:     'Réception confirmée, merci !',
      orderNumber: order.orderNumber,
      status:      order.status,
    };
  }

  // ─────────────────────────────────────────────────────
  // CAS C — ÉTAPE 2b : le client conteste la réception dans le délai
  // de 3 jours. Bloque la confirmation automatique.
  // ─────────────────────────────────────────────────────
  async openDispute(
    orderId: string,
    userId:  string,
    dto:     OpenDisputeDto,
    ip:      string,
  ) {
    const order = await this.orderRepo.findOne({ where: { id: orderId } });

    if (!order) throw new NotFoundException('Commande introuvable');

    if (order.userId !== userId) {
      throw new ForbiddenException(
        'Vous n\'êtes pas autorisé à contester cette commande'
      );
    }

    if (!order.transportMode) {
      throw new BadRequestException(
        'Cette contestation n\'est disponible que pour une livraison par bus/taxi'
      );
    }

    if (order.status !== OrderStatus.SHIPPED) {
      throw new BadRequestException(
        'Cette commande n\'est pas en attente de confirmation de réception'
      );
    }

    if (order.disputeOuverte) {
      throw new BadRequestException(
        'Un litige est déjà ouvert sur cette commande'
      );
    }

    order.disputeOuverte = true;
    await this.orderRepo.save(order);

    await this.logService.log({
      actorId:    userId,
      actorType:  ActorType.CLIENT,
      action:     LogAction.ORDER_DISPUTE_OPENED,
      entityType: 'order',
      entityId:   orderId,
      newValue:   { motif: dto.motif },
      ipAddress:  ip,
    });

    return {
      message: 'Votre litige a été transmis à notre équipe, nous revenons vers vous rapidement',
    };
  }

  // ─────────────────────────────────────────────────────
  // LISTER LES PREUVES D'UNE COMMANDE (vendeur / client / livreur
  // assigné / admin) — avec minimisation des données selon le rôle du
  // demandeur.
  // ─────────────────────────────────────────────────────
  async getProofsForOrder(
    orderId:  string,
    userId:   string,
    isAdmin:  boolean = false,
  ) {
    const order = await this.orderRepo.findOne({
      where:     { id: orderId },
      relations: ['vendor'],
    });

    if (!order) throw new NotFoundException('Commande introuvable');

    let viewerRole: 'admin' | 'vendor' | 'client' | 'agent' | null = null;

    if (isAdmin) {
      viewerRole = 'admin';
    } else if (order.userId === userId) {
      viewerRole = 'client';
    } else {
      const vendor = await this.vendorRepo.findOne({ where: { userId } });
      if (vendor && order.vendorId === vendor.id) {
        viewerRole = 'vendor';
      } else if (await this.deliveryService.isAgentAssignedToOrder(orderId, userId)) {
        viewerRole = 'agent';
      }
    }

    if (!viewerRole) {
      throw new ForbiddenException(
        'Vous n\'êtes pas autorisé à consulter les preuves de cette commande'
      );
    }

    const proofs = await this.proofRepo.find({
      where: { orderId },
      order: { createdAt: 'ASC' },
    });

    // Minimisation : le vendeur n'a pas besoin de voir la signature ni
    // la position GPS exacte du client au moment de la remise finale.
    return proofs.map((p) => {
      if (viewerRole === 'vendor' && p.stage === ProofStage.REMISE_CLIENT) {
        return {
          ...p,
          signatureData: null,
          latitude:      null,
          longitude:     null,
        };
      }
      return p;
    });
  }

  // ─────────────────────────────────────────────────────
  // CAS C — CONFIRMATION AUTOMATIQUE APRÈS 3 JOURS SANS RÉACTION
  // ─────────────────────────────────────────────────────
  // Vérifiée toutes les heures : toute commande bus/taxi "Expédiée"
  // depuis plus de 3 jours, sans litige ouvert, passe automatiquement
  // à "Livrée" (ce qui débloque le paiement du vendeur côté admin).
  // expedieAt est posé par le serveur uniquement (voir
  // submitDispatchProof) — non falsifiable par le client ou le
  // vendeur.
  @Cron(CronExpression.EVERY_HOUR)
  async checkAutoConfirmBusTaxiOrders(): Promise<void> {
    const threshold = new Date(Date.now() - 3 * 24 * 60 * 60 * 1000);

    const candidates = await this.orderRepo.find({
      where: {
        status:          OrderStatus.SHIPPED,
        transportMode:   Not(IsNull()) as any,
        disputeOuverte:  false,
        expedieAt:       LessThanOrEqual(threshold),
      },
      relations: ['user'],
    });

    for (const order of candidates) {
      try {
        order.status = OrderStatus.DELIVERED;
        order.confirmationAutomatique = true;
        await this.orderRepo.save(order);
        await this.incrementProductSales(order.id);

        await this.logService.log({
          actorType:  ActorType.SYSTEM,
          action:     LogAction.ORDER_STATUS_CHANGED,
          entityType: 'order',
          entityId:   order.id,
          oldValue:   { status: OrderStatus.SHIPPED },
          newValue:   { status: OrderStatus.DELIVERED, confirmationAutomatique: true },
        });

        // Préférence « Commandes & livraisons » de l'acheteur (e-mail de suivi).
        if (order.user?.email && (await this.notificationsService.isAllowed(order.userId, NotificationType.ORDER, 'orders'))) {
          void this.mailService.sendOrderStatusUpdate(order.user.email, {
            prenom:      order.user.prenom,
            orderNumber: order.orderNumber,
            status:      order.status,
            orderId:     order.id,
          });
        }
      } catch (err) {
        this.logger.error(
          `Confirmation automatique impossible pour la commande ${order.id} : ${(err as Error).message}`,
        );
      }
    }
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

  // Départements du Nord du Bénin : aucun livreur Asoukaa n'y opère, le
  // client choisit bus (tarif de base de la zone, 2000f) ou taxi (1500f)
  // au paiement — voir CreateOrderDto.transportMode. Doit rester cohérent
  // avec DeliveryZoneService (frontend) qui affiche ce choix.
  private static readonly NORD_DEPARTEMENTS = [
    'Alibori',
    'Atacora',
    'Borgou',
    'Donga',
  ];
  private static readonly TARIF_TAXI_NORD = 1500;

  // Frais de livraison fixe pour une commune (table delivery_zones,
  // paramétrée par l'admin). Comparaison insensible à la casse/espaces ;
  // si la commune n'a pas encore de zone connue, on n'empêche pas la
  // création de la commande — on applique 0 (à surveiller côté admin).
  // Pour une commune du Nord avec transportMode = 'taxi', le tarif fixe
  // de la zone (bus, 2000f) est remplacé par TARIF_TAXI_NORD (1500f).
  private async getFraisLivraisonForCommune(
    commune: string,
    transportMode?: string | null,
  ): Promise<number> {
    if (!commune) return 0;
    const target = commune.trim().toLowerCase();
    const zone = await this.deliveryZoneRepo
      .createQueryBuilder('zone')
      .where('LOWER(TRIM(zone.commune)) = :target', { target })
      .andWhere('zone.isActive = true')
      .getOne();
    if (!zone) return 0;
    const isNord = OrdersService.NORD_DEPARTEMENTS.includes(zone.departement);
    if (isNord && transportMode === 'taxi') {
      return OrdersService.TARIF_TAXI_NORD;
    }
    return Number(zone.fraisLivraison);
  }

  // Génère un numéro de commande unique.
  // ⚠️ Auparavant : `count() + 1`. Deux commandes simultanées obtenaient le
  // MÊME numéro → violation de la contrainte unique, transaction annulée et
  // panier perdu pour l'un des deux clients. C'était en plus un COUNT(*)
  // complet sur `orders` à chaque commande, de plus en plus lent.
  // Une séquence Postgres est atomique par construction et en O(1).
  private async generateOrderNumber(manager: EntityManager): Promise<string> {
    const year = new Date().getFullYear();

    const [{ nextval }] = await manager.query(
      `SELECT nextval('orders_number_seq') AS nextval`,
    );

    const seq = String(nextval).padStart(5, '0');
    return `ASK-${year}-${seq}`;
  }

  // Crée la séquence si elle n'existe pas encore, en la calant sur le plus
  // grand numéro déjà émis (reprise propre sur une base existante).
  // Appelée une seule fois au démarrage du module.
  async onModuleInit(): Promise<void> {
    try {
      await this.dataSource.query(
        `CREATE SEQUENCE IF NOT EXISTS orders_number_seq START WITH 1`,
      );

      const [{ max }] = await this.dataSource.query(
        `SELECT COALESCE(MAX(NULLIF(regexp_replace("orderNumber", '^ASK-\\d{4}-', ''), '')::int), 0) AS max
         FROM orders`,
      );

      if (Number(max) > 0) {
        await this.dataSource.query(
          `SELECT setval('orders_number_seq', $1)`,
          [Number(max)],
        );
      }
    } catch (err) {
      // Ne jamais empêcher l'application de démarrer pour ça : le premier
      // appel à generateOrderNumber remontera l'erreur réelle si besoin.
      this.logger.error(
        `Initialisation de orders_number_seq impossible : ${(err as Error).message}`,
      );
    }
  }

  // Valide les transitions de statut autorisées.
  // ⚠️ AGENT_ASSIGNED / SHIPPED / IN_TRANSIT / DELIVERED ne sont plus
  // censés être atteints par un simple appel à updateStatus() pour un
  // vendeur (voir le garde-fou au début de updateStatus ci-dessus) —
  // ils passent par les routes de preuve dédiées. Cette table reste
  // la source unique de vérité sur les transitions valides, utilisée
  // à la fois par updateStatus() (chemin PENDING/CANCELLED restant) et
  // par toutes les méthodes de preuve ci-dessous.
  // Incrémente le compteur de ventes des produits d'une commande livrée.
  //
  // Avant, Product.totalVentes existait mais n'était jamais mis à jour :
  // l'onglet "Statistiques" du vendeur affichait donc toujours 0 vente.
  //
  // On compte la QUANTITÉ vendue (pas le nombre de commandes), et on passe
  // par la variante pour retrouver le produit (OrderItem référence une
  // variante, pas directement un produit).
  //
  // Best-effort : un compteur qui échoue ne doit jamais faire échouer la
  // livraison elle-même (même principe que visitCount côté boutique).
  // Appelé uniquement au passage en "livré", statut terminal
  // (validateStatusTransition interdit d'en sortir) : pas de double comptage.
  private async incrementProductSales(orderId: string): Promise<void> {
    try {
      const items = await this.orderItemRepo.find({
        where:     { orderId },
        relations: ['variant'],
      });

      for (const item of items) {
        const productId = item.variant?.productId;
        if (!productId) continue;
        await this.productRepo.increment(
          { id: productId },
          'totalVentes',
          item.quantity,
        );
      }
    } catch (error: any) {
      this.logger.warn(
        `Échec incrément totalVentes pour la commande ${orderId}`,
        error?.message,
      );
    }
  }

  private validateStatusTransition(
    current: OrderStatus,
    next:    OrderStatus,
  ): void {
    const allowed: Record<OrderStatus, OrderStatus[]> = {
      [OrderStatus.PENDING]:        [OrderStatus.PREPARING, OrderStatus.CANCELLED],
      // Cas A : → AGENT_ASSIGNED (assignAgent)
      // Cas B : → DELIVERED directement (storePickupProof)
      // Cas C : → SHIPPED (dispatchProof)
      [OrderStatus.PREPARING]:      [
        OrderStatus.AGENT_ASSIGNED,
        OrderStatus.SHIPPED,
        OrderStatus.DELIVERED,
        OrderStatus.CANCELLED,
      ],
      // Cas A : le ramassage du livreur fait passer directement à
      // SHIPPED (submitPickupProof)
      [OrderStatus.AGENT_ASSIGNED]: [OrderStatus.SHIPPED],
      // Cas A : → IN_TRANSIT (startTransit) ; Cas C : → DELIVERED
      // (receptionProof ou confirmation automatique à 3 jours)
      [OrderStatus.SHIPPED]:        [OrderStatus.IN_TRANSIT, OrderStatus.DELIVERED],
      // Cas A : → DELIVERED (submitHandoffProof)
      [OrderStatus.IN_TRANSIT]:     [OrderStatus.DELIVERED],
      [OrderStatus.DELIVERED]:      [],
      [OrderStatus.CANCELLED]:      [],
    };

    if (!allowed[current].includes(next)) {
      throw new BadRequestException(
        `Transition de statut invalide : `
        + `${current} → ${next} n'est pas autorisée`
      );
    }
  }

  // Vérifie qu'une URL de photo de preuve appartient bien à notre
  // propre stockage (voir UploadService.assertIsOwnUploadUrl) — même
  // contrôle systématiquement appliqué avant d'enregistrer toute
  // preuve contenant une photo.
  private assertOwnProofPhoto(photoUrl: string): void {
    this.uploadService.assertIsOwnUploadUrl(photoUrl, UploadType.PROOF);
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