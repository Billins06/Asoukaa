import {
  Injectable,
  Logger,
  NotFoundException,
  BadRequestException,
  ForbiddenException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, In, EntityManager } from 'typeorm';
import { Cron } from '@nestjs/schedule';

import {
  IndependentDelivery,
  IndependentDeliveryStatus as S,
  IndependentDelay,
} from './entities/independent-delivery.entity';
import { DeliveryAgentProfile, AgentStatus } from '../users/entities/delivery-agent-profile.entity';
import { User } from '../users/entities/user.entity';
import { NotificationsService } from '../notifications/notifications.service';
import { PaymentsService } from '../payments/payments.service';
import { DeliveryService, DEFAULT_AGENT_EARNINGS_RATE } from './delivery.service';
import { DeliveryEarning, DeliveryEarningStatus } from './entities/delivery-earning.entity';
import { ActivityLogService } from '../../common/services/activity-log.service';
import { ActorType, LogAction } from '../../common/entities/activity-log.entity';

import {
  CreateIndependentDeliveryDto,
  INDEPENDENT_MIN_PRICE,
  INDEPENDENT_MAX_PRICE,
} from './dto/create-independent-delivery.dto';
import { PayIndependentDeliveryDto } from './dto/pay-independent-delivery.dto';

// Durée pendant laquelle un livreur est « réservé » (contre-proposition à
// valider, ou paiement à faire). Passé ce délai, la demande redevient libre.
const RESERVATION_MS = 15 * 60 * 1000;
// Un paiement Mobile Money encore « en attente » après 30 min est abandonné.
const PAYMENT_ABANDON_MS = 30 * 60 * 1000;
// Écart de montant toléré (arrondis) entre FeexPay et notre base, en FCFA.
const AMOUNT_TOLERANCE = 5;
// Demandes ouvertes en même temps pour un même client (anti-spam).
const MAX_OPEN_REQUESTS = 5;

// Paiements qui bloquent la remise en circulation / l'annulation : « en attente »
// (FeexPay interrogé) et « à vérifier » (résultat incertain, à trancher à la main).
const HELD_PAYMENT_STATUSES = ['en attente', 'à vérifier'];
const OPEN_STATUSES = [S.PENDING, S.COUNTER_OFFER, S.AWAITING_PAYMENT];
const AGENT_BUSY_STATUSES = [S.COUNTER_OFFER, S.AWAITING_PAYMENT, S.ACCEPTED, S.IN_TRANSIT];

const DELAY_LABELS: Record<IndependentDelay, string> = {
  [IndependentDelay.NORMAL]:  'Normal (dans la journée)',
  [IndependentDelay.URGENT]:  'Urgent (2 à 3 h)',
  [IndependentDelay.EXPRESS]: 'Express (moins d\'1 h)',
};

const fmtF = (n: number) => `${Math.round(Number(n)).toLocaleString('fr-FR')} F`;

@Injectable()
export class IndependentDeliveriesService {
  private readonly logger = new Logger(IndependentDeliveriesService.name);

  constructor(
    @InjectRepository(IndependentDelivery)
    private readonly repo: Repository<IndependentDelivery>,
    @InjectRepository(DeliveryAgentProfile)
    private readonly agentRepo: Repository<DeliveryAgentProfile>,
    @InjectRepository(User)
    private readonly userRepo: Repository<User>,
    private readonly notifications: NotificationsService,
    private readonly paymentsService: PaymentsService,
    private readonly deliveryService: DeliveryService,
    private readonly logService: ActivityLogService,
  ) {}

  // ───────────────────────── helpers ─────────────────────────

  private async approvedAgent(userId: string): Promise<DeliveryAgentProfile> {
    const agent = await this.agentRepo.findOne({ where: { userId } });
    if (!agent || agent.status !== AgentStatus.APPROVED) {
      throw new ForbiddenException('Seuls les livreurs approuvés peuvent effectuer cette action');
    }
    return agent;
  }

  private async findOwned(id: string, userId: string): Promise<IndependentDelivery> {
    const d = await this.repo.findOne({ where: { id } });
    // 404 (et non 403) : on ne révèle pas l'existence de la demande d'un autre.
    if (!d || d.requesterId !== userId) throw new NotFoundException('Demande introuvable');
    return d;
  }

