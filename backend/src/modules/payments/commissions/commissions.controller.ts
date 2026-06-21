import {
  Controller,
  Get,
  Post,
  Param,
  Query,
  Req,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { ApiTags, ApiBearerAuth, ApiOperation } from '@nestjs/swagger';
import type { Request } from 'express';
import type { CommissionFilters } from './commissions.service';
import { CommissionsService } from './commissions.service';
import { JwtAuthGuard } from 'src/modules/auth/guards/jwt-auth.guard';
import { RolesGuard } from 'src/modules/auth/guards/roles.guard';
import { Roles } from 'src/modules/auth/decorators/roles.decorator';
import { Role } from 'src/common/enums/role.enum';

const getIp = (req: Request): string =>
  (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim() ??
  req.socket?.remoteAddress ??
  'unknown';

@ApiTags('Admin - Commissions')
@ApiBearerAuth()
@Controller('admin/commissions')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(Role.SUPERADMIN, Role.ADMIN)
export class CommissionsController {
  constructor(private commissionsService: CommissionsService) {}

  @ApiOperation({ summary: 'Lister toutes les commissions' })
  @Get()
  @HttpCode(HttpStatus.OK)
  async getAll(@Query() filters: CommissionFilters) {
    return this.commissionsService.getAll(filters);
  }

  @ApiOperation({ summary: 'Récupérer une commission par ID' })
  @Get(':id')
  @HttpCode(HttpStatus.OK)
  async getById(@Param('id') id: string) {
    return this.commissionsService.getById(id);
  }

  @ApiOperation({ summary: 'Obtenir les statistiques des commissions' })
  @Get('stats/overview')
  @HttpCode(HttpStatus.OK)
  async getStatistics() {
    return this.commissionsService.getStatistics();
  }

  @ApiOperation({ summary: 'Marquer une commission comme payée' })
  @Post(':id/mark-paid')
  @HttpCode(HttpStatus.OK)
  async markAsPaid(@Param('id') id: string, @Req() req: Request) {
    const adminId = (req as any).user?.id;
    const ip = getIp(req);
    return this.commissionsService.markAsPaid(id, adminId, ip);
  }
}
