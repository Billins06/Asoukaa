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

import { VendorsService }            from './vendors.service';
import { SubmitVendorProfileDto }    from './dto/submit-vendor-profile.dto';
import { CompleteVendorDocumentsDto } from './dto/complete-vendor-documents.dto';
import { UpdateShopDto }             from './dto/update-shop.dto';
import { UpdatePaymentSettingsDto }  from './dto/update-payment-settings.dto';
import { UpdateVendorSettingsDto }    from './dto/update-vendor-settings.dto';
import { ReviewVendorDto }           from './dto/review-vendor.dto';
import { SetVendorCommissionDto }    from './dto/set-vendor-commission.dto';
import { VendorStatus }              from '../users/entities/vendor-profile.entity';
import { JwtAuthGuard }              from '../auth/guards/jwt-auth.guard';
import { RolesGuard }                from '../auth/guards/roles.guard';
import { Roles }                     from '../auth/decorators/roles.decorator';
import { Role }                      from '../../common/enums/role.enum';
import { clampLimit, clampPage } from '../../common/utils/pagination.util';

const getIp   = (req: Request) =>
  (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim()
  ?? req.socket?.remoteAddress ?? 'unknown';

const getUser = (req: Request): any => (req as any).user;

@ApiTags('Vendors')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('vendors')
export class VendorsController {
  constructor(private readonly vendorsService: VendorsService) {}

  // ─── Routes Vendeur ───────────────────────────────────

  @ApiOperation({ summary: 'Soumettre une demande de compte vendeur' })
  @Post('apply')
  @HttpCode(HttpStatus.CREATED)
  submitProfile(
    @Req() req: Request,
    @Body() dto: SubmitVendorProfileDto,
  ) {
    return this.vendorsService.submitProfile(
      getUser(req).id,
      dto,
      getIp(req),
    );
  }

  @ApiOperation({ summary: 'Voir mon profil vendeur' })
  @Get('me')
  getMyProfile(@Req() req: Request) {
    return this.vendorsService.getMyProfile(getUser(req).id);
  }

  @ApiOperation({ summary: 'Compléter les documents manquants (dossier en attente)' })
  @Patch('me/documents')
  @HttpCode(HttpStatus.OK)
  completeDocuments(
    @Req() req: Request,
    @Body() dto: CompleteVendorDocumentsDto,
  ) {
    return this.vendorsService.completeDocuments(
      getUser(req).id,
      dto,
      getIp(req),
    );
  }

  @ApiOperation({ summary: 'Mes réglages vendeur (boutique visible)' })
  @Patch('me/settings')
  @HttpCode(HttpStatus.OK)
  updateSettings(
    @Req() req: Request,
    @Body() dto: UpdateVendorSettingsDto,
  ) {
    return this.vendorsService.updateSettings(getUser(req).id, dto);
  }

  @ApiOperation({ summary: 'Voir mes gains (solde, historique des commissions)' })
  @Get('me/earnings')
  getMyEarnings(@Req() req: Request) {
    return this.vendorsService.getMyEarnings(getUser(req).id);
  }

  // ⚠️ Route statique déclarée AVANT les routes ':id/...' (NestJS
  // résout dans l'ordre de déclaration).
  @ApiOperation({ summary: 'Boutiques que je suis (abonnements)' })
  @ApiQuery({ name: 'page',  required: false })
  @ApiQuery({ name: 'limit', required: false })
  @Get('me/following')
  getMyFollowedShops(
    @Req() req: Request,
    @Query('page')  page:  number = 1,
    @Query('limit') limit: number = 20,
  ) {
    return this.vendorsService.getFollowedShops(
      getUser(req).id,
      clampPage(page),
      clampLimit(limit),
    );
  }

  // ⚠️ Route statique déclarée AVANT les routes ':id/...' et ':id'.
  @ApiOperation({ summary: 'Annuaire des boutiques approuvées (recherche, filtres, catégorie)' })
  @ApiQuery({ name: 'search',     required: false })
  @ApiQuery({ name: 'filter',     required: false, enum: ['all', 'verified', 'new'] })
  @ApiQuery({ name: 'categoryId', required: false })
  @ApiQuery({ name: 'page',       required: false })
  @ApiQuery({ name: 'limit',      required: false })
  @Get('directory')
  getDirectory(
    @Req() req: Request,
    @Query('search')     search?:     string,
    @Query('filter')     filter?:     string,
    @Query('categoryId') categoryId?: string,
    @Query('page')       page?:      number,
    @Query('limit')      limit?:     number,
  ) {
    return this.vendorsService.getDirectory(getUser(req)?.id, {
      search,
      filter,
      categoryId,
      page:  clampPage(page),
      limit: clampLimit(limit, 20),
    });
  }

  @ApiOperation({ summary: 'Fiche boutique publique (vue acheteur) — incrémente le compteur de visites' })
  @Get(':id/public')
  getPublicShop(@Param('id', ParseUUIDPipe) id: string, @Req() req: Request) {
    return this.vendorsService.getPublicShop(id, getUser(req)?.id);
  }

  // Déclarée après ':id/public' ; aucune autre route GET à deux segments
  // ':id/...' ne la masque (':id' seul n'a qu'un segment).
  @ApiOperation({ summary: 'Présence du vendeur ({ lastSeenAt, isOnline }) — léger, sans incrément de visite' })
  @Get(':id/presence')
  getVendorPresence(@Param('id', ParseUUIDPipe) id: string, @Req() req: Request) {
    return this.vendorsService.getVendorPresence(id, getUser(req)?.id);
  }

  // ─── Abonnements aux boutiques ────────────────────────

  @ApiOperation({ summary: 'Est-ce que je suis cette boutique ? (+ nombre d\'abonnés)' })
  @Get(':id/follow')
  getFollowStatus(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
  ) {
    return this.vendorsService.getFollowStatus(getUser(req).id, id);
  }

  @ApiOperation({ summary: 'Suivre une boutique (idempotent)' })
  @Post(':id/follow')
  @HttpCode(HttpStatus.OK)
  followShop(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
  ) {
    return this.vendorsService.followShop(getUser(req).id, id);
  }

  @ApiOperation({ summary: 'Ne plus suivre une boutique (idempotent)' })
  @Delete(':id/follow')
  @HttpCode(HttpStatus.OK)
  unfollowShop(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
  ) {
    return this.vendorsService.unfollowShop(getUser(req).id, id);
  }

  @ApiOperation({ summary: 'Mettre à jour ma boutique (après validation)' })
  @Put('me/shop')
  updateShop(
    @Req() req: Request,
    @Body() dto: UpdateShopDto,
  ) {
    return this.vendorsService.updateShop(
      getUser(req).id,
      dto,
      getIp(req),
    );
  }

  @ApiOperation({ summary: 'Configurer mes paramètres de paiement' })
  @Patch('me/payment-settings')
  @HttpCode(HttpStatus.OK)
  updatePaymentSettings(
    @Req() req: Request,
    @Body() dto: UpdatePaymentSettingsDto,
  ) {
    return this.vendorsService.updatePaymentSettings(
      getUser(req).id,
      dto,
    );
  }

  // ─── Routes Admin ─────────────────────────────────────

  @ApiOperation({ summary: '[ADMIN] Liste des vendeurs en attente' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @Get('pending')
  getPendingVendors() {
    return this.vendorsService.getPendingVendors();
  }

  @ApiOperation({ summary: '[ADMIN] Liste tous les vendeurs' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @ApiQuery({ name: 'status', required: false, enum: VendorStatus })
  @ApiQuery({ name: 'page',   required: false })
  @ApiQuery({ name: 'limit',  required: false })
  @Get()
  getAllVendors(
    @Query('status') status?: VendorStatus,
    @Query('page')   page:   number = 1,
    @Query('limit')  limit:  number = 20,
  ) {
    return this.vendorsService.getAllVendors(
      status,
      clampPage(page),
      clampLimit(limit),
    );
  }

  @ApiOperation({ summary: '[ADMIN] Détails d\'un vendeur' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @Get(':id')
  getVendorById(@Param('id', ParseUUIDPipe) id: string) {
    return this.vendorsService.getVendorById(id);
  }

  @ApiOperation({ summary: '[ADMIN] Valider ou refuser un vendeur' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @Patch(':id/review')
  @HttpCode(HttpStatus.OK)
  reviewVendor(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
    @Body() dto: ReviewVendorDto,
  ) {
    return this.vendorsService.reviewVendor(
      id,
      getUser(req).id,
      dto,
      getIp(req),
    );
  }

  @ApiOperation({ summary: '[ADMIN] Fixer la commission d\'un vendeur (pourcentage, montant fixe par commande, ou défaut)' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @Patch(':id/commission')
  @HttpCode(HttpStatus.OK)
  setCommission(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: SetVendorCommissionDto,
    @Req() req: Request,
  ) {
    return this.vendorsService.setVendorCommission(
      id, dto.type, dto.value, getUser(req).id, getIp(req),
    );
  }

  @ApiOperation({ summary: '[ADMIN] Bloquer un vendeur' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @Patch(':id/block')
  @HttpCode(HttpStatus.OK)
  blockVendor(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
  ) {
    return this.vendorsService.blockVendor(
      id,
      getUser(req).id,
      getIp(req),
    );
  }

  @ApiOperation({ summary: '[ADMIN] Débloquer un vendeur' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @Patch(':id/unblock')
  @HttpCode(HttpStatus.OK)
  unblockVendor(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
  ) {
    return this.vendorsService.unblockVendor(
      id,
      getUser(req).id,
      getIp(req),
    );
  }
}
