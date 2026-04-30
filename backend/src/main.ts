// src/main.ts
import { NestFactory } from '@nestjs/core';
import { AppModule }   from './app.module';
import { ValidationPipe } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { ConfigService } from '@nestjs/config';
import { AllExceptionsFilter } from './common/filters/http-exception.filter';


async function bootstrap() {
  const app = await NestFactory.create(AppModule);
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

  // CORS
  app.enableCors({
    origin: [
      config.get<string>('FRONTEND_WEB_URL') ?? 'http://localhost:3001',
    ],
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    credentials: true,
  });


// Dans bootstrap(), après useGlobalPipes :
app.useGlobalFilters(new AllExceptionsFilter());

  // Swagger — doc auto sur /api/docs
  const swaggerConfig = new DocumentBuilder()
    .setTitle('Asoukaa API')
    .setDescription('Documentation de l\'API e-commerce Asoukaa')
    .setVersion('1.0')
    .addBearerAuth()
    .build();
  const document = SwaggerModule.createDocument(app, swaggerConfig);
  SwaggerModule.setup('api/docs', app, document);

  const port = config.get<number>('APP_PORT') ?? 3000;
  await app.listen(port);
  console.log(`🚀 Asoukaa API lancée sur http://localhost:${port}/api/v1`);
  console.log(`📚 Swagger dispo sur  http://localhost:${port}/api/docs`);
}
bootstrap();