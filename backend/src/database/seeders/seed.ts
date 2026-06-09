// src/database/seeders/seed.ts

import { DataSource } from 'typeorm';
import { config } from 'dotenv';
import * as bcrypt from 'bcrypt';

// Entities
import { User } from '../../modules/users/entities/user.entity';
import { UserRole, UserRoleEnum } from '../../modules/users/entities/user-role.entity';
import { Address } from '../../modules/users/entities/address.entity';
import { VendorProfile } from '../../modules/users/entities/vendor-profile.entity';
import { DeliveryAgentProfile } from '../../modules/users/entities/delivery-agent-profile.entity';
import { AdminAccount, AdminRole } from '../../modules/auth/entities/admin-account.entity';

config(); // charge le .env

// ─── Config DataSource ─────────────────────────────────────────────────────
const AppDataSource = new DataSource({
  type: 'postgres',
  url: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
  entities: [
    User,
    UserRole,
    Address,
    VendorProfile,
    DeliveryAgentProfile,
    AdminAccount,
  ],
  synchronize: false,
});

// ─── Données des utilisateurs ─────────────────────────────────────────────
const DEFAULT_PASSWORD = 'Azerty1234@';

const USERS_DATA = [
  {
    prenom: 'Jean',
    name: 'Client',
    email: 'client@asoukaa.com',
    phone: '+22961000001',
    role: UserRoleEnum.CLIENT,
  },
  {
    prenom: 'Marie',
    name: 'Vendeur',
    email: 'vendeur@asoukaa.com',
    phone: '+22961000002',
    role: UserRoleEnum.VENDOR,
  },
  {
    prenom: 'Paul',
    name: 'Livreur',
    email: 'livreur@asoukaa.com',
    phone: '+22961000003',
    role: UserRoleEnum.DELIVERY_AGENT,
  },
];