  private refusedList(d: IndependentDelivery): string[] {
    return d.refusedAgentIds ? d.refusedAgentIds.split(',').filter(Boolean) : [];
  }

  private safeNotify(fn: () => Promise<unknown>, what: string) {
    fn().catch((e) => this.logger.error(`Notification « ${what} » échouée : ${e?.message}`));
  }

  private async assertAgentFree(agent: DeliveryAgentProfile, m?: EntityManager) {
    if (!agent.isAvailableNow) {
      throw new BadRequestException('Vous n\'êtes pas disponible actuellement');
    }
    const busy = await (m ?? this.repo.manager).count(IndependentDelivery, {
      where: { agentId: agent.id, status: In(AGENT_BUSY_STATUSES) },
    });
    if (busy > 0) {
      throw new BadRequestException(
        'Vous avez déjà une course en attente de réponse, de paiement ou en cours.',
      );
    }
  }

  // Remet en circulation les demandes dont la réservation a expiré
  // (sauf si un paiement Mobile Money est en cours : le rattrapage décidera).
  async releaseExpired(): Promise<number> {
    const res = await this.repo
      .createQueryBuilder()
      .update(IndependentDelivery)
      .set({
        status: S.PENDING,
        agentId: null,
        counterPrice: null,
        tarifConvenu: null,
        reservedUntil: null,
        paymentStatus: null,
        paymentRef: null,
        paymentOperator: null,
        paymentRequestedAt: null,
      })
      .where('status IN (:...st)', { st: [S.COUNTER_OFFER, S.AWAITING_PAYMENT] })
      .andWhere('"reservedUntil" < :now', { now: new Date() })
      .andWhere('("paymentStatus" IS NULL OR "paymentStatus" NOT IN (:...held))', { held: HELD_PAYMENT_STATUSES })
      .execute();
    return res.affected ?? 0;
  }

  // ───────────────────────── client ─────────────────────────

  async create(userId: string, dto: CreateIndependentDeliveryDto, ip: string) {
    if (dto.proposedPrice < INDEPENDENT_MIN_PRICE || dto.proposedPrice > INDEPENDENT_MAX_PRICE) {
      throw new BadRequestException('Prix invalide');
    }
    const open = await this.repo.count({
      where: { requesterId: userId, status: In(OPEN_STATUSES) },
    });
    if (open >= MAX_OPEN_REQUESTS) {
      throw new BadRequestException(
        `Vous avez déjà ${MAX_OPEN_REQUESTS} demandes en cours. Annulez-en une ou attendez qu'elle soit traitée.`,
      );
    }

    const d = this.repo.create({
      requesterId:        userId,
      agentId:            null,
      pickupAddress:      dto.pickupAddress,
      adresseLivraison:   dto.adresseLivraison,
      packageDescription: dto.packageDescription || null,
      notes:              dto.notes || null,
      delai:              dto.delai,
      proposedPrice:      dto.proposedPrice,
      status:             S.PENDING,
      tarifConvenu:       null,
    });
    await this.repo.save(d);

    await this.logService.log({
      actorId: userId, actorType: ActorType.CLIENT,
      action: LogAction.DELIVERY_ASSIGNED, entityType: 'independent_delivery',
      entityId: d.id, newValue: { created: true, delai: d.delai, proposedPrice: d.proposedPrice },
      ipAddress: ip,
    });

    // Prévient les livreurs approuvés ET disponibles (best-effort).
    try {
      const agents = await this.agentRepo.find({
        where: { status: AgentStatus.APPROVED, isAvailableNow: true },
      });
      const details = `${DELAY_LABELS[d.delai]} · ${fmtF(dto.proposedPrice)}`;
      for (const a of agents) {
        if (a.userId === userId) continue;
        this.safeNotify(
          () => this.notifications.notifyNewIndependentDelivery(a.userId, d.id, details),
          `course express → livreur ${a.id}`,
        );
      }
    } catch (e) {
      this.logger.error(`Notification des livreurs impossible (course ${d.id}) : ${(e as Error)?.message}`);
    }

    return {
      message:    'Demande créée. Les livreurs disponibles sont prévenus.',
      deliveryId: d.id,
    };
  }

