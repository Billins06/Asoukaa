import {
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import type { Request } from 'express';
import { TokenBlacklistService } from '../../../common/services/token-blacklist.service';

/**
 * Guard JWT + vérification de révocation.
 *
 * ⚠️ Auparavant ce guard était un `AuthGuard('jwt')` nu : la blacklist
 * alimentée par POST /auth/logout n'était JAMAIS consultée, donc un token
 * « déconnecté » restait parfaitement valide jusqu'à son expiration.
 */
@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {
  constructor(private readonly tokenBlacklist: TokenBlacklistService) {
    super();
  }

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const req = context.switchToHttp().getRequest<Request>();
    const authHeader = req.headers.authorization;

    if (authHeader?.startsWith('Bearer ')) {
      const token = authHeader.substring(7);
      if (this.tokenBlacklist.isTokenRevoked(token)) {
        throw new UnauthorizedException('Session expiree, reconnectez-vous');
      }
    }

    return (await super.canActivate(context)) as boolean;
  }
}
