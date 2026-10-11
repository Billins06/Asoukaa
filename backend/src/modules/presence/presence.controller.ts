import {
  Controller,
  Post,
  Req,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { ApiTags, ApiBearerAuth, ApiOperation } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { createHash } from 'crypto';
import type { Request } from 'express';

import { PresenceService } from './presence.service';
import { JwtAuthGuard }    from '../auth/guards/jwt-auth.guard';

const getUser = (req: Request): any => (req as any).user;

// Limite ≈ 6 pings / minute / utilisateur.
// Le ThrottlerGuard global s'exécute AVANT JwtAuthGuard : req.user n'existe
// pas encore, et la clé par défaut est l'IP (plusieurs utilisateurs derrière
// le même réseau mobile se partageraient le quota). On identifie donc
// l'appelant par l'empreinte de son jeton : un utilisateur = son jeton.
// ⚠️ Seul un en-tête de forme « Bearer xxx.yyy.zzz » (JWT à trois segments)
// est haché ; sinon (absent, malformé, jeton bidon) on retombe sur l'IP, afin
// qu'on ne puisse pas contourner la limite en variant l'en-tête Authorization.
const BEARER_JWT = /^Bearer\s+[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/;
const trackByToken = (req: Record<string, any>): string => {
  const auth = String(req?.headers?.authorization ?? '').trim();
  if (!BEARER_JWT.test(auth)) return `ip:${req?.ip ?? 'inconnue'}`;
  return `tok:${createHash('sha256').update(auth).digest('hex').slice(0, 32)}`;
};

const PING_THROTTLE = {
  default: {
    limit: 6,
    ttl: 60_000,
    getTracker: trackByToken,
  },
};

@ApiTags('Présence')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('presence')
export class PresenceController {
  constructor(private readonly presenceService: PresenceService) {}

  @ApiOperation({ summary: 'Signaler que je suis actif (présence « En ligne »)' })
  @Post('ping')
  @HttpCode(HttpStatus.OK)
  @Throttle(PING_THROTTLE)
  async ping(@Req() req: Request) {
    await this.presenceService.ping(getUser(req).id);
    return { ok: true };
  }
}
