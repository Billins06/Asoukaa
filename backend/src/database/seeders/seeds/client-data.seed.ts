import { DataSource } from 'typeorm';
import * as bcrypt from 'bcrypt';
import { User } from 'src/modules/users/entities/user.entity';
import { UserRole, UserRoleEnum } from 'src/modules/users/entities/user-role.entity';
import { VendorProfile, VendorStatus } from 'src/modules/users/entities/vendor-profile.entity';
import { Product } from 'src/modules/products/entities/product.entity';
import { ProductVariant } from 'src/modules/products/entities/product-variant.entity';
import { Address } from 'src/modules/users/entities/address.entity';
import { Order, OrderStatus } from 'src/modules/orders/entities/order.entity';
import { OrderItem } from 'src/modules/orders/entities/order-item.entity';
import { Wishlist } from 'src/modules/wishlist/entities/wishlist.entity';
import { Cart } from 'src/modules/cart/entities/cart.entity';
import { CartItem } from 'src/modules/cart/entities/cart-item.entity';
import { Conversation } from 'src/modules/chat/entities/conversation.entity';
import { Message } from 'src/modules/chat/entities/message.entity';
import { Notification, NotificationType } from 'src/modules/notifications/entities/notification.entity';

export async function seedClientData(dataSource: DataSource) {
  console.log('\n🛍️  Seeding Client Test Data...\n');

  // ══════════════════════════════════════════════════════════════
  // CLEANUP: DELETE ALL OLD TEST DATA BEFORE RESEEDING
  // ══════════════════════════════════════════════════════════════
  console.log('🧹 CLEANUP: Removing all old client test data from database...\n');

  const userRepo = dataSource.getRepository(User);
  const roleRepo = dataSource.getRepository(UserRole);
  const vendorRepo = dataSource.getRepository(VendorProfile);
  const wishlistRepo = dataSource.getRepository(Wishlist);
  const conversationRepo = dataSource.getRepository(Conversation);
  const notificationRepo = dataSource.getRepository(Notification);
  const cartRepo = dataSource.getRepository(Cart);
  const orderRepo = dataSource.getRepository(Order);
  const addressRepo = dataSource.getRepository(Address);

  try {
    // Simple direct delete approach using parameterized queries
    console.log('   [1/11] Deleting messages...');
    await dataSource.query(
      `DELETE FROM messages WHERE "conversationId" IN (SELECT id FROM conversations WHERE "clientId" IN (SELECT id FROM users WHERE email IN ($1, $2, $3)))`,
      ['acheteur@test.com', 'vendeur@test.com', 'vendeur2@test.com']
    );

    console.log('   [2/11] Deleting conversations...');
    await dataSource.query(
      `DELETE FROM conversations WHERE "clientId" IN (SELECT id FROM users WHERE email IN ($1, $2, $3))`,
      ['acheteur@test.com', 'vendeur@test.com', 'vendeur2@test.com']
    );

    console.log('   [3/11] Deleting wishlist items...');
    await dataSource.query(
      `DELETE FROM wishlists WHERE "userId" IN (SELECT id FROM users WHERE email IN ($1, $2, $3))`,
      ['acheteur@test.com', 'vendeur@test.com', 'vendeur2@test.com']
    );

    console.log('   [4/11] Deleting cart items...');
    await dataSource.query(
      `DELETE FROM cart_items WHERE "cartId" IN (SELECT id FROM carts WHERE "userId" IN (SELECT id FROM users WHERE email IN ($1, $2, $3)))`,
      ['acheteur@test.com', 'vendeur@test.com', 'vendeur2@test.com']
    );

    console.log('   [5/11] Deleting carts...');
    await dataSource.query(
      `DELETE FROM carts WHERE "userId" IN (SELECT id FROM users WHERE email IN ($1, $2, $3))`,
      ['acheteur@test.com', 'vendeur@test.com', 'vendeur2@test.com']
    );

    console.log('   [6/11] Deleting order items...');
    await dataSource.query(
      `DELETE FROM order_items WHERE "orderId" IN (SELECT id FROM orders WHERE "userId" IN (SELECT id FROM users WHERE email IN ($1, $2, $3)))`,
      ['acheteur@test.com', 'vendeur@test.com', 'vendeur2@test.com']
    );

    console.log('   [7/11] Deleting orders...');
    await dataSource.query(
      `DELETE FROM orders WHERE "userId" IN (SELECT id FROM users WHERE email IN ($1, $2, $3))`,
      ['acheteur@test.com', 'vendeur@test.com', 'vendeur2@test.com']
    );

    console.log('   [8/11] Deleting addresses...');
    await dataSource.query(
      `DELETE FROM addresses WHERE "userId" IN (SELECT id FROM users WHERE email IN ($1, $2, $3))`,
      ['acheteur@test.com', 'vendeur@test.com', 'vendeur2@test.com']
    );

    console.log('   [9/11] Deleting notifications...');
    await dataSource.query(
      `DELETE FROM notifications WHERE "userId" IN (SELECT id FROM users WHERE email IN ($1, $2, $3))`,
      ['acheteur@test.com', 'vendeur@test.com', 'vendeur2@test.com']
    );

    console.log('   [10/11] Deleting products & variants...');
    await dataSource.query(
      `DELETE FROM product_variants WHERE "productId" IN (SELECT id FROM products WHERE "vendorId" IN (SELECT id FROM vendor_profiles WHERE "userId" IN (SELECT id FROM users WHERE email IN ($1, $2, $3))))`,[
        'acheteur@test.com', 'vendeur@test.com', 'vendeur2@test.com'
      ]
    );

    await dataSource.query(
      `DELETE FROM products WHERE "vendorId" IN (SELECT id FROM vendor_profiles WHERE "userId" IN (SELECT id FROM users WHERE email IN ($1, $2, $3)))`,
      ['acheteur@test.com', 'vendeur@test.com', 'vendeur2@test.com']
    );

    console.log('   [11/11] Deleting user roles & vendor profiles...');
    await dataSource.query(
      `DELETE FROM user_roles WHERE "userId" IN (SELECT id FROM users WHERE email IN ($1, $2, $3))`,
      ['acheteur@test.com', 'vendeur@test.com', 'vendeur2@test.com']
    );

    await dataSource.query(
      `DELETE FROM vendor_profiles WHERE "userId" IN (SELECT id FROM users WHERE email IN ($1, $2, $3))`,
      ['acheteur@test.com', 'vendeur@test.com', 'vendeur2@test.com']
    );

    console.log('   [FINAL] Deleting users...');
    await dataSource.query(
      `DELETE FROM users WHERE email IN ($1, $2, $3)`,
      ['acheteur@test.com', 'vendeur@test.com', 'vendeur2@test.com']
    );

    console.log('   ✅ All old test data removed\n');

  } catch (error) {
    console.log('   ❌ Cleanup error:', (error as any).message);
    throw error;
  }

  console.log('🌱 Now seeding fresh test data...\n');

  // Setup repositories
  const productRepo = dataSource.getRepository(Product);
  const variantRepo = dataSource.getRepository(ProductVariant);
  const orderItemRepo = dataSource.getRepository(OrderItem);
  const cartItemRepo = dataSource.getRepository(CartItem);
  const messageRepo = dataSource.getRepository(Message);

  // ─── 1. Users ───────────────────────────────────
  console.log('👤 1️⃣ Creating users...');

  const buyerPassword = await bcrypt.hash('Test1234!', 12);
  const vendorPassword = await bcrypt.hash('Test1234!', 12);

  // Generate unique phone numbers to avoid conflicts
  const timestamp = Date.now().toString().slice(-5);
  const buyerPhone = `+2296${timestamp}01`;
  const vendorPhone = `+2296${timestamp}02`;
  const vendor2Phone = `+2296${timestamp}03`;

  // Create Buyer
  const buyer = userRepo.create({
    email: 'acheteur@test.com',
    phone: buyerPhone,
    prenom: 'Kofi',
    name: 'Mensah',
    passwordHash: buyerPassword,
    isVerified: true,
    isActive: true,
  });
  const savedBuyer = await userRepo.save(buyer);

  const buyerRole = roleRepo.create({
    userId: savedBuyer.id,
    role: UserRoleEnum.CLIENT,
  });
  await roleRepo.save(buyerRole);

  // Create Vendor 1 (Approved)
  const vendor = userRepo.create({
    email: 'vendeur@test.com',
    phone: vendorPhone,
    prenom: 'Aminata',
    name: 'Sow',
    passwordHash: vendorPassword,
    isVerified: true,
    isActive: true,
  });
  const savedVendor = await userRepo.save(vendor);

  const vendorRole = roleRepo.create({
    userId: savedVendor.id,
    role: UserRoleEnum.VENDOR,
  });
  await roleRepo.save(vendorRole);

  // Create Vendor 2 (Pending Approval)
  const vendor2 = userRepo.create({
    email: 'vendeur2@test.com',
    phone: vendor2Phone,
    prenom: 'Ibrahim',
    name: 'Diallo',
    passwordHash: vendorPassword,
    isVerified: true,
    isActive: true,
  });
  const savedVendor2 = await userRepo.save(vendor2);

  const vendor2Role = roleRepo.create({
    userId: savedVendor2.id,
    role: UserRoleEnum.VENDOR,
  });
  await roleRepo.save(vendor2Role);

  console.log(`   ✅ Created: acheteur@test.com | vendeur@test.com | vendeur2@test.com`);

  // ─── 2. Vendor Shop ─────────────────────────────
  console.log('🏪 2️⃣ Creating shops...');

  // Shop 1: Boutique Eleganza (APPROVED)
  const shop = vendorRepo.create({
    userId: savedVendor.id,
    shopName: 'Boutique Eleganza',
    shopAddress: 'Cotonou, Bénin',
    activityType: 'Mode & Vêtements',
    description: 'Mode et accessoires authentiques - Wax, tissus traditionnels',
    idDocumentUrl: 'https://via.placeholder.com/400x300?text=ID',
    selfieUrl: 'https://via.placeholder.com/400x300?text=Vendor',
    sampleProductUrls: ['https://via.placeholder.com/400x300?text=Product1'],
    status: VendorStatus.APPROVED,
    termsAccepted: true,
    fraudPenaltiesAccepted: true,
    submissionCount: 1,
    submittedAt: new Date(),
    reviewedAt: new Date(),
  });
  const savedShop = await vendorRepo.save(shop);

  // Shop 2: Tech Store Premium (PENDING - awaiting admin approval)
  const shop2 = vendorRepo.create({
    userId: savedVendor2.id,
    shopName: 'Tech Store Premium',
    shopAddress: 'Porto-Novo, Bénin',
    activityType: 'Électronique & Gadgets',
    description: 'Électronique de qualité, gadgets innovants et accessoires tech',
    idDocumentUrl: 'https://via.placeholder.com/400x300?text=ID2',
    selfieUrl: 'https://via.placeholder.com/400x300?text=Vendor2',
    sampleProductUrls: ['https://via.placeholder.com/400x300?text=Product2'],
    status: VendorStatus.PENDING,
    termsAccepted: true,
    fraudPenaltiesAccepted: true,
    submissionCount: 1,
    submittedAt: new Date(),
  });
  await vendorRepo.save(shop2);

  console.log('   ✅ Created: Boutique Eleganza (APPROVED) | Tech Store Premium (PENDING)');

  // ─── 3. Products + Variants ─────────────────────
  console.log('📦 3️⃣ Creating 8 products with variants...');

  const productsData = [
    {
      name: 'Robe Wax Ankara',
      description: 'Belle robe en tissu wax 100% coton authentique avec motifs colorés',
      basePrice: 15000,
      originalPrice: 20000,
      image: 'https://via.placeholder.com/400x300?text=Robe+Wax',
      isFeatured: true,
    },
    {
      name: 'Tissu Wax Pagne',
      description: 'Pagne traditionnel coloré - 6 mètres de tissu premium',
      basePrice: 8000,
      originalPrice: 10000,
      image: 'https://via.placeholder.com/400x300?text=Pagne',
      isFeatured: true,
    },
    {
      name: 'Bracelet Doré',
      description: 'Bracelet doré avec motifs traditionnels africains',
      basePrice: 5000,
      originalPrice: 7000,
      image: 'https://via.placeholder.com/400x300?text=Bracelet',
      isFeatured: true,
    },
    {
      name: 'Foulard Silk',
      description: 'Foulard en soie multicolore - accessoire élégant',
      basePrice: 3500,
      originalPrice: 5000,
      image: 'https://via.placeholder.com/400x300?text=Foulard',
      isFeatured: false,
    },
    {
      name: 'Sandales Artisanales',
      description: 'Sandales faites à la main avec cuir naturel - confort garanti',
      basePrice: 12000,
      originalPrice: 15000,
      image: 'https://via.placeholder.com/400x300?text=Sandales',
      isFeatured: false,
    },
    {
      name: 'Sac à Main Wax',
      description: 'Grand sac en tissu wax pratique et stylé pour tous les jours',
      basePrice: 7500,
      originalPrice: 10000,
      image: 'https://via.placeholder.com/400x300?text=Sac',
      isFeatured: false,
    },
    {
      name: 'Chemise Homme Wax',
      description: 'Chemise pour homme en wax premium - coupe moderne',
      basePrice: 18000,
      originalPrice: 24000,
      image: 'https://via.placeholder.com/400x300?text=Chemise',
      isFeatured: false,
    },
    {
      name: 'Cache-Cou Traditionnel',
      description: 'Accessoire traditionnel multifonction - châle wax',
      basePrice: 2500,
      originalPrice: 4000,
      image: 'https://via.placeholder.com/400x300?text=Cache',
      isFeatured: false,
    },
  ];

  const products: Product[] = [];
  const variants: ProductVariant[] = [];

  for (const p of productsData) {
    const product = new Product();
    product.vendorId = savedShop.id;
    product.prod_name = p.name;
    product.slug = p.name.toLowerCase().replace(/\s+/g, '-');
    product.description = p.description;
    product.basePrice = p.basePrice;
    product.weight = 0.5;
    product.dimensions = '10x10x10 cm';
    product.isVedette = p.isFeatured;
    products.push(product);
  }

  const savedProducts = await productRepo.save(products);

  // Create variants for each product
  for (let i = 0; i < savedProducts.length; i++) {
    const variant = new ProductVariant();
    variant.productId = savedProducts[i].id;
    variant.sku = `SKU-${savedProducts[i].id.slice(0, 8).toUpperCase()}`;
    variant.color = 'Standard';
    variant.size = null;
    variant.model = null;
    variant.price = productsData[i].basePrice;
    variant.stockQuantity = 10;
    variant.lowStockAlert = 3;
    variant.imageUrl = productsData[i].image;
    variant.isActive = true;
    variants.push(variant);
  }

  await variantRepo.save(variants);
  console.log('   ✅ Created: 8 products + variants');

  // ─── 4. Addresses ────────────────────────────────
  console.log('📍 4️⃣ Creating addresses...');

  const address1 = addressRepo.create({
    userId: savedBuyer.id,
    label: 'Maison',
    nom_destinataire: 'Kofi Mensah',
    phone_destinataire: '+22961000001',
    quartier: 'Akpakpa',
    ville: 'Cotonou',
    country: 'Bénin',
    isDefault: true,
  });

  const address2 = addressRepo.create({
    userId: savedBuyer.id,
    label: 'Bureau',
    nom_destinataire: 'Kofi M.',
    phone_destinataire: '+22961000001',
    quartier: 'Plateau',
    ville: 'Cotonou',
    country: 'Bénin',
    isDefault: false,
  });

  const [savedAddr1, savedAddr2] = await addressRepo.save([address1, address2]);
  console.log('   ✅ Created: 2 addresses');

  // ─── 5. Orders (3 avec statuts différents) ──────
  console.log('📋 5️⃣ Creating 3 orders with different statuses...');

  const ordersData = [
    {
      status: OrderStatus.PENDING,
      addressId: savedAddr1.id,
      items: [{ variant: variants[0], quantity: 1, price: productsData[0].basePrice }],
    },
    {
      status: OrderStatus.PREPARING,
      addressId: savedAddr1.id,
      items: [
        { variant: variants[1], quantity: 1, price: productsData[1].basePrice },
        { variant: variants[2], quantity: 2, price: productsData[2].basePrice },
      ],
    },
    {
      status: OrderStatus.DELIVERED,
      addressId: savedAddr2.id,
      items: [
        { variant: variants[4], quantity: 1, price: productsData[4].basePrice },
        { variant: variants[5], quantity: 1, price: productsData[5].basePrice },
      ],
    },
  ];

  const savedOrders: Order[] = [];
  for (const orderData of ordersData) {
    const subtotal = orderData.items.reduce(
      (sum, item) => sum + item.price * item.quantity,
      0
    );

    const order = new Order();
    order.orderNumber = `ASK-${new Date().getFullYear()}-${String(savedOrders.length + 1).padStart(5, '0')}`;
    order.userId = savedBuyer.id;
    order.vendorId = savedShop.id;
    order.addressId = orderData.addressId;
    order.status = orderData.status;
    order.subtotal = subtotal;
    order.fraisLivraison = 2000;
    order.rabais = 0;
    order.montantCommission = subtotal * 0.1;
    order.total = subtotal + 2000;
    order.instructions = null;
    order.motifAnnulation = null;

    const savedOrder = await orderRepo.save(order);
    savedOrders.push(savedOrder);

    // Create order items
    for (const itemData of orderData.items) {
      const orderItem = new OrderItem();
      orderItem.orderId = savedOrder.id;
      orderItem.variantId = itemData.variant.id;
      orderItem.quantity = itemData.quantity;
      orderItem.unitPrice = itemData.price;
      await orderItemRepo.save(orderItem);
    }
  }

  console.log('   ✅ Created: 3 orders (en_attente, en_cours, livré)');

  // ─── 6. Wishlist ────────────────────────────────
  console.log('❤️ 6️⃣ Creating wishlist items...');

  const wishlistItems = [
    { productId: savedProducts[0].id },
    { productId: savedProducts[2].id },
    { productId: savedProducts[6].id },
  ];

  const wishlists = wishlistItems.map(item =>
    wishlistRepo.create({
      userId: savedBuyer.id,
      productId: item.productId,
    })
  );

  await wishlistRepo.save(wishlists);
  console.log('   ✅ Created: 3 wishlist items');

  // ─── 7. Cart ────────────────────────────────────
  console.log('🛒 7️⃣ Creating cart with items...');

  const cart = cartRepo.create({
    userId: savedBuyer.id,
  });
  const savedCart = await cartRepo.save(cart);

  const cartItems = [
    { variantId: variants[3].id, quantity: 1, price: productsData[3].basePrice },
    { variantId: variants[6].id, quantity: 2, price: productsData[6].basePrice },
  ];

  for (const cartItemData of cartItems) {
    const cartItem = new CartItem();
    cartItem.cartId = savedCart.id;
    cartItem.variantId = cartItemData.variantId;
    cartItem.quantity = cartItemData.quantity;
    cartItem.unitPrice = cartItemData.price;
    cartItem.priceChanged = false;
    await cartItemRepo.save(cartItem);
  }

  console.log('   ✅ Created: Cart with 2 items');

  // ─── 8. Conversation + Messages ─────────────────
  console.log('💬 8️⃣ Creating conversation with messages...');

  const conversation = conversationRepo.create({
    clientId: savedBuyer.id,
    vendorId: savedShop.id,
    productId: savedProducts[0].id,
    isArchived: false,
  });
  const savedConversation = await conversationRepo.save(conversation);

  const messages = [
    {
      senderId: savedVendor.id,
      content: 'Bonjour ! Bienvenue dans ma boutique. Comment puis-je vous aider ?',
    },
    {
      senderId: savedBuyer.id,
      content: 'Bonjour, j\'aimerais des informations sur la Robe Wax Ankara',
    },
    {
      senderId: savedVendor.id,
      content: 'Bien sûr ! C\'est notre produit phare. Disponible en plusieurs tailles. Avez-vous une taille en particulier ?',
    },
  ];

  for (const msgData of messages) {
    const message = new Message();
    message.conversationId = savedConversation.id;
    message.senderId = msgData.senderId;
    message.content = msgData.content;
    message.imageUrl = null;
    message.isBlocked = false;
    message.blockReason = null;
    message.isReported = false;
    message.isRead = false;
    await messageRepo.save(message);
  }

  console.log('   ✅ Created: 1 conversation with 3 messages');

  // ─── 9. Notifications ───────────────────────────
  console.log('🔔 9️⃣ Creating notifications...');

  const notificationsData = [
    {
      title: 'Commande confirmée',
      body: 'Votre commande #' + savedOrders[1].orderNumber + ' a été confirmée et sera préparée sous peu.',
      type: NotificationType.ORDER,
      referenceId: savedOrders[1].id,
      referenceType: 'order',
      isRead: false,
    },
    {
      title: 'Nouveau message',
      body: 'Aminata Sow vous a répondu sur la Robe Wax Ankara',
      type: NotificationType.CHAT,
      referenceId: savedConversation.id,
      referenceType: 'conversation',
      isRead: false,
    },
    {
      title: 'Commande livrée',
      body: 'Votre commande #' + savedOrders[2].orderNumber + ' a été livrée avec succès',
      type: NotificationType.DELIVERY,
      referenceId: savedOrders[2].id,
      referenceType: 'order',
      isRead: true,
    },
  ];

  const notifications = notificationsData.map(notifData =>
    notificationRepo.create({
      userId: savedBuyer.id,
      title: notifData.title,
      body: notifData.body,
      type: notifData.type,
      referenceId: notifData.referenceId,
      referenceType: notifData.referenceType,
      isRead: notifData.isRead,
    })
  );

  await notificationRepo.save(notifications);
  console.log('   ✅ Created: 3 notifications');

  // ─── Summary ────────────────────────────────────
  console.log('\n✨ Client Test Data Seeding Complete!\n');
  console.log('📊 Summary:');
  console.log('   👤 Users: 3 (1 buyer + 2 sellers)');
  console.log('   🏪 Shops: 2');
  console.log('      ✅ Boutique Eleganza (APPROVED)');
  console.log('      ⏳ Tech Store Premium (PENDING - awaiting admin approval)');
  console.log('   📦 Products: 8 with variants (in Boutique Eleganza)');
  console.log('   📍 Addresses: 2');
  console.log('   📋 Orders: 3 (en_attente, en_cours, livré)');
  console.log('   ❤️ Wishlist items: 3');
  console.log('   🛒 Cart items: 2');
  console.log('   💬 Conversations: 1 with 3 messages');
  console.log('   🔔 Notifications: 3\n');
  console.log('📝 Credentials:');
  console.log('   Buyer:                 acheteur@test.com / Test1234!');
  console.log('   Seller 1 (Approved):   vendeur@test.com / Test1234!');
  console.log('   Seller 2 (Pending):    vendeur2@test.com / Test1234!\n');
  console.log('💡 Admin Action Needed: Approve "Tech Store Premium" shop\n');

  return {
    buyer: savedBuyer,
    vendor: savedVendor,
    vendor2: savedVendor2,
    shop: savedShop,
    products: savedProducts,
    orders: savedOrders,
    conversation: savedConversation,
  };
}
