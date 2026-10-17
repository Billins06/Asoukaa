import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { VendorWithdrawal } from './entities/vendor-withdrawal.entity';
import { VendorProfile } from '../users/entities/vendor-profile.entity';
import { Order } from '../orders/entities/order.entity';
import { Commission } from '../payments/entities/commission.entity';
import { VendorEarningAdjustment } from '../payments/entities/vendor-earning-adjustment.entity';
import { VendorWithdrawalsService } from './vendor-withdrawals.service';
import { VendorWithdrawalsController } from './vendor-withdrawals.controller';
import { AdminVendorWithdrawalsController } from './admin-vendor-withdrawals.controller';
import { CommonModule } from '../../common/common.module';

// Retraits de gains vendeurs. Volontairement calque sur
// DeliveryEarningsModule (delivery-earnings/) : un service, un controleur
// metier, un controleur admin.
@Module({
  imports: [
    TypeOrmModule.forFeature([VendorWithdrawal, VendorProfile, Order, Commission, VendorEarningAdjustment]),
    CommonModule,
  ],
  controllers: [
    VendorWithdrawalsController,
    AdminVendorWithdrawalsController,
  ],
  providers: [VendorWithdrawalsService],
  exports: [VendorWithdrawalsService],
})
export class VendorWithdrawalsModule {}
