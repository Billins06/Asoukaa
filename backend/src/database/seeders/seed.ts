import { DataSource } from 'typeorm';
import { seedAdmins } from './seeds/admin.seed';
import { seedUsers } from './seeds/user.seed';
import { seedVendorProfiles } from './seeds/vendor-profile.seed';
import { seedCategories } from './seeds/category.seed';
import { seedProducts } from './seeds/product.seed';
import { seedOrders } from './seeds/order.seed';

export async function runAllSeeds(dataSource: DataSource) {
  console.log('🌱 Starting database seeding...\n');

  try {
    // Order matters - dependencies first
    await seedAdmins(dataSource);
    await seedUsers(dataSource);
    await seedVendorProfiles(dataSource);
    await seedCategories(dataSource);
    await seedProducts(dataSource);
    await seedOrders(dataSource);

    console.log('\n✅ Database seeding completed successfully!');
  } catch (error) {
    console.error('❌ Seeding failed:', error);
    process.exit(1);
  }
}
