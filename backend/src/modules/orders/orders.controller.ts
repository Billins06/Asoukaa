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
import { Throttle } from '@nestjs/throttler';

import { OrdersService }          from './orders.service';
import { CreateOrderDto }         from './dto/create-order.dto';
import { UpdateOrderStatusDto }   from './dto/update-order-status.dto';
import { CreateVendorOrderDto }   from './dto/create-vendor-order.dto';
import { SubmitStorePickupProofDto } from './dto/submit-store-pickup-proof.dto';
import { SubmitDispatchProofDto }    from './dto/submit-dispatch-proof.dto';
import { SubmitReceptionProofDto }   from './dto/submit-reception-proof.dto';
import { OpenDisputeDto }            from './dto/open-dispute.dto';
import { AdminCloseDisputeDto }      from './dto/admin-close-dispute.dto';
import { VendorActiveGuard }         from '../../common/guards/vendor-active.guard';
import { OrderStatus }            from './entities/order.entity';
import { JwtAuthGuard }           from '../auth/guards/jwt-auth.guard';
import { RolesGuard }             from '../auth/guards/roles.guard';
import { Roles }                  from '../auth/decorators/roles.decorator';
import { Role }                   from '../../common/enums/role.enum';
import { clampLimit, clampPage } from '../../common/utils/pagination.util';

