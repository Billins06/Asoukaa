import {
  Controller, Get, Put,  Post,  Delete, Patch, Body, Param, Query, Req, UseGuards, ParseUUIDPipe, HttpCode,
  HttpStatus,
} from '@nestjs/common';
import {
  ApiTags,
  ApiBearerAuth,
  ApiOperation,
  ApiQuery,
} from '@nestjs/swagger';
import type { Request } from 'express';

import { UsersService }       from './users.service';
import { UpdateProfileDto }   from './dto/update-profile.dto';
import { CreateAddressDto }   from './dto/create-address.dto';
import { UpdateAddressDto }   from './dto/update-address.dto';
import { ChangePasswordDto }  from './dto/change-password.dto';
import { JwtAuthGuard }       from '../auth/guards/jwt-auth.guard';
import { RolesGuard }         from '../auth/guards/roles.guard';
import { Roles }              from '../auth/decorators/roles.decorator';
import { Role }               from '../../common/enums/role.enum';

// Helper IP
const getIp = (req: Request): string =>
  (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim()
  ?? req.socket?.remoteAddress
  ?? 'unknown';

// Helper pour récupérer l'utilisateur connecté depuis le token JWT
const getUser = (req: Request): any => (req as any).user;

@ApiTags('Users')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard) // Toutes les routes nécessitent un token
@Controller('users')
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  // ─── Profil utilisateur connecté ─────────────────────

  @ApiOperation({ summary: 'Voir mon profil' })
  @Get('me')
  getMyProfile(@Req() req: Request) {
    return this.usersService.getMyProfile(getUser(req).id);
  }

  @ApiOperation({ summary: 'Modifier mon profil' })
  @Put('me')
  updateProfile(
    @Req() req: Request,
    @Body() dto: UpdateProfileDto,
  ) {
    return this.usersService.updateProfile(
      getUser(req).id,
      dto,
      getIp(req),
    );
  }

  @ApiOperation({ summary: 'Changer mon mot de passe' })
  @Patch('me/password')
  @HttpCode(HttpStatus.OK)
  changePassword(
    @Req() req: Request,
    @Body() dto: ChangePasswordDto,
  ) {
    return this.usersService.changePassword(
      getUser(req).id,
      dto.currentPassword,
      dto.newPassword,
      dto.confirmPassword,
      getIp(req),
    );
  }

  // ─── Adresses ─────────────────────────────────────────

  @ApiOperation({ summary: 'Lister mes adresses' })
  @Get('me/addresses')
  getMyAddresses(@Req() req: Request) {
    return this.usersService.getMyAddresses(getUser(req).id);
  }

  @ApiOperation({ summary: 'Ajouter une adresse' })
  @Post('me/addresses')
  @HttpCode(HttpStatus.CREATED)
  createAddress(
    @Req() req: Request,
    @Body() dto: CreateAddressDto,
  ) {
    return this.usersService.createAddress(getUser(req).id, dto);
  }

  @ApiOperation({ summary: 'Modifier une adresse' })
  @Put('me/addresses/:id')
  updateAddress(
    @Req() req: Request,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateAddressDto,
  ) {
    return this.usersService.updateAddress(getUser(req).id, id, dto);
  }

  @ApiOperation({ summary: 'Supprimer une adresse' })
  @Delete('me/addresses/:id')
  @HttpCode(HttpStatus.OK)
  deleteAddress(
    @Req() req: Request,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.usersService.deleteAddress(getUser(req).id, id);
  }

  @ApiOperation({ summary: 'Définir une adresse comme principale' })
  @Patch('me/addresses/:id/default')
  @HttpCode(HttpStatus.OK)
  setDefaultAddress(
    @Req() req: Request,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.usersService.setDefaultAddress(getUser(req).id, id);
  }

  // ─── Administration ────────────────────────────────────
  // ⚠️ Ces routes sont réservées aux admins
  // RolesGuard vérifie que le token contient bien le rôle admin

  @ApiOperation({ summary: '[ADMIN] Liste tous les utilisateurs' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @ApiQuery({ name: 'page',  required: false })
  @ApiQuery({ name: 'limit', required: false })
  @Get()
  getAllUsers(
    @Query('page')  page:  number = 1,
    @Query('limit') limit: number = 20,
  ) {
    return this.usersService.getAllUsers(
      Number(page),
      Number(limit),
    );
  }

  @ApiOperation({ summary: '[ADMIN] Détails d\'un utilisateur' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @Get(':id')
  getUserById(@Param('id', ParseUUIDPipe) id: string) {
    return this.usersService.getUserById(id);
  }

  @ApiOperation({ summary: '[ADMIN] Bloquer un utilisateur' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @Patch(':id/block')
  @HttpCode(HttpStatus.OK)
  blockUser(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
  ) {
    return this.usersService.blockUser(
      id,
      getUser(req).id,
      getIp(req),
    );
  }

  @ApiOperation({ summary: '[ADMIN] Débloquer un utilisateur' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @Patch(':id/unblock')
  @HttpCode(HttpStatus.OK)
  unblockUser(
    @Param('id', ParseUUIDPipe) id: string,
    @Req() req: Request,
  ) {
    return this.usersService.unblockUser(
      id,
      getUser(req).id,
      getIp(req),
    );
  }
}
