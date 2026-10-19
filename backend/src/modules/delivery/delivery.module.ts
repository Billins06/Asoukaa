import { Module }        from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { DeliveryController }       from './delivery.controller';
import { DeliveryService }          from './delivery.service';
import { IndependentDeliveriesService } from './independent-deliveries.service';
import { AdminIndependentDeliveriesService } from './admin-independent-deliveries.service';
import { AdminIndependentDeliveriesController } from './admin-independent-deliveries.controller';
import { Delivery }                 from './entities/delivery.entity';
import { IndependentDelivery }      from './entities/independent-delivery.entity';
import { DeliveryProof }            from './entities/delivery-proof.entity';
import { DeliveryEarning }          from './entities/delivery-earning.entity';
import { Order }                    from '../orders/entities/order.entity';
import { OrderItem }                from '../orders/entities/order-item.entity';
import { Product }                  from '../products/entities/product.entity';
import { DeliveryAgentProfile }     from '../users/entities/delivery-agent-profile.entity';
import { VendorProfile }            from '../users/entities/vendor-profile.entity';
import { User }                     from '../users/entities/user.entity';
import { CommonModule }             from '../../common/common.module';
import { UploadModule }             from '../upload/upload.module';
import { DeliveryEarningsModule }   from '../delivery-earnings/delivery-earnings.module';
import { NotificationsModule }      from '../notifications/notifications.module';
import { PaymentsModule }           from '../payments/payments.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      Delivery,
      IndependentDelivery,
      DeliveryProof,
      DeliveryEarning,
      Order,
      OrderItem,
      Product,
      DeliveryAgentProfile,
      VendorProfile,
      User,
    ]),
    CommonModule,
    UploadModule,
    DeliveryEarningsModule,
    NotificationsModule,
    PaymentsModule,
  ],
  controllers: [DeliveryController, AdminIndependentDeliveriesController],
  providers:   [DeliveryService, IndependentDeliveriesService, AdminIndependentDeliveriesService],
  exports:     [DeliveryService, TypeOrmModule],
})
export class DeliveryModule {}