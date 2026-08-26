import { NestFactory } from '@nestjs/core';
import { AppModule }   from './app.module';
import { ValidationPipe } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { ConfigService } from '@nestjs/config';
import { AllExceptionsFilter } from './common/filters/http-exception.filter';
import { SanitizeLogsInterceptor } from './common/interceptors/sanitize-logs.interceptor';
import { NestExpressApplication } from '@nestjs/platform-express';

async function bootstrap() {
  const app = await NestFactory.create<NestExpressApplication>(AppModule);
  const config = app.get(ConfigService);

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

  // 🛡️ Rate Limiting global (anti-brute force)
  // ThrottlerGuard est automatiquement appliqué via la configuration du module

  // 🔒 Log Sanitization (remove sensitive data from responses)
  app.useGlobalInterceptors(new SanitizeLogsInterceptor());

  // CORS - Stricte en prod, permissif en dev
  app.enableCors({
    origin: config.get<string>('NODE_ENV') === 'production'
      ? [
          config.get<string>('FRONTEND_WEB_URL') ?? 'http://localhost:3002',
          'http://localhost:3001', // API
        ]
      : true, // Accepte toutes les origines en développement
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    credentials: true,
    allowedHeaders: ['Content-Type', 'Authorization'],
  });

// Dans bootstrap(), après useGlobalPipes :
app.useGlobalFilters(new AllExceptionsFilter());

  // Swagger — doc auto sur /api/docs (désactivé en production)
  if (process.env.NODE_ENV !== 'production') {
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
bootstrap();