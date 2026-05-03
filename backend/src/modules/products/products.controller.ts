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

import { ProductsService }    from './products.service';
import { CreateProductDto }   from './dto/create-product.dto';
import { UpdateProductDto }   from './dto/update-product.dto';
import { CreateVariantDto }   from './dto/create-variant.dto';
import { UpdateVariantDto }   from './dto/update-variant.dto';
import { CreateTierPriceDto } from './dto/create-tier-price.dto';
import { ProductStatus }      from './entities/product.entity';
import { JwtAuthGuard }       from '../auth/guards/jwt-auth.guard';
import { RolesGuard }         from '../auth/guards/roles.guard';
import { Roles }              from '../auth/decorators/roles.decorator';
import { Role }               from '../../common/enums/role.enum';

const getIp   = (req: Request) =>
  (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim()
  ?? req.socket?.remoteAddress ?? 'unknown';

const getUser = (req: Request): any => (req as any).user;

@ApiTags('Products')
@Controller('products')
export class ProductsController {
  constructor(private readonly productsService: ProductsService) {}

  // ─── Routes publiques ─────────────────────────────────

  @ApiOperation({ summary: 'Liste des produits (avec filtres)' })
  @ApiQuery({ name: 'page',       required: false })
  @ApiQuery({ name: 'limit',      required: false })
  @ApiQuery({ name: 'search',     required: false })
  @ApiQuery({ name: 'categoryId', required: false })
  @ApiQuery({ name: 'vendorId',   required: false })
  @ApiQuery({ name: 'minPrice',   required: false })
  @ApiQuery({ name: 'maxPrice',   required: false })
  @Get()
  findAll(
    @Query('page')       page?:       number,
    @Query('limit')      limit?:      number,
    @Query('search')     search?:     string,
    @Query('categoryId') categoryId?: string,
    @Query('vendorId')   vendorId?:   string,
    @Query('minPrice')   minPrice?:   number,
    @Query('maxPrice')   maxPrice?:   number,
  ) {
    return this.productsService.findAll({
      page:       Number(page)     || 1,
      limit:      Number(limit)    || 20,
      search,
      categoryId,
      vendorId,
      minPrice:   minPrice ? Number(minPrice) : undefined,
      maxPrice:   maxPrice ? Number(maxPrice) : undefined,
    });
  }

  @ApiOperation({ summary: 'Détails d\'un produit' })
  @Get(':id')
  findOne(@Param('id', ParseUUIDPipe) id: string) {
    return this.productsService.findOne(id);
  }

  // ─── Routes Vendeur ───────────────────────────────────

  @ApiOperation({ summary: 'Mes produits' })
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @ApiQuery({ name: 'status', required: false, enum: ProductStatus })
  @ApiQuery({ name: 'page',   required: false })
  @ApiQuery({ name: 'limit',  required: false })
  @Get('vendor/me')
  findMyProducts(
    @Req() req: Request,
    @Query('status') status?: ProductStatus,
    @Query('page')   page?:   number,
    @Query('limit')  limit?:  number,
  ) {
    return this.productsService.findByVendor(
      getUser(req).id,
      status,
      Number(page)  || 1,
      Number(limit) || 20,
    );
  }

  @ApiOperation({ summary: 'Créer un produit' })
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Post()
  @HttpCode(HttpStatus.CREATED)
  create(
    @Req() req: Request,
    @Body() dto: CreateProductDto,
  ) {
    return this.productsService.create(
      getUser(req).id,
      dto,
      getIp(req),
    );
  }

  @ApiOperation({ summary: 'Modifier un produit' })
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Put(':id')
  update(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
    @Body() dto: UpdateProductDto,
  ) {
    return this.productsService.update(
      id,
      getUser(req).id,
      dto,
      getIp(req),
    );
  }

  @ApiOperation({ summary: 'Désactiver un produit' })
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Delete(':id')
  @HttpCode(HttpStatus.OK)
  remove(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
  ) {
    return this.productsService.remove(
      id,
      getUser(req).id,
      getIp(req),
    );
  }

  // ─── Variantes ────────────────────────────────────────

  @ApiOperation({ summary: 'Ajouter une variante' })
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Post(':id/variants')
  @HttpCode(HttpStatus.CREATED)
  createVariant(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
    @Body() dto: CreateVariantDto,
  ) {
    return this.productsService.createVariant(
      id,
      getUser(req).id,
      dto,
    );
  }

  @ApiOperation({ summary: 'Modifier une variante' })
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Put(':id/variants/:variantId')
  updateVariant(
    @Param('id',        ParseUUIDPipe) id:        string,
    @Param('variantId', ParseUUIDPipe) variantId: string,
    @Req() req: Request,
    @Body() dto: UpdateVariantDto,
  ) {
    return this.productsService.updateVariant(
      id,
      variantId,
      getUser(req).id,
      dto,
    );
  }

  // ─── Images ───────────────────────────────────────────

  @ApiOperation({ summary: 'Ajouter une image' })
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Post(':id/images')
  @HttpCode(HttpStatus.CREATED)
  addImage(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
    @Body() body: {
      imageUrl:  string;
      isPrimary?: boolean;
      isVideo?:   boolean;
    },
  ) {
    return this.productsService.addImage(
      id,
      getUser(req).id,
      body.imageUrl,
      body.isPrimary,
      body.isVideo,
    );
  }

  @ApiOperation({ summary: 'Supprimer une image' })
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Delete(':id/images/:imageId')
  @HttpCode(HttpStatus.OK)
  removeImage(
    @Param('id',      ParseUUIDPipe) id:      string,
    @Param('imageId', ParseUUIDPipe) imageId: string,
    @Req() req: Request,
  ) {
    return this.productsService.removeImage(
      id,
      imageId,
      getUser(req).id,
    );
  }

  // ─── Prix dégressifs ──────────────────────────────────

  @ApiOperation({ summary: 'Définir les prix dégressifs' })
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Put(':id/tier-prices')
  @HttpCode(HttpStatus.OK)
  setTierPrices(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
    @Body() tiers: CreateTierPriceDto[],
  ) {
    return this.productsService.setTierPrices(
      id,
      getUser(req).id,
      tiers,
    );
  }

  // ─── Routes Admin ─────────────────────────────────────

  @ApiOperation({ summary: '[ADMIN] Mettre en vedette un produit' })
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(Role.ADMIN)
  @Patch(':id/featured')
  @HttpCode(HttpStatus.OK)
  toggleFeatured(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
  ) {
    return this.productsService.toggleFeatured(
      id,
      getUser(req).id,
    );
  }
}