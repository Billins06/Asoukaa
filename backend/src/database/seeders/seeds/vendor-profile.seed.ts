import { DataSource } from 'typeorm';
import { VendorProfile, VendorStatus, PaymentMethod } from 'src/modules/users/entities/vendor-profile.entity';
import { User } from 'src/modules/users/entities/user.entity';

export async function seedVendorProfiles(dataSource: DataSource) {
  const vendorProfileRepo = dataSource.getRepository(VendorProfile);
  const userRepo = dataSource.getRepository(User);

  const count = await vendorProfileRepo.count();
  if (count > 0) {
    console.log('✅ Vendor profiles already seeded, skipping...');
    return;
  }

  const vendors = await userRepo.find({
    where: [
      { email: 'vendor1@test.com' },
      { email: 'vendor2@test.com' },
      { email: 'vendor3@test.com' },
    ],
  });

  if (vendors.length === 0) {
    console.log('⚠️  No vendor users found, skipping vendor profiles...');
    return;
  }

  const profiles = vendors.map((vendor, i) => {
    const profile = new VendorProfile();
    profile.userId = vendor.id;
    profile.shopName = `Boutique ${vendor.prenom} ${i + 1}`;
    profile.shopAddress = `123 Rue du Commerce, Ville ${i + 1}`;
    profile.activityType = ['Électronique', 'Mode', 'Maison'][i];
    profile.description = `Boutique en ligne spécialisée dans ${['Électronique', 'Mode', 'Maison'][i].toLowerCase()}`;
    profile.idDocumentUrl = `https://via.placeholder.com/400x300?text=ID${i + 1}`;
    profile.selfieUrl = `https://via.placeholder.com/400x300?text=Selfie${i + 1}`;
    profile.sampleProductUrls = [
      `https://via.placeholder.com/400x300?text=Product1`,
      `https://via.placeholder.com/400x300?text=Product2`,
    ];
    profile.status = VendorStatus.APPROVED;
    profile.termsAccepted = true;
    profile.fraudPenaltiesAccepted = true;
    profile.submissionCount = 1;
    profile.submittedAt = new Date();
    profile.reviewedAt = new Date();
    profile.paymentMethod = PaymentMethod.BANK;
    return profile;
  });

  await vendorProfileRepo.save(profiles);
  console.log(`✅ Seeded ${profiles.length} vendor profiles`);
}
