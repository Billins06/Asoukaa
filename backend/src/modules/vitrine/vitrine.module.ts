import { Module }        from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { VitrineController }      from './vitrine.controller';
import { AdminVitrineController } from './admin-vitrine.controller';
import { VitrineService }         from './vitrine.service';
import { VitrineRayon }           from './entities/vitrine-rayon.entity';
import { VitrineRayonProduit }    from './entities/vitrine-rayon-produit.entity';
import { VitrineBandeau }         from './entities/vitrine-bandeau.entity';
import { FeaturedShop }           from './entities/featured-shop.entity';
import { FeaturedShopsService }    from './featured-shops.service';
import { Product }                from '../products/entities/product.entity';
import { ProductsModule }         from '../products/products.module';
import { CommonModule }           from '../../common/common.module';

// Vitrine de la page d'accueil (rayons composés par l'admin + bandeau).
// ProductsModule est importé pour ProductsService : la vitrine réutilise
// sa requête publique afin que chaque produit ait la forme de GET /products.
@Module({
  imports: [
    TypeOrmModule.forFeature([VitrineRayon, VitrineRayonProduit, VitrineBandeau, FeaturedShop, Product]),
    ProductsModule,
    CommonModule,
  ],
  controllers: [VitrineController, AdminVitrineController],
  providers:   [VitrineService, FeaturedShopsService],
  exports:     [VitrineService, FeaturedShopsService],
})
export class VitrineModule {}
