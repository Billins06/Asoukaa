import {
  Body,
  Controller,
  Headers,
  HttpCode,
  HttpStatus,
  Logger,
  OnModuleInit,
  Post,
  Query,
  Req,
  BadRequestException,
  UnauthorizedException,
} from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { ConfigService } from '@nestjs/config';
import { Throttle } from '@nestjs/throttler';
import { createHash, timingSafeEqual } from 'crypto';
import type { Request } from 'express';

import { PaymentsService } from './payments.service';

// ─────────────────────────────────────────────────────────────────────────
// WEBHOOK FEEXPAY — POST /api/v1/payments/webhook/feexpay
//
// Contrôleur SÉPARÉ de PaymentsController : celui-ci est protégé par
// JwtAuthGuard au niveau du contrôleur ; FeexPay n'a pas de jeton. Seul
// ThrottlerGuard (global) s'applique ici.
//
// ⚠️ On ne sait pas si FeexPay propose un webhook, ni son format ni sa
// signature. Cette route est donc DÉFENSIVE et sans danger si elle n'est
// jamais appelée :
//   - secret facultatif (FEEXPAY_WEBHOOK_SECRET) : s'il est défini, il doit
//     être fourni dans l'en-tête `x-feexpay-secret` ou dans `?token=` ;
//   - corps de forme inconnue : tout objet JSON est accepté ; on y cherche
//     seulement une référence de transaction (plusieurs noms de champs) ;
//   - le statut du corps n'est JAMAIS cru : le service re-interroge FeexPay ;
//   - réponse toujours rapide `200 { received: true }` (référence inconnue ou
//     déjà traitée comprise, pour ne rien révéler), sauf 401 (secret invalide)
//     et 400 (corps qui n'est pas un objet) ;
//   - chaque réception est journalisée (clés + corps tronqué) pour découvrir
//     le vrai format de FeexPay.
// Le rattrapage automatique (PaymentReconciliationService) couvre de toute
// façon les paiements dont le webhook n'arrive jamais.
// ─────────────────────────────────────────────────────────────────────────

const BODY_LOG_MAX_CHARS = 2000;

// Noms de champs possibles pour la référence de transaction (essayés dans
// l'ordre, d'abord à la racine du corps puis dans les sous-objets courants).
const REFERENCE_KEYS = [
  'reference', 'ref', 'trans_id', 'transaction_id', 'transactionId',
  'transaction_ref', 'transactionRef', 'transactionReference', 'id', '_id',
];
const NESTED_KEYS = ['data', 'transaction', 'payload', 'result', 'response'];

// Champs jamais écrits dans les logs (valeur remplacée par [masqué]).
const SENSITIVE_KEY = /secret|token|authorization|password|passwd|pwd|api[_-]?key|cookie/i;

const isPlainObject = (v: unknown): v is Record<string, unknown> =>
  typeof v === 'object' && v !== null && !Array.isArray(v);

@ApiTags('Payments')
@Controller('payments/webhook')
export class PaymentsWebhookController implements OnModuleInit {
  private readonly logger = new Logger(PaymentsWebhookController.name);

  constructor(
    private readonly paymentsService: PaymentsService,
    private readonly configService:   ConfigService,
  ) {}

  onModuleInit() {
    if (!this.getSecret()) {
      this.logger.warn(
        'FEEXPAY_WEBHOOK_SECRET n\'est pas défini : le webhook FeexPay accepte toutes les '
        + 'requêtes (sans danger : le statut est toujours re-vérifié auprès de FeexPay). '
        + 'Recommandé : définir un secret et le mettre dans l\'adresse donnée à FeexPay (?token=...).',
      );
    }
  }

  private getSecret(): string {
    return (this.configService.get<string>('FEEXPAY_WEBHOOK_SECRET') ?? '').trim();
  }

  // Comparaison à temps constant (les deux valeurs sont d'abord hachées pour
  // avoir la même longueur, ce que timingSafeEqual exige).
  private secretMatches(provided: unknown, expected: string): boolean {
    if (typeof provided !== 'string' || provided.length === 0) return false;
    const a = createHash('sha256').update(provided).digest();
    const b = createHash('sha256').update(expected).digest();
    return timingSafeEqual(a, b);
  }

