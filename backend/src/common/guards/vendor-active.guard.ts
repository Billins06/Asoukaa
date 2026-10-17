import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';

import {
  VendorProfile,
  VendorStatus,
} from '../../modules/users/entities/vendor-profile.entity';

// ─────────────────────────────────────────────────────────────────────────
// Garde « vendeur actif » : refuse (403, message en français) toute action
// d'écriture d'un vendeur dont la boutique n'est PAS au statut « approuvé »
// (bloqué, rejeté, en attente...).
//
// Avant, seul le rôle était testé : un vendeur bloqué gardait l'accès à la
// modification de ses produits, au changement de statut de ses commandes et
// aux preuves de livraison. Ici, la fiche vendeur est relue en base à chaque
// appel (par userId) : un blocage prend effet immédiatement, sans attendre
// l'expiration du jeton.
//
// À placer APRÈS JwtAuthGuard :  @UseGuards(JwtAuthGuard, VendorActiveGuard)
// Le module qui l'utilise doit fournir le dépôt VendorProfile
// (TypeOrmModule.forFeature([VendorProfile])).
// ─────────────────────────────────────────────────────────────────────────
@Injectable()
export class VendorActiveGuard implements CanActivate {
  constructor(
    @InjectRepository(VendorProfile)
    private readonly vendorRepo: Repository<VendorProfile>,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const req  = context.switchToHttp().getRequest();
    const user = req?.user;

    if (!user?.id) {
      throw new ForbiddenException('Accès refusé.');
    }

    const vendor = await this.vendorRepo.findOne({
      where:  { userId: user.id },
      select: ['id', 'status'],
    });

    if (!vendor) {
      throw new ForbiddenException('Profil vendeur introuvable.');
    }

    if (vendor.status !== VendorStatus.APPROVED) {
      throw new ForbiddenException(
        'Votre boutique n\'est pas active (en attente, rejetée ou bloquée) : '
        + 'cette action est impossible. Contactez le support.',
      );
    }

    return true;
  }
}
