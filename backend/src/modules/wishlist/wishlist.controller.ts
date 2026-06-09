import {
  Controller,
  Get,
  Post,
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

import { WishlistService }    from './wishlist.service';
import { AddToWishlistDto }   from './dto/add-to-wishlist.dto';
import { JwtAuthGuard }       from '../auth/guards/jwt-auth.guard';

const getUser = (req: Request): any => (req as any).user;

@ApiTags('Wishlist')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('wishlist')
export class WishlistController {
  constructor(private readonly wishlistService: WishlistService) {}

  @ApiOperation({ summary: 'Ajouter un produit à ma wishlist' })
  @Post()
  @HttpCode(HttpStatus.CREATED)
  add(
    @Req() req: Request,
    @Body() dto: AddToWishlistDto,
  ) {
    return this.wishlistService.add(getUser(req).id, dto);
  }

  @ApiOperation({ summary: 'Ma wishlist' })
  @ApiQuery({ name: 'page',  required: false })
  @ApiQuery({ name: 'limit', required: false })
  @Get()
  getMyWishlist(
    @Req() req: Request,
    @Query('page')  page?:  number,
    @Query('limit') limit?: number,
  ) {
    return this.wishlistService.getMyWishlist(
      getUser(req).id,
      Number(page)  || 1,
      Number(limit) || 20,
    );
  }

  @ApiOperation({ summary: 'Compter mes éléments wishlist' })
  @Get('count')
  count(@Req() req: Request) {
    return this.wishlistService.count(getUser(req).id);
  }

  @ApiOperation({ summary: 'Vérifier si un produit est dans ma wishlist' })
  @Get('check/:productId')
  isInWishlist(
    @Req() req: Request,
    @Param('productId', ParseUUIDPipe) productId: string,
  ) {
    return this.wishlistService.isInWishlist(getUser(req).id, productId);
  }

  @ApiOperation({ summary: 'Retirer un produit de ma wishlist' })
  @Delete(':productId')
  @HttpCode(HttpStatus.OK)
  remove(
    @Req() req: Request,
    @Param('productId', ParseUUIDPipe) productId: string,
  ) {
    return this.wishlistService.remove(getUser(req).id, productId);
  }

  @ApiOperation({ summary: 'Vider ma wishlist' })
  @Delete()
  @HttpCode(HttpStatus.OK)
  clear(@Req() req: Request) {
    return this.wishlistService.clear(getUser(req).id);
  }
}