  async myRequests(userId: string) {
    await this.releaseExpired();
    const rows = await this.repo.find({
      where:     { requesterId: userId },
      relations: ['agent', 'agent.user'],
      order:     { createdAt: 'DESC' },
      take:      50,
    });
    // Rattrapage opportuniste des paiements en cours de CE client.
    for (const d of rows) {
      if (d.paymentStatus === 'en attente') {
        await this.syncPayment(d).catch(() => undefined);
      }
    }
    const fresh = rows.some((r) => r.paymentStatus === 'en attente')
      ? await this.repo.find({
          where: { requesterId: userId }, relations: ['agent', 'agent.user'],
          order: { createdAt: 'DESC' }, take: 50,
        })
      : rows;
    return fresh.map((d) => this.toClientView(d));
  }

  private toClientView(d: IndependentDelivery) {
    const revealAgent = [S.ACCEPTED, S.IN_TRANSIT, S.DELIVERED].includes(d.status);
    const agentUser = d.agent?.user;
    return {
      id:                 d.id,
      status:             d.status,
      pickupAddress:      d.pickupAddress,
      adresseLivraison:   d.adresseLivraison,
      packageDescription: d.packageDescription,
      notes:              d.notes,
      delai:              d.delai,
      proposedPrice:      d.proposedPrice !== null ? Number(d.proposedPrice) : null,
      counterPrice:       d.counterPrice !== null ? Number(d.counterPrice) : null,
      tarifConvenu:       d.tarifConvenu !== null ? Number(d.tarifConvenu) : null,
      paymentStatus:      d.paymentStatus,
      refundStatus:       d.refundStatus,
      cancelReason:       d.cancelReason,
      reservedUntil:      d.reservedUntil,
      createdAt:          d.createdAt,
      // Le livreur n'est visible (avec son téléphone) qu'une fois la course payée.
      agent: d.agentId && agentUser
        ? {
            prenom: agentUser.prenom,
            ...(revealAgent ? { phone: agentUser.phone } : {}),
          }
        : null,
    };
  }

  async respondToCounter(id: string, userId: string, accept: boolean, ip: string) {
    await this.releaseExpired();
    const d = await this.findOwned(id, userId);
    if (d.status !== S.COUNTER_OFFER || !d.agentId || d.counterPrice === null) {
      throw new BadRequestException('Il n\'y a pas de contre-proposition en attente de réponse (elle a peut-être expiré).');
    }
    const agent = await this.agentRepo.findOne({ where: { id: d.agentId } });

    if (accept) {
      const res = await this.repo
        .createQueryBuilder()
        .update(IndependentDelivery)
        .set({
          status:        S.AWAITING_PAYMENT,
          tarifConvenu:  () => '"counterPrice"',
          reservedUntil: new Date(Date.now() + RESERVATION_MS),
        })
        .where('id = :id AND status = :st', { id, st: S.COUNTER_OFFER })
        .execute();
      if (!res.affected) throw new BadRequestException('Cette contre-proposition n\'est plus disponible.');
      if (agent) {
        this.safeNotify(() => this.notifications.notifyIndependentCounterAnswer(agent.userId, id, true), 'contre-prop acceptée');
      }
    } else {
      const refused = [...this.refusedList(d), d.agentId].join(',');
      const res = await this.repo
        .createQueryBuilder()
        .update(IndependentDelivery)
        .set({
          status: S.PENDING, agentId: null, counterPrice: null,
          reservedUntil: null, refusedAgentIds: refused,
        })
        .where('id = :id AND status = :st', { id, st: S.COUNTER_OFFER })
        .execute();
      if (!res.affected) throw new BadRequestException('Cette contre-proposition n\'est plus disponible.');
      if (agent) {
        this.safeNotify(() => this.notifications.notifyIndependentCounterAnswer(agent.userId, id, false), 'contre-prop refusée');
      }
    }

    await this.logService.log({
      actorId: userId, actorType: ActorType.CLIENT,
      action: LogAction.DELIVERY_STATUS_CHANGED, entityType: 'independent_delivery',
      entityId: id, newValue: { counterOfferAccepted: accept }, ipAddress: ip,
    });

    return {
      message: accept
        ? 'Prix accepté. Payez maintenant pour confirmer la course (15 min).'
        : 'Contre-proposition refusée. Votre demande reste ouverte aux autres livreurs.',
    };
  }

