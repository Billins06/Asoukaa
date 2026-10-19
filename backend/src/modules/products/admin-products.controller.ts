import {
  Controller,
  Get,
  Patch,
  Body,
  Param,
  Query,
  Req,
  UseGuards,
  ParseUUIDPipe,
  BadRequestException,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { ApiTags, ApiBearerAuth, ApiOperation } from '@nestjs/swagger';
import type { Request } from 'express';
import { isUUID } from 'class-validator';

import { AdminProductsService } from './admin-products.service';
import { AdminBlockProductDto } from './dto/admin-block-product.dto';
import { ProductStatus } from './entities/product.entity';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { Role } from '../../common/enums/role.enum';
import { clampLimit, clampPage } from '../../common/utils/pagination.util';

const getIp = (req: Request) =>
  (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim()
  ?? req.socket?.remoteAddress ?? 'unknown';
const getUser = (req: Request): any => (req as any).user;

@ApiTags('Admin Products')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(Role.ADMIN)
@Controller('admin/products')
export class AdminProductsController {
  constructor(private readonly adminProducts: AdminProductsService) {}

  @ApiOperation({ summary: '[ADMIN] Liste des produits (tous statuts)' })
  @Get()
  list(
    @Query('page')       page?: string,
    @Query('limit')      limit?: string,
    @Query('search')     search?: string,
    @Query('status')     status?: string,
    @Query('vendorId')   vendorId?: string,
    @Query('categoryId') categoryId?: string,
    @Query('isDigital')  isDigital?: string,
    @Query('blocked')    blocked?: string,
  ) {
    if (status && !Object.values(ProductStatus).includes(status as ProductStatus)) {
      throw new BadRequestException('Statut invalide');
    }
    if (vendorId && !isUUID(vendorId))     throw new BadRequestException('vendorId invalide');
    if (categoryId && !isUUID(categoryId)) throw new BadRequestException('categoryId invalide');
    const bool = (v?: string) => (v === 'true' ? true : v === 'false' ? false : undefined);

    return this.adminProducts.list({
      search:     search?.trim() ? search.trim().slice(0, 100) : undefined,
      status:     status as ProductStatus | undefined,
      vendorId,
      categoryId,
      isDigital:  bool(isDigital),
      blocked:    bool(blocked),
      page:       clampPage(page),
      limit:      clampLimit(limit, 20),
    });
  }

  @ApiOperation({ summary: '[ADMIN] Détail d\'un produit' })
  @Get(':id')
  getOne(@Param('id', ParseUUIDPipe) id: string) {
    return this.adminProducts.getOne(id);
  }

  @ApiOperation({ summary: '[ADMIN] Désactiver / réactiver un produit' })
  @Patch(':id/block')
  @HttpCode(HttpStatus.OK)
  setBlocked(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: AdminBlockProductDto,
    @Req() req: Request,
  ) {
    return this.adminProducts.setBlocked(id, dto.blocked, dto.reason, getUser(req).id, getIp(req));
  }
}
