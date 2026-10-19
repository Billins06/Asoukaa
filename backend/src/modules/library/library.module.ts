import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { LibraryItem } from './entities/library-item.entity';
import { Product } from '../products/entities/product.entity';
import { LibraryService } from './library.service';
import { LibraryController, LibraryLocalFileController } from './library.controller';
import { UploadModule } from '../upload/upload.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([LibraryItem, Product]),
    UploadModule,
  ],
  controllers: [LibraryController, LibraryLocalFileController],
  providers:   [LibraryService],
  exports:     [LibraryService],
})
export class LibraryModule {}
