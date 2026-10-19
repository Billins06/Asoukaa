import {
  Controller, Get, Post, Body, Param, Query, Req, UseGuards,
  ParseUUIDPipe, BadRequestException, HttpCode, HttpStatus,
} from '@nestjs/common';
import { ApiTags, ApiBearerAuth, ApiOperation } from '@nestjs/swagger';
import type { Request } from 'express';

import { AdminIndependentDeliveriesService } from './admin-independent-deliveries.service';
import {
  AdminResolvePaymentDto,
  AdminCancelIndependentDeliveryDto,
  AdminMarkRefundedDto,
} from './dto/admin-independent-delivery.dto';
import { IndependentDeliveryStatus } from './entities/independent-delivery.entity';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { Role } from '../../common/enums/role.enum';
import { clampLimit, clampPage } from '../../common/utils/pagination.util';

const getIp = (req: Request) =>
  (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim()
  ?? req.socket?.remoteAddress ?? 'unknown';
const adminId = (req: Request): string => (req as any).user?.id;

const PAYMENT_STATUSES = ['en attente', 'success', 'échoué', 'à vérifier', 'none'];
const REFUND_STATUSES  = ['à rembourser', 'remboursé'];

@ApiTags('Admin Courses express')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(Role.ADMIN)
@Controller('admin/independent-deliveries')
export class AdminIndependentDeliveriesController {
  constructor(private readonly admin: AdminIndependentDeliveriesService) {}

  @ApiOperation({ summary: '[ADMIN] Liste des courses express' })
  @Get()
  list(
    @Query('page')          page?: string,
    @Query('limit')         limit?: string,
    @Query('search')        search?: string,
    @Query('status')        status?: string,
    @Query('paymentStatus') paymentStatus?: string,
    @Query('refundStatus')  refundStatus?: string,
    @Query('attention')     attention?: string,
  ) {
    // Un paramètre répété (?search=a&search=b) arrive sous forme de tableau.
    for (const v of [search, status, paymentStatus, refundStatus, attention, page, limit]) {
      if (v !== undefined && typeof v !== 'string') throw new BadRequestException('Paramètre invalide');
    }
    if (status && !Object.values(IndependentDeliveryStatus).includes(status as IndependentDeliveryStatus)) {
      throw new BadRequestException('Statut invalide');
    }
    if (paymentStatus && !PAYMENT_STATUSES.includes(paymentStatus)) {
      throw new BadRequestException('Statut de paiement invalide');
    }
    if (refundStatus && !REFUND_STATUSES.includes(refundStatus)) {
      throw new BadRequestException('Statut de remboursement invalide');
    }
    return this.admin.list({
      search:        search?.trim() ? search.trim().slice(0, 100) : undefined,
      status:        status as IndependentDeliveryStatus | undefined,
      paymentStatus,
      refundStatus,
      attention:     attention === 'true',
      page:          clampPage(page),
      limit:         clampLimit(limit, 20),
    });
  }

  @ApiOperation({ summary: '[ADMIN] Détail d\'une course express' })
  @Get(':id')
  getOne(@Param('id', ParseUUIDPipe) id: string) {
    return this.admin.getOne(id);
  }

  @ApiOperation({ summary: '[ADMIN] Trancher un paiement « à vérifier »' })
  @Post(':id/resolve-payment')
  @HttpCode(HttpStatus.OK)
  resolvePayment(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: AdminResolvePaymentDto,
    @Req() req: Request,
  ) {
    return this.admin.resolvePayment(id, dto.outcome, dto.note, adminId(req), getIp(req));
  }

  @ApiOperation({ summary: '[ADMIN] Annuler une course (remboursement à faire si payée)' })
  @Post(':id/cancel')
  @HttpCode(HttpStatus.OK)
  cancel(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: AdminCancelIndependentDeliveryDto,
    @Req() req: Request,
  ) {
    return this.admin.cancel(id, dto.reason, adminId(req), getIp(req));
  }

  @ApiOperation({ summary: '[ADMIN] Marquer le remboursement comme effectué' })
  @Post(':id/mark-refunded')
  @HttpCode(HttpStatus.OK)
  markRefunded(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: AdminMarkRefundedDto,
    @Req() req: Request,
  ) {
    return this.admin.markRefunded(id, dto.note, adminId(req), getIp(req));
  }
}
