import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';

import { User } from '../users/entities/user.entity';

// Écriture espacée : si la dernière activité enregistrée date de moins de
// 20 secondes, le ping ne touche pas la base.
export const PING_MIN_INTERVAL_MS = 20_000;

@Injectable()
export class PresenceService {
  constructor(
    @InjectRepository(User)
    private readonly userRepo: Repository<User>,
  ) {}

  // Met à jour users.lastSeenAt en UNE requête atomique, seulement si la
  // valeur précédente est absente ou vieille de plus de 20 s (pas de lecture
  // préalable, pas d'écriture inutile).
  // ⚠️ Requête SQL directe et non repo.update() : un UPDATE TypeORM
  // rafraîchirait aussi users.updatedAt à chaque ping (toutes les 20 s).
  // Un jeton admin n'a pas de ligne dans "users" : l'UPDATE ne touche alors
  // aucune ligne, sans erreur.
  async ping(userId: string): Promise<void> {
    const now = new Date();
    const threshold = new Date(now.getTime() - PING_MIN_INTERVAL_MS);
    await this.userRepo.query(
      `UPDATE "users" SET "lastSeenAt" = $1
       WHERE "id" = $2 AND ("lastSeenAt" IS NULL OR "lastSeenAt" < $3)`,
      [now, userId, threshold],
    );
  }
}
