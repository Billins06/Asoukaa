import { Module }        from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { DeliveryZonesController } from './delivery-zones.controller';
import { DeliveryZonesService }    from './delivery-zones.service';
import { DeliveryZone }            from './entities/delivery-zone.entity';

@Module({
  imports: [
    TypeOrmModule.forFeature([DeliveryZone]),
  ],
  controllers: [DeliveryZonesController],
  providers:   [DeliveryZonesService],
  exports:     [DeliveryZonesService, TypeOrmModule],
})
export class DeliveryZonesModule {}
