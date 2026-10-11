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
  Res,
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
import type { Response } from 'express';

import { VitrineService }      from './vitrine.service';
import { FeaturedShopsService } from './featured-shops.service';
import {
  AddFeaturedShopDto,
  UpdateFeaturedShopDto,
  ReorderFeaturedShopsDto,
} from './dto/featured-shop.dto';
import { CreateRayonDto }      from './dto/create-rayon.dto';
import { UpdateRayonDto }      from './dto/update-rayon.dto';
import { SetRayonProductsDto } from './dto/set-rayon-products.dto';
import { UpsertBandeauDto }    from './dto/upsert-bandeau.dto';
import { JwtAuthGuard }        from '../auth/guards/jwt-auth.guard';
import { RolesGuard }          from '../auth/guards/roles.guard';
import { Roles }               from '../auth/decorators/roles.decorator';
import { Role }                from '../../common/enums/role.enum';
import { clampLimit, clampPage } from '../../common/utils/pagination.util';

// Pilotage de la vitrine depuis le back-office : rayons, produits des
// rayons, bandeau d'accueil. Mêmes gardes que admin/vendor-withdrawals.
@ApiTags('Admin - Vitrine')
@ApiBearerAuth()
@Controller('admin/vitrine')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(Role.SUPERADMIN, Role.ADMIN)
export class AdminVitrineController {
  constructor(
    private readonly vitrineService: VitrineService,
    private readonly featuredShopsService: FeaturedShopsService,
  ) {}

  // ─── Rayons ───────────────────────────────────────────

  @ApiOperation({ summary: 'Tous les rayons (actifs ou non) avec productCount' })
  @Get('rayons')
  listRayons() {
    return this.vitrineService.listRayonsAdmin();
  }

  @ApiOperation({ summary: 'Détail d\'un rayon + ses produits dans l\'ordre' })
  @Get('rayons/:id')
  getRayon(@Param('id', ParseUUIDPipe) id: string) {
    return this.vitrineService.getRayonAdmin(id);
  }

  @ApiOperation({ summary: 'Créer un rayon' })
  @Post('rayons')
  @HttpCode(HttpStatus.CREATED)
  createRayon(@Body() dto: CreateRayonDto) {
    return this.vitrineService.createRayon(dto);
  }

  @ApiOperation({ summary: 'Modifier un rayon (partiel ; imageUrl/startsAt/endsAt acceptent null)' })
  @Patch('rayons/:id')
  updateRayon(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateRayonDto,
  ) {
    return this.vitrineService.updateRayon(id, dto);
  }

  @ApiOperation({ summary: 'Supprimer un rayon' })
  @Delete('rayons/:id')
  @HttpCode(HttpStatus.OK)
  deleteRayon(@Param('id', ParseUUIDPipe) id: string) {
    return this.vitrineService.deleteRayon(id);
  }

  @ApiOperation({ summary: 'Remplacer la liste ordonnée des produits du rayon' })
  @Put('rayons/:id/products')
  setRayonProducts(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: SetRayonProductsDto,
  ) {
    return this.vitrineService.setRayonProducts(id, dto);
  }

  // ─── Bandeau d'accueil ────────────────────────────────

  // ⚠️ @Res() : renvoyer `null` depuis un contrôleur Nest produit une
  // réponse au corps VIDE (pas le JSON "null"), ce qui fait planter
  // response.json() côté client. On écrit donc la réponse nous-mêmes.
  @ApiOperation({ summary: 'Bandeau d\'accueil (ou null)' })
  @Get('bandeau')
  async getBandeau(@Res() res: Response) {
    res.status(HttpStatus.OK).json(await this.vitrineService.getBandeauAdmin());
  }

  @ApiOperation({ summary: 'Créer ou mettre à jour le bandeau d\'accueil' })
  @Put('bandeau')
  upsertBandeau(@Body() dto: UpsertBandeauDto) {
    return this.vitrineService.upsertBandeau(dto);
  }

  // ─── Meilleures boutiques ─────────────────────────────

  @ApiOperation({ summary: 'Meilleures boutiques : liste ordonnée avec infos vendeur' })
  @Get('best-shops')
  listBestShops() {
    return this.featuredShopsService.listAdmin();
  }

  // ⚠️ Déclarée AVANT toute route paramétrée sous best-shops/.
  @ApiOperation({ summary: 'Vendeurs approuvés pas encore dans les meilleures boutiques' })
  @ApiQuery({ name: 'search', required: false })
  @ApiQuery({ name: 'page',   required: false })
  @ApiQuery({ name: 'limit',  required: false })
  @Get('best-shops/candidates')
  listBestShopCandidates(
    @Query('search') search?: string,
    @Query('page')   page?:   number,
    @Query('limit')  limit?:  number,
  ) {
    return this.featuredShopsService.listCandidates(
      search,
      clampPage(page),
      clampLimit(limit, 20),
    );
  }

  @ApiOperation({ summary: 'Ajouter une boutique en fin de liste (max 20, vendeur approuvé)' })
  @Post('best-shops')
  @HttpCode(HttpStatus.CREATED)
  addBestShop(@Body() dto: AddFeaturedShopDto) {
    return this.featuredShopsService.add(dto);
  }

  @ApiOperation({ summary: 'Réordonner : ids de TOUTES les boutiques dans le nouvel ordre' })
  @Put('best-shops/order')
  reorderBestShops(@Body() dto: ReorderFeaturedShopsDto) {
    return this.featuredShopsService.reorder(dto);
  }

  @ApiOperation({ summary: 'Activer / masquer une boutique de la liste' })
  @Patch('best-shops/:id')
  updateBestShop(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateFeaturedShopDto,
  ) {
    return this.featuredShopsService.update(id, dto);
  }

  @ApiOperation({ summary: 'Retirer une boutique de la liste' })
  @Delete('best-shops/:id')
  @HttpCode(HttpStatus.OK)
  removeBestShop(@Param('id', ParseUUIDPipe) id: string) {
    return this.featuredShopsService.remove(id);
  }

  // ─── Sélecteur de produits ────────────────────────────

  @ApiOperation({ summary: 'Rechercher des produits (tous statuts) pour composer un rayon' })
  @ApiQuery({ name: 'search', required: false })
  @ApiQuery({ name: 'limit',  required: false })
  @Get('products-search')
  searchProducts(
    @Query('search') search?: string,
    @Query('limit')  limit?:  number,
  ) {
    return this.vitrineService.searchProductsAdmin(search, clampLimit(limit, 20));
  }
}
