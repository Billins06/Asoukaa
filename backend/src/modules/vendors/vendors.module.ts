import { Module }        from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { VendorsController } from './vendors.controller';
import { VendorsService }    from './vendors.service';
import { VendorProfile }     from '../users/entities/vendor-profile.entity';
import { UserRole }          from '../users/entities/user-role.entity';
import { User }              from '../users/entities/user.entity';
import { Commission }        from '../payments/entities/commission.entity';
import { VendorEarningAdjustment } from '../payments/entities/vendor-earning-adjustment.entity';
import { Product }           from '../products/entities/product.entity';
import { Order }             from '../orders/entities/order.entity';
import { Review }            from '../reviews/entities/review.entity';
import { ShopFollow }        from './entities/shop-follow.entity';
import { Category }          from '../categories/entities/category.entity';
import { CommonModule }      from '../../common/common.module';
import { ProductsModule }    from '../products/products.module';
import { UploadModule }      from '../upload/upload.module';
import { VendorWithdrawalsModule } from '../vendor-withdrawals/vendor-withdrawals.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([VendorProfile, UserRole, User, Commission, VendorEarningAdjustment, Product, Order, Review, ShopFollow, Category]),
    CommonModule,
    // ProductsService : visibilité produit + sous-catégories (annuaire)
    ProductsModule,
    // UploadService : rafraîchit les URL signées des documents (fiches admin)
    UploadModule,
    // VendorWithdrawalsService : solde / dette du vendeur (getMyEarnings).
    // Ce module n'importe pas VendorsModule : pas de dépendance circulaire.
    VendorWithdrawalsModule,
  ],
  controllers: [VendorsController],
  providers:   [VendorsService],
  exports:     [VendorsService, TypeOrmModule],
})
export class VendorsModule {}