  @ApiOperation({ summary: 'Webhook FeexPay (public, secret facultatif)' })
  // Limite adaptée : un webhook par paiement en temps normal ; assez large
  // pour un pic, assez serrée pour décourager l'abus.
  @Throttle({ default: { limit: 60, ttl: 60_000 } })
  @Post('feexpay')
  @HttpCode(HttpStatus.OK)
  receiveFeexPay(
    @Req() req: Request,
    // Pas de DTO : le type Record fait ignorer la validation globale
    // (forbidNonWhitelisted) pour ce corps de forme inconnue.
    @Body() body: Record<string, unknown>,
    @Headers('x-feexpay-secret') headerSecret?: string,
    @Query('token') queryToken?: unknown,
  ) {
    const ip = req.ip ?? req.socket?.remoteAddress ?? 'unknown';

    // 1. Secret (si configuré)
    const expected = this.getSecret();
    if (expected) {
      const ok =
        this.secretMatches(headerSecret, expected)
        || this.secretMatches(queryToken, expected);
      if (!ok) {
        this.logger.warn(`Webhook FeexPay refusé (secret absent ou invalide) depuis ${ip}`);
        throw new UnauthorizedException();
      }
    }

    // 2. Corps : doit être un objet
    if (!isPlainObject(body)) {
      throw new BadRequestException('Corps invalide');
    }

    // 3. Journal de réception (jamais d'en-têtes d'autorisation ni de secrets)
    this.logger.log(
      `Webhook FeexPay reçu | ip=${ip}`
      + ` | content-type=${String(req.headers['content-type'] ?? '')}`
      + ` | clés=[${this.safeKeysForLog(body)}]`
      + ` | corps=${this.safeBodyForLog(body)}`,
    );

    // 4. Traitement en arrière-plan : on répond tout de suite à FeexPay.
    const refs = this.extractReferences(body);
    void this.paymentsService
      .handleFeexPayWebhook(refs, ip)
      .catch(err =>
        this.logger.error(`Webhook FeexPay : traitement en échec : ${(err as Error)?.message}`),
      );

    return { received: true };
  }

  // Clés du corps pour les logs : le corps vient de l'extérieur, les noms de
  // clés sont donc nettoyés (retours à la ligne / caractères de contrôle
  // supprimés, chaque clé tronquée à 40 caractères, 30 clés au maximum).
  private safeKeysForLog(body: Record<string, unknown>): string {
    const keys = Object.keys(body);
    const cleaned = keys.slice(0, 30).map(k =>
      // eslint-disable-next-line no-control-regex
      k.replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029]/g, '').slice(0, 40),
    );
    return cleaned.join(', ') + (keys.length > 30 ? `, …(+${keys.length - 30})` : '');
  }

  // Corps sérialisé pour les logs : champs sensibles masqués, tronqué à 2000.
  private safeBodyForLog(body: Record<string, unknown>): string {
    try {
      const json = JSON.stringify(body, (key, value: unknown) =>
        key && SENSITIVE_KEY.test(key) ? '[masqué]' : value,
      ) ?? '';
      return json.length > BODY_LOG_MAX_CHARS
        ? `${json.slice(0, BODY_LOG_MAX_CHARS)}…[tronqué]`
        : json;
    } catch {
      return '[corps illisible]';
    }
  }

  // Références candidates (texte ou nombre non vides), sans doublon, 10 max.
  private extractReferences(body: Record<string, unknown>): string[] {
    const containers: Record<string, unknown>[] = [body];
    for (const key of NESTED_KEYS) {
      const nested = body[key];
      if (isPlainObject(nested)) containers.push(nested);
    }

    const found: string[] = [];
    for (const container of containers) {
      for (const key of REFERENCE_KEYS) {
        const value = container[key];
        if (typeof value === 'string' || typeof value === 'number') {
          const text = String(value).trim();
          if (text.length > 0 && text.length <= 255 && !found.includes(text)) {
            found.push(text);
          }
        }
      }
    }
    return found.slice(0, 10);
  }
}
