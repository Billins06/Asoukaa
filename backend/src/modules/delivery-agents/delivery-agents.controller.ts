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

import { DeliveryAgentsService }      from './delivery-agents.service';
import { SubmitAgentProfileDto }      from './dto/submit-agent-profile.dto';
import { CompleteAgentDocumentsDto }  from './dto/complete-agent-documents.dto';
import { UpdateAgentAvailabilityDto } from './dto/update-availability.dto';
import { ReviewAgentDto }             from './dto/review-agent.dto';
import { AgentStatus }                from '../users/entities/delivery-agent-profile.entity';
import { JwtAuthGuard }               from '../auth/guards/jwt-auth.guard';
import { RolesGuard }                 from '../auth/guards/roles.guard';
import { Roles }                      from '../auth/decorators/roles.decorator';
import { Role }                       from '../../common/enums/role.enum';
import { clampLimit, clampPage } from '../../common/utils/pagination.util';

const getIp   = (req: Request) =>
  (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim()
  ?? req.socket?.remoteAddress ?? 'unknown';

const getUser = (req: Request): any => (req as any).user;

@ApiTags('Delivery Agents')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('delivery-agents')
export class DeliveryAgentsController {
  constructor(
    private readonly deliveryAgentsService: DeliveryAgentsService,
  ) {}

  // ─── Routes Livreur ───────────────────────────────────

  @ApiOperation({ summary: 'Soumettre une demande de compte livreur' })
  @Post('apply')
  @HttpCode(HttpStatus.CREATED)
  submitProfile(
    @Req() req: Request,
    @Body() dto: SubmitAgentProfileDto,
  ) {
    return this.deliveryAgentsService.submitProfile(
      getUser(req).id,
      dto,
      getIp(req),
    );
  }

  @ApiOperation({ summary: 'Voir mon profil livreur' })
  @Get('me')
  getMyProfile(@Req() req: Request) {
    return this.deliveryAgentsService.getMyProfile(getUser(req).id);
  }

  @ApiOperation({ summary: 'Compléter les documents manquants (dossier en attente)' })
  @Patch('me/documents')
  @HttpCode(HttpStatus.OK)
  completeDocuments(
    @Req() req: Request,
    @Body() dto: CompleteAgentDocumentsDto,
  ) {
    return this.deliveryAgentsService.completeDocuments(
      getUser(req).id,
      dto,
      getIp(req),
    );
  }

  @ApiOperation({ summary: 'Voir mes gains (solde, historique des livraisons payées)' })
  @Get('me/earnings')
  getMyEarnings(@Req() req: Request) {
    return this.deliveryAgentsService.getMyEarnings(getUser(req).id);
  }

  @ApiOperation({ summary: 'Mettre à jour ma disponibilité' })
  @Patch('me/availability')
  @HttpCode(HttpStatus.OK)
  updateAvailability(
    @Req() req: Request,
    @Body() dto: UpdateAgentAvailabilityDto,
  ) {
    return this.deliveryAgentsService.updateAvailability(
      getUser(req).id,
      dto,
    );
  }

  @ApiOperation({ summary: 'Liste des livreurs disponibles' })
  @Get('available')
  getAvailableAgents() {
    return this.deliveryAgentsService.getAvailableAgents();
  }

  // ─── Routes Admin ─────────────────────────────────────

  @ApiOperation({ summary: '[ADMIN] Demandes en attente' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @Get('pending')
  getPendingAgents() {
    return this.deliveryAgentsService.getPendingAgents();
  }

  @ApiOperation({ summary: '[ADMIN] Liste tous les livreurs' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @ApiQuery({ name: 'status', required: false, enum: AgentStatus })
  @ApiQuery({ name: 'page',   required: false })
  @ApiQuery({ name: 'limit',  required: false })
  @Get()
  getAllAgents(
    @Query('status') status?: AgentStatus,
    @Query('page')   page:   number = 1,
    @Query('limit')  limit:  number = 20,
  ) {
    return this.deliveryAgentsService.getAllAgents(
      status,
      clampPage(page),
      clampLimit(limit),
    );
  }

  @ApiOperation({ summary: '[ADMIN] Détails d\'un livreur' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @Get(':id')
  getAgentById(@Param('id', ParseUUIDPipe) id: string) {
    return this.deliveryAgentsService.getAgentById(id);
  }

  @ApiOperation({ summary: '[ADMIN] Valider ou refuser un livreur' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @Patch(':id/review')
  @HttpCode(HttpStatus.OK)
  reviewAgent(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
    @Body() dto: ReviewAgentDto,
  ) {
    return this.deliveryAgentsService.reviewAgent(
      id,
      getUser(req).id,
      dto,
      getIp(req),
    );
  }

  @ApiOperation({ summary: '[ADMIN] Bloquer un livreur' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @Patch(':id/block')
  @HttpCode(HttpStatus.OK)
  blockAgent(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
  ) {
    return this.deliveryAgentsService.blockAgent(
      id,
      getUser(req).id,
      getIp(req),
    );
  }

  @ApiOperation({ summary: '[ADMIN] Débloquer un livreur' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @Patch(':id/unblock')
  @HttpCode(HttpStatus.OK)
  unblockAgent(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
  ) {
    return this.deliveryAgentsService.unblockAgent(
      id,
      getUser(req).id,
      getIp(req),
    );
  }
}