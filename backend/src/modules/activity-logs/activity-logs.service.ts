import {
  Injectable,
  NotFoundException,
  Logger,
} from '@nestjs/common';
import { InjectRepository }  from '@nestjs/typeorm';
import { Repository, LessThan } from 'typeorm';
import { Cron, CronExpression } from '@nestjs/schedule';

import {
  ActivityLog,
  ActorType,
  LogAction,
  LogResult,
} from '../../common/entities/activity-log.entity';
import { ActivityLogQueryDto } from '../../common/dto/activity-log-query.dto';

@Injectable()
export class ActivityLogsService {

  private readonly logger = new Logger(ActivityLogsService.name);

  constructor(
    @InjectRepository(ActivityLog)
    private readonly logRepo: Repository<ActivityLog>,
  ) {}

  // ─────────────────────────────────────────────────────
  // CONSULTER LES LOGS (avec filtres avancés)
  // ─────────────────────────────────────────────────────
  async findAll(query: ActivityLogQueryDto) {
    const {
      actorType,
      actorId,
      action,
      result,
      startDate,
      endDate,
      page  = 1,
      limit = 20,
    } = query;

    const qb = this.logRepo
      .createQueryBuilder('log')
      .orderBy('log.createdAt', 'DESC')
      .skip((page - 1) * limit)
      .take(limit);

    // Filtres dynamiques
    if (actorType) {
      qb.andWhere('log.actorType = :actorType', { actorType });
    }

    if (actorId) {
      qb.andWhere('log.actorId = :actorId', { actorId });
    }

    if (action) {
      qb.andWhere('log.action = :action', { action });
    }

    if (result) {
      qb.andWhere('log.result = :result', { result });
    }

    if (startDate && endDate) {
      qb.andWhere('log.createdAt BETWEEN :start AND :end', {
        start: new Date(startDate),
        end:   new Date(endDate),
      });
    } else if (startDate) {
      qb.andWhere('log.createdAt >= :start', {
        start: new Date(startDate),
      });
    } else if (endDate) {
      qb.andWhere('log.createdAt <= :end', {
        end: new Date(endDate),
      });
    }

    const [logs, total] = await qb.getManyAndCount();

    return {
      data:  logs,
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
    };
  }

  // ─────────────────────────────────────────────────────
  // DÉTAILS D'UN LOG
  // ─────────────────────────────────────────────────────
  async findOne(id: string) {
    const log = await this.logRepo.findOne({
      where: { id },
    });

    if (!log) throw new NotFoundException('Log introuvable');

    return log;
  }

  // ─────────────────────────────────────────────────────
  // LOGS D'UN ACTEUR SPÉCIFIQUE
  // (utile pour suivre l'activité d'un user, vendor, admin)
  // ─────────────────────────────────────────────────────
  async findByActor(
    actorId: string,
    page    = 1,
    limit   = 20,
  ) {
    const [logs, total] = await this.logRepo.findAndCount({
      where: { actorId },
      order: { createdAt: 'DESC' },
      skip:  (page - 1) * limit,
      take:  limit,
    });

    return {
      data:  logs,
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
    };
  }

  // ─────────────────────────────────────────────────────
  // LOGS D'UNE ENTITÉ SPÉCIFIQUE
  // (ex: voir l'historique complet d'une commande)
  // ─────────────────────────────────────────────────────
  async findByEntity(
    entityType: string,
    entityId:   string,
    page        = 1,
    limit       = 50,
  ) {
    const [logs, total] = await this.logRepo.findAndCount({
      where: { entityType, entityId },
      order: { createdAt: 'DESC' },
      skip:  (page - 1) * limit,
      take:  limit,
    });

    return {
      data:  logs,
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
    };
  }

  // ─────────────────────────────────────────────────────
  // STATISTIQUES SUR LES LOGS
  // ─────────────────────────────────────────────────────
  async getStats() {
    const total = await this.logRepo.count();

    // Logs par type d'acteur
    const byActorType = await this.logRepo
      .createQueryBuilder('log')
      .select('log.actorType', 'actorType')
      .addSelect('COUNT(log.id)', 'count')
      .groupBy('log.actorType')
      .getRawMany();

    // Logs par résultat (success / failure)
    const byResult = await this.logRepo
      .createQueryBuilder('log')
      .select('log.result', 'result')
      .addSelect('COUNT(log.id)', 'count')
      .groupBy('log.result')
      .getRawMany();

    // Top 10 des actions les plus fréquentes
    const topActions = await this.logRepo
      .createQueryBuilder('log')
      .select('log.action', 'action')
      .addSelect('COUNT(log.id)', 'count')
      .groupBy('log.action')
      .orderBy('count', 'DESC')
      .limit(10)
      .getRawMany();

    // Logs des dernières 24h
    const last24h = new Date();
    last24h.setHours(last24h.getHours() - 24);
    const recentCount = await this.logRepo.count({
      where: { createdAt: LessThan(new Date()) },
    });

    return {
      total,
      byActorType,
      byResult,
      topActions,
      last24hCount: recentCount,
    };
  }

  // ─────────────────────────────────────────────────────
  // ÉCHECS DE CONNEXION (sécurité)
  // ─────────────────────────────────────────────────────
  async getLoginFailures(page = 1, limit = 50) {
    const [logs, total] = await this.logRepo.findAndCount({
      where: [
        { action: LogAction.USER_LOGIN_FAILED },
        { action: LogAction.ADMIN_LOGIN_FAILED },
      ],
      order: { createdAt: 'DESC' },
      skip:  (page - 1) * limit,
      take:  limit,
    });

    return {
      data:  logs,
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
    };
  }

  // ─────────────────────────────────────────────────────
  // PURGE AUTOMATIQUE — TÂCHE CRON
  // S'exécute tous les jours à minuit
  // Supprime les logs > 1 an
  // ─────────────────────────────────────────────────────
  @Cron(CronExpression.EVERY_DAY_AT_MIDNIGHT)
  async purgeOldLogs() {
    const oneYearAgo = new Date();
    oneYearAgo.setFullYear(oneYearAgo.getFullYear() - 1);

    const result = await this.logRepo.delete({
      createdAt: LessThan(oneYearAgo),
    });

    this.logger.log(
      `Purge automatique : ${result.affected ?? 0} log(s) supprimé(s) `
      + `(plus de 1 an)`
    );

    return result.affected ?? 0;
  }

  // ─────────────────────────────────────────────────────
  // PURGE MANUELLE (admin uniquement)
  // ─────────────────────────────────────────────────────
  async manualPurge(beforeDate: Date) {
    const result = await this.logRepo.delete({
      createdAt: LessThan(beforeDate),
    });

    return {
      message: 'Purge manuelle effectuée',
      deleted: result.affected ?? 0,
    };
  }
}