import {
  Controller,
  Get,
  Post,
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

import { CouponsService }  from './coupons.service';
import { CreateCouponDto } from './dto/create-coupon.dto';
import { ApplyCouponDto }  from './dto/apply-coupon.dto';
import { JwtAuthGuard }    from '../auth/guards/jwt-auth.guard';
import { RolesGuard }      from '../auth/guards/roles.guard';
import { Roles }           from '../auth/decorators/roles.decorator';
import { Role }            from '../../common/enums/role.enum';

const getIp   = (req: Request) =>
  (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim()
  ?? req.socket?.remoteAddress ?? 'unknown';

const getUser = (req: Request): any => (req as any).user;

@ApiTags('Coupons')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('coupons')
export class CouponsController {
  constructor(private readonly couponsService: CouponsService) {}

  // ─── Routes Vendeur ───────────────────────────────────

  @ApiOperation({ summary: 'Créer un coupon (vendeur)' })
  @Post('vendor')
  @HttpCode(HttpStatus.CREATED)
  createAsVendor(
    @Req() req: Request,
    @Body() dto: CreateCouponDto,
  ) {
    return this.couponsService.create(
      dto,
      getUser(req).id,
      false,
      getIp(req),
    );
  }

  @ApiOperation({ summary: 'Mes coupons (vendeur)' })
  @ApiQuery({ name: 'page',  required: false })
  @ApiQuery({ name: 'limit', required: false })
  @Get('vendor/me')
  getMyVendorCoupons(
    @Req() req: Request,
    @Query('page')  page?:  number,
    @Query('limit') limit?: number,
  ) {
    return this.couponsService.getMyVendorCoupons(
      getUser(req).id,
      Number(page)  || 1,
      Number(limit) || 20,
    );
  }

  @ApiOperation({ summary: 'Désactiver un coupon (vendeur)' })
  @Patch('vendor/:id/deactivate')
  @HttpCode(HttpStatus.OK)
  deactivateAsVendor(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
  ) {
    return this.couponsService.deactivate(
      id,
      getUser(req).id,
      false,
      getIp(req),
    );
  }

  // ─── Route Client ─────────────────────────────────────

  @ApiOperation({ summary: 'Vérifier un coupon avant commande' })
  @Post('validate')
  @HttpCode(HttpStatus.OK)
  validateCoupon(
    @Req() req: Request,
    @Body() body: { code: string; subtotal: number },
  ) {
    return this.couponsService.validateCoupon(
      body.code,
      getUser(req).id,
      body.subtotal,
    );
  }

  // ─── Routes Admin ─────────────────────────────────────

  @ApiOperation({ summary: '[ADMIN] Créer un coupon' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @Post()
  @HttpCode(HttpStatus.CREATED)
  createAsAdmin(
    @Req() req: Request,
    @Body() dto: CreateCouponDto,
  ) {
    return this.couponsService.create(
      dto,
      getUser(req).id,
      true,
      getIp(req),
    );
  }

  @ApiOperation({ summary: '[ADMIN] Tous les coupons' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @ApiQuery({ name: 'isActive', required: false, type: Boolean })
  @ApiQuery({ name: 'page',     required: false })
  @ApiQuery({ name: 'limit',    required: false })
  @Get()
  getAllCoupons(
    @Query('isActive') isActive?: string,
    @Query('page')     page?:     number,
    @Query('limit')    limit?:    number,
  ) {
    const isActiveFilter = isActive !== undefined
      ? isActive === 'true'
      : undefined;

    return this.couponsService.getAllCoupons(
      isActiveFilter,
      Number(page)  || 1,
      Number(limit) || 20,
    );
  }

  @ApiOperation({ summary: '[ADMIN] Détails d\'un coupon' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @Get(':id')
  findOne(@Param('id', ParseUUIDPipe) id: string) {
    return this.couponsService.findOne(id);
  }

  @ApiOperation({ summary: '[ADMIN] Désactiver un coupon' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @Patch(':id/deactivate')
  @HttpCode(HttpStatus.OK)
  deactivateAsAdmin(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
  ) {
    return this.couponsService.deactivate(
      id,
      getUser(req).id,
      true,
      getIp(req),
    );
  }
}