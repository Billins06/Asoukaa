import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { MailerModule } from '@nestjs-modules/mailer';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ActivityLog } from './entities/activity-log.entity';
import { ActivityLogService } from './services/activity-log.service';
import { EncryptionService } from './services/encryption.service';
import { TokenBlacklistService } from './services/token-blacklist.service';

@Module({
  imports: [
    TypeOrmModule.forFeature([ActivityLog]),
    MailerModule.forRootAsync({
      imports: [ConfigModule],
      useFactory: (config: ConfigService) => ({
        transport: {
          host: config.getOrThrow<string>('MAIL_HOST'),
          port: Number(config.getOrThrow<string>('MAIL_PORT')),
          secure: false,
          auth: {
            user: config.getOrThrow<string>('MAIL_USER'),
            pass: config.get<string>('MAIL_PASS') ?? '',
          },
        },
        defaults: {
          from: config.getOrThrow<string>('MAIL_FROM'),
        },
      }),
      inject: [ConfigService],
    }),
  ],
  providers: [ActivityLogService, EncryptionService, TokenBlacklistService],
  exports: [ActivityLogService, EncryptionService, TokenBlacklistService, MailerModule],
})
export class CommonModule {}
