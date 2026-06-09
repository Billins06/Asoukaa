import { Module }        from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { CouponsController } from './coupons.controller';
import { CouponsService }    from './coupons.service';
import { Coupon }            from './entities/coupon.entity';
import { CouponUsage }       from './entities/coupon-usage.entity';
import { VendorProfile }     from '../users/entities/vendor-profile.entity';
import { CommonModule }      from '../../common/common.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      Coupon,
      CouponUsage,
      VendorProfile,
    ]),
    CommonModule,
  ],
  controllers: [CouponsController],
  providers:   [CouponsService],
  exports:     [CouponsService, TypeOrmModule],
})
export class CouponsModule {}