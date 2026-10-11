import { Module }        from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { CategoriesController } from './categories.controller';
import { CategoriesService }    from './categories.service';
import { Category }             from './entities/category.entity';
import { CommonModule }         from '../../common/common.module';
import { UploadModule }         from '../upload/upload.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([Category]),
    CommonModule,
    // UploadService.assertIsOwnUploadUrl : validation de l'image de catégorie.
    // UploadModule n'importe aucun module métier → pas de dépendance circulaire.
    UploadModule,
  ],
  controllers: [CategoriesController],
  providers:   [CategoriesService],
  exports:     [CategoriesService, TypeOrmModule],
})
export class CategoriesModule {}