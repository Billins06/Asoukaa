import {
  Controller,
  Get,
  Query,
  Req,
  UseGuards,
} from '@nestjs/common';
import {
  ApiTags,
  ApiBearerAuth,
  ApiOperation,
} from '@nestjs/swagger';
import type { Request } from 'express';

import { DashboardService }    from './dashboard.service';
import { DashboardQueryDto }   from './dto/dashboard-query.dto';
import { JwtAuthGuard }        from '../auth/guards/jwt-auth.guard';
import { RolesGuard }          from '../auth/guards/roles.guard';
import { Roles }               from '../auth/decorators/roles.decorator';
import { Role }                from '../../common/enums/role.enum';

const getUser = (req: Request): any => (req as any).user;

@ApiTags('Dashboard')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('dashboard')
export class DashboardController {
  constructor(private readonly dashboardService: DashboardService) {}

  // ─── Routes Admin ─────────────────────────────────────

  @ApiOperation({ summary: '[ADMIN] Vue d\'ensemble de la plateforme' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @Get('admin/overview')
  getAdminOverview(@Query() query: DashboardQueryDto) {
    return this.dashboardService.getAdminOverview(query);
  }

  @ApiOperation({ summary: '[ADMIN] Revenus par jour (graphique)' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @Get('admin/revenue-chart')
  getAdminRevenueChart(@Query() query: DashboardQueryDto) {
    return this.dashboardService.getAdminRevenueChart(query);
  }

  @ApiOperation({ summary: '[ADMIN] Top produits les plus vendus' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @Get('admin/top-products')
  getAdminTopProducts(
    @Query() query: DashboardQueryDto,
    @Query('limit') limit?: number,
  ) {
    return this.dashboardService.getAdminTopProducts(
      query,
      Number(limit) || 10,
    );
  }

  @ApiOperation({ summary: '[ADMIN] Top vendeurs' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @Get('admin/top-vendors')
  getAdminTopVendors(
    @Query() query: DashboardQueryDto,
    @Query('limit') limit?: number,
  ) {
    return this.dashboardService.getAdminTopVendors(
      query,
      Number(limit) || 10,
    );
  }

  // ─── Routes Vendeur ───────────────────────────────────

  @ApiOperation({ summary: 'Vue d\'ensemble de ma boutique' })
  @Get('vendor/overview')
  getVendorOverview(
    @Req() req: Request,
    @Query() query: DashboardQueryDto,
  ) {
    return this.dashboardService.getVendorOverview(getUser(req).id, query);
  }

  @ApiOperation({ summary: 'Revenus par jour de ma boutique' })
  @Get('vendor/revenue-chart')
  getVendorRevenueChart(
    @Req() req: Request,
    @Query() query: DashboardQueryDto,
  ) {
    return this.dashboardService.getVendorRevenueChart(
      getUser(req).id,
      query,
    );
  }

  @ApiOperation({ summary: 'Mes produits les plus vendus' })
  @Get('vendor/top-products')
  getVendorTopProducts(
    @Req() req: Request,
    @Query() query: DashboardQueryDto,
    @Query('limit') limit?: number,
  ) {
    return this.dashboardService.getVendorTopProducts(
      getUser(req).id,
      query,
      Number(limit) || 10,
    );
  }
}