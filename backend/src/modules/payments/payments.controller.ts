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
import { clampLimit, clampPage } from '../../common/utils/pagination.util';

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
      clampPage(page),
      clampLimit(limit, 10),
    );
  }

  @ApiOperation({ summary: 'Vérifier le statut d\'un paiement (polling client)' })
  @Get(':id/status')
  checkStatus(
    @Req() req: Request,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.paymentsService.checkPaymentStatus(
      id,
      getUser(req).id,
      getIp(req),
    );
  }

  @ApiOperation({ summary: 'Annuler mon paiement bloqué en attente (pour pouvoir réessayer)' })
  @Patch(':id/cancel')
  @HttpCode(HttpStatus.OK)
  cancelPending(
    @Req() req: Request,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.paymentsService.cancelMyPendingPayment(
      id,
      getUser(req).id,
      getIp(req),
    );
  }

  // ⚠️ Route "confirm-cod" (vendeur marque une commande payée en
  // espèces) retirée : un vendeur ne peut plus marquer unilatéralement
  // une commande comme payée. Les commandes initiées par un vendeur
  // (POST /orders/vendor-initiated) n'ont désormais plus de paiement
  // "cash_on_delivery" créé à la création — c'est le CLIENT qui paie
  // ensuite via le flux Mobile Money normal (POST /payments/initiate,
  // ci-dessus). Voir PaymentsService (confirmCodPayment supprimée) et
  // OrdersService.createVendorInitiated.

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

  @ApiOperation({ summary: 'Mes demandes de remboursement' })
  @ApiQuery({ name: 'page',  required: false })
  @ApiQuery({ name: 'limit', required: false })
  @Get('refunds/me')
  getMyRefunds(
    @Req() req: Request,
    @Query('page')  page?:  number,
    @Query('limit') limit?: number,
  ) {
    return this.paymentsService.getMyRefunds(
      getUser(req).id,
      clampPage(page),
      clampLimit(limit, 10),
    );
  }

  // ─── Callbacks opérateur ──────────────────────────────
  // ⚠️ SUPPRIMÉS — ces deux routes (POST callback/confirm/:paymentId et
  // POST callback/fail/:paymentId) étaient exposées SANS authentification
  // et sans vérification de signature : n'importe quel client connaissant
  // son propre paymentId (retourné par POST /payments/initiate) pouvait
  // marquer sa commande comme payée sans jamais payer.
  //
  // La confirmation passe désormais UNIQUEMENT par GET /payments/:id/status,
  // qui interroge réellement FeexPay avant de valider (voir
  // PaymentsService.checkPaymentStatus).
  //
  // Si un vrai webhook FeexPay est branché plus tard, il devra :
  //   1. vérifier une signature HMAC de l'opérateur sur le corps brut ;
  //   2. re-interroger l'API statut de FeexPay avant d'accepter ;
  //   3. ne jamais faire confiance au seul contenu du callback.

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
      clampPage(page),
      clampLimit(limit, 20),
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
      clampPage(page),
      clampLimit(limit, 20),
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