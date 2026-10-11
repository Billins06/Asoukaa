import {
  Controller,
  Get,
  Query,
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

import { OrderConfirmationService } from './order-confirmation.service';
import { JwtAuthGuard }  from '../auth/guards/jwt-auth.guard';
import { RolesGuard }    from '../auth/guards/roles.guard';
import { Roles }         from '../auth/decorators/roles.decorator';
import { Role }          from '../../common/enums/role.enum';
import { clampLimit, clampPage } from '../../common/utils/pagination.util';

// Commandes payées que le vendeur n'a pas confirmées dans le délai.
// Mêmes gardes que les autres contrôleurs admin/* (JwtAuthGuard + RolesGuard,
// admin et superadmin).
@ApiTags('Admin - Commandes en retard de confirmation')
@ApiBearerAuth()
@Controller('admin/orders')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(Role.SUPERADMIN, Role.ADMIN)
export class AdminOrderConfirmationController {
  constructor(private readonly confirmation: OrderConfirmationService) {}

  @ApiOperation({
    summary:
      'Commandes payées non confirmées par le vendeur au-delà du délai (rappel ou alerte)',
  })
  @ApiQuery({ name: 'level',    required: false, enum: ['reminder', 'alert'] })
  @ApiQuery({ name: 'vendorId', required: false })
  @ApiQuery({ name: 'page',     required: false })
  @ApiQuery({ name: 'limit',    required: false })
  @Get('late-confirmation')
  @HttpCode(HttpStatus.OK)
  getLateConfirmation(
    @Query('level')    level?:    string,
    @Query('vendorId') vendorId?: string,
    @Query('page')     page?:     number,
    @Query('limit')    limit?:    number,
  ) {
    return this.confirmation.listLateConfirmation({
      level:    level || undefined,
      vendorId: vendorId || undefined,
      page:     clampPage(page),
      limit:    clampLimit(limit, 20),
    });
  }
}
