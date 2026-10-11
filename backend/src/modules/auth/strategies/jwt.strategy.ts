import { Injectable, UnauthorizedException } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { UsersService } from '../../users/users.service';
import { AdminAccount } from '../entities/admin-account.entity';

interface JwtPayload {
  sub: string;
  email: string;
  type?: 'user' | 'admin';
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
    if (user.tokensValidAfter) {
      const issuedAtMs = (payload.iat ?? 0) * 1000;
      // `iat` est arrondi à la seconde : on arrondit aussi la date de
      // révocation, pour ne pas refuser un jeton émis dans la même seconde
      // (nouvelle connexion juste après un déblocage, par exemple).
      const validAfterMs =
        Math.floor(user.tokensValidAfter.getTime() / 1000) * 1000;
      if (issuedAtMs < validAfterMs) {
        throw new UnauthorizedException('Session expirée, reconnectez-vous');
      }
    }
    return user;
  }
}