import { DataSource } from 'typeorm';
import { Product, ProductStatus } from 'src/modules/products/entities/product.entity';
import { VendorProfile } from 'src/modules/users/entities/vendor-profile.entity';
import { Category } from 'src/modules/categories/entities/category.entity';

export async function seedProducts(dataSource: DataSource) {
  const productRepo = dataSource.getRepository(Product);
  const vendorRepo = dataSource.getRepository(VendorProfile);
  const categoryRepo = dataSource.getRepository(Category);

  const count = await productRepo.count();
  if (count > 0) {
    console.log('✅ Products already seeded, skipping...');
    return;
  }

  const vendors = await vendorRepo.find({ take: 3 });
  if (vendors.length === 0) {
    console.log('⚠️  No vendor profiles found, skipping products...');
    return;
  }

  const categories = await categoryRepo.find({ take: 8 });

  const productTemplates = [
    { name: 'Laptop Pro 15', basePrice: 1299.99, category: categories[0], desc: 'High performance laptop' },
    { name: 'Smartphone X', basePrice: 899.99, category: categories[0], desc: 'Latest smartphone model' },
    { name: 'T-Shirt Cotton', basePrice: 29.99, category: categories[1], desc: 'Comfortable cotton t-shirt' },
    { name: 'Jeans Classic', basePrice: 79.99, category: categories[1], desc: 'Classic style jeans' },
    { name: 'Coffee Maker', basePrice: 59.99, category: categories[2], desc: 'Modern coffee maker' },
    { name: 'Wall Clock', basePrice: 39.99, category: categories[2], desc: 'Elegant wall clock' },
    { name: 'Face Cream', basePrice: 49.99, category: categories[3], desc: 'Moisturizing face cream' },
    { name: 'Yoga Mat', basePrice: 39.99, category: categories[4], desc: 'Premium yoga mat' },
    { name: 'Organic Coffee', basePrice: 12.99, category: categories[5], desc: 'Organic coffee beans' },
    { name: 'JavaScript Book', basePrice: 39.99, category: categories[6], desc: 'Learn JavaScript' },
  ];

  const products = productTemplates.flatMap((template, idx) => {
    const vendor = vendors[idx % vendors.length];
    const slug = template.name.toLowerCase().replace(/\s+/g, '-') + '-' + idx;
    
    return {
      vendorId: vendor.id,
      prod_name: template.name,
      slug,
      description: template.desc,
      basePrice: template.basePrice,
      weight: 0.5,
      dimensions: '10x10x10 cm',
      status: ProductStatus.ACTIVE,
      isVedette: idx < 3,
      categoryId: template.category.id,
    };
  });

  await productRepo.insert(products);
  console.log(`✅ Seeded ${products.length} products`);
}

