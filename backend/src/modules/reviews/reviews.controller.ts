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

import { ReviewsService }     from './reviews.service';
import { CreateReviewDto }    from './dto/create-review.dto';
import { ModerateReviewDto }  from './dto/moderate-review.dto';
import { ReviewStatus }       from './entities/review.entity';
import { JwtAuthGuard }       from '../auth/guards/jwt-auth.guard';
import { RolesGuard }         from '../auth/guards/roles.guard';
import { Roles }              from '../auth/decorators/roles.decorator';
import { Role }               from '../../common/enums/role.enum';
import { clampLimit, clampPage } from '../../common/utils/pagination.util';

const getIp   = (req: Request) =>
  (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim()
  ?? req.socket?.remoteAddress ?? 'unknown';

const getUser = (req: Request): any => (req as any).user;

@ApiTags('Reviews')
@Controller('reviews')
export class ReviewsController {
  constructor(private readonly reviewsService: ReviewsService) {}

  // ─── Routes publiques ─────────────────────────────────

  @ApiOperation({ summary: 'Avis d\'un produit (publics)' })
  @ApiQuery({ name: 'page',  required: false })
  @ApiQuery({ name: 'limit', required: false })
  @Get('product/:productId')
  getProductReviews(
    @Param('productId', ParseUUIDPipe) productId: string,
    @Query('page')  page?:  number,
    @Query('limit') limit?: number,
  ) {
    return this.reviewsService.getProductReviews(
      productId,
      clampPage(page),
      clampLimit(limit, 10),
    );
  }

  @ApiOperation({ summary: 'Avis d\'une boutique, tous produits confondus (publics)' })
  @ApiQuery({ name: 'page',  required: false })
  @ApiQuery({ name: 'limit', required: false })
  @Get('shop/:vendorId')
  getShopReviews(
    @Param('vendorId', ParseUUIDPipe) vendorId: string,
    @Query('page')  page?:  number,
    @Query('limit') limit?: number,
  ) {
    return this.reviewsService.getShopReviews(
      vendorId,
      clampPage(page),
      clampLimit(limit, 10),
    );
  }

  // ─── Routes Client ────────────────────────────────────

  @ApiOperation({ summary: 'Laisser un avis' })
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Post()
  @HttpCode(HttpStatus.CREATED)
  create(
    @Req() req: Request,
    @Body() dto: CreateReviewDto,
  ) {
    return this.reviewsService.create(
      getUser(req).id,
      dto,
      getIp(req),
    );
  }

  @ApiOperation({ summary: 'Mes avis' })
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @ApiQuery({ name: 'page',  required: false })
  @ApiQuery({ name: 'limit', required: false })
  @Get('me')
  getMyReviews(
    @Req() req: Request,
    @Query('page')  page?:  number,
    @Query('limit') limit?: number,
  ) {
    return this.reviewsService.getMyReviews(
      getUser(req).id,
      clampPage(page),
      clampLimit(limit, 10),
    );
  }

  // ─── Routes Admin ─────────────────────────────────────

  @ApiOperation({ summary: '[ADMIN] Avis en attente de modération' })
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(Role.ADMIN)
  @ApiQuery({ name: 'page',  required: false })
  @ApiQuery({ name: 'limit', required: false })
  @Get('pending')
  getPendingReviews(
    @Query('page')  page?:  number,
    @Query('limit') limit?: number,
  ) {
    return this.reviewsService.getPendingReviews(
      clampPage(page),
      clampLimit(limit, 20),
    );
  }

  @ApiOperation({ summary: '[ADMIN] Tous les avis' })
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(Role.ADMIN)
  @ApiQuery({ name: 'status', required: false, enum: ReviewStatus })
  @ApiQuery({ name: 'page',   required: false })
  @ApiQuery({ name: 'limit',  required: false })
  @Get()
  getAllReviews(
    @Query('status') status?: ReviewStatus,
    @Query('page')   page?:   number,
    @Query('limit')  limit?:  number,
  ) {
    return this.reviewsService.getAllReviews(
      status,
      clampPage(page),
      clampLimit(limit, 20),
    );
  }

  @ApiOperation({ summary: '[ADMIN] Modérer un avis' })
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(Role.ADMIN)
  @Patch(':id/moderate')
  @HttpCode(HttpStatus.OK)
  moderate(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
    @Body() dto: ModerateReviewDto,
  ) {
    return this.reviewsService.moderate(
      id,
      getUser(req).id,
      dto,
      getIp(req),
    );
  }
}