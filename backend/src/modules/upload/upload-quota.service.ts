import { HttpException, HttpStatus, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

const WINDOW_MS = 60 * 60 * 1000; // 1 heure glissante

/**
 * Quota d'envois de fichiers PAR UTILISATEUR (fenêtre glissante d'1 heure).
 *
 * Pourquoi pas seulement @Throttle : le ThrottlerGuard global s'exécute AVANT
 * l'authentification et ne connaît donc que l'adresse IP (des centaines de
 * clients peuvent partager la même IP mobile). Ici on compte par identifiant
 * de compte, une fois le jeton validé. Un @Throttle par IP reste posé en plus
 * sur le contrôleur (rafale).
 *
 * Valeurs (modifiables dans .env) :
 *  - UPLOAD_MAX_PER_HOUR        : 60 fichiers / heure / utilisateur
 *  - UPLOAD_ADMIN_MAX_PER_HOUR  : 300 fichiers / heure / compte admin
 *
 * ⚠️ Compteur en mémoire du processus : il repart de zéro au redémarrage et
 * n'est pas partagé si plusieurs instances du serveur tournent. C'est un
 * garde-fou contre l'abus, pas un compteur de facturation.
 */
@Injectable()
export class UploadQuotaService {
  private readonly hits = new Map<string, number[]>();
  private readonly userLimit: number;
  private readonly adminLimit: number;

  constructor(config: ConfigService) {
    this.userLimit = this.positiveInt(config.get('UPLOAD_MAX_PER_HOUR'), 60);
    this.adminLimit = this.positiveInt(config.get('UPLOAD_ADMIN_MAX_PER_HOUR'), 300);
  }

  private positiveInt(raw: unknown, fallback: number): number {
    const n = Math.trunc(Number(raw));
    return Number.isFinite(n) && n > 0 ? n : fallback;
  }

  private recent(key: string, now: number): number[] {
    const list = (this.hits.get(key) ?? []).filter((t) => now - t < WINDOW_MS);
    if (list.length) this.hits.set(key, list);
    else this.hits.delete(key);
    return list;
  }

  /** Lève 429 si le quota est atteint ; sinon enregistre `count` envoi(s). */
  consume(key: string, isAdmin: boolean, count = 1): void {
    const now = Date.now();
    const limit = isAdmin ? this.adminLimit : this.userLimit;
    const list = this.recent(key, now);
    if (list.length + count > limit) {
      const oldest = list[0] ?? now;
      const minutes = Math.max(1, Math.ceil((oldest + WINDOW_MS - now) / 60000));
      throw new HttpException(
        `Trop d'envois de fichiers (maximum ${limit} par heure). Réessayez dans ${minutes} minute(s).`,
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
    for (let i = 0; i < count; i++) list.push(now);
    this.hits.set(key, list);

    // Nettoyage occasionnel pour que la table ne grossisse pas indéfiniment.
    if (this.hits.size > 5000) {
      for (const k of [...this.hits.keys()]) this.recent(k, now);
    }
  }
}
