import {
  Injectable,
  Logger,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';

import {
  IndependentDelivery,
  IndependentDeliveryStatus as S,
} from './entities/independent-delivery.entity';
import { DeliveryEarning } from './entities/delivery-earning.entity';
import { DeliveryAgentProfile, AgentStatus } from '../users/entities/delivery-agent-profile.entity';
import { NotificationsService } from '../notifications/notifications.service';
import { ActivityLogService } from '../../common/services/activity-log.service';
import { ActorType, LogAction } from '../../common/entities/activity-log.entity';

export interface AdminExpressFilters {
  search?:       string;
  status?:       S;
  paymentStatus?: string;   // 'en attente' | 'success' | 'échoué' | 'à vérifier' | 'none'
  refundStatus?: string;    // 'à rembourser' | 'remboursé'
  attention?:    boolean;   // à vérifier OU à rembourser
  page:          number;
  limit:         number;
}

const HELD = ['en attente', 'à vérifier'];

const person = (u: any) =>
  u ? { id: u.id, name: [u.prenom, u.name].filter(Boolean).join(' ').trim() || '—', phone: u.phone ?? null, email: u.email ?? null } : null;

// Administration des courses express : consultation, paiements « à vérifier »,
// annulation (avec remboursement à faire) et suivi des remboursements.
@Injectable()
export class AdminIndependentDeliveriesService {
  private readonly logger = new Logger(AdminIndependentDeliveriesService.name);

  constructor(
    @InjectRepository(IndependentDelivery)
    private readonly repo: Repository<IndependentDelivery>,
    @InjectRepository(DeliveryAgentProfile)
    private readonly agentRepo: Repository<DeliveryAgentProfile>,
    @InjectRepository(DeliveryEarning)
    private readonly earningRepo: Repository<DeliveryEarning>,
    private readonly notifications: NotificationsService,
    private readonly logService: ActivityLogService,
  ) {}

  private safeNotify(fn: () => Promise<unknown>, what: string) {
    fn().catch((e) => this.logger.error(`Notification « ${what} » échouée : ${e?.message}`));
  }

  // ───────────────────────── liste ─────────────────────────
  async list(f: AdminExpressFilters) {
    const qb = this.repo
      .createQueryBuilder('d')
      .leftJoin('d.requester', 'req')
      .leftJoin('d.agent', 'ag')
      .leftJoin('ag.user', 'agu')
      .select([
        'd.id', 'd.status', 'd.paymentStatus', 'd.refundStatus', 'd.delai',
        'd.tarifConvenu', 'd.proposedPrice', 'd.pickupAddress', 'd.adresseLivraison',
        'd.createdAt', 'd.paidAt',
        'req.id', 'req.prenom', 'req.name', 'req.phone',
        'ag.id', 'agu.id', 'agu.prenom', 'agu.name', 'agu.phone',
      ]);

    if (f.search) {
      const like = `%${f.search.replace(/[\\%_]/g, (c) => `\\${c}`)}%`;
      qb.andWhere(
        `(req.name ILIKE :like OR req.prenom ILIKE :like OR req.phone ILIKE :like OR req.email ILIKE :like
          OR agu.name ILIKE :like OR agu.prenom ILIKE :like OR agu.phone ILIKE :like
          OR d."pickupAddress" ILIKE :like OR d."adresseLivraison" ILIKE :like OR CAST(d.id AS text) ILIKE :like)`,
        { like },
      );
    }
    if (f.status) qb.andWhere('d.status = :st', { st: f.status });
    if (f.paymentStatus === 'none') qb.andWhere('d."paymentStatus" IS NULL');
    else if (f.paymentStatus) qb.andWhere('d."paymentStatus" = :ps', { ps: f.paymentStatus });
    if (f.refundStatus) qb.andWhere('d."refundStatus" = :rs', { rs: f.refundStatus });
    if (f.attention) {
      qb.andWhere(`(d."paymentStatus" = 'à vérifier' OR d."refundStatus" = 'à rembourser')`);
    }

    const total = await qb.getCount();
    const rows = await qb
      .orderBy('d.createdAt', 'DESC')
      .addOrderBy('d.id', 'ASC')
      .skip((f.page - 1) * f.limit)
      .take(f.limit)
      .getMany();

    const [toReview, toRefund] = await Promise.all([
      this.repo.count({ where: { paymentStatus: 'à vérifier' } }),
      this.repo.count({ where: { refundStatus: 'à rembourser' } }),
    ]);

    return {
      data: rows.map((d) => ({
        id: d.id,
        status: d.status,
        paymentStatus: d.paymentStatus,
        refundStatus: d.refundStatus,
        delai: d.delai,
        price: d.tarifConvenu != null ? Number(d.tarifConvenu) : null,
        proposedPrice: d.proposedPrice != null ? Number(d.proposedPrice) : null,
        pickupAddress: d.pickupAddress,
        adresseLivraison: d.adresseLivraison,
        createdAt: d.createdAt,
        paidAt: d.paidAt,
        requester: person(d.requester),
        agent: d.agent ? person((d.agent as any).user) : null,
      })),
      total,
      page:  f.page,
      pages: Math.max(1, Math.ceil(total / f.limit)),
      toReview,
      toRefund,
    };
  }

  // ───────────────────────── détail ─────────────────────────
  async getOne(id: string) {
    const d = await this.repo.findOne({
      where: { id },
      relations: ['requester', 'agent', 'agent.user'],
    });
    if (!d) throw new NotFoundException('Course introuvable');
    const earning = await this.earningRepo.findOne({ where: { independentDeliveryId: id } });
    const a: any = d.agent;
    return {
      id: d.id,
      status: d.status,
      delai: d.delai,
      pickupAddress: d.pickupAddress,
      adresseLivraison: d.adresseLivraison,
      packageDescription: d.packageDescription,
      notes: d.notes,
      proposedPrice: d.proposedPrice != null ? Number(d.proposedPrice) : null,
      counterPrice: d.counterPrice != null ? Number(d.counterPrice) : null,
      price: d.tarifConvenu != null ? Number(d.tarifConvenu) : null,
      reservedUntil: d.reservedUntil,
      paymentStatus: d.paymentStatus,
      paymentRef: d.paymentRef,
      paymentOperator: d.paymentOperator,
      paymentRequestedAt: d.paymentRequestedAt,
      paidAt: d.paidAt,
      cancelReason: d.cancelReason,
      refundStatus: d.refundStatus,
      refundedAt: d.refundedAt,
      adminNote: d.adminNote,
      createdAt: d.createdAt,
      updatedAt: d.updatedAt,
      requester: person(d.requester),
      agent: a ? { ...person(a.user), agentId: a.id } : null,
      earning: earning
        ? {
            id: earning.id,
            base: Number(earning.fraisLivraison),
            taux: Number(earning.taux),
            montantLivreur: Number(earning.montantLivreur),
            montantPlateforme: Number(earning.montantPlateforme),
            status: earning.status,
            paidAt: earning.paidAt,
          }
        : null,
    };
  }

  private async mustFind(id: string): Promise<IndependentDelivery> {
    const d = await this.repo.findOne({ where: { id } });
    if (!d) throw new NotFoundException('Course introuvable');
    return d;
  }

  private appendNote(prev: string | null, add?: string, label = ''): string | null {
    const line = add?.trim();
    if (!line) return prev;
    const stamp = `[${new Date().toISOString().slice(0, 16).replace('T', ' ')}${label ? ' · ' + label : ''}] ${line}`;
    return prev ? `${prev}\n${stamp}`.slice(-2000) : stamp;
  }

  // ─────────────── trancher un paiement « à vérifier » ───────────────
  async resolvePayment(
    id: string, outcome: 'paid' | 'failed', note: string | undefined, adminId: string, ip: string,
  ) {
    const d = await this.mustFind(id);
    if (d.paymentStatus !== 'à vérifier' || d.status !== S.AWAITING_PAYMENT) {
      throw new BadRequestException('Cette course n\'a pas de paiement « à vérifier ».');
    }
    const adminNote = this.appendNote(d.adminNote, note, outcome === 'paid' ? 'paiement reçu' : 'paiement non reçu');

    if (outcome === 'paid') {
      const res = await this.repo
        .createQueryBuilder()
        .update(IndependentDelivery)
        .set({ status: S.ACCEPTED, paymentStatus: 'success', paidAt: new Date(), reservedUntil: null, adminNote })
        .where('id = :id AND status = :st AND "paymentStatus" = :p', { id, st: S.AWAITING_PAYMENT, p: 'à vérifier' })
        .execute();
      if (!res.affected) throw new BadRequestException('Cette course vient d\'être modifiée. Actualisez la page.');

      if (d.agentId) {
        const agent = await this.agentRepo.findOne({ where: { id: d.agentId } });
        if (agent) {
          await this.agentRepo.update({ id: agent.id }, { isAvailableNow: false });
          this.safeNotify(
            () => this.notifications.notifyIndependentPaid(agent.userId, id, Number(d.tarifConvenu ?? 0)),
            'course payée (admin)',
          );
        }
      }
    } else {
      // Rien reçu : le client a 5 minutes pour réessayer, puis la course est remise en circulation.
      const res = await this.repo
        .createQueryBuilder()
        .update(IndependentDelivery)
        .set({ paymentStatus: 'échoué', reservedUntil: new Date(Date.now() + 5 * 60 * 1000), adminNote })
        .where('id = :id AND status = :st AND "paymentStatus" = :p', { id, st: S.AWAITING_PAYMENT, p: 'à vérifier' })
        .execute();
      if (!res.affected) throw new BadRequestException('Cette course vient d\'être modifiée. Actualisez la page.');
    }

    await this.logService.log({
      actorId: adminId, actorType: ActorType.ADMIN,
      action: LogAction.DELIVERY_STATUS_CHANGED, entityType: 'independent_delivery', entityId: id,
      oldValue: { paymentStatus: 'à vérifier' },
      newValue: { paymentStatus: outcome === 'paid' ? 'success' : 'échoué', note: note ?? null },
      ipAddress: ip,
    });
    return {
      message: outcome === 'paid'
        ? 'Paiement confirmé : la course est lancée.'
        : 'Paiement marqué non reçu : le client peut réessayer pendant 5 minutes.',
    };
  }

  // ───────────────────────── annuler ─────────────────────────
  async cancel(id: string, reason: string, adminId: string, ip: string) {
    const d = await this.mustFind(id);
    if (d.status === S.DELIVERED) {
      throw new BadRequestException('Une course livrée ne peut plus être annulée.');
    }
    if (d.status === S.CANCELLED) {
      throw new BadRequestException('Cette course est déjà annulée.');
    }
    if (d.paymentStatus === 'en attente') {
      throw new BadRequestException('Un paiement est en cours : patientez quelques instants avant d\'annuler.');
    }
    if (d.paymentStatus === 'à vérifier') {
      throw new BadRequestException('Tranchez d\'abord le paiement « à vérifier » (reçu ou non reçu).');
    }
    const refund = d.paymentStatus === 'success';

    const res = await this.repo
      .createQueryBuilder()
      .update(IndependentDelivery)
      .set({
        status: S.CANCELLED,
        reservedUntil: null,
        cancelReason: reason.slice(0, 300),
        refundStatus: refund ? 'à rembourser' : null,
      })
      .where(
        'id = :id AND status = :cur AND "status" NOT IN (:...fin) AND ("paymentStatus" IS NULL OR "paymentStatus" NOT IN (:...held))',
        { id, cur: d.status, fin: [S.DELIVERED, S.CANCELLED], held: HELD },
      )
      .execute();
    if (!res.affected) throw new BadRequestException('Cette course vient d\'être modifiée. Actualisez la page.');

    // Le livreur redevient libre (il était bloqué par cette course).
    if (d.agentId) {
      const agent = await this.agentRepo.findOne({ where: { id: d.agentId } });
      if (agent) {
        if (d.status === S.ACCEPTED || d.status === S.IN_TRANSIT) {
          await this.agentRepo
            .createQueryBuilder()
            .update(DeliveryAgentProfile)
            .set({ isAvailableNow: true })
            .where('id = :id AND status = :ok', { id: agent.id, ok: AgentStatus.APPROVED })
            .execute();
        }
        this.safeNotify(
          () => this.notifications.notifyIndependentAdminCancelledForAgent(agent.userId, id, reason),
          'annulation admin (livreur)',
        );
      }
    }
    this.safeNotify(
      () => this.notifications.notifyIndependentAdminCancelledForClient(d.requesterId, id, refund, reason),
      'annulation admin (client)',
    );

    await this.logService.log({
      actorId: adminId, actorType: ActorType.ADMIN,
      action: LogAction.DELIVERY_STATUS_CHANGED, entityType: 'independent_delivery', entityId: id,
      oldValue: { status: d.status }, newValue: { status: S.CANCELLED, reason, refundToDo: refund }, ipAddress: ip,
    });
    return {
      message: refund
        ? 'Course annulée. Le remboursement du client reste à effectuer.'
        : 'Course annulée.',
      refundToDo: refund,
    };
  }

  // ───────────────────────── remboursement fait ─────────────────────────
  async markRefunded(id: string, note: string | undefined, adminId: string, ip: string) {
    const d = await this.mustFind(id);
    if (d.refundStatus !== 'à rembourser') {
      throw new BadRequestException('Cette course n\'a pas de remboursement en attente.');
    }
    const res = await this.repo
      .createQueryBuilder()
      .update(IndependentDelivery)
      .set({
        refundStatus: 'remboursé',
        refundedAt: new Date(),
        adminNote: this.appendNote(d.adminNote, note, 'remboursement'),
      })
      .where('id = :id AND "refundStatus" = :r', { id, r: 'à rembourser' })
      .execute();
    if (!res.affected) throw new BadRequestException('Remboursement déjà enregistré.');

    this.safeNotify(
      () => this.notifications.notifyIndependentRefunded(d.requesterId, id, Number(d.tarifConvenu ?? 0)),
      'remboursement',
    );
    await this.logService.log({
      actorId: adminId, actorType: ActorType.ADMIN,
      action: LogAction.PAYMENT_SUCCESS, entityType: 'independent_delivery', entityId: id,
      oldValue: { refundStatus: 'à rembourser' }, newValue: { refundStatus: 'remboursé', note: note ?? null },
      ipAddress: ip,
    });
    return { message: 'Remboursement enregistré.' };
  }
}
