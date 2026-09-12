import {
  Injectable,
  NotFoundException,
  BadRequestException,
  ForbiddenException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository }       from 'typeorm';
import { MailerService }    from '@nestjs-modules/mailer';

import { Delivery, DeliveryStatus }                        from './entities/delivery.entity';
import { IndependentDelivery, IndependentDeliveryStatus }  from './entities/independent-delivery.entity';
import { Order, OrderStatus }                              from '../orders/entities/order.entity';
import { DeliveryAgentProfile, AgentStatus }               from '../users/entities/delivery-agent-profile.entity';
import { VendorProfile }                                   from '../users/entities/vendor-profile.entity';
import { User }                                            from '../users/entities/user.entity';

import { AssignDeliveryAgentDto }        from './dto/assign-agent.dto';
import { UpdateDeliveryStatusDto }       from './dto/update-delivery-status.dto';
import { CreateIndependentDeliveryDto }  from './dto/create-independent-delivery.dto';
import { ActivityLogService }            from '../../common/services/activity-log.service';
import {
  ActorType,
  LogAction,
} from '../../common/entities/activity-log.entity';

@Injectable()
export class DeliveryService {

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

    private readonly mailerService: MailerService,
    private readonly logService:    ActivityLogService,
  ) {}

  // ─────────────────────────────────────────────────────
  // TYPE A — CRÉER UNE LIVRAISON (auto après commande)
  // Appelée par le module orders lors de la création
  // ─────────────────────────────────────────────────────
  async createForOrder(
    orderId:         string,
    pickupAddress:   string,
    adresseLivraison: string,
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
    delivery.status                 = DeliveryStatus.PENDING;

    return this.deliveryRepo.save(delivery);
  }

  // ─────────────────────────────────────────────────────
  // TYPE A — AFFECTER UN LIVREUR (vendeur uniquement)
  // ─────────────────────────────────────────────────────
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

    // Notifier le livreur par email
    await this.mailerService.sendMail({
      to:      agent.user.email,
      subject: '📦 Nouvelle livraison affectée',
      html: `
        <p>Bonjour ${agent.user.prenom},</p>
        <p>Une nouvelle livraison vous a été affectée.</p>
        <p><strong>Adresse de récupération :</strong> 
           ${delivery.pickupAddress}</p>
        <p><strong>Adresse de livraison :</strong> 
           ${delivery.adresseLivraison}</p>
        <p>Connectez-vous à l'application pour plus de détails.</p>
      `,
    });

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
  // TYPE A — METTRE À JOUR LE STATUT (livreur)
  // ─────────────────────────────────────────────────────
  async updateDeliveryStatus(
    deliveryId: string,
    userId:     string,
    dto:        UpdateDeliveryStatusDto,
    ip:         string,
  ) {
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

    // Remplir les timestamps selon le statut
    if (dto.status === DeliveryStatus.PICKED_UP) {
      delivery.pickedUpAt = new Date();
    }

    if (dto.status === DeliveryStatus.DELIVERED) {
      delivery.deliveredAt = new Date();

      // Passer la commande en DELIVERED
      const order    = delivery.order;
      order.status   = OrderStatus.DELIVERED;
      await this.orderRepo.save(order);

      // Remettre le livreur disponible
      agent.isAvailableNow    = true;
      agent.totalLivraisons  += 1;
      await this.agentRepo.save(agent);

      // Recalculer le taux de réussite
      await this.recalculateSuccessRate(agent.id);

      // Notifier le client
      await this.mailerService.sendMail({
        to:      order.user.email,
        subject: '✅ Commande livrée !',
        html: `
          <p>Bonjour ${order.user.prenom},</p>
          <p>Votre commande <strong>${order.orderNumber}</strong> 
             a été livrée avec succès !</p>
          <p>Merci de faire confiance à Asoukaa.</p>
        `,
      });
    }

    if (dto.status === DeliveryStatus.FAILED) {
      // Remettre le livreur disponible même en cas d'échec
      agent.isAvailableNow   = true;
      agent.totalLivraisons += 1;
      await this.agentRepo.save(agent);

      // Recalculer le taux de réussite (livraison échouée)
      await this.recalculateSuccessRate(agent.id);
    }

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
      .where('delivery.agentId = :agentId', { agentId: agent.id })
      .orderBy('delivery.createdAt', 'DESC')
      .skip((page - 1) * limit)
      .take(limit);

    if (status) {
      query.andWhere('delivery.status = :status', { status });
    }

    const [deliveries, total] = await query.getManyAndCount();

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

    // Notifier le demandeur
    await this.mailerService.sendMail({
      to:      delivery.requester.email,
      subject: '✅ Un livreur a accepté votre demande',
      html: `
        <p>Bonjour ${delivery.requester.prenom},</p>
        <p>Un livreur a accepté votre demande de livraison.</p>
        <p>Il vous contactera prochainement pour les détails.</p>
      `,
    });

    await this.logService.log({
      actorId:    userId,
      actorType:  ActorType.DELIVERY_AGENT,
      action:     LogAction.DELIVERY_ASSIGNED,
      entityType: 'independent_delivery',
      entityId:   deliveryId,
      newValue:   { agentId: agent.id },
      ipAddress:  ip,
    });

    return {
      message:  'Livraison acceptée avec succès',
      delivery,
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
  async getPendingIndependentDeliveries() {
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
      data:  deliveries,
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