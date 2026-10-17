import { Module }        from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { ProductsController } from './products.controller';
import { ProductsService }    from './products.service';
import { Product }            from './entities/product.entity';
import { ProductVariant }     from './entities/product-variant.entity';
import { ProductImage }       from './entities/product-image.entity';
import { ProductTag }         from './entities/product-tag.entity';
import { ProductTierPrice }   from './entities/product-tier-price.entity';
import { Category }           from '../categories/entities/category.entity';
import { VendorProfile }      from '../users/entities/vendor-profile.entity';
import { CommonModule }       from '../../common/common.module';
import { UploadModule }       from '../upload/upload.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      Product,
      ProductVariant,
      ProductImage,
      ProductTag,
      ProductTierPrice,
      Category,
      VendorProfile,
    ]),
    CommonModule,
    // UploadService : contrôle « URL issue de notre stockage » des images de
    // produit / de variante (assertIsOwnUploadUrl).
    UploadModule,
  ],
  controllers: [ProductsController],
  providers:   [ProductsService],
  exports:     [ProductsService, TypeOrmModule],
})
export class ProductsModule {}