  async cancel(id: string, userId: string, ip: string) {
    await this.releaseExpired();
    const d = await this.findOwned(id, userId);
    if (d.paymentStatus === 'en attente') {
      throw new BadRequestException('Un paiement est en cours : patientez quelques instants avant d\'annuler.');
    }
    if (d.paymentStatus === 'à vérifier') {
      throw new BadRequestException('Un paiement est en cours de vérification : contactez le support.');
    }
    if (!OPEN_STATUSES.includes(d.status)) {
      throw new BadRequestException(
        d.paymentStatus === 'success'
          ? 'Cette course est déjà payée : contactez le support pour l\'annuler.'
          : 'Cette demande ne peut plus être annulée.',
      );
    }
    const res = await this.repo
      .createQueryBuilder()
      .update(IndependentDelivery)
      .set({ status: S.CANCELLED, reservedUntil: null })
      .where('id = :id AND status IN (:...st) AND ("paymentStatus" IS NULL OR "paymentStatus" NOT IN (:...held))', {
        id, st: OPEN_STATUSES, held: HELD_PAYMENT_STATUSES,
      })
      .execute();
    if (!res.affected) throw new BadRequestException('Cette demande ne peut plus être annulée.');

    if (d.agentId) {
      const agent = await this.agentRepo.findOne({ where: { id: d.agentId } });
      if (agent) {
        this.safeNotify(() => this.notifications.notifyIndependentCancelledForAgent(agent.userId, id), 'annulation');
      }
    }
    await this.logService.log({
      actorId: userId, actorType: ActorType.CLIENT,
      action: LogAction.DELIVERY_STATUS_CHANGED, entityType: 'independent_delivery',
      entityId: id, oldValue: { status: d.status }, newValue: { status: S.CANCELLED }, ipAddress: ip,
    });
    return { message: 'Demande annulée.' };
  }

  // ───────────────────────── paiement ─────────────────────────

  async pay(id: string, userId: string, dto: PayIndependentDeliveryDto, ip: string) {
    await this.releaseExpired();
    const d = await this.findOwned(id, userId);
    if (d.paymentStatus === 'en attente') await this.syncPayment(d);
    const cur = await this.findOwned(id, userId);

    if (cur.status !== S.AWAITING_PAYMENT || cur.tarifConvenu === null) {
      throw new BadRequestException(
        cur.paymentStatus === 'success'
          ? 'Cette course est déjà payée.'
          : 'Cette course ne peut pas être payée maintenant (réservation expirée ?).',
      );
    }
    if (cur.paymentStatus === 'en attente') {
      throw new BadRequestException('Un paiement est déjà en cours : confirmez-le sur votre téléphone.');
    }
    if (cur.paymentStatus === 'à vérifier') {
      throw new BadRequestException('Votre paiement précédent est en cours de vérification : contactez le support avant de repayer.');
    }

    // Verrou : un seul paiement à la fois.
    const claim = await this.repo
      .createQueryBuilder()
      .update(IndependentDelivery)
      .set({
        paymentStatus: 'en attente', paymentOperator: dto.operator,
        paymentRequestedAt: new Date(), paymentRef: null,
      })
      .where('id = :id AND status = :st AND "reservedUntil" > :now AND ("paymentStatus" IS NULL OR "paymentStatus" = :f)', {
        id, st: S.AWAITING_PAYMENT, f: 'échoué', now: new Date(),
      })
      .execute();
    if (!claim.affected) throw new BadRequestException('Un paiement est déjà en cours pour cette course.');

    const user = await this.userRepo.findOne({ where: { id: userId } });
    try {
      const ref = await this.paymentsService.callFeexPayRequestToPay({
        phoneNumber: dto.phoneNumber,
        amount:      Number(cur.tarifConvenu),
        reseau:      dto.operator === 'MTN' ? 'MTN' : 'MOOV',
        firstName:   user?.prenom ?? 'Client',
        email:       user?.email ?? '',
        customId:    `ind-${cur.id}`,
        description: 'Course express Asoukaa',
      });
      await this.repo.update({ id }, { paymentRef: ref });
    } catch (err) {
      await this.repo.update({ id, paymentStatus: 'en attente' }, { paymentStatus: 'échoué' });
      throw err;
    }

    await this.logService.log({
      actorId: userId, actorType: ActorType.CLIENT,
      action: LogAction.DELIVERY_STATUS_CHANGED, entityType: 'independent_delivery',
      entityId: id, newValue: { paymentRequested: Number(cur.tarifConvenu), operator: dto.operator },
      ipAddress: ip,
    });

    return {
      message: 'Demande envoyée. Confirmez le paiement sur votre téléphone.',
      amount:  Number(cur.tarifConvenu),
    };
  }

