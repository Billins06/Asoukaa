import { Injectable, UnauthorizedException } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { UsersService } from '../../users/users.service';
import { AdminAccount } from '../entities/admin-account.entity';
import { TokenService } from '../../../common/services/token.service';

interface JwtPayload {
  sub: string;
  email: string;
  type?: 'user' | 'admin';
  // Nature du jeton : 'access' (ou absent, anciens jetons) / 'refresh'.
  typ?: 'access' | 'refresh';
  role?: string;
  // « issued at » (secondes) : ajouté automatiquement par jsonwebtoken
  iat?: number;
}

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(
    private configService: ConfigService,
    private usersService: UsersService,
    @InjectRepository(AdminAccount)
    private adminRepo: Repository<AdminAccount>,
  ) {
    const secret = configService.get<string>('JWT_SECRET');
    if (!secret) {
      throw new Error('JWT_SECRET est manquant dans le fichier .env');
    }

    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: secret,
    });
  }

  async validate(payload: JwtPayload) {
    // Un jeton de rafraîchissement ne donne JAMAIS accès à l'API : il ne sert
    // qu'à POST /auth/refresh (même si, par erreur de configuration, les deux
    // secrets étaient identiques).
    if (payload.typ === 'refresh') {
      throw new UnauthorizedException('Jeton invalide');
    }

    // Token admin/superadmin
    if (payload.type === 'admin') {
      const admin = await this.adminRepo.findOne({ where: { id: payload.sub } });
      if (!admin) {
        throw new UnauthorizedException('Admin introuvable');
      }
      if (!admin.isActive) {
        throw new UnauthorizedException('Admin désactivé');
      }
      return admin; // sera disponible sur req.user
    }

    // Token utilisateur classique (client/vendor/livreur)
    const user = await this.usersService.findById(payload.sub);
    if (!user) {
      throw new UnauthorizedException('Utilisateur introuvable');
    }

    // Compte bloqué (admin, ou précaution après un « Ce n'est pas moi ») :
    // le jeton, pourtant encore valide, ne donne plus aucun accès. Sans cette
    // ligne, un utilisateur bloqué gardait toute sa session jusqu'à
    // l'expiration du jeton (seul le login contrôlait isActive).
    if (!user.isActive) {
      throw new UnauthorizedException('Compte bloqué');
    }

    // Révocation globale : après un « Ce n'est pas moi » sur un changement
    // d'e-mail, tous les jetons émis avant `tokensValidAfter` sont refusés
    // (le jeton garde sa validité cryptographique, c'est nous qui le
    // refusons). Un jeton sans `iat` est refusé par prudence.
    // (Comparaison arrondie à la seconde : voir TokenService.isRevoked.)
    if (TokenService.isRevoked(payload.iat, user.tokensValidAfter)) {
      throw new UnauthorizedException('Session expirée, reconnectez-vous');
    }
    return user;
  }
}