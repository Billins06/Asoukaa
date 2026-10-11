import {
  Controller,
  Get,
  Post,
  Body,
  Query,
  Req,
  UseGuards,
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
import { VendorWithdrawalsService } from './vendor-withdrawals.service';
import { CreateWithdrawalDto } from './dto/create-withdrawal.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { Role } from '../../common/enums/role.enum';

const getUser = (req: Request): any => (req as any).user;

// Routes VENDEUR : chacune travaille sur le profil du vendeur CONNECTE.
// Aucun vendorId n'est accepte en parametre — il est deduit du token
// (voir VendorWithdrawalsService.getVendorByUserId).
@ApiTags('Vendeur - Retraits de gains')
@ApiBearerAuth()
@Controller('vendor-withdrawals')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(Role.VENDOR)
export class VendorWithdrawalsController {
  constructor(
    private readonly withdrawalsService: VendorWithdrawalsService,
  ) {}

  @ApiOperation({
    summary: 'Mon solde retirable et mes gains (commandes livrées uniquement)',
  })
  @Get('me/balance')
  @HttpCode(HttpStatus.OK)
  getMyBalance(@Req() req: Request) {
    return this.withdrawalsService.getMyEarnings(getUser(req).id);
  }

  @ApiOperation({ summary: 'Historique de mes demandes de retrait' })
  @ApiQuery({ name: 'page',  required: false })
  @ApiQuery({ name: 'limit', required: false })
  @Get('me')
  @HttpCode(HttpStatus.OK)
  getMyWithdrawals(
    @Req() req: Request,
    @Query('page')  page?: string,
    @Query('limit') limit?: string,
  ) {
    return this.withdrawalsService.getMyWithdrawals(
      getUser(req).id,
      page,
      limit,
    );
  }

  @ApiOperation({ summary: 'Demander un retrait de mes gains' })
  @Post('me')
  @HttpCode(HttpStatus.CREATED)
  createWithdrawal(
    @Req() req: Request,
    @Body() dto: CreateWithdrawalDto,
  ) {
    return this.withdrawalsService.createWithdrawal(getUser(req).id, dto);
  }
}
