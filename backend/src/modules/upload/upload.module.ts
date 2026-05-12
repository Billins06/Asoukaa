import { Module } from '@nestjs/common';
import { MulterModule } from '@nestjs/platform-express';
import { memoryStorage } from 'multer';

import { UploadController } from './upload.controller';
import { UploadService }    from './upload.service';

@Module({
  imports: [
    MulterModule.register({
      // ⚠️ memoryStorage : on stocke en mémoire le temps de
      // valider, puis on écrit nous-mêmes sur le disque.
      // Évite que Multer écrive un fichier invalide
      // avant qu'on ait pu le vérifier.
      storage: memoryStorage(),
      limits: {
        fileSize: 5 * 1024 * 1024, // 5 MB
      },
    }),
  ],
  controllers: [UploadController],
  providers:   [UploadService],
  exports:     [UploadService],
})
export class UploadModule {}