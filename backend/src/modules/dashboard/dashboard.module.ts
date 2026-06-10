import { Module }        from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { DashboardController }         from './dashboard.controller';
import { DashboardService }            from './dashboard.service';
import { User }                        from '../users/entities/user.entity';
import { VendorProfile }               from '../users/entities/vendor-profile.entity';
import { DeliveryAgentProfile }        from '../users/entities/delivery-agent-profile.entity';
import { Product }                     from '../products/entities/product.entity';
import { Order }                       from '../orders/entities/order.entity';
import { OrderItem }                   from '../orders/entities/order-item.entity';
import { Payment }                     from '../payments/entities/payment.entity';
import { Commission }                  from '../payments/entities/commission.entity';
import { Review }                      from '../reviews/entities/review.entity';
import { Delivery }                    from '../delivery/entities/delivery.entity';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      User,
      VendorProfile,
      DeliveryAgentProfile,
      Product,
      Order,
      OrderItem,
      Payment,
      Commission,
      Review,
      Delivery,
    ]),
  ],
  controllers: [DashboardController],
  providers:   [DashboardService],
  exports:     [DashboardService],
})
export class DashboardModule {}