import {
  Controller,
  Get,
  Patch,
  Body,
  Param,
  UseGuards,
  ParseUUIDPipe,
} from '@nestjs/common';
import { ApiTags, ApiBearerAuth, ApiOperation } from '@nestjs/swagger';

import { DeliveryZonesService }  from './delivery-zones.service';
import { UpdateDeliveryZoneDto } from './dto/update-delivery-zone.dto';
import { JwtAuthGuard }          from '../auth/guards/jwt-auth.guard';
import { RolesGuard }            from '../auth/guards/roles.guard';
import { Roles }                 from '../auth/decorators/roles.decorator';
import { Role }                  from '../../common/enums/role.enum';

@ApiTags('Delivery Zones')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('delivery-zones')
export class DeliveryZonesController {
  constructor(private readonly deliveryZonesService: DeliveryZonesService) {}

  @ApiOperation({ summary: 'Liste des 77 communes et leurs frais de livraison' })
  @Get()
  findAll() {
    return this.deliveryZonesService.findAll();
  }

  @ApiOperation({ summary: "[ADMIN] Mettre à jour les frais d'une commune" })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @Patch(':id')
  update(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateDeliveryZoneDto,
  ) {
    return this.deliveryZonesService.update(id, dto);
  }
}
