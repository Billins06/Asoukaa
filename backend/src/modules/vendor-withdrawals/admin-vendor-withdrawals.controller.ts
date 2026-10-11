import {
  Controller,
  Get,
  Post,
  Patch,
  Body,
  Param,
  Query,
  Req,
  UseGuards,
  ParseUUIDPipe,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import {
  ApiTags,
  ApiBearerAuth,
  ApiOperation,
  ApiQuery,
} from '@nestjs/swagger';
import type { Request } from 'express';
import type { VendorWithdrawalFilters } from './vendor-withdrawals.service';
import { VendorWithdrawalsService } from './vendor-withdrawals.service';
import { VendorWithdrawalStatus } from './entities/vendor-withdrawal.entity';
import { MarkWithdrawalPaidDto } from './dto/mark-withdrawal-paid.dto';
import { RejectWithdrawalDto } from './dto/reject-withdrawal.dto';
import { SetMinWithdrawalDto } from './dto/set-min-withdrawal.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { Role } from '../../common/enums/role.enum';

const getIp = (req: Request): string =>
  (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim() ??
  req.socket?.remoteAddress ??
  'unknown';

// Pendant de admin/delivery-earnings (delivery-earnings.controller.ts) cote
// vendeur : memes routes, meme forme, memes gardes.
//
// ⚠️ "Marquer comme payé" n'envoie AUCUN argent : l'admin fait le virement
// Mobile Money par ses propres moyens, cette route ne fait qu'enregistrer
// la confirmation.
@ApiTags('Admin - Retraits vendeurs')
@ApiBearerAuth()
@Controller('admin/vendor-withdrawals')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(Role.SUPERADMIN, Role.ADMIN)
export class AdminVendorWithdrawalsController {
  constructor(
    private readonly withdrawalsService: VendorWithdrawalsService,
  ) {}

  @ApiOperation({ summary: 'Lister toutes les demandes de retrait' })
  @ApiQuery({ name: 'status',   required: false, enum: VendorWithdrawalStatus })
  @ApiQuery({ name: 'vendorId', required: false })
  @ApiQuery({ name: 'page',     required: false })
  @ApiQuery({ name: 'limit',    required: false })
  @Get()
  @HttpCode(HttpStatus.OK)
  getAll(@Query() filters: VendorWithdrawalFilters) {
    return this.withdrawalsService.getAll(filters);
  }

  // ⚠️ Route statique declaree AVANT ':id' (NestJS resout dans l'ordre
  // de declaration).
  @ApiOperation({ summary: 'Statistiques des retraits vendeurs' })
  @Get('stats/overview')
  @HttpCode(HttpStatus.OK)
  getStatistics() {
    return this.withdrawalsService.getStatistics();
  }

  @ApiOperation({ summary: 'Détail d\'une demande de retrait' })
  @Get(':id')
  @HttpCode(HttpStatus.OK)
  getById(@Param('id', ParseUUIDPipe) id: string) {
    return this.withdrawalsService.getById(id);
  }

  @ApiOperation({
    summary: 'Marquer une demande comme payée (virement Mobile Money déjà effectué)',
  })
  @Post(':id/mark-paid')
  @HttpCode(HttpStatus.OK)
  markAsPaid(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: MarkWithdrawalPaidDto,
    @Req() req: Request,
  ) {
    return this.withdrawalsService.markAsPaid(
      id,
      dto,
      (req as any).user?.id,
      getIp(req),
    );
  }

  @ApiOperation({ summary: 'Rejeter une demande de retrait (motif obligatoire)' })
  @Post(':id/reject')
  @HttpCode(HttpStatus.OK)
  reject(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: RejectWithdrawalDto,
    @Req() req: Request,
  ) {
    return this.withdrawalsService.reject(
      id,
      dto,
      (req as any).user?.id,
      getIp(req),
    );
  }

  @ApiOperation({
    summary: 'Fixer le montant minimum de retrait d\'un vendeur (0 = aucun minimum)',
  })
  @Patch('vendors/:vendorId/min-amount')
  @HttpCode(HttpStatus.OK)
  setMinWithdrawalAmount(
    @Param('vendorId', ParseUUIDPipe) vendorId: string,
    @Body() dto: SetMinWithdrawalDto,
    @Req() req: Request,
  ) {
    return this.withdrawalsService.setMinWithdrawalAmount(
      vendorId,
      dto.minWithdrawalAmount,
      (req as any).user?.id,
      getIp(req),
    );
  }
}
