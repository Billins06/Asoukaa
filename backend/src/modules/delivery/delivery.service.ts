import { toPublicVendor } from '../products/public-vendor.util';
import { toPublicDelivery, toPublicRequester } from './public-delivery.util';
import { stripSecrets } from '../../common/utils/strip-secrets.util';
import {
  Injectable,
  Logger,
  NotFoundException,
  BadRequestException,
  ForbiddenException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository }       from 'typeorm';
import { MailService }      from '../mail/mail.service';

import { Delivery, DeliveryStatus }                        from './entities/delivery.entity';
import { DeliveryEarning, DeliveryEarningStatus }          from './entities/delivery-earning.entity';
import { IndependentDelivery, IndependentDeliveryStatus }  from './entities/independent-delivery.entity';
import { DeliveryProof, ProofRole, ProofStage }            from './entities/delivery-proof.entity';
import { Order, OrderStatus }                              from '../orders/entities/order.entity';
import { DeliveryAgentProfile, AgentStatus }               from '../users/entities/delivery-agent-profile.entity';
import { VendorProfile }                                   from '../users/entities/vendor-profile.entity';
import { User }                                            from '../users/entities/user.entity';
import { OrderItem }                                        from '../orders/entities/order-item.entity';
import { Product }                                          from '../products/entities/product.entity';
import { UploadService, UploadType }                       from '../upload/upload.service';
import { NotificationsService }                            from '../notifications/notifications.service';
import { NotificationType }                                from '../notifications/entities/notification.entity';

import { AssignDeliveryAgentDto }        from './dto/assign-agent.dto';
import { UpdateDeliveryStatusDto }       from './dto/update-delivery-status.dto';
import { CreateIndependentDeliveryDto }  from './dto/create-independent-delivery.dto';
import { SubmitPickupProofDto }          from './dto/submit-pickup-proof.dto';
import { SubmitHandoffProofDto }         from './dto/submit-handoff-proof.dto';
import { ActivityLogService }            from '../../common/services/activity-log.service';
import {
  ActorType,
  LogAction,
} from '../../common/entities/activity-log.entity';

// Pourcentage par défaut du livreur quand DeliveryAgentProfile.earningsRate
// n'est pas encore fixé par l'admin pour ce livreur précis (voir 80/20
// convenu avec Collins — ajustable par livreur depuis l'admin plus tard).
const DEFAULT_AGENT_EARNINGS_RATE = 80; // 80% pour le livreur, 20% pour la plateforme

@Injectable()
export class DeliveryService {
  private readonly logger = new Logger(DeliveryService.name);

  constructor(
    @InjectRepository(Delivery)
    private readonly deliveryRepo: Repository<Delivery>,

    @InjectRepository(IndependentDelivery)
    private readonly indepDeliveryRepo: Repository<IndependentDelivery>,

    @InjectRepository(Order)
    private readonly orderRepo: Repository<Order>,

    @InjectRepository(DeliveryAgentProfile)
    private readonly agentRepo: Repository<DeliveryAgentProfile>,

    @InjectRepository(VendorProfile)
    private readonly vendorRepo: Repository<VendorProfile>,

    @InjectRepository(User)
    private readonly userRepo: Repository<User>,

    @InjectRepository(OrderItem)
    private readonly orderItemRepo: Repository<OrderItem>,

    @InjectRepository(Product)
    private readonly productRepo: Repository<Product>,

    @InjectRepository(DeliveryProof)
    private readonly proofRepo: Repository<DeliveryProof>,

    @InjectRepository(DeliveryEarning)
    private readonly earningRepo: Repository<DeliveryEarning>,

    private readonly mailService:   MailService,
    private readonly logService:    ActivityLogService,
    private readonly uploadService: UploadService,
    private readonly notificationsService: NotificationsService,
  ) {}

