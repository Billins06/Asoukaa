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

import { FournisseursService }    from './fournisseurs.service';
import { CreateFournisseurDto }   from './dto/create-fournisseur.dto';
import { UpdateFournisseurDto }   from './dto/update-fournisseur.dto';
import { JwtAuthGuard }           from '../auth/guards/jwt-auth.guard';
import { RolesGuard }             from '../auth/guards/roles.guard';
import { Roles }                  from '../auth/decorators/roles.decorator';
import { Role }                   from '../../common/enums/role.enum';

const getIp   = (req: Request) =>
  (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim()
  ?? req.socket?.remoteAddress ?? 'unknown';

const getUser = (req: Request): any => (req as any).user;

@ApiTags('Fournisseurs')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(Role.ADMIN)        // ⚠️ TOUTES les routes admin uniquement
@Controller('fournisseurs')
export class FournisseursController {
  constructor(private readonly fournisseursService: FournisseursService) {}

  @ApiOperation({ summary: '[ADMIN] Créer un fournisseur' })
  @Post()
  @HttpCode(HttpStatus.CREATED)
  create(
    @Body() dto: CreateFournisseurDto,
    @Req() req: Request,
  ) {
    return this.fournisseursService.create(
      dto,
      getUser(req).id,
      getIp(req),
    );
  }

  @ApiOperation({ summary: '[ADMIN] Statistiques fournisseurs' })
  @Get('stats')
  getStats() {
    return this.fournisseursService.getStats();
  }

  @ApiOperation({ summary: '[ADMIN] Liste des fournisseurs (avec filtres)' })
  @ApiQuery({ name: 'search',   required: false })
  @ApiQuery({ name: 'country',  required: false })
  @ApiQuery({ name: 'ville',    required: false })
  @ApiQuery({ name: 'currency', required: false })
  @ApiQuery({ name: 'isActive', required: false, type: Boolean })
  @ApiQuery({ name: 'page',     required: false })
  @ApiQuery({ name: 'limit',    required: false })
  @Get()
  findAll(
    @Query('search')   search?:   string,
    @Query('country')  country?:  string,
    @Query('ville')    ville?:    string,
    @Query('currency') currency?: string,
    @Query('isActive') isActive?: string,
    @Query('page')     page?:     number,
    @Query('limit')    limit?:    number,
  ) {
    return this.fournisseursService.findAll({
      search,
      country,
      ville,
      currency,
      isActive: isActive !== undefined ? isActive === 'true' : undefined,
      page:  Number(page)  || 1,
      limit: Number(limit) || 20,
    });
  }

  @ApiOperation({ summary: '[ADMIN] Détails d\'un fournisseur' })
  @Get(':id')
  findOne(@Param('id', ParseUUIDPipe) id: string) {
    return this.fournisseursService.findOne(id);
  }

  @ApiOperation({ summary: '[ADMIN] Modifier un fournisseur' })
  @Put(':id')
  update(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateFournisseurDto,
    @Req() req: Request,
  ) {
    return this.fournisseursService.update(
      id,
      dto,
      getUser(req).id,
      getIp(req),
    );
  }

  @ApiOperation({ summary: '[ADMIN] Activer ou désactiver un fournisseur' })
  @Patch(':id/toggle')
  @HttpCode(HttpStatus.OK)
  toggleActive(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
  ) {
    return this.fournisseursService.toggleActive(
      id,
      getUser(req).id,
      getIp(req),
    );
  }

  @ApiOperation({ summary: '[ADMIN] Supprimer un fournisseur' })
  @Delete(':id')
  @HttpCode(HttpStatus.OK)
  remove(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
  ) {
    return this.fournisseursService.remove(
      id,
      getUser(req).id,
      getIp(req),
    );
  }
}