// src/app.module.ts
import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ThrottlerModule, ThrottlerGuard } from '@nestjs/throttler';
import { AuthModule } from './modules/auth/auth.module';
import { CartModule } from './modules/cart/cart.module';
import { CategoriesModule } from './modules/categories/categories.module';
import { ChatModule } from './modules/chat/chat.module';
import { CouponsModule } from './modules/coupons/coupons.module';
import { DashboardModule } from './modules/dashboard/dashboard.module';
import { DeliveryAgentsModule } from './modules/delivery-agents/delivery-agents.module';
import { DeliveryModule } from './modules/delivery/delivery.module';
import { DeliveryZonesModule } from './modules/delivery-zones/delivery-zones.module';
import { FournisseursModule } from './modules/fournisseurs/fournisseurs.module';
import { NotificationsModule } from './modules/notifications/notifications.module';
import { OrdersModule } from './modules/orders/orders.module';
import { PartnersModule } from './modules/partners/partners.module';
import { PaymentsModule } from './modules/payments/payments.module';
import { ProductsModule } from './modules/products/products.module';
import { ReviewsModule } from './modules/reviews/reviews.module';
import { UsersModule } from './modules/users/users.module';
import { VendorsModule } from './modules/vendors/vendors.module';
import { WishlistModule } from './modules/wishlist/wishlist.module';
import { MailModule } from './modules/mail/mail.module';
import { UploadModule } from './modules/upload/upload.module';
import { ScheduleModule } from '@nestjs/schedule';
import { ActivityLogsModule } from './modules/activity-logs/activity-logs.module';
import { VendorWithdrawalsModule } from './modules/vendor-withdrawals/vendor-withdrawals.module';
import { VitrineModule } from './modules/vitrine/vitrine.module';
import { BannersModule } from './modules/banners/banners.module';
import { SupportTicketsModule } from './modules/support-tickets/support-tickets.module';
import { LibraryModule } from './modules/library/library.module';
import { CommonModule } from './common/common.module';
import { PresenceModule } from './modules/presence/presence.module';
import { validateEnvironment } from './config/env.validation';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath: '.env',
      // Vérification du .env au démarrage (clé de chiffrement, secrets JWT,
      // DB_SYNCHRONIZE...) : bloque en production, avertit en développement.
      validate: validateEnvironment,
    }),
    // 🛡️ Rate limiting global : 100 requêtes / minute / IP.
    // ⚠️ Cette limite globale est volontairement large (navigation
    // catalogue, images, polling du statut de paiement). Les routes
    // sensibles (login, OTP, mot de passe oublié) sont bridées beaucoup
    // plus sévèrement via @Throttle() sur AuthController.
    // ⚠️ Le ThrottlerGuard DOIT être enregistré comme APP_GUARD
    // (voir `providers` plus bas) : sans ça, ThrottlerModule.forRoot()
    // ne fait strictement rien.
    ThrottlerModule.forRoot([
      {
        ttl: 60000,
        limit: 100,
      },
    ]),
    TypeOrmModule.forRootAsync({
      imports: [ConfigModule],
      useFactory: (config: ConfigService) => {
        const isDevelopment = config.get<string>('NODE_ENV') === 'development';
        const isProduction = config.get<string>('NODE_ENV') === 'production';

        return {
          type: 'postgres',
          host: config.getOrThrow<string>('DB_HOST'),
          port: Number(config.getOrThrow<string>('DB_PORT')),
          username: config.getOrThrow<string>('DB_USER'),
          password: config.getOrThrow<string>('DB_PASSWORD'),
          database: config.getOrThrow<string>('DB_NAME'),
          entities: [__dirname + '/**/*.entity{.ts,.js}'],
          // ⚠️ JAMAIS de synchronize en production : TypeORM peut
          // supprimer des colonnes pour aligner le schéma sur les
          // entités → perte de commandes et de paiements.
          // En production, le schéma évolue UNIQUEMENT par migrations
          // (npm run typeorm:generate puis npm run typeorm:run).
          synchronize:
            !isProduction && config.get<string>('DB_SYNCHRONIZE') === 'true',
          logging:
            config.get<string>('DB_LOGGING') === 'true' || isDevelopment,
          // Supabase / Postgres managé exige TLS en production.
          // ⚠️ rejectUnauthorized:false accepte un certificat non vérifié :
          // c'est ce qu'exigent la plupart des hébergeurs managés (Supabase,
          // Render, Railway) qui présentent un certificat auto-signé, mais ça
          // n'empêche pas un MITM actif. Si votre hébergeur fournit le
          // certificat racine, poser DB_SSL_CA dans .env pour le vérifier.
          ssl: isProduction
            ? {
                rejectUnauthorized: !!config.get<string>('DB_SSL_CA'),
                ca: config.get<string>('DB_SSL_CA'),
              }
            : false,
        };
      },
      inject: [ConfigService],
    }),
    // ⚠️ CommonModule est @Global : importé une fois ici, ses providers
    // (ActivityLogService, EncryptionService, TokenBlacklistService) sont
    // résolvables dans tous les modules — nécessaire pour JwtAuthGuard.
    CommonModule,
    AuthModule,
    UsersModule,
    ProductsModule,
    CategoriesModule,
    CartModule,
    OrdersModule,
    PaymentsModule,
    DeliveryModule,
    DeliveryZonesModule,
    ReviewsModule,
    CouponsModule,
    NotificationsModule,
    DashboardModule,
    DeliveryAgentsModule,
    PartnersModule,
    FournisseursModule,
    VendorsModule,
    WishlistModule,
    ChatModule,
    MailModule,
    UploadModule,
    ScheduleModule.forRoot(),     // ⚠️ activer le système de cron
    ActivityLogsModule,
    VendorWithdrawalsModule,
    VitrineModule,
    BannersModule,
    SupportTicketsModule,
    LibraryModule,
    PresenceModule,
  ],
  providers: [
    // 🛡️ Applique le rate limiting à TOUTES les routes.
    // Sans cet APP_GUARD, ThrottlerModule.forRoot() est inopérant.
    {
      provide: APP_GUARD,
      useClass: ThrottlerGuard,
    },
  ],
})
export class AppModule {}
