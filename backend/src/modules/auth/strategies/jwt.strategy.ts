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
    return user;
  }
}