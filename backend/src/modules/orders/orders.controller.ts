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

import { OrdersService }          from './orders.service';
import { CreateOrderDto }         from './dto/create-order.dto';
import { UpdateOrderStatusDto }   from './dto/update-order-status.dto';
import { OrderStatus }            from './entities/order.entity';
import { JwtAuthGuard }           from '../auth/guards/jwt-auth.guard';
import { RolesGuard }             from '../auth/guards/roles.guard';
import { Roles }                  from '../auth/decorators/roles.decorator';
import { Role }                   from '../../common/enums/role.enum';

const getIp   = (req: Request) =>
  (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim()
  ?? req.socket?.remoteAddress ?? 'unknown';

const getUser = (req: Request): any => (req as any).user;

@ApiTags('Orders')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('orders')
export class OrdersController {
  constructor(private readonly ordersService: OrdersService) {}

  // ─── Routes Client ────────────────────────────────────

  @ApiOperation({ summary: 'Créer une commande depuis le panier' })
  @Post()
  @HttpCode(HttpStatus.CREATED)
  createFromCart(
    @Req() req: Request,
    @Body() dto: CreateOrderDto,
  ) {
    return this.ordersService.createFromCart(
      getUser(req).id,
      dto,
      getIp(req),
    );
  }

  @ApiOperation({ summary: 'Mes commandes' })
  @ApiQuery({ name: 'page',  required: false })
  @ApiQuery({ name: 'limit', required: false })
  @Get('me')
  getMyOrders(
    @Req() req: Request,
    @Query('page')  page?:  number,
    @Query('limit') limit?: number,
  ) {
    return this.ordersService.getMyOrders(
      getUser(req).id,
      Number(page)  || 1,
      Number(limit) || 10,
    );
  }

  @ApiOperation({ summary: 'Détails d\'une commande' })
  @Get('me/:id')
  getMyOrder(
    @Req() req: Request,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.ordersService.getOrderById(id, getUser(req).id);
  }

  // ─── Routes Vendeur ───────────────────────────────────

  @ApiOperation({ summary: 'Commandes de ma boutique' })
  @ApiQuery({ name: 'status', required: false, enum: OrderStatus })
  @ApiQuery({ name: 'page',   required: false })
  @ApiQuery({ name: 'limit',  required: false })
  @Get('vendor/me')
  getVendorOrders(
    @Req() req: Request,
    @Query('status') status?: OrderStatus,
    @Query('page')   page?:   number,
    @Query('limit')  limit?:  number,
  ) {
    return this.ordersService.getVendorOrders(
      getUser(req).id,
      status,
      Number(page)  || 1,
      Number(limit) || 20,
    );
  }

  @ApiOperation({ summary: 'Mettre à jour le statut d\'une commande' })
  @Patch(':id/status')
  @HttpCode(HttpStatus.OK)
  updateStatus(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
    @Body() dto: UpdateOrderStatusDto,
  ) {
    return this.ordersService.updateStatus(
      id,
      getUser(req).id,
      dto,
      getIp(req),
      false, // isAdmin = false
    );
  }

  // ─── Routes Admin ─────────────────────────────────────

  @ApiOperation({ summary: '[ADMIN] Toutes les commandes' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @ApiQuery({ name: 'status',   required: false, enum: OrderStatus })
  @ApiQuery({ name: 'vendorId', required: false })
  @ApiQuery({ name: 'userId',   required: false })
  @ApiQuery({ name: 'page',     required: false })
  @ApiQuery({ name: 'limit',    required: false })
  @Get()
  getAllOrders(
    @Query('status')   status?:   OrderStatus,
    @Query('vendorId') vendorId?: string,
    @Query('userId')   userId?:   string,
    @Query('page')     page?:     number,
    @Query('limit')    limit?:    number,
  ) {
    return this.ordersService.getAllOrders({
      status,
      vendorId,
      userId,
      page:  Number(page)  || 1,
      limit: Number(limit) || 20,
    });
  }

  @ApiOperation({ summary: '[ADMIN] Modifier le statut d\'une commande' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @Patch(':id/admin-status')
  @HttpCode(HttpStatus.OK)
  adminUpdateStatus(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
    @Body() dto: UpdateOrderStatusDto,
  ) {
    return this.ordersService.updateStatus(
      id,
      getUser(req).id,
      dto,
      getIp(req),
      true, // isAdmin = true
    );
  }
}