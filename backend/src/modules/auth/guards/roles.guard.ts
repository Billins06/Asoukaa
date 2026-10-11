import { Injectable, CanActivate, ExecutionContext } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { Role } from '../../../common/enums/role.enum';
import { ROLES_KEY } from '../decorators/roles.decorator';

@Injectable()
export class RolesGuard implements CanActivate {
  // Hiérarchie des rôles : SUPERADMIN > ADMIN > VENDOR/DELIVERY_AGENT > CLIENT
  private readonly roleHierarchy: Record<string, number> = {
    [Role.SUPERADMIN]: 100,
    [Role.ADMIN]: 90,
    [Role.VENDOR]: 50,
    [Role.DELIVERY_AGENT]: 50,
    [Role.CLIENT]: 10,
  };

  constructor(private reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const requiredRoles = this.reflector.getAllAndOverride<Role[]>(ROLES_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (!requiredRoles?.length) return true;

    const { user } = context.switchToHttp().getRequest();
    const userRoles = this.extractRoles(user);

    if (!userRoles.length) return false;

    return requiredRoles.some((requiredRole) => {
      // ⚠️ Comparaison EXACTE pour VENDOR et DELIVERY_AGENT : ils sont au
      // même niveau (50) dans la hiérarchie, donc un `>=` laissait un
      // livreur passer une vérification @Roles(Role.VENDOR) et inversement.
      // La hiérarchie ne doit jouer que pour ADMIN/SUPERADMIN, qui
      // supervisent légitimement les rôles inférieurs.
      if (
        requiredRole === Role.VENDOR ||
        requiredRole === Role.DELIVERY_AGENT
      ) {
        return (
          userRoles.includes(requiredRole) ||
          userRoles.some((r) => this.level(r) >= this.roleHierarchy[Role.ADMIN])
        );
      }

      const requiredLevel = this.level(requiredRole);
      return userRoles.some((r) => this.level(r) >= requiredLevel);
    });
  }

  private level(role: string): number {
    return this.roleHierarchy[role] ?? 0;
  }

  /**
   * Extrait les rôles du principal attaché par JwtStrategy.
   *
   * ⚠️ Deux formes très différentes selon le type de token :
   *  - AdminAccount → un seul rôle scalaire `role` ('admin' | 'superadmin')
   *  - User         → une relation `roles: UserRole[]`, PAS de champ `role`
   *
   * L'ancienne version ne lisait que `user.role` : pour tout token
   * utilisateur elle renvoyait donc toujours false. C'était sans danger
   * (fail-closed) mais rendait impossible toute route @Roles(Role.VENDOR)
   * ou @Roles(Role.DELIVERY_AGENT) — elle aurait refusé tout le monde.
   */
  private extractRoles(user: any): string[] {
    if (!user) return [];

    // Compte admin / superadmin
    if (typeof user.role === 'string') {
      return [user.role];
    }

    // Utilisateur classique : on ne retient que les rôles actifs
    if (Array.isArray(user.roles)) {
      return user.roles
        .filter((r: any) => r?.isActive !== false)
        .map((r: any) => (typeof r === 'string' ? r : r?.role))
        .filter(Boolean);
    }

    return [];
  }
}
