import { Controller, Get } from '@nestjs/common';
import { ApiTags, ApiOperation } from '@nestjs/swagger';

import { BannersService } from './banners.service';

// Bannières défilantes de l'accueil — route PUBLIQUE (aucun guard, comme
// GET /vitrine) : consultable sans être connecté.
@ApiTags('Bannières')
@Controller('banners')
export class BannersController {
  constructor(private readonly bannersService: BannersService) {}

  @ApiOperation({ summary: 'Bannières visibles maintenant (actives, dans leur période, cible valide)' })
  @Get()
  getBanners() {
    return this.bannersService.getPublic();
  }
}
