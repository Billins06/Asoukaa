import { Module }        from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { OrdersController } from './orders.controller';
import { OrdersService }    from './orders.service';
import { Order }            from './entities/order.entity';
import { OrderItem }        from './entities/order-item.entity';
import { Cart }             from '../cart/entities/cart.entity';
import { CartItem }         from '../cart/entities/cart-item.entity';
import { ProductVariant }   from '../products/entities/product-variant.entity';
import { Product }          from '../products/entities/product.entity';
import { Address }          from '../users/entities/address.entity';
import { VendorProfile }    from '../users/entities/vendor-profile.entity';
import { User }             from '../users/entities/user.entity';
import { Coupon }           from '../coupons/entities/coupon.entity';
import { CouponUsage }      from '../coupons/entities/coupon-usage.entity';
import { DeliveryZone }     from '../delivery-zones/entities/delivery-zone.entity';
import { Payment }          from '../payments/entities/payment.entity';
import { DeliveryProof }    from '../delivery/entities/delivery-proof.entity';
import { CommonModule }     from '../../common/common.module';
import { DeliveryModule }   from '../delivery/delivery.module';
import { UploadModule }     from '../upload/upload.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { AdminAccount }        from '../auth/entities/admin-account.entity';
import { OrderConfirmationService }         from './order-confirmation.service';
import { UnpaidOrdersService }              from './unpaid-orders.service';
import { AdminOrderConfirmationController } from './admin-order-confirmation.controller';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      Order,
      OrderItem,
      Cart,
      CartItem,
      ProductVariant,
      Product,
      Address,
      VendorProfile,
      User,
      Coupon,
      CouponUsage,
      DeliveryZone,
      Payment,
      DeliveryProof,
      AdminAccount,
    ]),
    CommonModule,
    DeliveryModule,
    UploadModule,
    NotificationsModule,
  ],
  controllers: [OrdersController, AdminOrderConfirmationController],
  providers:   [OrdersService, OrderConfirmationService, UnpaidOrdersService],
  exports:     [OrdersService, OrderConfirmationService, TypeOrmModule],
})
export class OrdersModule {}