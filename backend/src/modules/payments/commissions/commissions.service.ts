import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, FindOptionsWhere, FindManyOptions } from 'typeorm';
import { Commission, CommissionStatus } from '../entities/commission.entity';
import { ActivityLogService } from 'src/common/services/activity-log.service';
import { ActorType, LogAction, LogResult } from 'src/common/entities/activity-log.entity';

export interface CommissionFilters {
  vendorId?: string;
  status?: CommissionStatus;
  page?: number;
  limit?: number;
}

@Injectable()
export class CommissionsService {
  constructor(
    @InjectRepository(Commission)
    private commissionRepo: Repository<Commission>,
    private logService: ActivityLogService,
  ) {}

  async getAll(filters: CommissionFilters = {}) {
    const { vendorId, status, page = 1, limit = 20 } = filters;

    const where: FindOptionsWhere<Commission> = {};
    if (vendorId) where.vendorId = vendorId;
    if (status) where.status = status;

    const options: FindManyOptions<Commission> = {
      where,
      relations: ['order', 'vendor', 'vendor.user', 'processedBy'],
      order: { createdAt: 'DESC' },
      skip: (page - 1) * limit,
      take: limit,
    };

    const [commissions, total] = await this.commissionRepo.findAndCount(options);

    return {
      data: commissions,
      pagination: {
        total,
        page,
        limit,
        pages: Math.ceil(total / limit),
      },
    };
  }

  async getById(id: string) {
    const commission = await this.commissionRepo.findOne({
      where: { id },
      relations: ['order', 'vendor', 'vendor.user', 'processedBy'],
    });

    if (!commission) {
      throw new NotFoundException(`Commission ${id} not found`);
    }

    return commission;
  }

  async markAsPaid(
    commissionId: string,
    processedById: string,
    ipAddress?: string,
  ) {
    const commission = await this.getById(commissionId);

    if (commission.status === CommissionStatus.PAID) {
      throw new BadRequestException('Commission already marked as paid');
    }

    commission.status = CommissionStatus.PAID;
    commission.paidAt = new Date();
    commission.processedById = processedById;

    const updated = await this.commissionRepo.save(commission);

    await this.logService.log({
      actorId: processedById,
      actorType: ActorType.ADMIN,
      action: LogAction.PAYMENT_SUCCESS,
      entityType: 'Commission',
      entityId: commissionId,
      oldValue: { status: CommissionStatus.PENDING, paidAt: null },
      newValue: { status: CommissionStatus.PAID, paidAt: commission.paidAt },
      ipAddress,
    });

    return updated;
  }

  async getStatistics() {
    const [
      totalPending,
      totalPaid,
      sumPending,
      sumPaid,
    ] = await Promise.all([
      this.commissionRepo.count({ where: { status: CommissionStatus.PENDING } }),
      this.commissionRepo.count({ where: { status: CommissionStatus.PAID } }),
      this.commissionRepo
        .createQueryBuilder('c')
        .select('COALESCE(SUM(c.montantCommission), 0)', 'sum')
        .where('c.status = :status', { status: CommissionStatus.PENDING })
        .getRawOne(),
      this.commissionRepo
        .createQueryBuilder('c')
        .select('COALESCE(SUM(c.montantCommission), 0)', 'sum')
        .where('c.status = :status', { status: CommissionStatus.PAID })
        .getRawOne(),
    ]);

    return {
      pending: {
        count: totalPending,
        amount: parseFloat(sumPending.sum || 0),
      },
      paid: {
        count: totalPaid,
        amount: parseFloat(sumPaid.sum || 0),
      },
      total: {
        count: totalPending + totalPaid,
        amount: parseFloat(sumPending.sum || 0) + parseFloat(sumPaid.sum || 0),
      },
    };
  }
}
