import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { DeliveryController } from './delivery.controller';
import { DeliveryService } from './delivery.service';
import { Delivery } from './entities/delivery.entity';
import { IndependentDelivery } from './entities/independent-delivery.entity';

@Module({
  imports: [
    TypeOrmModule.forFeature([Delivery, IndependentDelivery]),
  ],
  controllers: [DeliveryController],
  providers: [DeliveryService],
  exports: [TypeOrmModule],
})
export class DeliveryModule {}