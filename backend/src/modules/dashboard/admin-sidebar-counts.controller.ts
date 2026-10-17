import {
  Controller,
  Get,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import {
  ApiTags,
  ApiBearerAuth,
  ApiOperation,
} from '@nestjs/swagger';

import { DashboardService } from './dashboard.service';
import { JwtAuthGuard }     from '../auth/guards/jwt-auth.guard';
import { RolesGuard }       from '../auth/guards/roles.guard';
import { Roles }            from '../auth/decorators/roles.decorator';
import { Role }             from '../../common/enums/role.enum';

// Compteurs (pastilles) du menu latéral du site admin.
// GET /api/v1/admin/sidebar-counts — admin et superadmin uniquement.
@ApiTags('Admin - Compteurs du menu')
@ApiBearerAuth()
@Controller('admin')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(Role.SUPERADMIN, Role.ADMIN)
export class AdminSidebarCountsController {
  constructor(private readonly dashboardService: DashboardService) {}

  @ApiOperation({
    summary:
      'Nombre d\'éléments à traiter par section (vendeurs, livreurs, tickets, remboursements, commandes à confirmer, alertes de sécurité, paiements reçus à examiner)',
  })
  @Get('sidebar-counts')
  @HttpCode(HttpStatus.OK)
  getSidebarCounts() {
    return this.dashboardService.getSidebarCounts();
  }
}
