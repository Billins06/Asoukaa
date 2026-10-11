import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';

/**
 * Service pour blacklister les tokens révoqués (logout).
 *
 * ⚠️ Chaque entrée porte sa propre date d'expiration (celle du JWT) :
 * sans ça, le Set grossissait indéfiniment — une fuite mémoire lente
 * mais certaine sur un serveur qui tourne des semaines.
 *
 * ⚠️ LIMITE CONNUE : ce stockage est en mémoire, donc local au process.
 * Avec plusieurs instances (PM2 cluster, plusieurs conteneurs), un logout
 * sur l'instance A ne révoque pas le token sur l'instance B, et un
 * redémarrage vide la liste. Pour une vraie révocation multi-instance,
 * remplacer la Map par Redis (SET <jti> avec EXPIRE = durée de vie du
 * token) — l'interface publique de ce service ne change pas.
 */
@Injectable()
export class TokenBlacklistService {
  private readonly logger = new Logger(TokenBlacklistService.name);

  /** token → timestamp (ms) d'expiration du JWT */
  private blacklist = new Map<string, number>();

  /**
   * Ajoute un token à la blacklist (logout).
   * `expiresAt` = claim `exp` du JWT, en millisecondes. Si absent, on
   * retient le token 24 h par défaut (borne haute raisonnable).
   */
  revokeToken(token: string, expiresAt?: number): void {
    this.blacklist.set(
      token,
      expiresAt ?? Date.now() + 24 * 60 * 60 * 1000,
    );
  }

  /**
   * Vérifie si un token est révoqué.
   * Un token dont le JWT a de toute façon expiré est retiré au passage.
   */
  isTokenRevoked(token: string): boolean {
    const expiresAt = this.blacklist.get(token);
    if (expiresAt === undefined) return false;

    if (expiresAt <= Date.now()) {
      this.blacklist.delete(token);
      return false;
    }

    return true;
  }

  /**
   * Purge horaire des tokens déjà expirés naturellement : une fois passée
   * la date d'expiration du JWT, le garder en blacklist ne sert plus à rien.
   */
  @Cron(CronExpression.EVERY_HOUR)
  clearExpiredTokens(): void {
    const now = Date.now();
    let removed = 0;

    for (const [token, expiresAt] of this.blacklist) {
      if (expiresAt <= now) {
        this.blacklist.delete(token);
        removed++;
      }
    }

    if (removed > 0) {
      this.logger.log(
        `Blacklist purgée : ${removed} token(s) expiré(s) retiré(s), `
        + `${this.blacklist.size} restant(s)`,
      );
    }
  }
}
