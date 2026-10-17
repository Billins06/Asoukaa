import { AppDataSource } from './data-source';
import { seedCategories } from './seeders/seeds/category.seed';

// Exécute UNIQUEMENT le seeder de catégories (npm run seed:categories).
// Sans risque à relancer : aucun doublon, aucune catégorie existante modifiée.
async function bootstrap() {
  try {
    if (!AppDataSource.isInitialized) {
      await AppDataSource.initialize();
    }

    console.log('🌱 Seeding des catégories uniquement...\n');
    await seedCategories(AppDataSource);
    await AppDataSource.destroy();
    console.log('✅ Seed-categories-runner completed and disconnected');
  } catch (error) {
    console.error('❌ Seed-categories-runner failed:', error);
    if (AppDataSource.isInitialized) {
      await AppDataSource.destroy();
    }
    process.exit(1);
  }
}

bootstrap();
