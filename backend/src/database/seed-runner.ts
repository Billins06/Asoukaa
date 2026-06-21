import { AppDataSource } from './data-source';
import { runAllSeeds } from './seeders/seed';

async function bootstrap() {
  try {
    if (!AppDataSource.isInitialized) {
      await AppDataSource.initialize();
    }

    await runAllSeeds(AppDataSource);
    await AppDataSource.destroy();
    console.log('✅ Seed-runner completed and disconnected');
  } catch (error) {
    console.error('❌ Seed-runner failed:', error);
    process.exit(1);
  }
}

bootstrap();
