import {
  Controller,
  Get,
  Post,
  Put,
  Delete,
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

import { CategoriesService }  from './categories.service';
import { CreateCategoryDto }  from './dto/create-category.dto';
import { UpdateCategoryDto }  from './dto/update-category.dto';
import { JwtAuthGuard }       from '../auth/guards/jwt-auth.guard';
import { RolesGuard }         from '../auth/guards/roles.guard';
import { Roles }              from '../auth/decorators/roles.decorator';
import { Role }               from '../../common/enums/role.enum';

const getIp   = (req: Request) =>
  (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim()
  ?? req.socket?.remoteAddress ?? 'unknown';

const getUser = (req: Request): any => (req as any).user;

@ApiTags('Categories')
@Controller('categories')
export class CategoriesController {
  constructor(private readonly categoriesService: CategoriesService) {}

  // ─── Routes publiques ─────────────────────────────────
  // Pas de JwtAuthGuard ici — tout le monde peut
  // voir les catégories sans être connecté

  @ApiOperation({ summary: 'Arbre complet des catégories' })
  @Get('tree')
  findAll() {
    return this.categoriesService.findAll();
  }

  @ApiOperation({ summary: 'Liste plate des catégories actives' })
  @ApiQuery({ name: 'all', required: false, type: Boolean })
  @Get('flat')
  findFlat(@Query('all') all?: string) {
    // all=true → retourner aussi les inactives (admin)
    const onlyActive = all !== 'true';
    return this.categoriesService.findFlat(onlyActive);
  }

  @ApiOperation({ summary: 'Détails d\'une catégorie' })
  @Get(':id')
  findOne(@Param('id', ParseUUIDPipe) id: string) {
    return this.categoriesService.findOne(id);
  }

  // ─── Routes Admin ─────────────────────────────────────

  @ApiOperation({ summary: '[ADMIN] Créer une catégorie' })
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(Role.ADMIN)
  @Post()
  @HttpCode(HttpStatus.CREATED)
  create(
    @Body() dto: CreateCategoryDto,
    @Req() req: Request,
  ) {
    return this.categoriesService.create(
      dto,
      getUser(req).id,
      getIp(req),
    );
  }

  @ApiOperation({ summary: '[ADMIN] Modifier une catégorie' })
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(Role.ADMIN)
  @Put(':id')
  update(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateCategoryDto,
    @Req() req: Request,
  ) {
    return this.categoriesService.update(
      id,
      dto,
      getUser(req).id,
      getIp(req),
    );
  }

  @ApiOperation({ summary: '[ADMIN] Activer ou désactiver une catégorie' })
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(Role.ADMIN)
  @Patch(':id/toggle')
  @HttpCode(HttpStatus.OK)
  toggleActive(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
  ) {
    return this.categoriesService.toggleActive(
      id,
      getUser(req).id,
      getIp(req),
    );
  }

  @ApiOperation({ summary: '[ADMIN] Supprimer une catégorie' })
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(Role.ADMIN)
  @Delete(':id')
  @HttpCode(HttpStatus.OK)
  remove(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
  ) {
    return this.categoriesService.remove(
      id,
      getUser(req).id,
      getIp(req),
    );
  }
}