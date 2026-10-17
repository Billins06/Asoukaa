import {
  Controller,
  Get,
  Patch,
  Delete,
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

import { NotificationsService }       from './notifications.service';
import { MarkNotificationsReadDto }   from './dto/mark-read.dto';
import { GetNotificationsQueryDto }   from './dto/get-notifications-query.dto';
import { JwtAuthGuard }               from '../auth/guards/jwt-auth.guard';
import { clampLimit, clampPage } from '../../common/utils/pagination.util';

const getUser = (req: Request): any => (req as any).user;

@ApiTags('Notifications')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('notifications')
export class NotificationsController {
  constructor(private readonly notificationsService: NotificationsService) {}

  @ApiOperation({ summary: 'Mes notifications' })
  @ApiQuery({ name: 'unread', required: false, type: Boolean })
  @ApiQuery({ name: 'page',   required: false })
  @ApiQuery({ name: 'limit',  required: false })
  @ApiQuery({
    name: 'since',
    required: false,
    description: 'Date ISO 8601 : seulement les notifications créées strictement après',
  })
  @Get()
  getMyNotifications(
    @Req() req: Request,
    @Query() query: GetNotificationsQueryDto,
  ) {
    return this.notificationsService.getMyNotifications(
      getUser(req).id,
      query.unread === 'true',
      clampPage(query.page),
      clampLimit(query.limit, 20),
      query.since ? new Date(query.since) : undefined,
    );
  }

  @ApiOperation({ summary: 'Nombre de notifications non lues' })
  @Get('unread-count')
  countUnread(@Req() req: Request) {
    return this.notificationsService.countUnread(getUser(req).id);
  }

  @ApiOperation({ summary: 'Marquer des notifications comme lues' })
  @Patch('mark-read')
  @HttpCode(HttpStatus.OK)
  markAsRead(
    @Req() req: Request,
    @Body() dto: MarkNotificationsReadDto,
  ) {
    return this.notificationsService.markAsRead(getUser(req).id, dto);
  }

  @ApiOperation({ summary: 'Marquer toutes mes notifications comme lues' })
  @Patch('mark-all-read')
  @HttpCode(HttpStatus.OK)
  markAllAsRead(@Req() req: Request) {
    return this.notificationsService.markAllAsRead(getUser(req).id);
  }

  @ApiOperation({ summary: 'Supprimer une notification' })
  @Delete(':id')
  @HttpCode(HttpStatus.OK)
  remove(
    @Req() req: Request,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.notificationsService.remove(getUser(req).id, id);
  }

  @ApiOperation({ summary: 'Supprimer toutes les notifications lues' })
  @Delete()
  @HttpCode(HttpStatus.OK)
  removeAllRead(@Req() req: Request) {
    return this.notificationsService.removeAllRead(getUser(req).id);
  }
}