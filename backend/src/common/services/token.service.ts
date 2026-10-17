import { Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import type { StringValue } from 'ms';

/**
 * Émission et vérification des jetons « utilisateur » (client / vendeur /
 * livreur). Les jetons admin ne passent pas par ici.
 *
 * Deux sortes de jetons, signés avec deux secrets DIFFÉRENTS :
 *  - jeton d'accès      : secret JWT_SECRET,         claim `typ: 'access'`
 *  - jeton de rafraîchissement : secret JWT_REFRESH_SECRET, claim `typ: 'refresh'`
 *
 * Le claim `typ` est la ceinture de sécurité : même si, par erreur, les deux
 * secrets étaient identiques dans le .env, un jeton de rafraîchissement ne
 * peut jamais servir de jeton d'accès (refusé par JwtStrategy) et inversement.
 */
export interface UserTokenPayload {
  sub: string;
  email: string;
  type: 'user';
  typ: 'access' | 'refresh';
  iat?: number;
  exp?: number;
}

@Injectable()
export class TokenService {
  constructor(
    private readonly jwtService: JwtService,
    private readonly configService: ConfigService,
  ) {}

  issueUserTokens(user: { id: string; email: string }): {
    accessToken: string;
    refreshToken: string;
  } {
    const base = { sub: user.id, email: user.email, type: 'user' as const };

    const accessToken = this.jwtService.sign(
      { ...base, typ: 'access' as const },
      {
        secret: this.configService.getOrThrow<string>('JWT_SECRET'),
        expiresIn:
          this.configService.getOrThrow<number | StringValue>('JWT_EXPIRES_IN'),
      },
    );

    const refreshToken = this.jwtService.sign(
      { ...base, typ: 'refresh' as const },
      {
        secret: this.configService.getOrThrow<string>('JWT_REFRESH_SECRET'),
        expiresIn: this.configService.getOrThrow<number | StringValue>(
          'JWT_REFRESH_EXPIRES_IN',
        ),
      },
    );

    return { accessToken, refreshToken };
  }

  /**
   * Vérifie un jeton de rafraîchissement : signature (secret de refresh),
   * expiration, et nature du jeton. Toute erreur → 401 au message neutre.
   */
  verifyRefreshToken(token: string): UserTokenPayload {
    let payload: UserTokenPayload;
    try {
      payload = this.jwtService.verify<UserTokenPayload>(token, {
        secret: this.configService.getOrThrow<string>('JWT_REFRESH_SECRET'),
        algorithms: ['HS256'],
      });
    } catch {
      throw new UnauthorizedException('Session expirée, reconnectez-vous');
    }
    if (
      !payload ||
      payload.typ !== 'refresh' ||
      payload.type !== 'user' ||
      !payload.sub
    ) {
      throw new UnauthorizedException('Session expirée, reconnectez-vous');
    }
    return payload;
  }

  /**
   * Un jeton émis AVANT `tokensValidAfter` est révoqué. `iat` est en secondes :
   * on arrondit aussi la date de révocation à la seconde, pour ne pas refuser
   * un jeton émis dans la même seconde (ex. le nouveau jeton renvoyé juste
   * après un changement de mot de passe). Jeton sans `iat` = refusé.
   */
  static isRevoked(
    iat: number | undefined,
    tokensValidAfter: Date | null | undefined,
  ): boolean {
    if (!tokensValidAfter) return false;
    const issuedAtMs = (iat ?? 0) * 1000;
    const validAfterMs = Math.floor(tokensValidAfter.getTime() / 1000) * 1000;
    return issuedAtMs < validAfterMs;
  }
}
