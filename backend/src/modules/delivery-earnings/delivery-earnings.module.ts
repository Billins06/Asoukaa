import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { DeliveryEarning } from '../delivery/entities/delivery-earning.entity';
import { DeliveryEarningsService } from './delivery-earnings.service';
import { DeliveryEarningsController } from './delivery-earnings.controller';
import { CommonModule } from '../../common/common.module';

@Module({
  imports: [TypeOrmModule.forFeature([DeliveryEarning]), CommonModule],
  controllers: [DeliveryEarningsController],
  providers: [DeliveryEarningsService],
  exports: [DeliveryEarningsService],
})
export class DeliveryEarningsModule {}
