import {
  Controller,
  Get,
  Post,
  Put,
  Delete,
  Body,
  Param,
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
} from '@nestjs/swagger';
import type { Request } from 'express';

import { CartService }       from './cart.service';
import { AddToCartDto }      from './dto/add-to-cart.dto';
import { UpdateCartItemDto } from './dto/update-cart-item.dto';
import { JwtAuthGuard }      from '../auth/guards/jwt-auth.guard';

const getUser = (req: Request): any => (req as any).user;

@ApiTags('Cart')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard) // Toutes les routes nécessitent un token
@Controller('cart')
export class CartController {
  constructor(private readonly cartService: CartService) {}

  @ApiOperation({ summary: 'Voir mon panier' })
  @Get()
  getMyCart(@Req() req: Request) {
    return this.cartService.getMyCart(getUser(req).id);
  }

  @ApiOperation({ summary: 'Ajouter un article au panier' })
  @Post('items')
  @HttpCode(HttpStatus.OK)
  addItem(
    @Req() req: Request,
    @Body() dto: AddToCartDto,
  ) {
    return this.cartService.addItem(getUser(req).id, dto);
  }

  @ApiOperation({ summary: 'Modifier la quantité d\'un article' })
  @Put('items/:id')
  updateItem(
    @Req() req: Request,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateCartItemDto,
  ) {
    return this.cartService.updateItem(getUser(req).id, id, dto);
  }

  @ApiOperation({ summary: 'Supprimer un article du panier' })
  @Delete('items/:id')
  @HttpCode(HttpStatus.OK)
  removeItem(
    @Req() req: Request,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.cartService.removeItem(getUser(req).id, id);
  }

  @ApiOperation({ summary: 'Vider le panier' })
  @Delete()
  @HttpCode(HttpStatus.OK)
  clearCart(@Req() req: Request) {
    return this.cartService.clearCart(getUser(req).id);
  }
}