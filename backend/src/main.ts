import { NestFactory } from '@nestjs/core';
import { AppModule }   from './app.module';
import { LogLevel, ValidationPipe } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { ConfigService } from '@nestjs/config';
import { AllExceptionsFilter } from './common/filters/http-exception.filter';
import { NestExpressApplication } from '@nestjs/platform-express';
import helmet from 'helmet';
import compression from 'compression';
import { join } from 'path';

async function bootstrap() {
  // 🔒 En production : pas de niveau « debug » (il imprimait les réponses brutes
  // de FeexPay : numéros de téléphone, références de transaction). En
  // développement : comportement inchangé (tous les niveaux).
  const productionLevels: LogLevel[] = ['log', 'warn', 'error'];
  const app = await NestFactory.create<NestExpressApplication>(
    AppModule,
    process.env.NODE_ENV === 'production' ? { logger: productionLevels } : {},
  );
  const config = app.get(ConfigService);
  const isProduction = config.get<string>('NODE_ENV') === 'production';
  // NODE_ENV défini seulement dans le fichier .env (pas dans l'environnement du
  // processus) : on applique quand même les niveaux de production.
  if (isProduction && process.env.NODE_ENV !== 'production') {
    app.useLogger(productionLevels);
  }

  // ⚠️ Indispensable derrière un reverse proxy (Nginx, Render, Railway...).
  // Sans ça, Express ignore X-Forwarded-For et :
  //   - req.ip vaut l'IP du proxy → le rate limiting bride TOUT LE MONDE
  //     ensemble au lieu de brider par client ;
  //   - les helpers getIp() des contrôleurs lisent un en-tête que le client
  //     contrôle entièrement → IP falsifiables dans les logs d'audit.
  // `1` = on ne fait confiance qu'au premier proxy devant l'app.
  app.set('trust proxy', 1);

  // 🔒 En-têtes de sécurité HTTP (HSTS, X-Frame-Options, nosniff...)
  // CSP désactivée hors production : elle casse l'UI de Swagger.
  app.use(
    helmet({
      contentSecurityPolicy: isProduction ? undefined : false,
      crossOriginResourcePolicy: { policy: 'cross-origin' },
    }),
  );

  // 📦 Compression gzip des réponses JSON (les listes produits/commandes
  // avec leurs relations pèsent lourd sur une connexion mobile).
  app.use(compression());

  // Préfixe global : /api/v1/...
  app.setGlobalPrefix('api/v1');

  // Validation globale (class-validator)
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,          // supprime les champs non déclarés dans les DTOs
      forbidNonWhitelisted: true,
      transform: true,          // transforme les types automatiquement
    }),
  );

  // 🛡️ Rate Limiting global : assuré par le ThrottlerGuard enregistré comme
  // APP_GUARD dans AppModule. ⚠️ ThrottlerModule.forRoot() seul ne bride
  // rien — c'est l'APP_GUARD qui applique la limite.

  // 🔒 SanitizeLogsInterceptor RETIRÉ : il faisait un JSON.parse(JSON.stringify())
  // — un clone profond de CHAQUE réponse de l'API — puis parcourait
  // récursivement la copie pour la jeter (le console.log était commenté).
  // Double sérialisation par requête pour rien, et une TypeError garantie
  // sur toute réponse contenant une référence circulaire.
  // Les champs sensibles sont déjà retirés à la source dans les services
  // (destructuration de passwordHash / invitationToken).

  // CORS - Stricte en prod, permissif en dev
  app.enableCors({
    origin: isProduction
      ? [
          config.get<string>('FRONTEND_WEB_URL'),
          // autres sites autorisés (ex. version web de l'appli), séparés par des virgules
          ...(config.get<string>('CORS_EXTRA_ORIGINS') ?? '').split(','),
        ]
          .map((o) => (o ?? '').trim().replace(/\/+$/, ''))
          .filter((o) => !!o)
      : true, // Accepte toutes les origines en développement
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    credentials: true,
    allowedHeaders: ['Content-Type', 'Authorization'],
  });

  // 📁 Repli stockage local (dev) : quand STORAGE_DRIVER=local (voir
  // upload.service.ts), les fichiers "publics" (produits, boutique,
  // avatars, véhicules, chat) sont servis directement en statique sous
  // /uploads/... — comme le ferait l'URL publique Supabase. Les fichiers
  // privés (documents/selfies) NE sont PAS ici : ils passent par la route
  // authentifiée GET /api/v1/upload/file/:type/:filename.
  if (config.get<string>('STORAGE_DRIVER') === 'local') {
    const uploadsRoot = join(process.cwd(), 'uploads');
    // 'proofs' (photos de preuve de livraison) manquait ici : les URLs
    // publiques étaient bien générées par upload.service.ts, mais
    // aucune route statique ne les servait -> 404 systématique à
    // l'affichage (aperçu photo livreur, etc.).
    // 'vitrine' et 'categories' : images du back-office (rayons/bandeau de
    // la vitrine, catégories), publiques comme les images produits.
    for (const publicType of ['avatars', 'shop', 'products', 'product-videos', 'vehicles', 'chat', 'proofs', 'vitrine', 'categories', 'tickets']) {
      app.useStaticAssets(join(uploadsRoot, publicType), { prefix: `/uploads/${publicType}/` });
    }
  }

  app.useGlobalFilters(new AllExceptionsFilter());

  // Swagger — doc auto sur /api/docs (désactivé en production)
  if (!isProduction) {
    const swaggerConfig = new DocumentBuilder()
      .setTitle('Asoukaa API')
      .setDescription('Documentation de l\'API e-commerce Asoukaa')
      .setVersion('1.0')
      .addBearerAuth()
      .build();
    const document = SwaggerModule.createDocument(app, swaggerConfig);
    SwaggerModule.setup('api/docs', app, document);
  }

  const port = config.get<number>('PORT') ?? config.get<number>('APP_PORT') ?? 3000;
  await app.listen(port);
  console.log(`🚀 Asoukaa API lancée sur http://localhost:${port}/api/v1`);
  console.log(`📚 Swagger dispo sur  http://localhost:${port}/api/docs`);
}
void bootstrap();