  async paymentStatus(id: string, userId: string) {
    const d = await this.findOwned(id, userId);
    if (d.paymentStatus === 'en attente') await this.syncPayment(d);
    const cur = await this.findOwned(id, userId);
    return { status: cur.status, paymentStatus: cur.paymentStatus };
  }

  // Interroge FeexPay pour un paiement « en attente » et le règle. Ne lève pas.
  private async syncPayment(d: IndependentDelivery): Promise<void> {
    if (d.paymentStatus !== 'en attente') return;
    const age = d.paymentRequestedAt ? Date.now() - new Date(d.paymentRequestedAt).getTime() : 0;

    // La demande n'est jamais partie chez FeexPay (plantage entre-temps).
    if (!d.paymentRef) {
      if (age > 5 * 60 * 1000) {
        await this.repo.update({ id: d.id, paymentStatus: 'en attente' }, { paymentStatus: 'échoué' });
      }
      return;
    }

    try {
      const feex = await this.paymentsService.fetchFeexPayStatus(d.paymentRef);
      if (!feex.reachable) {
        // FeexPay injoignable très longtemps : on ne libère rien, on signale.
        if (age > PAYMENT_ABANDON_MS * 4) await this.markNeedsReview(d, 'FeexPay injoignable');
        return;
      }

      if (feex.state === 'success') {
        const expected = Number(d.tarifConvenu ?? 0);
        // Les frais FeexPay s'ajoutent par-dessus : seul un montant INFÉRIEUR est suspect.
        if (feex.amount !== undefined && feex.amount < expected - AMOUNT_TOLERANCE) {
          this.logger.warn(
            `Course express ${d.id} : montant FeexPay (${feex.amount}) < attendu (${expected}) — NON confirmé.`,
          );
          if (age > PAYMENT_ABANDON_MS) {
            await this.markNeedsReview(d, `montant reçu ${feex.amount} < attendu ${expected}`);
          }
          return;
        }
        await this.confirmPaid(d);
      } else if (feex.state === 'failed') {
        await this.markPaymentFailed(d);
      } else if (age > PAYMENT_ABANDON_MS) {
        // « en cours » ou statut inconnu après 30 min : le client peut encore
        // valider son paiement plus tard. On NE libère PAS la course (risque
        // de débit sans course) : elle passe « à vérifier ».
        await this.markNeedsReview(d, `FeexPay : ${feex.state}`);
      }
    } catch (e) {
      this.logger.warn(`Course express ${d.id} : règlement du paiement impossible : ${(e as Error)?.message}`);
    }
  }

  // Résultat de paiement incertain : la course reste réservée, à examiner à la main.
  private async markNeedsReview(d: IndependentDelivery, why: string) {
    const res = await this.repo
      .createQueryBuilder()
      .update(IndependentDelivery)
      .set({ paymentStatus: 'à vérifier' })
      .where('id = :id AND "paymentStatus" = :p', { id: d.id, p: 'en attente' })
      .execute();
    if (res.affected) {
      this.logger.error(
        `Course express ${d.id} : paiement FeexPay (réf. ${d.paymentRef}) à VÉRIFIER manuellement — ${why}.`,
      );
    }
  }