const getIp   = (req: Request) =>
  (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim()
  ?? req.socket?.remoteAddress ?? 'unknown';

const getUser = (req: Request): any => (req as any).user;

// Recherche de clients / adresses par un vendeur : limite stricte pour
// empêcher le moissonnage des comptes (téléphone, e-mail, adresses).
const CLIENT_LOOKUP_THROTTLE = { default: { limit: 15, ttl: 60_000 } };

@ApiTags('Orders')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('orders')
export class OrdersController {
  constructor(private readonly ordersService: OrdersService) {}

  // ─── Routes Client ────────────────────────────────────

  @ApiOperation({ summary: 'Créer une commande depuis le panier' })
  @Post()
  @HttpCode(HttpStatus.CREATED)
  createFromCart(
    @Req() req: Request,
    @Body() dto: CreateOrderDto,
  ) {
    return this.ordersService.createFromCart(
      getUser(req).id,
      dto,
      getIp(req),
    );
  }

  @ApiOperation({ summary: 'Mes commandes' })
  @ApiQuery({ name: 'page',  required: false })
  @ApiQuery({ name: 'limit', required: false })
  @Get('me')
  getMyOrders(
    @Req() req: Request,
    @Query('page')  page?:  number,
    @Query('limit') limit?: number,
  ) {
    return this.ordersService.getMyOrders(
      getUser(req).id,
      clampPage(page),
      clampLimit(limit, 10),
    );
  }

  @ApiOperation({ summary: 'Détails d\'une commande' })
  @Get('me/:id')
  getMyOrder(
    @Req() req: Request,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.ordersService.getOrderById(id, getUser(req).id);
  }

  // ─── Routes Vendeur ───────────────────────────────────

  @ApiOperation({ summary: 'Commandes de ma boutique' })
  @ApiQuery({ name: 'status', required: false, enum: OrderStatus })
  @ApiQuery({ name: 'page',   required: false })
  @ApiQuery({ name: 'limit',  required: false })
  @Get('vendor/me')
  getVendorOrders(
    @Req() req: Request,
    @Query('status') status?: OrderStatus,
    @Query('page')   page?:   number,
    @Query('limit')  limit?:  number,
  ) {
    return this.ordersService.getVendorOrders(
      getUser(req).id,
      status,
      clampPage(page),
      clampLimit(limit, 20),
    );
  }

  @ApiOperation({ summary: 'Rechercher des clients par téléphone, nom/prénom ou email (pour initier une commande)' })
  @ApiQuery({ name: 'query', required: true })
  @Throttle(CLIENT_LOOKUP_THROTTLE)
  @Get('vendor/find-client')
  findClients(
    @Req() req: Request,
    @Query('query') query: string,
  ) {
    return this.ordersService.findClients(getUser(req).id, query);
  }

  @ApiOperation({ summary: "Adresses d'un client (étape 2, après avoir choisi dans la liste de find-client)" })
  @Throttle(CLIENT_LOOKUP_THROTTLE)
  @Get('vendor/client/:id/addresses')
  getClientAddresses(
    @Req() req: Request,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.ordersService.getClientAddresses(getUser(req).id, id);
  }

  @ApiOperation({ summary: 'Initier une commande pour un client (vente téléphonique/boutique)' })
  @UseGuards(VendorActiveGuard)
  @Post('vendor-initiated')
  @HttpCode(HttpStatus.CREATED)
  createVendorInitiated(
    @Req() req: Request,
    @Body() dto: CreateVendorOrderDto,
  ) {
    return this.ordersService.createVendorInitiated(
      getUser(req).id,
      dto,
      getIp(req),
    );
  }

  @ApiOperation({ summary: 'Mettre à jour le statut d\'une commande' })
  @UseGuards(VendorActiveGuard)
  @Patch(':id/status')
  @HttpCode(HttpStatus.OK)
  updateStatus(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
    @Body() dto: UpdateOrderStatusDto,
  ) {
    return this.ordersService.updateStatus(
      id,
      getUser(req).id,
      dto,
      getIp(req),
      false, // isAdmin = false
    );
  }

  @ApiOperation({ summary: 'Cas B — preuve de retrait en boutique (saisie / scan du code de remise du client)' })
  @UseGuards(VendorActiveGuard)
  @Post(':id/store-pickup-proof')
  @HttpCode(HttpStatus.OK)
  submitStorePickupProof(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
    @Body() dto: SubmitStorePickupProofDto,
  ) {
    return this.ordersService.submitStorePickupProof(
      id,
      getUser(req).id,
      dto,
      getIp(req),
    );
  }

  @ApiOperation({ summary: 'Cas C — preuve de remise au transporteur bus/taxi (photo + état)' })
  @UseGuards(VendorActiveGuard)
  @Post(':id/dispatch-proof')
  @HttpCode(HttpStatus.OK)
  submitDispatchProof(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
    @Body() dto: SubmitDispatchProofDto,
  ) {
    return this.ordersService.submitDispatchProof(
      id,
      getUser(req).id,
      dto,
      getIp(req),
    );
  }

  // ─── Routes Client ────────────────────────────────────

  @ApiOperation({ summary: 'Cas C — le client confirme avoir reçu le colis (photo)' })
  @Post(':id/reception-proof')
  @HttpCode(HttpStatus.OK)
  submitReceptionProof(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
    @Body() dto: SubmitReceptionProofDto,
  ) {
    return this.ordersService.submitReceptionProof(
      id,
      getUser(req).id,
      dto,
      getIp(req),
    );
  }

  @ApiOperation({ summary: 'Cas C — le client conteste la réception du colis' })
  @Post(':id/dispute')
  @HttpCode(HttpStatus.OK)
  openDispute(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
    @Body() dto: OpenDisputeDto,
  ) {
    return this.ordersService.openDispute(
      id,
      getUser(req).id,
      dto,
      getIp(req),
    );
  }

  @ApiOperation({ summary: 'Preuves de livraison d\'une commande (vendeur, client, livreur assigné)' })
  @Get(':id/proofs')
  getProofs(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
  ) {
    return this.ordersService.getProofsForOrder(id, getUser(req).id, false);
  }

  // ─── Routes Admin ─────────────────────────────────────

  @ApiOperation({ summary: '[ADMIN] Toutes les commandes' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @ApiQuery({ name: 'status',   required: false, enum: OrderStatus })
  @ApiQuery({ name: 'vendorId', required: false })
  @ApiQuery({ name: 'userId',   required: false })
  @ApiQuery({ name: 'disputeOuverte', required: false, description: 'true = seulement les commandes avec un litige ouvert' })
  @ApiQuery({ name: 'page',     required: false })
  @ApiQuery({ name: 'limit',    required: false })
  @Get()
  getAllOrders(
    @Query('status')   status?:   OrderStatus,
    @Query('vendorId') vendorId?: string,
    @Query('userId')   userId?:   string,
    @Query('disputeOuverte') disputeOuverte?: string,
    @Query('page')     page?:     number,
    @Query('limit')    limit?:    number,
  ) {
    return this.ordersService.getAllOrders({
      status,
      vendorId,
      userId,
      disputeOuverte: disputeOuverte === 'true',
      page:  clampPage(page),
      limit: clampLimit(limit, 20),
    });
  }

  @ApiOperation({ summary: '[ADMIN] Modifier le statut d\'une commande' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @Patch(':id/admin-status')
  @HttpCode(HttpStatus.OK)
  adminUpdateStatus(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
    @Body() dto: UpdateOrderStatusDto,
  ) {
    return this.ordersService.updateStatus(
      id,
      getUser(req).id,
      dto,
      getIp(req),
      true, // isAdmin = true
    );
  }

  @ApiOperation({
    summary:
      '[ADMIN] Clore un litige (livraison bus/taxi contestée) : rejete = reprend son cours, fonde = commande annulée',
  })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @Patch(':id/admin-close-dispute')
  @HttpCode(HttpStatus.OK)
  adminCloseDispute(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
    @Body() dto: AdminCloseDisputeDto,
  ) {
    return this.ordersService.closeDispute(
      id,
      getUser(req).id,
      dto,
      getIp(req),
    );
  }
}