// ─── Fonction principale ───────────────────────────────────────────────────
async function seed() {
  console.log('🌱 Démarrage du seeder Asoukaa...\n');

  await AppDataSource.initialize();
  console.log('✅ Connexion Supabase établie\n');

  const userRepo = AppDataSource.getRepository(User);
  const userRoleRepo = AppDataSource.getRepository(UserRole);
  const vendorRepo = AppDataSource.getRepository(VendorProfile);
  const agentRepo = AppDataSource.getRepository(DeliveryAgentProfile);
  const adminRepo = AppDataSource.getRepository(AdminAccount);

  const passwordHash = await bcrypt.hash(DEFAULT_PASSWORD, 12);

  // ─── 1. CLIENT ────────────────────────────────────────────────────────────
  console.log('👤 Création du client...');
  const clientData = USERS_DATA[0];

  const existingClient = await userRepo.findOne({ where: { email: clientData.email } });
  if (!existingClient) {
    const client = userRepo.create({
      prenom: clientData.prenom,
      name: clientData.name,
      email: clientData.email,
      phone: clientData.phone,
      passwordHash,
      isVerified: true,  // ✅ compte activé
      isActive: true,
    });
    const savedClient = await userRepo.save(client);

    await userRoleRepo.save(
      userRoleRepo.create({
        userId: savedClient.id,
        role: UserRoleEnum.CLIENT,
        isActive: true,
      }),
    );
    console.log(`   ✅ Client créé : ${clientData.email}`);
  } else {
    console.log(`   ⚠️  Client déjà existant : ${clientData.email}`);
  }

  // ─── 2. VENDEUR ───────────────────────────────────────────────────────────
  console.log('🏪 Création du vendeur...');
  const vendorData = USERS_DATA[1];

  const existingVendor = await userRepo.findOne({ where: { email: vendorData.email } });
  if (!existingVendor) {
    const vendor = userRepo.create({
      prenom: vendorData.prenom,
      name: vendorData.name,
      email: vendorData.email,
      phone: vendorData.phone,
      passwordHash,
      isVerified: true,
      isActive: true,
    });
    const savedVendor = await userRepo.save(vendor);

    // Rôle client de base
    await userRoleRepo.save(
      userRoleRepo.create({
        userId: savedVendor.id,
        role: UserRoleEnum.CLIENT,
        isActive: true,
      }),
    );

    // Rôle vendeur
    await userRoleRepo.save(
      userRoleRepo.create({
        userId: savedVendor.id,
        role: UserRoleEnum.VENDOR,
        isActive: true,
      }),
    );

    // Profil vendeur — status approuvé directement
    await vendorRepo.save({
      userId: savedVendor.id,
      shopName: 'Boutique Marie',
      shopAddress: 'Cotonou, Bénin',
      activityType: 'Vêtements & Mode',
      description: 'Boutique de mode féminine au Bénin',
      idDocumentUrl: 'https://placeholder.com/id-document.jpg',
      selfieUrl: 'https://placeholder.com/selfie.jpg',
      sampleProductUrls: ['https://placeholder.com/product1.jpg', 'https://placeholder.com/product2.jpg'],
      status: 'approuvé',           // ✅ validé directement
      termsAccepted: true,
      fraudPenaltiesAccepted: true,
      submissionCount: 1,
      submittedAt: new Date(),
      reviewedAt: new Date(),
      paymentMethod: 'mobile_money',
      paymentDetails: {
        operateur: 'MTN',
        numero: '+22961000002',
        titulaire: 'Marie Vendeur',
      },
    } as any);

    console.log(`   ✅ Vendeur créé : ${vendorData.email}`);
  } else {
    console.log(`   ⚠️  Vendeur déjà existant : ${vendorData.email}`);
  }

  // ─── 3. LIVREUR ───────────────────────────────────────────────────────────
  console.log('🚚 Création du livreur...');
  const agentData = USERS_DATA[2];

  const existingAgent = await userRepo.findOne({ where: { email: agentData.email } });
  if (!existingAgent) {
    const agent = userRepo.create({
      prenom: agentData.prenom,
      name: agentData.name,
      email: agentData.email,
      phone: agentData.phone,
      passwordHash,
      isVerified: true,
      isActive: true,
    });
    const savedAgent = await userRepo.save(agent);

    // Rôle client de base
    await userRoleRepo.save(
      userRoleRepo.create({
        userId: savedAgent.id,
        role: UserRoleEnum.CLIENT,
        isActive: true,
      }),
    );

    // Rôle livreur
    await userRoleRepo.save(
      userRoleRepo.create({
        userId: savedAgent.id,
        role: UserRoleEnum.DELIVERY_AGENT,
        isActive: true,
      }),
    );

    // Profil livreur — status approuvé directement
    await agentRepo.save({
      userId: savedAgent.id,
      vehicleType: 'moto',
      availability: 'Temps_plein',
      isAvailableNow: true,
      ville: 'Cotonou',
      quartier: 'Akpakpa',
      preciseAddress: 'Rue 10, Akpakpa, Cotonou',
      idDocumentUrl: 'https://placeholder.com/id-document.jpg',
      selfieUrl: 'https://placeholder.com/selfie.jpg',
      vehiclePhotoUrl: 'https://placeholder.com/vehicle.jpg',
      licensePlate: 'BJ-1234-AB',
      status: 'approuvé',           // ✅ validé directement
      termsAccepted: true,
      fraudPenaltiesAccepted: true,
      noteMoyenne: 5.00,
      tauxDeReussite: 100.00,
      totalLivraisons: 0,
      reviewedAt: new Date(),
    } as any);

    console.log(`   ✅ Livreur créé : ${agentData.email}`);
  } else {
    console.log(`   ⚠️  Livreur déjà existant : ${agentData.email}`);
  }

  // ─── 4. ADMIN ─────────────────────────────────────────────────────────────
  console.log('🔐 Création de l\'admin...');
  const existingAdmin = await adminRepo.findOne({
    where: { email: 'admin@asoukaa.com' },
  });

  if (!existingAdmin) {
    await adminRepo.save(
      adminRepo.create({
        prenom: 'Admin',
        name: 'Asoukaa',
        email: 'admin@asoukaa.com',
        passwordHash,
        role: AdminRole.ADMIN,
        isActive: true,
        isPasswordSet: true,          // ✅ mot de passe déjà défini
        invitationToken: null,
        invitationExpiresAt: null,
      }),
    );
    console.log('   ✅ Admin créé : admin@asoukaa.com');
  } else {
    console.log('   ⚠️  Admin déjà existant : admin@asoukaa.com');
  }

  // ─── 5. SUPERADMIN ────────────────────────────────────────────────────────
  console.log('👑 Création du superadmin...');
  const existingSuperAdmin = await adminRepo.findOne({
    where: { email: 'superadmin@asoukaa.com' },
  });

  if (!existingSuperAdmin) {
    await adminRepo.save(
      adminRepo.create({
        prenom: 'Super',
        name: 'Admin',
        email: 'superadmin@asoukaa.com',
        passwordHash,
        role: AdminRole.SUPERADMIN,
        isActive: true,
        isPasswordSet: true,          // ✅ mot de passe déjà défini
        invitationToken: null,
        invitationExpiresAt: null,
      }),
    );
    console.log('   ✅ SuperAdmin créé : superadmin@asoukaa.com');
  } else {
    console.log('   ⚠️  SuperAdmin déjà existant : superadmin@asoukaa.com');
  }

  // ─── Résumé final ─────────────────────────────────────────────────────────
  console.log('\n✅ Seeder terminé avec succès !\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('📋 Comptes créés (mot de passe : Azerty1234@)');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('👤 Client       → client@asoukaa.com');
  console.log('🏪 Vendeur      → vendeur@asoukaa.com');
  console.log('🚚 Livreur      → livreur@asoukaa.com');
  console.log('🔐 Admin        → admin@asoukaa.com');
  console.log('👑 SuperAdmin   → superadmin@asoukaa.com');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  await AppDataSource.destroy();
}

seed().catch((err) => {
  console.error('❌ Erreur seeder :', err);
  process.exit(1);
});