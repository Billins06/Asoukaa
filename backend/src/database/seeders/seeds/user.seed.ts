import { DataSource } from 'typeorm';
import * as bcrypt from 'bcrypt';
import { User } from 'src/modules/users/entities/user.entity';
import { UserRole, UserRoleEnum } from 'src/modules/users/entities/user-role.entity';

export async function seedUsers(dataSource: DataSource) {
  const userRepo = dataSource.getRepository(User);
  const roleRepo = dataSource.getRepository(UserRole);

  const count = await userRepo.count();
  if (count > 0) {
    console.log('✅ Users already seeded, skipping...');
    return;
  }

  const passwordHash = await bcrypt.hash('User1234!', 12);

  // Regular customers
  const customers = [
    { prenom: 'Alice', name: 'Dupont', email: 'alice@test.com', phone: '+22501234567' },
    { prenom: 'Bob', name: 'Martin', email: 'bob@test.com', phone: '+22501234568' },
    { prenom: 'Carol', name: 'Durand', email: 'carol@test.com', phone: '+22501234569' },
    { prenom: 'David', name: 'Moreau', email: 'david@test.com', phone: '+22501234570' },
    { prenom: 'Emma', name: 'Leblanc', email: 'emma@test.com', phone: '+22501234571' },
  ];

  // Vendors
  const vendors = [
    { prenom: 'Vendor', name: 'One', email: 'vendor1@test.com', phone: '+22501235001' },
    { prenom: 'Vendor', name: 'Two', email: 'vendor2@test.com', phone: '+22501235002' },
    { prenom: 'Vendor', name: 'Three', email: 'vendor3@test.com', phone: '+22501235003' },
  ];

  const allUsers = [...customers, ...vendors];

  const users = await userRepo.save(
    allUsers.map(u => userRepo.create({
      ...u,
      passwordHash,
      isVerified: true,
      isActive: true,
    }))
  );

  // Assign roles
  const roles = [
    ...customers.map((_, i) => ({ userId: users[i].id, role: UserRoleEnum.CLIENT })),
    ...vendors.map((_, i) => ({ userId: users[customers.length + i].id, role: UserRoleEnum.VENDOR })),
  ];

  await roleRepo.insert(roles);

  console.log(`✅ Seeded ${users.length} users (${customers.length} customers + ${vendors.length} vendors)`);
  console.log('   Customer credentials: email + password: User1234!');
  console.log('   Vendor credentials: email + password: User1234!');
}

