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
  BadRequestException,
} from '@nestjs/common';
import {
  ApiTags,
  ApiBearerAuth,
  ApiOperation,
  ApiQuery,
} from '@nestjs/swagger';
import type { Request } from 'express';

import { AdminSupportTicketsService, AdminActor } from './admin-support-tickets.service';
import { ReplySupportTicketDto } from './dto/reply-support-ticket.dto';
import { UpdateTicketStatusDto } from './dto/update-ticket-status.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { Role } from '../../common/enums/role.enum';
import { clampLimit, clampPage } from '../../common/utils/pagination.util';

const getIp = (req: Request): string =>
  (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim() ??
  req.socket?.remoteAddress ??
  'unknown';

const getAdmin = (req: Request): AdminActor => {
  const a = (req as any).user;
  return { id: a.id, role: a.role };
};

const ticketIdPipe = () =>
  new ParseUUIDPipe({
    exceptionFactory: () => new BadRequestException('Identifiant de ticket invalide'),
  });

const asString = (v: unknown): string | undefined =>
  typeof v === 'string' && v.trim() ? v : undefined;

// Gestion des tickets de support depuis le back-office. Mêmes gardes que
// admin/vitrine et admin/vendor-withdrawals.
@ApiTags('Admin - Support Tickets')
@ApiBearerAuth()
@Controller('admin/support-tickets')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(Role.SUPERADMIN, Role.ADMIN)
export class AdminSupportTicketsController {
  constructor(private readonly adminService: AdminSupportTicketsService) {}

  // ⚠️ 'stats' déclarée AVANT ':id'.
  @ApiOperation({ summary: 'Nombre de tickets par statut' })
  @Get('stats')
  stats() {
    return this.adminService.stats();
  }

  @ApiOperation({ summary: 'Liste des tickets (filtres status, category, search)' })
  @ApiQuery({ name: 'status',   required: false })
  @ApiQuery({ name: 'category', required: false })
  @ApiQuery({ name: 'search',   required: false, description: 'Numéro (TCK-000042 ou 42), sujet ou e-mail' })
  @ApiQuery({ name: 'page',     required: false })
  @ApiQuery({ name: 'limit',    required: false })
  @Get()
  list(
    @Query('status')   status?:   string,
    @Query('category') category?: string,
    @Query('search')   search?:   string,
    @Query('page')     page?:     number,
    @Query('limit')    limit?:    number,
  ) {
    return this.adminService.list(
      { status: asString(status), category: asString(category), search: asString(search) },
      clampPage(page),
      clampLimit(limit, 20),
    );
  }

  @ApiOperation({ summary: 'Détail d\'un ticket : messages, utilisateur, commande' })
  @Get(':id')
  getOne(@Param('id', ticketIdPipe()) id: string) {
    return this.adminService.getOne(id);
  }

  @ApiOperation({ summary: 'Répondre à un ticket (au nom de l\'« Équipe Asoukaa »)' })
  @Post(':id/messages')
  @HttpCode(HttpStatus.CREATED)
  reply(
    @Req() req: Request,
    @Param('id', ticketIdPipe()) id: string,
    @Body() dto: ReplySupportTicketDto,
  ) {
    return this.adminService.reply(getAdmin(req), id, dto, getIp(req));
  }

  @ApiOperation({ summary: 'Changer le statut d\'un ticket' })
  @Patch(':id/status')
  setStatus(
    @Req() req: Request,
    @Param('id', ticketIdPipe()) id: string,
    @Body() dto: UpdateTicketStatusDto,
  ) {
    return this.adminService.setStatus(getAdmin(req), id, dto.status, getIp(req));
  }

  @ApiOperation({ summary: 'M\'assigner le ticket' })
  @Patch(':id/assign')
  assign(@Req() req: Request, @Param('id', ticketIdPipe()) id: string) {
    return this.adminService.assignToMe(getAdmin(req), id, getIp(req));
  }
}
