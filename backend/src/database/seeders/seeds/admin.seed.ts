import { DataSource } from 'typeorm';
import * as bcrypt from 'bcrypt';
import { AdminAccount, AdminRole } from 'src/modules/auth/entities/admin-account.entity';

export async function seedAdmins(dataSource: DataSource) {
  const adminRepo = dataSource.getRepository(AdminAccount);

  const count = await adminRepo.count();
  if (count > 0) {
    console.log('✅ Admins already seeded, skipping...');
    return;
  }

  const adminPassword = await bcrypt.hash('Admin1234!', 12);

  const admin1 = new AdminAccount();
  admin1.email = 'superadmin@asoukaa.com';
  admin1.prenom = 'Super';
  admin1.name = 'Admin';
  admin1.role = AdminRole.SUPERADMIN;
  admin1.passwordHash = adminPassword;
  admin1.isPasswordSet = true;
  admin1.isActive = true;

  const admin2 = new AdminAccount();
  admin2.email = 'admin@asoukaa.com';
  admin2.prenom = 'Admin';
  admin2.name = 'Support';
  admin2.role = AdminRole.ADMIN;
  admin2.passwordHash = adminPassword;
  admin2.isPasswordSet = true;
  admin2.isActive = true;

  const admin3 = new AdminAccount();
  admin3.email = 'manager@asoukaa.com';
  admin3.prenom = 'Manager';
  admin3.name = 'Operations';
  admin3.role = AdminRole.ADMIN;
  admin3.passwordHash = adminPassword;
  admin3.isPasswordSet = true;
  admin3.isActive = true;

  await adminRepo.save([admin1, admin2, admin3]);
  console.log(`✅ Seeded 3 admin accounts`);
  console.log('   Credentials: email + password: Admin1234!');
}
