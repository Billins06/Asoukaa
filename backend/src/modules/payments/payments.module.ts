import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { PaymentsController } from './payments.controller';
import { PaymentsService } from './payments.service';
import { Payment } from './entities/payment.entity';
import { Commission } from './entities/commission.entity';
import { Refund } from './entities/refund.entity';

@Module({
  imports: [
    TypeOrmModule.forFeature([Payment, Commission, Refund]),
  ],
  controllers: [PaymentsController],
  providers: [PaymentsService],
  exports: [TypeOrmModule],
})
export class PaymentsModule {}