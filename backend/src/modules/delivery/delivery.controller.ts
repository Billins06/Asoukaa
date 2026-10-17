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

import { DeliveryService }               from './delivery.service';
import { AssignDeliveryAgentDto }        from './dto/assign-agent.dto';
import { UpdateDeliveryStatusDto }       from './dto/update-delivery-status.dto';
import { UpdateIndependentDeliveryStatusDto } from './dto/update-independent-delivery-status.dto';
import { CreateIndependentDeliveryDto }  from './dto/create-independent-delivery.dto';
import { SubmitPickupProofDto }          from './dto/submit-pickup-proof.dto';
import { SubmitHandoffProofDto }         from './dto/submit-handoff-proof.dto';
import { DeliveryStatus }                from './entities/delivery.entity';
import { IndependentDeliveryStatus }     from './entities/independent-delivery.entity';
import { JwtAuthGuard }                  from '../auth/guards/jwt-auth.guard';
import { RolesGuard }                    from '../auth/guards/roles.guard';
import { Roles }                         from '../auth/decorators/roles.decorator';
import { Role }                          from '../../common/enums/role.enum';
import { clampLimit, clampPage } from '../../common/utils/pagination.util';
import { VendorActiveGuard }             from '../../common/guards/vendor-active.guard';

const getIp   = (req: Request) =>
  (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim()
  ?? req.socket?.remoteAddress ?? 'unknown';

const getUser = (req: Request): any => (req as any).user;

@ApiTags('Delivery')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('delivery')
export class DeliveryController {
  constructor(private readonly deliveryService: DeliveryService) {}

  // ─── Type A — Routes Vendeur ──────────────────────────

  @ApiOperation({ summary: 'Récupérer la fiche de livraison d\'une commande' })
  @Get('order/:orderId')
  getDeliveryForOrder(
    @Param('orderId', ParseUUIDPipe) orderId: string,
    @Req() req: Request,
  ) {
    return this.deliveryService.getDeliveryForOrder(
      orderId,
      getUser(req).id,
    );
  }

  @ApiOperation({ summary: 'Affecter un livreur à une livraison' })
  @UseGuards(VendorActiveGuard)
  @Patch(':id/assign')
  @HttpCode(HttpStatus.OK)
  assignAgent(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
    @Body() dto: AssignDeliveryAgentDto,
  ) {
    return this.deliveryService.assignAgent(
      id,
      getUser(req).id,
      dto,
      getIp(req),
    );
  }

  @ApiOperation({ summary: 'Cas A — démarrer la livraison (actif seulement après la preuve de ramassage du livreur)' })
  @UseGuards(VendorActiveGuard)
  @Post(':id/start-transit')
  @HttpCode(HttpStatus.OK)
  startTransit(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
  ) {
    return this.deliveryService.startTransit(
      id,
      getUser(req).id,
      getIp(req),
    );
  }

  // ─── Type A — Routes Livreur ──────────────────────────

  @ApiOperation({ summary: 'Mes livraisons' })
  @ApiQuery({ name: 'status', required: false, enum: DeliveryStatus })
  @ApiQuery({ name: 'page',   required: false })
  @ApiQuery({ name: 'limit',  required: false })
  @Get('me')
  getMyDeliveries(
    @Req() req: Request,
    @Query('status') status?: DeliveryStatus,
    @Query('page')   page?:   number,
    @Query('limit')  limit?:  number,
  ) {
    return this.deliveryService.getMyDeliveries(
      getUser(req).id,
      status,
      clampPage(page),
      clampLimit(limit, 20),
    );
  }

  @ApiOperation({ summary: 'Signaler un échec de livraison' })
  @Patch(':id/status')
  @HttpCode(HttpStatus.OK)
  updateStatus(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
    @Body() dto: UpdateDeliveryStatusDto,
  ) {
    return this.deliveryService.updateDeliveryStatus(
      id,
      getUser(req).id,
      dto,
      getIp(req),
    );
  }

  @ApiOperation({ summary: 'Cas A — preuve de ramassage chez le vendeur (photo + état)' })
  @Post(':id/pickup-proof')
  @HttpCode(HttpStatus.OK)
  submitPickupProof(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
    @Body() dto: SubmitPickupProofDto,
  ) {
    return this.deliveryService.submitPickupProof(
      id,
      getUser(req).id,
      dto,
      getIp(req),
    );
  }

  @ApiOperation({ summary: 'Cas A — preuve de remise finale au client (code de remise du client saisi / scanné + GPS + signature)' })
  @Post(':id/handoff-proof')
  @HttpCode(HttpStatus.OK)
  submitHandoffProof(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
    @Body() dto: SubmitHandoffProofDto,
  ) {
    return this.deliveryService.submitHandoffProof(
      id,
      getUser(req).id,
      dto,
      getIp(req),
    );
  }

  // ─── Type B — Routes Client ───────────────────────────

  @ApiOperation({ summary: 'Créer une demande de livraison indépendante' })
  @Post('independent')
  @HttpCode(HttpStatus.CREATED)
  createIndependent(
    @Req() req: Request,
    @Body() dto: CreateIndependentDeliveryDto,
  ) {
    return this.deliveryService.createIndependent(
      getUser(req).id,
      dto,
      getIp(req),
    );
  }

  @ApiOperation({ summary: 'Demandes de livraison disponibles (livreur)' })
  @Get('independent/available')
  getPendingIndependent(@Req() req: Request) {
    return this.deliveryService.getPendingIndependentDeliveries(
      getUser(req).id,
    );
  }

  @ApiOperation({ summary: 'Mes courses express acceptées (livreur)' })
  @Get('independent/mine')
  getMyIndependentDeliveries(@Req() req: Request) {
    return this.deliveryService.getMyIndependentDeliveries(getUser(req).id);
  }

  @ApiOperation({ summary: 'Accepter une livraison indépendante' })
  @Patch('independent/:id/accept')
  @HttpCode(HttpStatus.OK)
  acceptIndependent(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
  ) {
    return this.deliveryService.acceptIndependent(
      id,
      getUser(req).id,
      getIp(req),
    );
  }

  @ApiOperation({ summary: 'Mettre à jour statut livraison indépendante' })
  @Patch('independent/:id/status')
  @HttpCode(HttpStatus.OK)
  updateIndependentStatus(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
    @Body() body: UpdateIndependentDeliveryStatusDto,
  ) {
    return this.deliveryService.updateIndependentStatus(
      id,
      getUser(req).id,
      body.status,
      getIp(req),
    );
  }

  // ─── Routes Admin ─────────────────────────────────────

  @ApiOperation({ summary: '[ADMIN] Toutes les livraisons' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @ApiQuery({ name: 'status', required: false, enum: DeliveryStatus })
  @ApiQuery({ name: 'page',   required: false })
  @ApiQuery({ name: 'limit',  required: false })
  @Get()
  getAllDeliveries(
    @Query('status') status?: DeliveryStatus,
    @Query('page')   page?:   number,
    @Query('limit')  limit?:  number,
  ) {
    return this.deliveryService.getAllDeliveries(
      status,
      clampPage(page),
      clampLimit(limit, 20),
    );
  }
}