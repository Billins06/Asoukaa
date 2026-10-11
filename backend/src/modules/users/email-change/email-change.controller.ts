import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpException,
  HttpStatus,
  Logger,
  Param,
  Post,
  Req,
  Res,
  ServiceUnavailableException,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import type { Request, Response } from 'express';

import { JwtAuthGuard } from '../../auth/guards/jwt-auth.guard';
import { ConfirmEmailChangeDto } from './dto/confirm-email-change.dto';
import { RequestEmailChangeDto } from './dto/request-email-change.dto';
import { EmailChangeService } from './email-change.service';
import {
  revertConfirmPage,
  revertDonePage,
  revertInvalidPage,
  revertPartialPage,
} from './email-change.pages';

// Limites par IP (le ThrottlerGuard global ne connaît pas encore l'utilisateur
// à ce stade). Les vrais plafonds « par utilisateur » (5 demandes/heure,
// 5 essais par code, 5 envois par demande) sont appliqués en base par
// EmailChangeService ; ceux-ci ne servent qu'à freiner les rafales.
const REQUEST_THROTTLE = { default: { limit: 10, ttl: 3_600_000 } };
const RESEND_THROTTLE  = { default: { limit: 6,  ttl: 3_600_000 } };
const CONFIRM_THROTTLE = { default: { limit: 10, ttl: 60_000 } };
// Routes publiques du lien « Ce n'est pas moi » : le GET est tolérant
// (scanners d'e-mails), le POST est strict.
const REVERT_VIEW_THROTTLE = { default: { limit: 20, ttl: 60_000 } };
const REVERT_POST_THROTTLE = { default: { limit: 5,  ttl: 60_000 } };

const getIp = (req: Request): string =>
  req.ip ?? req.socket?.remoteAddress ?? 'unknown';

const getUserId = (req: Request): string => (req as any).user?.id;

// ─────────────────────────────────────────────────────────────────────────
// Routes authentifiées : /api/v1/users/me/email/*
// ⚠️ Les erreurs métier sont des 400/409/429/503, JAMAIS 401/403 : l'appli
// mobile déconnecte l'utilisateur sur un 401.
// ─────────────────────────────────────────────────────────────────────────
@ApiTags('Users')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('users/me/email')
export class EmailChangeController {
  constructor(private readonly emailChangeService: EmailChangeService) {}

  @ApiOperation({ summary: 'Demander un changement d\'e-mail (code envoyé à la nouvelle adresse)' })
  @Throttle(REQUEST_THROTTLE)
  @Post('request')
  @HttpCode(HttpStatus.OK)
  request(@Req() req: Request, @Body() dto: RequestEmailChangeDto) {
    return this.emailChangeService.requestChange(getUserId(req), dto, getIp(req));
  }

  @ApiOperation({ summary: 'Renvoyer le code de changement d\'e-mail' })
  @Throttle(RESEND_THROTTLE)
  @Post('resend')
  @HttpCode(HttpStatus.OK)
  resend(@Req() req: Request) {
    return this.emailChangeService.resendCode(getUserId(req));
  }

  @ApiOperation({ summary: 'Confirmer le changement d\'e-mail avec le code reçu' })
  @Throttle(CONFIRM_THROTTLE)
  @Post('confirm')
  @HttpCode(HttpStatus.OK)
  confirm(@Req() req: Request, @Body() dto: ConfirmEmailChangeDto) {
    return this.emailChangeService.confirmChange(getUserId(req), dto, getIp(req));
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Routes PUBLIQUES : lien « Ce n'est pas moi » reçu par e-mail.
// - GET  : affiche une page, n'exécute RIEN (les scanners de liens d'e-mail
//          ouvrent les URL automatiquement) ;
// - POST : le bouton de la page ; c'est lui qui annule vraiment.
// ─────────────────────────────────────────────────────────────────────────
@ApiTags('Auth')
@Controller('auth/email-change')
export class EmailChangeRevertController {
  private readonly logger = new Logger(EmailChangeRevertController.name);

  constructor(private readonly emailChangeService: EmailChangeService) {}

  @ApiOperation({ summary: 'Page de confirmation « Ce n\'est pas moi » (lecture seule)' })
  @Throttle(REVERT_VIEW_THROTTLE)
  @Get('revert/:token')
  async showRevertPage(
    @Param('token') token: string,
    @Res({ passthrough: true }) res: Response,
  ): Promise<string> {
    this.setHtmlHeaders(res);
    const state = await this.guard(() =>
      this.emailChangeService.inspectRevertToken(token),
    );
    if (!state.valid) {
      res.status(HttpStatus.NOT_FOUND);
      return revertInvalidPage();
    }
    res.status(HttpStatus.OK);
    return revertConfirmPage(state.maskedNewEmail);
  }

  @ApiOperation({ summary: 'Annuler le changement d\'e-mail et sécuriser le compte' })
  @Throttle(REVERT_POST_THROTTLE)
  @Post('revert/:token')
  async executeRevert(
    @Req() req: Request,
    @Param('token') token: string,
    @Res({ passthrough: true }) res: Response,
  ): Promise<string> {
    this.setHtmlHeaders(res);
    const result = await this.guard(() =>
      this.emailChangeService.executeRevert(token, getIp(req)),
    );
    if (result.outcome === 'invalid') {
      res.status(HttpStatus.NOT_FOUND);
      return revertInvalidPage();
    }
    res.status(HttpStatus.OK);
    return result.outcome === 'restored' ? revertDonePage() : revertPartialPage();
  }

  // ⚠️ Le jeton est dans l'URL, et AllExceptionsFilter journalise
  // « méthode + URL » de toute erreur inattendue (500) : le jeton, encore
  // valable, finirait en clair dans les logs. On intercepte donc ici les
  // erreurs non prévues et on les journalise SANS l'URL.
  private async guard<T>(action: () => Promise<T>): Promise<T> {
    try {
      return await action();
    } catch (error) {
      if (error instanceof HttpException) throw error;
      this.logger.error(
        `Erreur inattendue sur le lien d'annulation d'e-mail : ${(error as Error)?.message}`,
      );
      throw new ServiceUnavailableException(
        'Service momentanément indisponible, réessayez dans un instant.',
      );
    }
  }

  // Le jeton est dans l'URL : pas de cache, pas de Referer, pas d'indexation.
  private setHtmlHeaders(res: Response): void {
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('X-Robots-Tag', 'noindex, nofollow');
  }
}
