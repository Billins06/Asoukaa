import { Module }        from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { ReviewsController } from './reviews.controller';
import { ReviewsService }    from './reviews.service';
import { Review }            from './entities/review.entity';
import { Order }             from '../orders/entities/order.entity';
import { OrderItem }         from '../orders/entities/order-item.entity';
import { Product }           from '../products/entities/product.entity';
import { ProductVariant }    from '../products/entities/product-variant.entity';
import { CommonModule }      from '../../common/common.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      Review,
      Order,
      OrderItem,
      Product,
      ProductVariant,
    ]),
    CommonModule,
  ],
  controllers: [ReviewsController],
  providers:   [ReviewsService],
  exports:     [ReviewsService, TypeOrmModule],
})
export class ReviewsModule {}