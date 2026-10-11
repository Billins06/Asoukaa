import {
  Controller,
  Get,
  Param,
  Query,
  ParseUUIDPipe,
} from '@nestjs/common';
import {
  ApiTags,
  ApiOperation,
  ApiQuery,
} from '@nestjs/swagger';

import { VitrineService } from './vitrine.service';
import { FeaturedShopsService } from './featured-shops.service';
import { clampLimit, clampPage } from '../../common/utils/pagination.util';

// Vitrine de la page d'accueil — routes PUBLIQUES (aucun guard, comme
// GET /products) : consultables sans être connecté.
// Les produits renvoyés ont exactement la forme de GET /products.
@ApiTags('Vitrine')
@Controller('vitrine')
export class VitrineController {
  constructor(
    private readonly vitrineService: VitrineService,
    private readonly featuredShopsService: FeaturedShopsService,
  ) {}

  @ApiOperation({ summary: 'Bandeau d\'accueil + rayons visibles maintenant' })
  @Get()
  getVitrine() {
    return this.vitrineService.getVitrine();
  }

  // ⚠️ Routes statiques ('by-type/...') et paramétrées ('rayons/:id/...')
  // n'ont pas de préfixe commun : aucun conflit d'ordre de déclaration.
  @ApiOperation({ summary: 'Produits d\'un rayon (paginés, ordre du rayon)' })
  @ApiQuery({ name: 'page',  required: false })
  @ApiQuery({ name: 'limit', required: false })
  @Get('rayons/:id/products')
  getRayonProducts(
    @Param('id', ParseUUIDPipe) id: string,
    @Query('page')  page?:  number,
    @Query('limit') limit?: number,
  ) {
    return this.vitrineService.getRayonProducts(
      id,
      clampPage(page),
      clampLimit(limit, 20),
    );
  }

  @ApiOperation({ summary: 'Meilleures boutiques (choisies par l\'admin) + leurs produits' })
  @Get('best-shops')
  getBestShops() {
    return this.featuredShopsService.getBestShops();
  }

  @ApiOperation({ summary: 'Premier rayon visible d\'un type donné + ses produits' })
  @ApiQuery({ name: 'limit', required: false })
  @Get('by-type/:type')
  getByType(
    @Param('type')  type:   string,
    @Query('limit') limit?: number,
  ) {
    return this.vitrineService.getByType(type, clampLimit(limit, 10));
  }
}
