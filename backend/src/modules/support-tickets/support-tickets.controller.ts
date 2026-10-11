import {
  Controller,
  Get,
  Post,
  Body,
  Param,
  Query,
  Req,
  UseGuards,
  ParseUUIDPipe,
  HttpCode,
  HttpStatus,
  BadRequestException,
  ForbiddenException,
} from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import {
  ApiTags,
  ApiBearerAuth,
  ApiOperation,
  ApiQuery,
} from '@nestjs/swagger';
import type { Request } from 'express';

import { SupportTicketsService } from './support-tickets.service';
import { CreateSupportTicketDto } from './dto/create-support-ticket.dto';
import { ReplySupportTicketDto } from './dto/reply-support-ticket.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { clampLimit, clampPage } from '../../common/utils/pagination.util';
import { TICKET_LIMITS } from './support-ticket.constants';

// Rafales d'écriture : 10 par minute et par IP, en plus des limites métier
// (5 tickets/heure, 20 messages/heure) appliquées en base.
const WRITE_THROTTLE = { default: { limit: 10, ttl: 60_000 } };

// Un id invalide répond 400 en français (et non une erreur Postgres 500).
const ticketIdPipe = () =>
  new ParseUUIDPipe({
    exceptionFactory: () => new BadRequestException('Identifiant de ticket invalide'),
  });

// Le JwtAuthGuard accepte aussi les jetons des comptes admin : ces routes
// sont réservées aux UTILISATEURS (acheteur / vendeur / livreur). Un compte
// admin porte un champ scalaire `role` que les utilisateurs n'ont pas.
const currentUserId = (req: Request): string => {
  const principal = (req as any).user;
  if (!principal?.id || typeof principal.role === 'string') {
    throw new ForbiddenException('Cette route est réservée aux utilisateurs de l\'application');
  }
  return principal.id as string;
};

@ApiTags('Support Tickets')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('support-tickets')
export class SupportTicketsController {
  constructor(private readonly ticketsService: SupportTicketsService) {}

  @ApiOperation({ summary: 'Ouvrir un ticket de support (+ premier message)' })
  @Throttle(WRITE_THROTTLE)
  @Post()
  @HttpCode(HttpStatus.CREATED)
  create(@Req() req: Request, @Body() dto: CreateSupportTicketDto) {
    return this.ticketsService.createTicket(currentUserId(req), dto);
  }

  // ⚠️ Déclarée AVANT ':id' : sinon « unread-count » serait lu comme un id.
  @ApiOperation({ summary: 'Nombre de tickets avec une réponse non lue (badge)' })
  @Get('unread-count')
  unreadCount(@Req() req: Request) {
    return this.ticketsService.unreadCount(currentUserId(req));
  }

  @ApiOperation({ summary: 'Mes tickets (plus récents en premier)' })
  @ApiQuery({ name: 'page',  required: false })
  @ApiQuery({ name: 'limit', required: false })
  @Get()
  list(
    @Req() req: Request,
    @Query('page')  page?:  number,
    @Query('limit') limit?: number,
  ) {
    return this.ticketsService.listMine(
      currentUserId(req),
      clampPage(page),
      Math.min(clampLimit(limit, 20), TICKET_LIMITS.MAX_PAGE_SIZE),
    );
  }

  @ApiOperation({ summary: 'Détail d\'un de mes tickets + messages (marque comme lu)' })
  @Get(':id')
  getOne(@Req() req: Request, @Param('id', ticketIdPipe()) id: string) {
    return this.ticketsService.getMine(currentUserId(req), id);
  }

  @ApiOperation({ summary: 'Répondre à un de mes tickets' })
  @Throttle(WRITE_THROTTLE)
  @Post(':id/messages')
  @HttpCode(HttpStatus.CREATED)
  reply(
    @Req() req: Request,
    @Param('id', ticketIdPipe()) id: string,
    @Body() dto: ReplySupportTicketDto,
  ) {
    return this.ticketsService.addUserMessage(currentUserId(req), id, dto);
  }
}
