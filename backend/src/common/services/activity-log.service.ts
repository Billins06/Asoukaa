import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import {
  ActivityLog,
  ActorType,
  LogAction,
  LogResult,
} from '../entities/activity-log.entity';

interface LogParams {
  actorId?:    string;
  actorType:   ActorType;
  action:      LogAction;
  entityType?: string;
  entityId?:   string;
  oldValue?:   Record<string, any>;
  newValue?:   Record<string, any>;
  ipAddress?:  string;
  result?:     LogResult;
  errorMessage?: string;
}

@Injectable()
export class ActivityLogService {
  constructor(
    @InjectRepository(ActivityLog)
    private readonly logRepo: Repository<ActivityLog>,
  ) {}

  async log(params: LogParams): Promise<void> {
    try {
      const entry = this.logRepo.create({
        actorId:      params.actorId,
        actorType:    params.actorType,
        action:       params.action,
        entityType:   params.entityType,
        entityId:     params.entityId,
        oldValue:     params.oldValue,
        newValue:     params.newValue,
        ipAddress:    params.ipAddress,
        result:       params.result ?? LogResult.SUCCESS,
        errorMessage: params.errorMessage,
      });
      await this.logRepo.save(entry);
    } catch {
      // ⚠️ On ne bloque jamais l'app si le log échoue
      // On log juste dans la console
      console.error('ActivityLog save failed');
    }
  }
}