import { DataSource } from 'typeorm';
import { Category } from 'src/modules/categories/entities/category.entity';

// Helper: Convert "Électronique" → "electronique"
function generateSlug(name: string): string {
  return name
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '') // Remove accents
    .replace(/[^\w\s-]/g, '') // Remove special chars
    .replace(/\s+/g, '-') // Replace spaces with hyphens
    .replace(/-+/g, '-') // Remove duplicate hyphens
    .trim();
}

export async function seedCategories(dataSource: DataSource) {
  const categoryRepo = dataSource.getRepository(Category);

  const count = await categoryRepo.count();
  if (count > 0) {
    console.log('✅ Categories already seeded, skipping...');
    return;
  }

  const categoryData = [
    { name: 'Électronique', description: 'Appareils électroniques et gadgets' },
    { name: 'Mode', description: 'Vêtements et accessoires de mode' },
    { name: 'Maison', description: 'Articles de maison et décoration' },
    { name: 'Beauté', description: 'Produits de beauté et cosmétiques' },
    { name: 'Sports', description: 'Équipements et articles de sport' },
    { name: 'Alimentation', description: 'Produits alimentaires et boissons' },
    { name: 'Livres', description: 'Livres et publications' },
    { name: 'Jouets', description: 'Jouets et jeux' },
  ];

  // Generate slug for each category
  const categories = categoryData.map(cat => ({
    name: cat.name,
    slug: generateSlug(cat.name),
    description: cat.description,
  }));

  await categoryRepo.insert(categories);
  console.log(`✅ Seeded ${categories.length} categories`);
}

