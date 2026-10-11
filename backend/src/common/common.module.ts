import { Global, Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ActivityLog } from './entities/activity-log.entity';
import { ActivityLogService } from './services/activity-log.service';
import { EncryptionService } from './services/encryption.service';
import { TokenBlacklistService } from './services/token-blacklist.service';

// ⚠️ @Global : JwtAuthGuard dépend désormais de TokenBlacklistService pour
// vérifier la révocation des tokens, et ce guard est utilisé dans les 22
// modules — dont plusieurs n'importaient pas CommonModule (cart, chat,
// dashboard, notifications, upload, wishlist...). Sans @Global, Nest ne
// peut pas résoudre la dépendance du guard dans ces modules-là.
@Global()
@Module({
  imports: [
    TypeOrmModule.forFeature([ActivityLog]),
  ],
  providers: [ActivityLogService, EncryptionService, TokenBlacklistService],
  exports: [ActivityLogService, EncryptionService, TokenBlacklistService],
})
export class CommonModule {}
