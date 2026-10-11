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
import type { DeliveryEarningFilters } from './delivery-earnings.service';
import { DeliveryEarningsService } from './delivery-earnings.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { Role } from '../../common/enums/role.enum';

const getIp = (req: Request): string =>
  (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim() ??
  req.socket?.remoteAddress ??
  'unknown';

// Pendant de admin/commissions (payments/commissions/commissions.controller.ts)
// côté livreur : mêmes routes, même forme.
@ApiTags('Admin - Gains livreurs')
@ApiBearerAuth()
@Controller('admin/delivery-earnings')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(Role.SUPERADMIN, Role.ADMIN)
export class DeliveryEarningsController {
  constructor(private deliveryEarningsService: DeliveryEarningsService) {}

  @ApiOperation({ summary: 'Lister tous les gains livreurs' })
  @Get()
  @HttpCode(HttpStatus.OK)
  async getAll(@Query() filters: DeliveryEarningFilters) {
    return this.deliveryEarningsService.getAll(filters);
  }

  @ApiOperation({ summary: 'Statistiques des gains livreurs' })
  @Get('stats/overview')
  @HttpCode(HttpStatus.OK)
  async getStatistics() {
    return this.deliveryEarningsService.getStatistics();
  }

  @ApiOperation({ summary: 'Récupérer un gain livreur par ID' })
  @Get(':id')
  @HttpCode(HttpStatus.OK)
  async getById(@Param('id') id: string) {
    return this.deliveryEarningsService.getById(id);
  }

  @ApiOperation({ summary: 'Marquer un gain livreur comme payé (virement effectué)' })
  @Post(':id/mark-paid')
  @HttpCode(HttpStatus.OK)
  async markAsPaid(@Param('id') id: string, @Req() req: Request) {
    const adminId = (req as any).user?.id;
    const ip = getIp(req);
    return this.deliveryEarningsService.markAsPaid(id, adminId, ip);
  }
}
