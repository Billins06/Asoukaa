import { Injectable, CanActivate, ExecutionContext } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { Role } from '../../../common/enums/role.enum';
import { AdminRole } from '../entities/admin-account.entity';
import { ROLES_KEY } from '../decorators/roles.decorator';

@Injectable()
export class RolesGuard implements CanActivate {
  // Hiérarchie des rôles : SUPERADMIN > ADMIN > autres rôles
  private readonly roleHierarchy = {
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
    if (!requiredRoles) return true;

    const { user } = context.switchToHttp().getRequest();
    const userRole = user?.role;

    if (!userRole) return false;

    // Vérifier si l'utilisateur a un rôle autorisé
    // Les superadmins peuvent accéder aux routes ADMIN
    return requiredRoles.some(requiredRole => {
      const userLevel = this.roleHierarchy[userRole] || 0;
      const requiredLevel = this.roleHierarchy[requiredRole] || 0;
      return userLevel >= requiredLevel;
    });
  }
}