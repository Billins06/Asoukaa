import {
  Controller,
  Get,
  Delete,
  Query,
  Param,
  Body,
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

import { ActivityLogsService }  from './activity-logs.service';
import { ActivityLogQueryDto }  from '../../common/dto/activity-log-query.dto';
import { JwtAuthGuard }         from '../auth/guards/jwt-auth.guard';
import { RolesGuard }           from '../auth/guards/roles.guard';
import { Roles }                from '../auth/decorators/roles.decorator';
import { Role }                 from '../../common/enums/role.enum';

@ApiTags('Activity Logs')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(Role.ADMIN)        // ⚠️ TOUTES les routes admin uniquement
@Controller('activity-logs')
export class ActivityLogsController {
  constructor(private readonly activityLogsService: ActivityLogsService) {}

  @ApiOperation({ summary: '[ADMIN] Liste des logs avec filtres' })
  @Get()
  findAll(@Query() query: ActivityLogQueryDto) {
    return this.activityLogsService.findAll(query);
  }

  @ApiOperation({ summary: '[ADMIN] Statistiques des logs' })
  @Get('stats')
  getStats() {
    return this.activityLogsService.getStats();
  }

  @ApiOperation({ summary: '[ADMIN] Échecs de connexion (sécurité)' })
  @ApiQuery({ name: 'page',  required: false })
  @ApiQuery({ name: 'limit', required: false })
  @Get('login-failures')
  getLoginFailures(
    @Query('page')  page?:  number,
    @Query('limit') limit?: number,
  ) {
    return this.activityLogsService.getLoginFailures(
      Number(page)  || 1,
      Number(limit) || 50,
    );
  }

  @ApiOperation({ summary: '[ADMIN] Logs d\'un acteur spécifique' })
  @ApiQuery({ name: 'page',  required: false })
  @ApiQuery({ name: 'limit', required: false })
  @Get('actor/:actorId')
  findByActor(
    @Param('actorId', ParseUUIDPipe) actorId: string,
    @Query('page')  page?:  number,
    @Query('limit') limit?: number,
  ) {
    return this.activityLogsService.findByActor(
      actorId,
      Number(page)  || 1,
      Number(limit) || 20,
    );
  }

  @ApiOperation({ summary: '[ADMIN] Logs d\'une entité spécifique' })
  @ApiQuery({ name: 'page',  required: false })
  @ApiQuery({ name: 'limit', required: false })
  @Get('entity/:entityType/:entityId')
  findByEntity(
    @Param('entityType') entityType: string,
    @Param('entityId', ParseUUIDPipe) entityId: string,
    @Query('page')  page?:  number,
    @Query('limit') limit?: number,
  ) {
    return this.activityLogsService.findByEntity(
      entityType,
      entityId,
      Number(page)  || 1,
      Number(limit) || 50,
    );
  }

  @ApiOperation({ summary: '[ADMIN] Détails d\'un log' })
  @Get(':id')
  findOne(@Param('id', ParseUUIDPipe) id: string) {
    return this.activityLogsService.findOne(id);
  }

  @ApiOperation({ summary: '[ADMIN] Purge manuelle des logs' })
  @Delete('purge')
  @HttpCode(HttpStatus.OK)
  manualPurge(@Body() body: { beforeDate: string }) {
    return this.activityLogsService.manualPurge(new Date(body.beforeDate));
  }
}