import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, FindOptionsWhere, FindManyOptions } from 'typeorm';
import { DeliveryEarning, DeliveryEarningStatus } from '../delivery/entities/delivery-earning.entity';
import { ActivityLogService } from '../../common/services/activity-log.service';
import { ActorType, LogAction } from '../../common/entities/activity-log.entity';
import { stripSecrets } from '../../common/utils/strip-secrets.util';

export interface DeliveryEarningFilters {
  agentId?: string;
  status?: DeliveryEarningStatus;
  page?: number;
  limit?: number;
}

// Même logique que CommissionsService (payments/commissions/commissions.service.ts),
// côté livreur : lister/consulter/marquer payés les gains calculés à chaque
// livraison terminée (voir DeliveryService.submitHandoffProof).
@Injectable()
export class DeliveryEarningsService {
  constructor(
    @InjectRepository(DeliveryEarning)
    private earningRepo: Repository<DeliveryEarning>,
    private logService: ActivityLogService,
  ) {}

  async getAll(filters: DeliveryEarningFilters = {}) {
    const { agentId, status, page = 1, limit = 20 } = filters;

    const where: FindOptionsWhere<DeliveryEarning> = {};
    if (agentId) where.agentId = agentId;
    if (status) where.status = status;

    const options: FindManyOptions<DeliveryEarning> = {
      where,
      relations: ['delivery', 'agent', 'agent.user', 'processedBy'],
      order: { createdAt: 'DESC' },
      skip: (page - 1) * limit,
      take: limit,
    };

    const [earnings, total] = await this.earningRepo.findAndCount(options);

    return {
      data: stripSecrets(earnings),
      pagination: {
        total,
        page,
        limit,
        pages: Math.ceil(total / limit),
      },
    };
  }

  private async findOrFail(id: string) {
    const earning = await this.earningRepo.findOne({
      where: { id },
      relations: ['delivery', 'agent', 'agent.user', 'processedBy'],
    });

    if (!earning) {
      throw new NotFoundException(`Gain livreur ${id} introuvable`);
    }

    return earning;
  }

  // Version destinée à l'API (route admin) : sans champs secrets des comptes
  // chargés en relation (user, processedBy...). Les méthodes internes qui
  // modifient puis ENREGISTRENT l'entité utilisent findOrFail (entité brute).
  async getById(id: string) {
    return stripSecrets(await this.findOrFail(id));
  }

  async markAsPaid(
    earningId: string,
    processedById: string,
    ipAddress?: string,
  ) {
    const earning = await this.findOrFail(earningId);

    if (earning.status === DeliveryEarningStatus.PAID) {
      throw new BadRequestException('Ce gain a déjà été marqué comme payé');
    }

    earning.status = DeliveryEarningStatus.PAID;
    earning.paidAt = new Date();
    earning.processedById = processedById;

    const updated = await this.earningRepo.save(earning);

    await this.logService.log({
      actorId: processedById,
      actorType: ActorType.ADMIN,
      action: LogAction.PAYMENT_SUCCESS,
      entityType: 'DeliveryEarning',
      entityId: earningId,
      oldValue: { status: DeliveryEarningStatus.PENDING, paidAt: null },
      newValue: { status: DeliveryEarningStatus.PAID, paidAt: earning.paidAt },
      ipAddress,
    });

    return stripSecrets(updated);
  }

  async getStatistics() {
    const [totalPending, totalPaid, sumPending, sumPaid] = await Promise.all([
      this.earningRepo.count({ where: { status: DeliveryEarningStatus.PENDING } }),
      this.earningRepo.count({ where: { status: DeliveryEarningStatus.PAID } }),
      this.earningRepo
        .createQueryBuilder('e')
        .select('COALESCE(SUM(e.montantLivreur), 0)', 'sum')
        .where('e.status = :status', { status: DeliveryEarningStatus.PENDING })
        .getRawOne(),
      this.earningRepo
        .createQueryBuilder('e')
        .select('COALESCE(SUM(e.montantLivreur), 0)', 'sum')
        .where('e.status = :status', { status: DeliveryEarningStatus.PAID })
        .getRawOne(),
    ]);

    return {
      pending: { count: totalPending, amount: parseFloat(sumPending.sum || 0) },
      paid:    { count: totalPaid,    amount: parseFloat(sumPaid.sum || 0) },
      total: {
        count: totalPending + totalPaid,
        amount: parseFloat(sumPending.sum || 0) + parseFloat(sumPaid.sum || 0),
      },
    };
  }
}
