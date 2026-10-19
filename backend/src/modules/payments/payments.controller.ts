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
import { RejectRefundDto }    from './dto/reject-refund.dto';
import { MarkRefundProcessedDto } from './dto/mark-refund-processed.dto';
import { MarkPaymentReviewedDto } from './dto/mark-payment-reviewed.dto';
import { ClaimFreeOrdersDto }    from './dto/claim-free-orders.dto';
import { AdminRefundDigitalDto } from './dto/admin-refund-digital.dto';
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

  // Livres numériques à 0 F : validation sans paiement Mobile Money.
  @ApiOperation({ summary: 'Valider des livres numériques gratuits (0 F)' })
  @Post('free')
  @HttpCode(HttpStatus.CREATED)
  claimFreeOrders(
    @Req() req: Request,
    @Body() dto: ClaimFreeOrdersDto,
  ) {
    return this.paymentsService.claimFreeOrders(getUser(req).id, dto.orderIds, getIp(req));
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

  @ApiOperation({ summary: 'Aperçu du remboursement d\'une commande (montant fixe ou libre)' })
  @Get(['refund-preview/:orderId', 'refund-quote/:orderId'])
  getRefundQuote(
    @Req() req: Request,
    @Param('orderId', ParseUUIDPipe) orderId: string,
  ) {
    return this.paymentsService.getRefundQuote(getUser(req).id, orderId);
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
  @ApiQuery({
    name: 'toReview',
    required: false,
    description: 'true = seulement les paiements reçus mais non validés (stock / commande annulée)',
  })
  @Get()
  getAllPayments(
    @Query('status') status?: PaymentStatus,
    @Query('page')   page?:   number,
    @Query('limit')  limit?:  number,
    @Query('toReview') toReview?: string,
  ) {
    return this.paymentsService.getAllPayments(
      status,
      clampPage(page),
      clampLimit(limit, 20),
      toReview === 'true',
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

  // Livre numérique : aperçu (téléchargé ? délai de 24 h ?) puis remboursement
  // décidé par un admin après un ticket d'assistance.
  @ApiOperation({ summary: '[ADMIN] Aperçu du remboursement d\'un livre numérique' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @Get('refunds/digital-preview/:orderId')
  getDigitalRefundPreview(
    @Param('orderId', ParseUUIDPipe) orderId: string,
    @Query('ticketId', new ParseUUIDPipe({ optional: true })) ticketId?: string,
  ) {
    return this.paymentsService.getDigitalRefundPreview(orderId, ticketId);
  }

  @ApiOperation({ summary: '[ADMIN] Rembourser un livre numérique (après ticket)' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @Post('refunds/digital')
  @HttpCode(HttpStatus.OK)
  refundDigitalOrder(
    @Req() req: Request,
    @Body() dto: AdminRefundDigitalDto,
  ) {
    return this.paymentsService.adminRefundDigitalOrder(getUser(req).id, dto, getIp(req));
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
    // Corps facultatif : { motif?: string } (nom envoyé par le site admin).
    @Body() dto: RejectRefundDto,
  ) {
    return this.paymentsService.processRefund(
      id,
      getUser(req).id,
      'reject',
      getIp(req),
      dto?.motif,
    );
  }

  // Passe un remboursement « approuvé » à « traité » : l'argent a été rendu
  // au client À LA MAIN. Aucun appel FeexPay, aucun montant modifié (la
  // reprise sur les gains du vendeur a déjà eu lieu à l'approbation).
  @ApiOperation({
    summary: '[ADMIN] Marquer un remboursement approuvé comme traité (argent rendu à la main)',
  })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @Patch('refunds/:id/processed')
  @HttpCode(HttpStatus.OK)
  markRefundProcessed(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
    // Corps facultatif : { note?: string } (500 caractères maximum).
    @Body() dto: MarkRefundProcessedDto,
  ) {
    return this.paymentsService.markRefundProcessed(
      id,
      getUser(req).id,
      getIp(req),
      dto?.note,
    );
  }

  // Sort un « paiement à examiner » de la liste une fois le dossier traité.
  @ApiOperation({
    summary: '[ADMIN] Marquer un paiement reçu à examiner comme traité',
  })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @Patch(':id/reviewed')
  @HttpCode(HttpStatus.OK)
  markPaymentReviewed(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
    // Corps facultatif : { note?: string } (500 caractères maximum).
    @Body() dto: MarkPaymentReviewedDto,
  ) {
    return this.paymentsService.markPaymentReviewed(
      id,
      getUser(req).id,
      getIp(req),
      dto?.note,
    );
  }
}