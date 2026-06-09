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

import { PaymentsService }    from './payments.service';
import { InitiatePaymentDto } from './dto/initiate-payment.dto';
import { RequestRefundDto }   from './dto/request-refund.dto';
import { PaymentStatus }      from './entities/payment.entity';
import { RefundStatus }       from './entities/refund.entity';
import { JwtAuthGuard }       from '../auth/guards/jwt-auth.guard';
import { RolesGuard }         from '../auth/guards/roles.guard';
import { Roles }              from '../auth/decorators/roles.decorator';
import { Role }               from '../../common/enums/role.enum';

const getIp   = (req: Request) =>
  (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim()
  ?? req.socket?.remoteAddress ?? 'unknown';

const getUser = (req: Request): any => (req as any).user;

@ApiTags('Payments')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('payments')
export class PaymentsController {
  constructor(private readonly paymentsService: PaymentsService) {}

  // ─── Routes Client ────────────────────────────────────

  @ApiOperation({ summary: 'Initier un paiement' })
  @Post('initiate')
  @HttpCode(HttpStatus.CREATED)
  initiatePayment(
    @Req() req: Request,
    @Body() dto: InitiatePaymentDto,
  ) {
    return this.paymentsService.initiatePayment(
      getUser(req).id,
      dto,
      getIp(req),
    );
  }

  @ApiOperation({ summary: 'Mes paiements' })
  @ApiQuery({ name: 'page',  required: false })
  @ApiQuery({ name: 'limit', required: false })
  @Get('me')
  getMyPayments(
    @Req() req: Request,
    @Query('page')  page?:  number,
    @Query('limit') limit?: number,
  ) {
    return this.paymentsService.getMyPayments(
      getUser(req).id,
      Number(page)  || 1,
      Number(limit) || 10,
    );
  }

  @ApiOperation({ summary: 'Demander un remboursement' })
  @Post('refund')
  @HttpCode(HttpStatus.CREATED)
  requestRefund(
    @Req() req: Request,
    @Body() dto: RequestRefundDto,
  ) {
    return this.paymentsService.requestRefund(
      getUser(req).id,
      dto,
      getIp(req),
    );
  }

  // ─── Callbacks opérateur (sans auth JWT) ──────────────
  // ⚠️ Ces routes sont appelées par l'opérateur de paiement
  // Pas de JwtAuthGuard ici — sécurisées par signature HMAC
  // en production

  @ApiOperation({ summary: 'Callback confirmation paiement (opérateur)' })
  @Post('callback/confirm/:paymentId')
  @HttpCode(HttpStatus.OK)
  confirmPayment(
    @Param('paymentId', ParseUUIDPipe) paymentId: string,
    @Body() body: { providerRef: string },
    @Req() req: Request,
  ) {
    return this.paymentsService.confirmPayment(
      paymentId,
      body.providerRef,
      getIp(req),
    );
  }

  @ApiOperation({ summary: 'Callback échec paiement (opérateur)' })
  @Post('callback/fail/:paymentId')
  @HttpCode(HttpStatus.OK)
  failPayment(
    @Param('paymentId', ParseUUIDPipe) paymentId: string,
    @Req() req: Request,
  ) {
    return this.paymentsService.failPayment(
      paymentId,
      getIp(req),
    );
  }

  // ─── Routes Admin ─────────────────────────────────────

  @ApiOperation({ summary: '[ADMIN] Tous les paiements' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @ApiQuery({ name: 'status', required: false, enum: PaymentStatus })
  @ApiQuery({ name: 'page',   required: false })
  @ApiQuery({ name: 'limit',  required: false })
  @Get()
  getAllPayments(
    @Query('status') status?: PaymentStatus,
    @Query('page')   page?:   number,
    @Query('limit')  limit?:  number,
  ) {
    return this.paymentsService.getAllPayments(
      status,
      Number(page)  || 1,
      Number(limit) || 20,
    );
  }

  @ApiOperation({ summary: '[ADMIN] Toutes les demandes de remboursement' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @ApiQuery({ name: 'status', required: false, enum: RefundStatus })
  @ApiQuery({ name: 'page',   required: false })
  @ApiQuery({ name: 'limit',  required: false })
  @Get('refunds')
  getAllRefunds(
    @Query('status') status?: RefundStatus,
    @Query('page')   page?:   number,
    @Query('limit')  limit?:  number,
  ) {
    return this.paymentsService.getAllRefunds(
      status,
      Number(page)  || 1,
      Number(limit) || 20,
    );
  }

  @ApiOperation({ summary: '[ADMIN] Approuver un remboursement' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @Patch('refunds/:id/approve')
  @HttpCode(HttpStatus.OK)
  approveRefund(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
  ) {
    return this.paymentsService.processRefund(
      id,
      getUser(req).id,
      'approve',
      getIp(req),
    );
  }

  @ApiOperation({ summary: '[ADMIN] Refuser un remboursement' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @Patch('refunds/:id/reject')
  @HttpCode(HttpStatus.OK)
  rejectRefund(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
  ) {
    return this.paymentsService.processRefund(
      id,
      getUser(req).id,
      'reject',
      getIp(req),
    );
  }
}