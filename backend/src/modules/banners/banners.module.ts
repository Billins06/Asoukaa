import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { BannersController } from './banners.controller';
import { AdminBannersController } from './admin-banners.controller';
import { BannersService } from './banners.service';
import { HomeBanner } from './entities/home-banner.entity';
import { Category } from '../categories/entities/category.entity';
import { Product } from '../products/entities/product.entity';
import { ProductsModule } from '../products/products.module';

// Bannières défilantes de l'accueil, composées par l'admin.
// ProductsModule est importé pour ProductsService.filterPublicVisibleIds :
// un produit n'est « valide » que s'il est réellement visible des acheteurs.
@Module({
  imports: [
    TypeOrmModule.forFeature([HomeBanner, Category, Product]),
    ProductsModule,
  ],
  controllers: [BannersController, AdminBannersController],
  providers:   [BannersService],
  exports:     [BannersService],
})
export class BannersModule {}
