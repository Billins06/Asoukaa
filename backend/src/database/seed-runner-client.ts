import { AppDataSource } from './data-source';
import { seedClientData } from './seeders/seeds/client-data.seed';

async function bootstrap() {
  try {
    if (!AppDataSource.isInitialized) {
      await AppDataSource.initialize();
    }

    await seedClientData(AppDataSource);
    await AppDataSource.destroy();
    console.log('✅ Client seed-runner completed and disconnected');
  } catch (error) {
    console.error('❌ Client seed-runner failed:', error);
    process.exit(1);
  }
}

bootstrap();