  private async markPaymentFailed(d: IndependentDelivery) {
    // On laisse 5 min de plus pour réessayer avec un autre numéro.
    await this.repo
      .createQueryBuilder()
      .update(IndependentDelivery)
      .set({ paymentStatus: 'échoué', reservedUntil: new Date(Date.now() + 5 * 60 * 1000) })
      .where('id = :id AND "paymentStatus" = :p', { id: d.id, p: 'en attente' })
      .execute();
  }

  private async confirmPaid(d: IndependentDelivery) {
    const res = await this.repo
      .createQueryBuilder()
      .update(IndependentDelivery)
      .set({ status: S.ACCEPTED, paymentStatus: 'success', paidAt: new Date(), reservedUntil: null })
      .where('id = :id AND status = :st AND "paymentStatus" = :p', {
        id: d.id, st: S.AWAITING_PAYMENT, p: 'en attente',
      })
      .execute();
    if (!res.affected) return; // déjà réglé par un autre passage

    if (d.agentId) {
      const agent = await this.agentRepo.findOne({ where: { id: d.agentId } });
      if (agent) {
        await this.agentRepo.update({ id: agent.id }, { isAvailableNow: false });
        this.safeNotify(
          () => this.notifications.notifyIndependentPaid(agent.userId, d.id, Number(d.tarifConvenu ?? 0)),
          'course payée',
        );
      }
    }
    await this.logService.log({
      actorId: d.requesterId, actorType: ActorType.CLIENT,
      action: LogAction.DELIVERY_STATUS_CHANGED, entityType: 'independent_delivery',
      entityId: d.id, newValue: { paid: Number(d.tarifConvenu ?? 0) }, ipAddress: 'system',
    });
  }

  // Toutes les minutes : libère les réservations expirées et règle les
  // paiements Mobile Money restés « en attente ».
  @Cron('*/1 * * * *', { name: 'independent-deliveries-maintenance' })
  async maintenance(): Promise<void> {
    try {
      const released = await this.releaseExpired();
      if (released > 0) this.logger.log(`${released} course(s) express remise(s) en circulation (réservation expirée).`);

      const pending = await this.repo.find({
        where: { paymentStatus: 'en attente' },
        order: { paymentRequestedAt: 'ASC' },
        take:  30,
      });
      for (const d of pending) await this.syncPayment(d);
    } catch (e) {
      this.logger.error(`Maintenance courses express : ${(e as Error)?.message}`);
    }
  }

  // ───────────────────────── livreur ─────────────────────────

  async available(userId: string) {
    const agent = await this.approvedAgent(userId);
    await this.releaseExpired();
    return this.repo
      .createQueryBuilder('delivery')
      .leftJoin('delivery.requester', 'requester')
      .select([
        'delivery.id', 'delivery.pickupAddress', 'delivery.adresseLivraison',
        'delivery.packageDescription', 'delivery.notes', 'delivery.delai',
        'delivery.proposedPrice', 'delivery.status', 'delivery.createdAt',
        'requester.id', 'requester.prenom',
      ])
      .where('delivery.status = :st', { st: S.PENDING })
      .andWhere('delivery."proposedPrice" IS NOT NULL')
      .andWhere('delivery."requesterId" <> :uid', { uid: userId })
      .andWhere('(delivery."refusedAgentIds" IS NULL OR delivery."refusedAgentIds" NOT LIKE :like)', {
        like: `%${agent.id}%`,
      })
      .orderBy('delivery.createdAt', 'ASC')
      .getMany();
  }

  async mine(userId: string) {
    const agent = await this.agentRepo.findOne({ where: { userId } });
    if (!agent) throw new NotFoundException('Profil livreur introuvable');
    await this.releaseExpired();
    const rows = await this.repo
      .createQueryBuilder('delivery')
      .leftJoin('delivery.requester', 'requester')
      .select([
        'delivery.id', 'delivery.pickupAddress', 'delivery.adresseLivraison',
        'delivery.packageDescription', 'delivery.notes', 'delivery.delai', 'delivery.status',
        'delivery.proposedPrice', 'delivery.counterPrice', 'delivery.tarifConvenu',
        'delivery.paymentStatus', 'delivery.reservedUntil', 'delivery.createdAt',
        'requester.id', 'requester.prenom', 'requester.phone',
      ])
      .where('delivery.agentId = :agentId', { agentId: agent.id })
      .orderBy('delivery.createdAt', 'DESC')
      .take(100)
      .getMany();
    // Le téléphone du client n'est donné qu'une fois la course payée.
    return rows.map((d) => {
      const paid = [S.ACCEPTED, S.IN_TRANSIT, S.DELIVERED].includes(d.status);
      if (!paid && d.requester) (d.requester as any).phone = null;
      return d;
    });
  }

