import { Module } from '@nestjs/common';
import { MulterModule } from '@nestjs/platform-express';
import { memoryStorage } from 'multer';

import { UploadController } from './upload.controller';
import { UploadService, DEFAULT_MAX_VIDEO_FILE_SIZE } from './upload.service';
import { UploadQuotaService } from './upload-quota.service';

@Module({
  imports: [
    MulterModule.register({
      // ⚠️ memoryStorage : on stocke en mémoire le temps de
      // valider, puis on écrit nous-mêmes sur le disque.
      // Évite que Multer écrive un fichier invalide
      // avant qu'on ait pu le vérifier.
      storage: memoryStorage(),
      limits: {
        // Plafond global Multer : doit être >= la plus grande limite
        // par type gérée dans UploadService (actuellement les vidéos
        // produit, DEFAULT_MAX_VIDEO_FILE_SIZE = 50 MB). Multer rejette
        // le fichier AVANT que UploadService puisse appliquer ses
        // propres limites par type ; c'est donc un plafond global "large
        // ouverture", pas la vraie limite (images/documents restent
        // plafonnés à MAX_FILE_SIZE = 5 MB dans UploadService.uploadFile).
        fileSize: DEFAULT_MAX_VIDEO_FILE_SIZE,
      },
    }),
  ],
  controllers: [UploadController],
  providers:   [UploadService, UploadQuotaService],
  exports:     [UploadService],
})
export class UploadModule {}