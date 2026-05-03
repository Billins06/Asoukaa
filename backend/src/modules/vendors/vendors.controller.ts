import {
  Controller,
  Get,
  Post,
  Put,
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

import { VendorsService }            from './vendors.service';
import { SubmitVendorProfileDto }    from './dto/submit-vendor-profile.dto';
import { UpdateShopDto }             from './dto/update-shop.dto';
import { UpdatePaymentSettingsDto }  from './dto/update-payment-settings.dto';
import { ReviewVendorDto }           from './dto/review-vendor.dto';
import { VendorStatus }              from '../users/entities/vendor-profile.entity';
import { JwtAuthGuard }              from '../auth/guards/jwt-auth.guard';
import { RolesGuard }                from '../auth/guards/roles.guard';
import { Roles }                     from '../auth/decorators/roles.decorator';
import { Role }                      from '../../common/enums/role.enum';

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
      Number(page),
      Number(limit),
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
}
