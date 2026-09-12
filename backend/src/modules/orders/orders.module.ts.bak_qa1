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
import { Coupon }           from '../coupons/entities/coupon.entity';
import { CouponUsage }      from '../coupons/entities/coupon-usage.entity';
import { CommonModule }     from '../../common/common.module';

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
      Coupon,
      CouponUsage,
    ]),
    CommonModule,
  ],
  controllers: [OrdersController],
  providers:   [OrdersService],
  exports:     [OrdersService, TypeOrmModule],
})
export class OrdersModule {}