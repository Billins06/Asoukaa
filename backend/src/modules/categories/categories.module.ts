import { Module }        from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { CategoriesController } from './categories.controller';
import { CategoriesService }    from './categories.service';
import { Category }             from './entities/category.entity';
import { CommonModule }         from '../../common/common.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([Category]),
    CommonModule,
  ],
  controllers: [CategoriesController],
  providers:   [CategoriesService],
  exports:     [CategoriesService, TypeOrmModule],
})
export class CategoriesModule {}