  // Incremente le compteur de ventes des produits d'une commande livree.
  //
  // Jumelle de OrdersService.incrementProductSales : c'est ICI que passe le
  // circuit de livraison principal (le livreur scanne le QR du client), qui
  // ne traverse jamais OrdersService. Sans cet appel, les ventes livrees par
  // les livreurs Asoukaa — la majorite — n'etaient pas comptees du tout.
  //
  // Dupliquee plutot que partagee pour ne pas creer de dependance entre
  // DeliveryModule et OrdersModule (risque de cycle).
  //
  // Best-effort : un compteur qui echoue ne doit jamais faire echouer la
  // livraison elle-meme.
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
        `Echec increment totalVentes pour la commande ${orderId}`,
        error?.message,
      );
    }
  }

  // ─────────────────────────────────────────────────────
  // TYPE A — CRÉER UNE LIVRAISON (auto après commande)
  // Appelée par le module orders lors de la création
  // ─────────────────────────────────────────────────────
  async createForOrder(
    orderId:          string,
    pickupAddress:    string,
    adresseLivraison: string,
    latitude?:        number | null,
    longitude?:       number | null,
  ): Promise<Delivery> {
    // Vérifier qu'une livraison n'existe pas déjà
    const existing = await this.deliveryRepo.findOne({
      where: { orderId },
    });

    if (existing) return existing;

    const delivery                  = this.deliveryRepo.create();
    delivery.orderId                = orderId;
    delivery.agentId                = null;
    delivery.pickupAddress          = pickupAddress;
    delivery.adresseLivraison       = adresseLivraison;
    delivery.latitude               = latitude ?? null;
    delivery.longitude              = longitude ?? null;
    delivery.status                 = DeliveryStatus.PENDING;

    return this.deliveryRepo.save(delivery);
  }

  // ─────────────────────────────────────────────────────
  // TYPE A — AFFECTER UN LIVREUR (vendeur uniquement)
  // ─────────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────
  // TYPE A — RÉCUPÉRER LA LIVRAISON D'UNE COMMANDE (vendeur)
  // Permet au vendeur de retrouver la fiche Delivery (et son id)
  // à partir de l'id de la commande, pour ensuite affecter un livreur.
  // ─────────────────────────────────────────────────────
  // Utilisé côté acheteur (écran de suivi de commande) : pas de
  // vérification de propriété vendeur ici, l'appelant
  // (OrdersService.getOrderById) a déjà vérifié que la commande
  // appartient bien au client qui fait la demande.
  //
  // ⚠️ USAGE INTERNE UNIQUEMENT (ex. notification du livreur) : renvoie
  // l'entité complète, livreur + compte utilisateur compris (hash du mot
  // de passe, e-mail, documents...). Ne JAMAIS renvoyer ce résultat tel
  // quel à un client ou à un vendeur : utiliser getPublicDeliveryForOrder.
  async getDeliveryForOrderRaw(orderId: string) {
    return this.deliveryRepo.findOne({
      where:     { orderId },
      relations: ['agent', 'agent.user'],
    });
  }

  // Version « publique » de la fiche de livraison, destinée au client
  // (suivi de commande) et au vendeur : le livreur n'y apparaît que par sa
  // fiche réduite (id, prénom, nom, téléphone, photo, type de véhicule).
  async getPublicDeliveryForOrder(orderId: string) {
    const delivery = await this.getDeliveryForOrderRaw(orderId);
    return delivery ? toPublicDelivery(delivery) : null;
  }

  // Utilisé par OrdersService.getProofsForOrder pour savoir si
  // l'appelant est le livreur assigné à cette commande (pas de
  // ForbiddenException ici — juste un booléen, contrairement à
  // getDeliveryForOrder ci-dessous qui est réservé au vendeur).
  async isAgentAssignedToOrder(orderId: string, userId: string): Promise<boolean> {
    const agent = await this.agentRepo.findOne({ where: { userId } });
    if (!agent) return false;

    const delivery = await this.deliveryRepo.findOne({
      where: { orderId, agentId: agent.id },
    });

    return !!delivery;
  }

  async getDeliveryForOrder(orderId: string, userId: string) {
    const vendor = await this.vendorRepo.findOne({
      where: { userId },
    });

    if (!vendor) {
      throw new ForbiddenException('Profil vendeur introuvable');
    }

    const delivery = await this.deliveryRepo.findOne({
      where:     { orderId },
      relations: ['order', 'agent', 'agent.user'],
    });

    if (!delivery) {
      throw new NotFoundException(
        'Aucune fiche de livraison pour cette commande '
        + '(commande en retrait en boutique, ou pas encore synchronisée)'
      );
    }

    if (delivery.order.vendorId !== vendor.id) {
      throw new ForbiddenException(
        'Cette commande ne vous appartient pas'
      );
    }

    // Fiche publique du livreur uniquement (jamais pièce d'identité,
    // selfie, hash du mot de passe, e-mail...).
    return toPublicDelivery(delivery, { withOrder: true });
  }

  async assignAgent(
    deliveryId: string,
    userId:     string,
    dto:        AssignDeliveryAgentDto,
    ip:         string,
  ) {
    const delivery = await this.deliveryRepo.findOne({
      where:     { id: deliveryId },
      relations: ['order', 'order.vendor'],
    });

    if (!delivery) throw new NotFoundException('Livraison introuvable');

    // Vérifier que c'est bien le vendeur de la commande
    const vendor = await this.vendorRepo.findOne({
      where: { userId },
    });

    if (!vendor || delivery.order.vendorId !== vendor.id) {
      throw new ForbiddenException(
        'Vous n\'êtes pas autorisé à affecter un livreur à cette livraison'
      );
    }

    // Vérifier que la livraison est en attente
    if (delivery.status !== DeliveryStatus.PENDING) {
      throw new BadRequestException(
        'Un livreur ne peut être affecté qu\'à une livraison en attente'
      );
    }

    // La commande doit être en préparation avant d'affecter un livreur
    // (sinon le statut client/vendeur "Livreur affecté" n'aurait pas
    // de sens juste après la création de la commande).
    if (delivery.order.status !== OrderStatus.PREPARING) {
      throw new BadRequestException(
        'La commande doit être "En préparation" avant d\'affecter un livreur'
      );
    }

    // Vérifier que le livreur est approuvé et disponible
    const agent = await this.agentRepo.findOne({
      where:     { id: dto.agentId },
      relations: ['user'],
    });

    if (!agent) {
      throw new NotFoundException('Livreur introuvable');
    }

    if (agent.status !== AgentStatus.APPROVED) {
      throw new BadRequestException(
        'Ce livreur n\'est pas approuvé'
      );
    }

    if (!agent.isAvailableNow) {
      throw new BadRequestException(
        'Ce livreur n\'est pas disponible actuellement'
      );
    }

    const oldStatus     = delivery.status;
    delivery.agentId    = dto.agentId;
    delivery.status     = DeliveryStatus.ASSIGNED;

    // Marquer le livreur comme indisponible
    agent.isAvailableNow = false;
    await this.agentRepo.save(agent);

    await this.deliveryRepo.save(delivery);

    // Le client/vendeur voient désormais "Livreur affecté".
    delivery.order.status = OrderStatus.AGENT_ASSIGNED;
    await this.orderRepo.save(delivery.order);

    // Notifier le livreur par email (best-effort)
    try {
      // Livraison AFFECTÉE = transactionnel : envoyé sans tenir compte des
      // préférences de notification.
      await this.mailService.sendDeliveryAssigned(agent.user.email, {
        prenom:          agent.user.prenom,
        pickupAddress:   delivery.pickupAddress,
        deliveryAddress: delivery.adresseLivraison,
      });
    } catch (error) {
      this.logger.error(`Échec envoi mail affectation livraison → ${agent.user.email}`, error?.message);
    }

    // Notification in-app au livreur (best-effort : même logique que l'email
    // ci-dessus et que chat.service.ts — l'affectation doit aboutir même si
    // la notification plante).
    try {
      await this.notificationsService.notifyDeliveryAssigned(
        agent.userId,
        delivery.id,
      );
    } catch (error) {
      this.logger.error(`Échec notification affectation livraison ${delivery.id}`, error?.message);
    }

    await this.logService.log({
      actorId:    userId,
      actorType:  ActorType.VENDOR,
      action:     LogAction.DELIVERY_ASSIGNED,
      entityType: 'delivery',
      entityId:   deliveryId,
      oldValue:   { status: oldStatus, agentId: null },
      newValue:   { status: delivery.status, agentId: dto.agentId },
      ipAddress:  ip,
    });

    return {
      message: 'Livreur affecté avec succès',
      delivery,
    };
  }

  // ─────────────────────────────────────────────────────
  // TYPE A — SIGNALER UN ÉCHEC DE LIVRAISON (livreur)
  // ─────────────────────────────────────────────────────
  // ⚠️ Cette route ne permet plus que le passage à FAILED. Les
  // transitions PICKED_UP / IN_TRANSIT / DELIVERED se font désormais
  // uniquement via les routes de preuve ci-dessous (submitPickupProof,
  // startTransit, submitHandoffProof) : un livreur ne doit jamais
  // pouvoir se déclarer "Livré" sans preuve — c'était le cas avant ce
  // correctif, et c'est exactement la faille que ce nouveau système
  // ferme.
  async updateDeliveryStatus(
    deliveryId: string,
    userId:     string,
    dto:        UpdateDeliveryStatusDto,
    ip:         string,
  ) {
    if (dto.status !== DeliveryStatus.FAILED) {
      throw new ForbiddenException(
        'Ce changement de statut doit passer par une preuve de livraison '
        + '(ramassage, démarrage ou remise au client)'
      );
    }

    const delivery = await this.deliveryRepo.findOne({
      where:     { id: deliveryId },
      relations: ['order', 'order.user', 'agent', 'agent.user'],
    });

    if (!delivery) throw new NotFoundException('Livraison introuvable');

    // Vérifier que c'est bien le livreur assigné
    const agent = await this.agentRepo.findOne({
      where: { userId },
    });

    if (!agent || delivery.agentId !== agent.id) {
      throw new ForbiddenException(
        'Vous n\'êtes pas le livreur assigné à cette livraison'
      );
    }

    // Vérifier les transitions autorisées
    this.validateDeliveryTransition(delivery.status, dto.status);

    const oldStatus  = delivery.status;
    delivery.status  = dto.status;

    // Remettre le livreur disponible même en cas d'échec
    agent.isAvailableNow   = true;
    agent.totalLivraisons += 1;
    await this.agentRepo.save(agent);

    // Recalculer le taux de réussite (livraison échouée)
    await this.recalculateSuccessRate(agent.id);

    await this.deliveryRepo.save(delivery);

    await this.logService.log({
      actorId:    userId,
      actorType:  ActorType.DELIVERY_AGENT,
      action:     LogAction.DELIVERY_STATUS_CHANGED,
      entityType: 'delivery',
      entityId:   deliveryId,
      oldValue:   { status: oldStatus },
      newValue:   { status: dto.status },
      ipAddress:  ip,
    });

    return {
      message: 'Statut de livraison mis à jour',
      status:  delivery.status,
    };
  }

  // ─────────────────────────────────────────────────────
  // TYPE A — CAS A, ÉTAPE 1 : PREUVE DE RAMASSAGE (livreur)
  // ─────────────────────────────────────────────────────
  // Le livreur photographie le colis chez le vendeur et déclare son
  // état. Cette preuve, à elle seule, fait passer la livraison à
  // PICKED_UP et la commande à "Expédiée" — et active côté vendeur le
  // bouton "Démarrer" (voir startTransit ci-dessous).
  async submitPickupProof(
    deliveryId: string,
    userId:     string,
    dto:        SubmitPickupProofDto,
    ip:         string,
  ) {
    const delivery = await this.deliveryRepo.findOne({
      where:     { id: deliveryId },
      relations: ['order'],
    });

    if (!delivery) throw new NotFoundException('Livraison introuvable');

    const agent = await this.agentRepo.findOne({ where: { userId } });

    if (!agent || delivery.agentId !== agent.id) {
      throw new ForbiddenException(
        'Vous n\'êtes pas le livreur assigné à cette livraison'
      );
    }

    this.validateDeliveryTransition(delivery.status, DeliveryStatus.PICKED_UP);

    // Défense en profondeur : les deux machines à état (Delivery et
    // Order) doivent rester synchronisées — si jamais l'une dérivait
    // de l'autre suite à un bug ailleurs, on refuse plutôt que de
    // pousser un statut incohérent.
    if (delivery.order.status !== OrderStatus.AGENT_ASSIGNED) {
      throw new BadRequestException(
        'La commande doit être au statut "Livreur affecté" pour enregistrer '
        + 'une preuve de ramassage'
      );
    }

    this.uploadService.assertIsOwnUploadUrl(dto.photoUrl, UploadType.PROOF);

    const oldStatus = delivery.status;

    delivery.status     = DeliveryStatus.PICKED_UP;
    delivery.pickedUpAt = new Date();
    await this.deliveryRepo.save(delivery);

    const order  = delivery.order;
    const oldOrderStatus = order.status;
    order.status = OrderStatus.SHIPPED;
    await this.orderRepo.save(order);

    await this.proofRepo.save(this.proofRepo.create({
      orderId:         order.id,
      deliveryId:      delivery.id,
      role:            ProofRole.LIVREUR,
      stage:           ProofStage.RAMASSAGE_LIVREUR,
      photoUrl:        dto.photoUrl,
      etatColis:       dto.etatColis,
      createdByUserId: userId,
    }));

    await this.logService.log({
      actorId:    userId,
      actorType:  ActorType.DELIVERY_AGENT,
      action:     LogAction.DELIVERY_PROOF_SUBMITTED,
      entityType: 'delivery',
      entityId:   deliveryId,
      oldValue:   { deliveryStatus: oldStatus, orderStatus: oldOrderStatus },
      newValue:   { deliveryStatus: delivery.status, orderStatus: order.status },
      ipAddress:  ip,
    });

    return {
      message:      'Preuve de ramassage enregistrée',
      deliveryStatus: delivery.status,
      orderStatus:    order.status,
    };
  }

  // ─────────────────────────────────────────────────────
  // TYPE A — CAS A, ÉTAPE 2 : DÉMARRER LA LIVRAISON (vendeur)
  // ─────────────────────────────────────────────────────
  // C'est le VENDEUR qui a la main ici, pas le livreur — décidé
  // explicitement pour éviter qu'un livreur récupère le colis sans
  // jamais "démarrer" la livraison. Le bouton n'est actif côté vendeur
  // que si la livraison est déjà PICKED_UP, c'est-à-dire si la preuve
  // de ramassage a bien été fournie.
  async startTransit(
    deliveryId: string,
    userId:     string,
    ip:         string,
  ) {
    const delivery = await this.deliveryRepo.findOne({
      where:     { id: deliveryId },
      // 'agent' est chargé uniquement pour connaître le userId du livreur
      // à notifier ci-dessous (c'est le vendeur qui agit ici, pas lui).
      relations: ['order', 'agent'],
    });

    if (!delivery) throw new NotFoundException('Livraison introuvable');

    const vendor = await this.vendorRepo.findOne({ where: { userId } });

    if (!vendor || delivery.order.vendorId !== vendor.id) {
      throw new ForbiddenException(
        'Vous n\'êtes pas autorisé à démarrer cette livraison'
      );
    }

    this.validateDeliveryTransition(delivery.status, DeliveryStatus.IN_TRANSIT);

    if (delivery.order.status !== OrderStatus.SHIPPED) {
      throw new BadRequestException(
        'La commande doit être au statut "Expédiée" pour démarrer la livraison'
      );
    }

    const oldStatus = delivery.status;
    delivery.status = DeliveryStatus.IN_TRANSIT;
    await this.deliveryRepo.save(delivery);

    const order = delivery.order;
    const oldOrderStatus = order.status;
    order.status = OrderStatus.IN_TRANSIT;
    await this.orderRepo.save(order);

    await this.logService.log({
      actorId:    userId,
      actorType:  ActorType.VENDOR,
      action:     LogAction.DELIVERY_STATUS_CHANGED,
      entityType: 'delivery',
      entityId:   deliveryId,
      oldValue:   { deliveryStatus: oldStatus, orderStatus: oldOrderStatus },
      newValue:   { deliveryStatus: delivery.status, orderStatus: order.status },
      ipAddress:  ip,
    });

    // Prévenir le livreur que le vendeur a lancé la course (best-effort).
    if (delivery.agent?.userId) {
      try {
        await this.notificationsService.notifyDeliveryStarted(
          delivery.agent.userId,
          delivery.id,
        );
      } catch (error) {
        this.logger.error(`Échec notification démarrage livraison ${delivery.id}`, error?.message);
      }
    }

    return {
      message:        'Livraison démarrée',
      deliveryStatus: delivery.status,
      orderStatus:    order.status,
    };
  }

  // ─────────────────────────────────────────────────────
  // TYPE A — CAS A, ÉTAPE 3 : PREUVE DE REMISE AU CLIENT (livreur)
  // ─────────────────────────────────────────────────────
  // Le livreur scanne le QR code du client ; sa position GPS est
  // capturée au même instant (même action = preuve qu'il est bien
  // avec le client) et le client signe directement sur l'écran du
  // livreur. Cette preuve fait passer la livraison et la commande à
  // "Livrée".
  async submitHandoffProof(
    deliveryId: string,
    userId:     string,
    dto:        SubmitHandoffProofDto,
    ip:         string,
  ) {
    const delivery = await this.deliveryRepo.findOne({
      where:     { id: deliveryId },
      relations: ['order', 'order.user', 'agent', 'agent.user'],
    });

    if (!delivery) throw new NotFoundException('Livraison introuvable');

    const agent = await this.agentRepo.findOne({ where: { userId } });

    if (!agent || delivery.agentId !== agent.id) {
      throw new ForbiddenException(
        'Vous n\'êtes pas le livreur assigné à cette livraison'
      );
    }

    this.validateDeliveryTransition(delivery.status, DeliveryStatus.DELIVERED);

    const order = delivery.order;

    if (order.status !== OrderStatus.IN_TRANSIT) {
      throw new BadRequestException(
        'La commande doit être "En transit" pour enregistrer la remise au client'
      );
    }

    // Le QR scanné doit correspondre à CETTE commande — sans quoi
    // n'importe quel QR récupéré ailleurs vaudrait "preuve".
    const expected = order.orderNumber.replace(/^ASK-/, '');
    const scanned  = dto.qrScanValue.replace(/^ASK-/, '');
    if (scanned !== expected) {
      throw new BadRequestException(
        'Le QR code scanné ne correspond pas à cette commande'
      );
    }

    const oldStatus = delivery.status;
    delivery.status      = DeliveryStatus.DELIVERED;
    delivery.deliveredAt = new Date();
    await this.deliveryRepo.save(delivery);

    const oldOrderStatus = order.status;
    order.status = OrderStatus.DELIVERED;
    await this.orderRepo.save(order);
    await this.incrementProductSales(order.id);

    await this.proofRepo.save(this.proofRepo.create({
      orderId:         order.id,
      deliveryId:      delivery.id,
      role:            ProofRole.LIVREUR,
      stage:           ProofStage.REMISE_CLIENT,
      qrScanValue:     dto.qrScanValue,
      latitude:        dto.latitude,
      longitude:       dto.longitude,
      signatureData:   dto.signatureData,
      createdByUserId: userId,
    }));

    // Remettre le livreur disponible
    agent.isAvailableNow   = true;
    agent.totalLivraisons += 1;
    await this.agentRepo.save(agent);
    await this.recalculateSuccessRate(agent.id);

    // Calculer le gain du livreur sur cette livraison (best-effort : un
    // échec ici ne doit jamais bloquer la confirmation de la livraison
    // elle-même, comme pour l'email juste après).
    try {
      await this.createDeliveryEarning(delivery, agent, order);
    } catch (error) {
      this.logger.error(`Échec calcul gain livreur ${agent.id} / livraison ${delivery.id}`, error?.message);
    }

    // Notifier le client (best-effort)
    try {
      // Préférence « Commandes & livraisons » de l'acheteur (e-mail de suivi).
      if (await this.notificationsService.isAllowed(order.userId, NotificationType.ORDER, 'orders')) await this.mailService.sendOrderStatusUpdate(order.user.email, {
        prenom:      order.user.prenom,
        orderNumber: order.orderNumber,
        status:      order.status,
        orderId:     order.id,
      });
    } catch (error) {
      this.logger.error(`Échec envoi mail commande livrée → ${order.user.email}`, error?.message);
    }

    await this.logService.log({
      actorId:    userId,
      actorType:  ActorType.DELIVERY_AGENT,
      action:     LogAction.DELIVERY_PROOF_SUBMITTED,
      entityType: 'delivery',
      entityId:   deliveryId,
      oldValue:   { deliveryStatus: oldStatus, orderStatus: oldOrderStatus },
      newValue:   { deliveryStatus: delivery.status, orderStatus: order.status },
      ipAddress:  ip,
    });

    return {
      message:        'Livraison confirmée',
      deliveryStatus: delivery.status,
      orderStatus:    order.status,
    };
  }

  // ─────────────────────────────────────────────────────
  // TYPE A — MES LIVRAISONS (livreur)
  // ─────────────────────────────────────────────────────
  async getMyDeliveries(
    userId: string,
    status?: DeliveryStatus,
    page:   number = 1,
    limit:  number = 20,
  ) {
    const agent = await this.agentRepo.findOne({
      where: { userId },
    });

    if (!agent) throw new NotFoundException('Profil livreur introuvable');

    const query = this.deliveryRepo
      .createQueryBuilder('delivery')
      .leftJoinAndSelect('delivery.order',         'order')
      .leftJoinAndSelect('order.items',            'item')
      .leftJoinAndSelect('item.variant',           'variant')
      .leftJoinAndSelect('variant.product',        'product')
      .leftJoinAndSelect('order.address',          'address')
      .leftJoinAndSelect('order.vendor',           'vendor')
      .where('delivery.agentId = :agentId', { agentId: agent.id })
      .orderBy('delivery.createdAt', 'DESC')
      .skip((page - 1) * limit)
      .take(limit);

    if (status) {
      query.andWhere('delivery.status = :status', { status });
    }

    const [deliveries, total] = await query.getManyAndCount();

    // Le livreur n'a besoin que de la fiche publique de la boutique
    // (nom, adresse de retrait) : jamais des documents ni du paiement.
    for (const d of deliveries) {
      if (d.order?.vendor) {
        (d.order as any).vendor = toPublicVendor(d.order.vendor);
      }
    }

    return {
      data:  deliveries,
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
    };
  }

  // ─────────────────────────────────────────────────────
  // TYPE B — CRÉER UNE LIVRAISON INDÉPENDANTE
  // ─────────────────────────────────────────────────────
  async createIndependent(
    userId: string,
    dto:    CreateIndependentDeliveryDto,
    ip:     string,
  ) {
    const delivery                    = this.indepDeliveryRepo.create();
    delivery.requesterId              = userId;
    delivery.agentId                  = null;
    delivery.pickupAddress            = dto.pickupAddress;
    delivery.adresseLivraison         = dto.adresseLivraison;
    delivery.packageDescription       = dto.packageDescription ?? null;
    delivery.status                   = IndependentDeliveryStatus.PENDING;
    delivery.tarifConvenu             = null;

    await this.indepDeliveryRepo.save(delivery);

    // Le message de retour ci-dessous promet depuis toujours que "les
    // livreurs disponibles seront notifiés" — c'est fait ici. Best-effort :
    // la demande doit être créée même si aucune notification ne part.
    try {
      const availableAgents = await this.agentRepo.find({
        where: {
          status:         AgentStatus.APPROVED,
          isAvailableNow: true,
        },
      });

      for (const availableAgent of availableAgents) {
        try {
          await this.notificationsService.notifyNewIndependentDelivery(
            availableAgent.userId,
            delivery.id,
          );
        } catch (error) {
          this.logger.error(`Échec notification course express → livreur ${availableAgent.id}`, error?.message);
        }
      }
    } catch (error) {
      this.logger.error(`Échec notification des livreurs pour la course express ${delivery.id}`, error?.message);
    }

    return {
      message:    'Demande de livraison créée. '
                + 'Les livreurs disponibles seront notifiés.',
      deliveryId: delivery.id,
    };
  }

  // ─────────────────────────────────────────────────────
  // TYPE B — ACCEPTER UNE LIVRAISON (livreur)
  // ─────────────────────────────────────────────────────
  async acceptIndependent(
    deliveryId: string,
    userId:     string,
    ip:         string,
  ) {
    const delivery = await this.indepDeliveryRepo.findOne({
      where:     { id: deliveryId },
      relations: ['requester'],
    });

    if (!delivery) throw new NotFoundException('Livraison introuvable');

    if (delivery.status !== IndependentDeliveryStatus.PENDING) {
      throw new BadRequestException(
        'Cette livraison n\'est plus disponible'
      );
    }

    const agent = await this.agentRepo.findOne({
      where: { userId },
    });

    if (!agent) throw new NotFoundException('Profil livreur introuvable');

    if (agent.status !== AgentStatus.APPROVED) {
      throw new ForbiddenException('Votre profil livreur n\'est pas approuvé');
    }

    if (!agent.isAvailableNow) {
      throw new BadRequestException('Vous n\'êtes pas disponible actuellement');
    }

    delivery.agentId         = agent.id;
    delivery.status          = IndependentDeliveryStatus.ACCEPTED;
    agent.isAvailableNow     = false;

    await this.agentRepo.save(agent);
    await this.indepDeliveryRepo.save(delivery);

    // Notifier le demandeur (best-effort)
    try {
      await this.mailService.sendIndependentDeliveryAccepted(
        delivery.requester.email,
        delivery.requester.prenom,
      );
    } catch (error) {
      this.logger.error(`Échec envoi mail acceptation livraison → ${delivery.requester.email}`, error?.message);
    }

    await this.logService.log({
      actorId:    userId,
      actorType:  ActorType.DELIVERY_AGENT,
      action:     LogAction.DELIVERY_ASSIGNED,
      entityType: 'independent_delivery',
      entityId:   deliveryId,
      newValue:   { agentId: agent.id },
      ipAddress:  ip,
    });

    // Le livreur ne reçoit du demandeur que son id, son prénom et son
    // téléphone (jamais le compte complet : hash du mot de passe, e-mail...).
    const { requester, ...deliveryRest } = delivery as any;
    return {
      message:  'Livraison acceptée avec succès',
      delivery: { ...deliveryRest, requester: toPublicRequester(requester) },
    };
  }

  // ─────────────────────────────────────────────────────
  // TYPE B — METTRE À JOUR LE STATUT (livreur)
  // ─────────────────────────────────────────────────────
  async updateIndependentStatus(
    deliveryId: string,
    userId:     string,
    status:     IndependentDeliveryStatus,
    ip:         string,
  ) {
    const delivery = await this.indepDeliveryRepo.findOne({
      where:     { id: deliveryId },
      relations: ['requester', 'agent', 'agent.user'],
    });

    if (!delivery) throw new NotFoundException('Livraison introuvable');

    const agent = await this.agentRepo.findOne({ where: { userId } });

    if (!agent || delivery.agentId !== agent.id) {
      throw new ForbiddenException(
        'Vous n\'êtes pas le livreur assigné à cette livraison'
      );
    }

    const oldStatus  = delivery.status;
    delivery.status  = status;

    if (status === IndependentDeliveryStatus.DELIVERED) {
      agent.isAvailableNow   = true;
      agent.totalLivraisons += 1;
      await this.agentRepo.save(agent);
      await this.recalculateSuccessRate(agent.id);
    }

    await this.indepDeliveryRepo.save(delivery);

    await this.logService.log({
      actorId:    userId,
      actorType:  ActorType.DELIVERY_AGENT,
      action:     LogAction.DELIVERY_STATUS_CHANGED,
      entityType: 'independent_delivery',
      entityId:   deliveryId,
      oldValue:   { status: oldStatus },
      newValue:   { status },
      ipAddress:  ip,
    });

    return {
      message: 'Statut mis à jour',
      status:  delivery.status,
    };
  }

  // ─────────────────────────────────────────────────────
  // TYPE B — LISTE DES DEMANDES EN ATTENTE (pour livreurs)
  // ─────────────────────────────────────────────────────
  async getPendingIndependentDeliveries(userId: string) {
    // ⚠️ Cette route n'était protégée que par JwtAuthGuard : n'importe quel
    // utilisateur connecté (un simple client) pouvait lister TOUTES les
    // demandes en attente, avec adresses d'enlèvement, de livraison et
    // numéros de téléphone des demandeurs.
    // On exige désormais un profil livreur APPROUVÉ — cohérent avec
    // acceptIndependent(), qui le vérifie déjà.
    const agent = await this.agentRepo.findOne({ where: { userId } });

    if (!agent || agent.status !== AgentStatus.APPROVED) {
      throw new ForbiddenException(
        'Seuls les livreurs approuves peuvent consulter les demandes de livraison',
      );
    }

    return this.indepDeliveryRepo
      .createQueryBuilder('delivery')
      .leftJoinAndSelect('delivery.requester', 'requester')
      .select([
        'delivery.id',
        'delivery.pickupAddress',
        'delivery.adresseLivraison',
        'delivery.packageDescription',
        'delivery.createdAt',
        'requester.id',
        'requester.prenom',
        'requester.phone',
      ])
      .where('delivery.status = :status', {
        status: IndependentDeliveryStatus.PENDING,
      })
      .orderBy('delivery.createdAt', 'ASC')
      .getMany();
  }

  // ─────────────────────────────────────────────────────
  // TYPE B — MES COURSES EXPRESS (livreur)
  // Les courses independantes que ce livreur a acceptees.
  // ─────────────────────────────────────────────────────
  async getMyIndependentDeliveries(userId: string) {
    const agent = await this.agentRepo.findOne({ where: { userId } });

    if (!agent) throw new NotFoundException('Profil livreur introuvable');

    return this.indepDeliveryRepo
      .createQueryBuilder('delivery')
      .leftJoinAndSelect('delivery.requester', 'requester')
      .select([
        'delivery.id',
        'delivery.pickupAddress',
        'delivery.adresseLivraison',
        'delivery.packageDescription',
        'delivery.status',
        'delivery.tarifConvenu',
        'delivery.createdAt',
        'requester.id',
        'requester.prenom',
        'requester.phone',
      ])
      .where('delivery.agentId = :agentId', { agentId: agent.id })
      .orderBy('delivery.createdAt', 'DESC')
      .getMany();
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — TOUTES LES LIVRAISONS TYPE A
  // ─────────────────────────────────────────────────────
  async getAllDeliveries(
    status?: DeliveryStatus,
    page:    number = 1,
    limit:   number = 20,
  ) {
    const query = this.deliveryRepo
      .createQueryBuilder('delivery')
      .leftJoinAndSelect('delivery.order', 'order')
      .leftJoinAndSelect('delivery.agent', 'agent')
      .leftJoinAndSelect('agent.user',     'agentUser')
      .orderBy('delivery.createdAt', 'DESC')
      .skip((page - 1) * limit)
      .take(limit);

    if (status) {
      query.where('delivery.status = :status', { status });
    }

    const [deliveries, total] = await query.getManyAndCount();

    return {
      // Route admin : on retire malgré tout les champs secrets des comptes
      // livreurs chargés par la jointure agent.user.
      data:  stripSecrets(deliveries),
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
    };
  }

  // ─────────────────────────────────────────────────────
  // MÉTHODES PRIVÉES
  // ─────────────────────────────────────────────────────

  // Transitions autorisées pour Type A
  private validateDeliveryTransition(
    current: DeliveryStatus,
    next:    DeliveryStatus,
  ): void {
    const allowed: Record<DeliveryStatus, DeliveryStatus[]> = {
      [DeliveryStatus.PENDING]:    [],
      [DeliveryStatus.ASSIGNED]:   [DeliveryStatus.PICKED_UP],
      [DeliveryStatus.PICKED_UP]:  [DeliveryStatus.IN_TRANSIT],
      [DeliveryStatus.IN_TRANSIT]: [DeliveryStatus.DELIVERED, DeliveryStatus.FAILED],
      [DeliveryStatus.DELIVERED]:  [],
      [DeliveryStatus.FAILED]:     [],
    };

    if (!allowed[current].includes(next)) {
      throw new BadRequestException(
        `Transition invalide : ${current} → ${next}`
      );
    }
  }

  // Calcule et enregistre le gain du livreur sur cette livraison — une
  // seule fois (deliveryId est UNIQUE sur delivery_earnings). Le calcul se
  // base sur order.fraisLivraison (ce que le client a payé pour la
  // livraison) et sur le taux propre à CE livreur, ou le taux par défaut
  // si l'admin n'en a pas encore fixé un pour lui (voir
  // DEFAULT_AGENT_EARNINGS_RATE).
  private async createDeliveryEarning(
    delivery: Delivery,
    agent:    DeliveryAgentProfile,
    order:    Order,
  ): Promise<void> {
    const existing = await this.earningRepo.findOne({ where: { deliveryId: delivery.id } });
    if (existing) return; // déjà calculé (ex: appel en double) — on ne double pas le gain

    const fraisLivraison = Number(order.fraisLivraison) || 0;
    const taux = agent.earningsRate != null
      ? Number(agent.earningsRate)
      : DEFAULT_AGENT_EARNINGS_RATE;

    const montantLivreur    = Math.round((fraisLivraison * taux / 100) * 100) / 100;
    const montantPlateforme = Math.round((fraisLivraison - montantLivreur) * 100) / 100;

    await this.earningRepo.save(this.earningRepo.create({
      deliveryId: delivery.id,
      agentId:    agent.id,
      fraisLivraison,
      taux,
      montantLivreur,
      montantPlateforme,
      status: DeliveryEarningStatus.PENDING,
    }));
  }

  // Recalcule le taux de réussite du livreur
  private async recalculateSuccessRate(agentId: string): Promise<void> {
    const total = await this.deliveryRepo.count({
      where: { agentId },
    });

    const delivered = await this.deliveryRepo.count({
      where: { agentId, status: DeliveryStatus.DELIVERED },
    });

    // Compter aussi les livraisons indépendantes
    const totalIndep = await this.indepDeliveryRepo.count({
      where: { agentId },
    });

    const deliveredIndep = await this.indepDeliveryRepo.count({
      where: {
        agentId,
        status: IndependentDeliveryStatus.DELIVERED,
      },
    });

    const totalAll     = total + totalIndep;
    const deliveredAll = delivered + deliveredIndep;

    const rate = totalAll > 0
      ? Number(((deliveredAll / totalAll) * 100).toFixed(2))
      : 0;

    await this.agentRepo.update(
      { id: agentId },
      { tauxDeReussite: rate },
    );
  }
}