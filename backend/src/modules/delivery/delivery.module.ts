import { Module }        from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { DeliveryController }       from './delivery.controller';
import { DeliveryService }          from './delivery.service';
import { Delivery }                 from './entities/delivery.entity';
import { IndependentDelivery }      from './entities/independent-delivery.entity';
import { Order }                    from '../orders/entities/order.entity';
import { DeliveryAgentProfile }     from '../users/entities/delivery-agent-profile.entity';
import { VendorProfile }            from '../users/entities/vendor-profile.entity';
import { User }                     from '../users/entities/user.entity';
import { CommonModule }             from '../../common/common.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      Delivery,
      IndependentDelivery,
      Order,
      DeliveryAgentProfile,
      VendorProfile,
      User,
    ]),
    CommonModule,
  ],
  controllers: [DeliveryController],
  providers:   [DeliveryService],
  exports:     [DeliveryService, TypeOrmModule],
})
export class DeliveryModule {}