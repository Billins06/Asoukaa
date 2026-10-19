import {
  Controller,
  Get,
  Post,
  Put,
  Patch,
  Delete,
  Body,
  Param,
  Query,
  UseGuards,
  ParseUUIDPipe,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { ApiTags, ApiBearerAuth, ApiOperation, ApiQuery } from '@nestjs/swagger';

import { BannersService } from './banners.service';
import { CreateBannerDto } from './dto/create-banner.dto';
import { UpdateBannerDto, ReorderBannersDto } from './dto/update-banner.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { Role } from '../../common/enums/role.enum';
import { clampLimit } from '../../common/utils/pagination.util';

// Pilotage des bannières d'accueil depuis le back-office.
// Mêmes gardes que admin/vitrine.
@ApiTags('Admin - Bannières')
@ApiBearerAuth()
@Controller('admin/banners')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(Role.SUPERADMIN, Role.ADMIN)
export class AdminBannersController {
  constructor(private readonly bannersService: BannersService) {}

  @ApiOperation({ summary: 'Toutes les bannières (actives ou non) avec statut et cible résolue' })
  @Get()
  list() {
    return this.bannersService.listAdmin();
  }

  // ⚠️ Déclarée avant toute route paramétrée.
  @ApiOperation({ summary: 'Chercher une cible : catégories, produits ou boutiques' })
  @ApiQuery({ name: 'type',   required: true, description: 'category | product | shop' })
  @ApiQuery({ name: 'search', required: false })
  @ApiQuery({ name: 'limit',  required: false })
  @Get('lookup')
  lookup(
    @Query('type')   type: string,
    @Query('search') search?: string,
    @Query('limit')  limit?: number,
  ) {
    return this.bannersService.lookup(type, search, clampLimit(limit, 20));
  }

  @ApiOperation({ summary: 'Créer une bannière' })
  @Post()
  @HttpCode(HttpStatus.CREATED)
  create(@Body() dto: CreateBannerDto) {
    return this.bannersService.create(dto);
  }

  @ApiOperation({ summary: 'Réordonner : ids dans le nouvel ordre' })
  @Put('order')
  reorder(@Body() dto: ReorderBannersDto) {
    return this.bannersService.reorder(dto);
  }

  @ApiOperation({ summary: 'Modifier une bannière (partiel ; titre/sousTitre/startsAt/endsAt acceptent null)' })
  @Patch(':id')
  update(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateBannerDto,
  ) {
    return this.bannersService.update(id, dto);
  }

  @ApiOperation({ summary: 'Supprimer une bannière' })
  @Delete(':id')
  @HttpCode(HttpStatus.OK)
  remove(@Param('id', ParseUUIDPipe) id: string) {
    return this.bannersService.remove(id);
  }
}
