import { Module }        from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ConfigModule }   from '@nestjs/config';

import { PaymentsController } from './payments.controller';
import { PaymentsService }    from './payments.service';
import { PaymentsWebhookController } from './payments-webhook.controller';
import { PaymentReconciliationService } from './payment-reconciliation.service';
import { Payment }            from './entities/payment.entity';
import { Commission }         from './entities/commission.entity';
import { Refund }             from './entities/refund.entity';
import { VendorEarningAdjustment } from './entities/vendor-earning-adjustment.entity';
import { Order }              from '../orders/entities/order.entity';
import { ProductVariant }     from '../products/entities/product-variant.entity';
import { VendorProfile }      from '../users/entities/vendor-profile.entity';
import { User }               from '../users/entities/user.entity';
import { CommonModule }       from '../../common/common.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { CommissionsModule }  from './commissions/commissions.module';
import { VendorWithdrawalsModule } from '../vendor-withdrawals/vendor-withdrawals.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      Payment,
      Commission,
      Refund,
      VendorEarningAdjustment,
      Order,
      ProductVariant,
      VendorProfile,
      User,
    ]),
    CommonModule,
    NotificationsModule,
    CommissionsModule,
    // Solde / dette du vendeur après une reprise de gains (remboursement client).
    VendorWithdrawalsModule,
    ConfigModule,
  ],
  // Webhook FeexPay = contrôleur public séparé (pas de JWT).
  controllers: [PaymentsController, PaymentsWebhookController],
  // PaymentReconciliationService = rattrapage automatique (cron toutes les 5 min).
  providers:   [PaymentsService, PaymentReconciliationService],
  exports:     [PaymentsService, TypeOrmModule],
})
export class PaymentsModule {}