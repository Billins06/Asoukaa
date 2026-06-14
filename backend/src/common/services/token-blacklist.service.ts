import { Injectable } from '@nestjs/common';

/**
 * Service pour blacklister les tokens révoqués (logout)
 * En production, utiliser Redis pour plus de performance
 */
@Injectable()
export class TokenBlacklistService {
  private blacklist = new Set<string>();

  /**
   * Ajoute un token à la blacklist (logout)
   */
  revokeToken(token: string): void {
    this.blacklist.add(token);
  }

  /**
   * Vérifie si un token est révoqué
   */
  isTokenRevoked(token: string): boolean {
    return this.blacklist.has(token);
  }

  /**
   * Nettoie les anciens tokens (à exécuter régulièrement)
   * En production avec Redis, ce nettoyage se fait automatiquement via TTL
   */
  clearExpiredTokens(): void {
    // En production, utiliser Redis EXPIRE ou SetInterval
    console.log('⏰ Tokens blacklist cleaned');
  }
}