  // Le livreur accepte le prix proposé par le client.
  async accept(id: string, userId: string, ip: string) {
    const agent = await this.approvedAgent(userId);
    await this.releaseExpired();
    const d = await this.repo.findOne({ where: { id } });
    if (!d || d.status !== S.PENDING || d.proposedPrice === null) {
      throw new BadRequestException('Cette livraison n\'est plus disponible');
    }
    if (d.requesterId === userId) throw new BadRequestException('Vous ne pouvez pas accepter votre propre demande');
    if (this.refusedList(d).includes(agent.id)) {
      throw new ForbiddenException('Votre contre-proposition a déjà été refusée pour cette demande');
    }
    const res = await this.repo.manager.transaction(async (m) => {
      // Verrou par livreur : deux demandes en parallèle ne peuvent pas lui
      // réserver deux courses à la fois.
      await m.query('SELECT pg_advisory_xact_lock(hashtext($1))', [agent.id]);
      await this.assertAgentFree(agent, m);
      return m
        .createQueryBuilder()
        .update(IndependentDelivery)
        .set({
          agentId: agent.id, status: S.AWAITING_PAYMENT,
          tarifConvenu: () => '"proposedPrice"',
          reservedUntil: new Date(Date.now() + RESERVATION_MS),
        })
        .where('id = :id AND status = :st', { id, st: S.PENDING })
        .execute();
    });
    if (!res.affected) throw new BadRequestException('Cette livraison n\'est plus disponible');

    this.safeNotify(
      () => this.notifications.notifyIndependentOffer(d.requesterId, id, 'accepted', Number(d.proposedPrice)),
      'livreur accepte',
    );
    await this.logService.log({
      actorId: userId, actorType: ActorType.DELIVERY_AGENT,
      action: LogAction.DELIVERY_ASSIGNED, entityType: 'independent_delivery',
      entityId: id, newValue: { agentId: agent.id, price: Number(d.proposedPrice) }, ipAddress: ip,
    });
    return {
      message: 'Prix accepté. En attente du paiement du client (15 min).',
    };
  }

  // Le livreur propose UN autre prix.
  async counter(id: string, userId: string, price: number, ip: string) {
    const agent = await this.approvedAgent(userId);
    await this.releaseExpired();
    const d = await this.repo.findOne({ where: { id } });
    if (!d || d.status !== S.PENDING || d.proposedPrice === null) {
      throw new BadRequestException('Cette livraison n\'est plus disponible');
    }
    if (d.requesterId === userId) throw new BadRequestException('Vous ne pouvez pas répondre à votre propre demande');
    if (this.refusedList(d).includes(agent.id)) {
      throw new ForbiddenException('Votre contre-proposition a déjà été refusée pour cette demande');
    }
    if (price < INDEPENDENT_MIN_PRICE || price > INDEPENDENT_MAX_PRICE) {
      throw new BadRequestException('Prix invalide');
    }
    if (price === Number(d.proposedPrice)) {
      throw new BadRequestException('Ce prix est identique à celui du client : utilisez « Accepter ».');
    }
    const res = await this.repo.manager.transaction(async (m) => {
      await m.query('SELECT pg_advisory_xact_lock(hashtext($1))', [agent.id]);
      await this.assertAgentFree(agent, m);
      return m
        .createQueryBuilder()
        .update(IndependentDelivery)
        .set({
          agentId: agent.id, status: S.COUNTER_OFFER, counterPrice: price,
          reservedUntil: new Date(Date.now() + RESERVATION_MS),
        })
        .where('id = :id AND status = :st', { id, st: S.PENDING })
        .execute();
    });
    if (!res.affected) throw new BadRequestException('Cette livraison n\'est plus disponible');

    this.safeNotify(
      () => this.notifications.notifyIndependentOffer(d.requesterId, id, 'counter', price),
      'contre-proposition',
    );
    await this.logService.log({
      actorId: userId, actorType: ActorType.DELIVERY_AGENT,
      action: LogAction.DELIVERY_STATUS_CHANGED, entityType: 'independent_delivery',
      entityId: id, newValue: { counterPrice: price }, ipAddress: ip,
    });
    return { message: 'Contre-proposition envoyée. Le client a 15 min pour répondre.' };
  }

