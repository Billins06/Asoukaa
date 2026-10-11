import {
  Controller,
  Get,
  Put,
  Body,
  Req,
  UseGuards,
} from '@nestjs/common';
import { ApiTags, ApiBearerAuth, ApiOperation } from '@nestjs/swagger';
import type { Request } from 'express';

import { NotificationsService } from './notifications.service';
import { UpdateNotificationPreferencesDto } from './dto/update-notification-preferences.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';

const getUser = (req: Request): any => (req as any).user;

// Chemin /users/me/notification-preferences : déclaré ici (module
// notifications) pour garder toute la logique des préférences au même
// endroit. Aucun conflit avec UsersController (GET /users/:id n'a qu'un
// segment, et sert aux admins).
@ApiTags('Notifications')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('users/me/notification-preferences')
export class NotificationPreferencesController {
  constructor(private readonly notificationsService: NotificationsService) {}

  @ApiOperation({ summary: 'Mes préférences de notification (toutes les clés)' })
  @Get()
  getMyPreferences(@Req() req: Request) {
    return this.notificationsService.getPreferences(getUser(req).id);
  }

  @ApiOperation({ summary: 'Modifier mes préférences de notification (corps partiel)' })
  @Put()
  updateMyPreferences(
    @Req() req: Request,
    @Body() dto: UpdateNotificationPreferencesDto,
  ) {
    return this.notificationsService.updatePreferences(getUser(req).id, dto);
  }
}
