import { Module }        from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { CartController } from './cart.controller';
import { CartService }    from './cart.service';
import { Cart }           from './entities/cart.entity';
import { CartItem }       from './entities/cart-item.entity';
import { ProductVariant } from '../products/entities/product-variant.entity';

@Module({
  imports: [
    TypeOrmModule.forFeature([Cart, CartItem, ProductVariant]),
  ],
  controllers: [CartController],
  providers:   [CartService],
  exports:     [CartService, TypeOrmModule],
})
export class CartModule {}