  async updateStatus(id: string, userId: string, status: S, ip: string) {
    const agent = await this.agentRepo.findOne({ where: { userId } });
    const d = await this.repo.findOne({ where: { id } });
    if (!d) throw new NotFoundException('Livraison introuvable');
    if (!agent || d.agentId !== agent.id) {
      throw new ForbiddenException('Vous n\'êtes pas le livreur assigné à cette livraison');
    }
    const allowed: Record<string, S[]> = {
      [S.ACCEPTED]:   [S.IN_TRANSIT, S.DELIVERED],
      [S.IN_TRANSIT]: [S.DELIVERED],
    };
    if (!allowed[d.status]?.includes(status)) {
      throw new BadRequestException(
        d.status === S.AWAITING_PAYMENT || d.status === S.COUNTER_OFFER
          ? 'Le client n\'a pas encore payé cette course.'
          : 'Changement de statut impossible depuis l\'état actuel.',
      );
    }
    // Changement de statut + gain du livreur dans UNE transaction : si le gain ne
    // peut pas être enregistré, la course n'est pas marquée « livrée ».
    const done = await this.repo.manager.transaction(async (m) => {
      const res = await m
        .createQueryBuilder()
        .update(IndependentDelivery)
        .set({ status })
        .where('id = :id AND status = :cur', { id, cur: d.status })
        .execute();
      if (!res.affected) return false;

      if (status === S.DELIVERED) {
        // Même répartition que les autres livraisons : taux du livreur
        // (80 % par défaut) sur le prix payé par le client, le reste à la plateforme.
        const base = Number(d.tarifConvenu) || 0;
        const taux = agent.earningsRate != null
          ? Number(agent.earningsRate)
          : DEFAULT_AGENT_EARNINGS_RATE;
        const montantLivreur    = Math.round((base * taux / 100) * 100) / 100;
        const montantPlateforme = Math.round((base - montantLivreur) * 100) / 100;
        await m
          .createQueryBuilder()
          .insert()
          .into(DeliveryEarning)
          .values({
            deliveryId:            null,
            independentDeliveryId: id,
            agentId:               agent.id,
            fraisLivraison:        base,
            taux,
            montantLivreur,
            montantPlateforme,
            status:                DeliveryEarningStatus.PENDING,
          })
          .orIgnore()
          .execute();
      }
      return true;
    });
    if (!done) throw new BadRequestException('Statut déjà modifié.');

    if (status === S.DELIVERED) {
      await this.agentRepo
        .createQueryBuilder()
        .update(DeliveryAgentProfile)
        .set({ isAvailableNow: true })
        .where('id = :id AND status = :ok', { id: agent.id, ok: AgentStatus.APPROVED })
        .execute();
      await this.agentRepo.increment({ id: agent.id }, 'totalLivraisons', 1);
      await this.deliveryService.recalculateSuccessRate(agent.id);
    }
    this.safeNotify(
      () => this.notifications.notifyIndependentStatusForClient(
        d.requesterId, id, status === S.DELIVERED ? 'delivered' : 'in_transit',
      ),
      'statut course',
    );
    await this.logService.log({
      actorId: userId, actorType: ActorType.DELIVERY_AGENT,
      action: LogAction.DELIVERY_STATUS_CHANGED, entityType: 'independent_delivery',
      entityId: id, oldValue: { status: d.status }, newValue: { status }, ipAddress: ip,
    });
    return { message: 'Statut mis à jour', status };
  }
}
