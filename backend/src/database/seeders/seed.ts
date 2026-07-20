import { DataSource } from 'typeorm';
import { seedAdmins } from './seeds/admin.seed';
import { seedUsers } from './seeds/user.seed';
import { seedVendorProfiles } from './seeds/vendor-profile.seed';
import { seedCategories } from './seeds/category.seed';
import { seedProducts } from './seeds/product.seed';
import { seedOrders } from './seeds/order.seed';

export async function runAllSeeds(dataSource: DataSource) {
  console.log('🌱 Starting database seeding (Admin + Base data)...\n');

  try {
    // Backend admin data
    await seedAdmins(dataSource);

    // Base data
    await seedCategories(dataSource);

    // Test users for admin dashboard
    await seedUsers(dataSource);
    await seedVendorProfiles(dataSource);
    await seedProducts(dataSource);
    await seedOrders(dataSource);

    console.log('\n✅ Base seeding completed successfully!');
    console.log('💡 Tip: Run "npm run seed:client" to add client test data\n');
  } catch (error) {
    console.error('❌ Seeding failed:', error);
    process.exit(1);
  }
}
