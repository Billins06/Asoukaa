import { Module }        from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { PaymentsController } from './payments.controller';
import { PaymentsService }    from './payments.service';
import { Payment }            from './entities/payment.entity';
import { Commission }         from './entities/commission.entity';
import { Refund }             from './entities/refund.entity';
import { Order }              from '../orders/entities/order.entity';
import { ProductVariant }     from '../products/entities/product-variant.entity';
import { VendorProfile }      from '../users/entities/vendor-profile.entity';
import { User }               from '../users/entities/user.entity';
import { CommonModule }       from '../../common/common.module';
import { CommissionsModule }  from './commissions/commissions.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      Payment,
      Commission,
      Refund,
      Order,
      ProductVariant,
      VendorProfile,
      User,
    ]),
    CommonModule,
    CommissionsModule,
  ],
  controllers: [PaymentsController],
  providers:   [PaymentsService],
  exports:     [PaymentsService, TypeOrmModule],
})
export class PaymentsModule {}