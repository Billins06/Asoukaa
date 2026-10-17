import { MigrationInterface, QueryRunner } from 'typeorm';

// Index de performance — UNE migration idempotente (CREATE INDEX IF NOT EXISTS).
//
// Contexte : jusqu'ici la base était créée par DB_SYNCHRONIZE=true (TypeORM
// créait alors les index déclarés par @Index dans les entités), et aucune
// migration ne les créait. Une base gérée uniquement par migrations (production)
// n'avait donc PAS ces index.
//
// Deux parties :
//  1. DECLARED : les index déjà déclarés par @Index dans les entités (mêmes
//     noms que ceux générés par TypeORM) ;
//  2. ADDED    : des index utiles qui manquaient. Ils sont AUSSI déclarés dans
//     les entités avec le même nom (sinon DB_SYNCHRONIZE=true les supprimerait).
//
// Sécurités :
//  - table ou colonne absente → l'index est ignoré (message dans les logs) ;
//  - un index de même nom, OU équivalent (mêmes colonnes dans le même ordre,
//    non partiel, ex. un index « IDX_payments_groupRef » créé par une autre
//    migration, ou une contrainte UNIQUE) → rien n'est créé : pas de doublon ;
//  - index UNIQUE : ignoré (avec avertissement) si des doublons existent déjà.
//
// down() ne supprime QUE les index de la partie ADDED : ceux de la partie
// DECLARED peuvent exister depuis longtemps (créés par synchronize) et servent
// aux entités ; les retirer ralentirait l'application.
//
// ⚠️ CREATE INDEX (non CONCURRENTLY) verrouille l'écriture sur la table le
// temps de la création : à lancer hors heures de pointe sur une grosse base.

interface IndexDef {
  table: string;
  name: string;
  columns: string[];
  unique?: boolean;
  where?: string;
}

// ── 1. Index déjà déclarés par @Index dans les entités ───────────────
const DECLARED: IndexDef[] = [
  { table: 'activity_logs', name: 'IDX_110bb0d32b7f65be46be37e257', columns: ['actorId'] },
  { table: 'activity_logs', name: 'IDX_377463c364326082e86ce68ed3', columns: ['entityId'] },
  { table: 'activity_logs', name: 'IDX_879e2d305a025dadfe9929c47d', columns: ['action'] },
  { table: 'activity_logs', name: 'IDX_95355d75c728050aae956cf016', columns: ['createdAt'] },
  { table: 'addresses', name: 'IDX_95c93a584de49f0b0e13f75363', columns: ['userId'] },
  { table: 'admin_accounts', name: 'IDX_05a0a0da9626f51206e41eda9d', columns: ['email'] },
  { table: 'admin_accounts', name: 'IDX_0cf69d77e55602fc5a3a03285e', columns: ['name'] },
  { table: 'admin_accounts', name: 'IDX_f3e8f14f60909edd8ccbe51cb8', columns: ['prenom'] },
  { table: 'cart_items', name: 'IDX_5a27845bc2d79be6f1fa3d2c03', columns: ['variantId'] },
  { table: 'cart_items', name: 'IDX_edd714311619a5ad0952504583', columns: ['cartId'] },
  { table: 'carts', name: 'IDX_69828a178f152f157dcf2f70a8', columns: ['userId'] },
  { table: 'categories', name: 'IDX_420d9f679d41281f282f5bc7d0', columns: ['slug'] },
  { table: 'categories', name: 'IDX_8b0be371d28245da6e4f4b6187', columns: ['name'] },
  { table: 'commissions', name: 'IDX_87a59dece25a9e3b3a9b1758ca', columns: ['createdAt'] },
  { table: 'commissions', name: 'IDX_a4fdb3d46dc59b3b32a5440db9', columns: ['status'] },
  { table: 'commissions', name: 'IDX_fa1f9e7b7627cacd0edd8f1cd2', columns: ['vendorId'] },
  { table: 'coupon_usages', name: 'IDX_803698570aee440e55af7d6a54', columns: ['couponId', 'userId'] },
  { table: 'coupon_usages', name: 'IDX_a7b422cc0dbf863671255eaad5', columns: ['couponId'] },
  { table: 'coupon_usages', name: 'IDX_f526503f2419217d16794648f2', columns: ['userId'] },
  { table: 'coupons', name: 'IDX_e025109230e82925843f2a14c4', columns: ['code'] },
  { table: 'deliveries', name: 'IDX_3235c9c06d9d3028a11ec8081d', columns: ['status'] },
  { table: 'deliveries', name: 'IDX_43a0308abeb6f1e56e4da75191', columns: ['agentId'] },
  { table: 'deliveries', name: 'IDX_9b9637db555f7f7355ddf0e36d', columns: ['agentId', 'status'] },
  { table: 'deliveries', name: 'IDX_f7433e3639e213f901e22cf864', columns: ['orderId'] },
  { table: 'delivery_earnings', name: 'IDX_20ae6b8874357317a98389100d', columns: ['agentId'] },
  { table: 'delivery_earnings', name: 'IDX_7f5ad6a3cc10c5b7fcc430339c', columns: ['status'] },
  { table: 'delivery_proofs', name: 'IDX_6b6f4fe1ad49a2fa4245f7db32', columns: ['deliveryId'] },
  { table: 'delivery_proofs', name: 'IDX_970782148dc0bd6a3418b03858', columns: ['orderId'] },
  { table: 'delivery_proofs', name: 'IDX_d7e8b3b6cd539f66d5c7bf8b60', columns: ['stage'] },
  { table: 'delivery_zones', name: 'IDX_ec3d83f811dece724baa7055c0', columns: ['commune'], unique: true },
  { table: 'email_changes', name: 'IDX_email_changes_revertTokenHash', columns: ['revertTokenHash'] },
  { table: 'email_changes', name: 'IDX_email_changes_userId', columns: ['userId'] },
  { table: 'featured_shops', name: 'IDX_featured_shops_isActive_position', columns: ['isActive', 'position'] },
  { table: 'notifications', name: 'IDX_4509d5b418f7eb05ac668d5056', columns: ['adminId'] },
  { table: 'notifications', name: 'IDX_692a909ee0fa9383e7859f9b40', columns: ['userId'] },
  { table: 'order_items', name: 'IDX_516736b9807228bb17b2d0a3e2', columns: ['variantId'] },
  { table: 'order_items', name: 'IDX_f1d359a55923bb45b057fbdab0', columns: ['orderId'] },
  { table: 'orders', name: 'IDX_14dffab8aee1ce044f8e8e5423', columns: ['vendorId', 'status'] },
  { table: 'orders', name: 'IDX_151b79a83ba240b0cb31b2302d', columns: ['userId'] },
  { table: 'orders', name: 'IDX_1f4b9818a08b822a31493fdee9', columns: ['createdAt'] },
  { table: 'orders', name: 'IDX_4fc5a9360e2b4e795f02344ae7', columns: ['vendorId'] },
  { table: 'orders', name: 'IDX_59b0c3b34ea0fa5562342f2414', columns: ['orderNumber'] },
  { table: 'orders', name: 'IDX_775c9f06fc27ae3ff8fb26f2c4', columns: ['status'] },
  { table: 'orders', name: 'IDX_orders_awaiting_vendor_confirmation', columns: ['createdAt'], where: `"status" = 'en attente' AND ("vendorReminderSentAt" IS NULL OR "adminAlertedAt" IS NULL)` },
  { table: 'otp_codes', name: 'IDX_51f6c167908c125bef1f18fe7b', columns: ['userId'] },
  { table: 'otp_codes', name: 'IDX_699c852115b1842430dd2ec0fa', columns: ['userId', 'type', 'isUsed'] },
  { table: 'otp_codes', name: 'IDX_7516487afe3800dd744fee1e86', columns: ['expiresAt'] },
  { table: 'payments', name: 'IDX_32b41cdb985a296213e9a928b5', columns: ['status'] },
  { table: 'payments', name: 'IDX_684d092a3d90f53057424fc1ec', columns: ['providerRef'] },
  { table: 'payments', name: 'IDX_b3bc8bbf17be94dfe42131abb1', columns: ['groupRef'] },
  { table: 'product_categories', name: 'IDX_6156a79599e274ee9d83b1de13', columns: ['productId'] },
  { table: 'product_categories', name: 'IDX_fdef3adba0c284fd103d0fd369', columns: ['categoryId'] },
  { table: 'product_images', name: 'IDX_b367708bf720c8dd62fc683316', columns: ['productId'] },
  { table: 'product_tags', name: 'IDX_bbc3fefb51e1b20fb586580133', columns: ['tag'] },
  { table: 'product_variants', name: 'IDX_46f236f21640f9da218a063a86', columns: ['sku'] },
  { table: 'products', name: 'IDX_05b74ed0488ecb76ae5dab37ac', columns: ['prod_name'] },
  { table: 'products', name: 'IDX_464f927ae360106b783ed0b410', columns: ['slug'] },
  { table: 'refunds', name: 'IDX_605cf4d367799f3e5cfb9f6822', columns: ['orderId'] },
  { table: 'refunds', name: 'IDX_90c78d3c32a3346772edf34e73', columns: ['status'] },
  { table: 'reviews', name: 'IDX_7b06c23cf52ca8aea0dcaf0ee2', columns: ['status'] },
  { table: 'reviews', name: 'IDX_7ed5659e7139fc8bc039198cc1', columns: ['userId'] },
  { table: 'reviews', name: 'IDX_a6b3c434392f5d10ec17104366', columns: ['productId'] },
  { table: 'shop_follows', name: 'IDX_shop_follows_vendorId', columns: ['vendorId'] },
  { table: 'support_ticket_messages', name: 'IDX_support_ticket_messages_authorId_createdAt', columns: ['authorId', 'createdAt'] },
  { table: 'support_ticket_messages', name: 'IDX_support_ticket_messages_ticketId_createdAt', columns: ['ticketId', 'createdAt'] },
  { table: 'support_tickets', name: 'IDX_support_tickets_status_lastMessageAt', columns: ['status', 'lastMessageAt'] },
  { table: 'support_tickets', name: 'IDX_support_tickets_userId_lastMessageAt', columns: ['userId', 'lastMessageAt'] },
  { table: 'user_roles', name: 'IDX_472b25323af01488f1f66a06b6', columns: ['userId'] },
  { table: 'users', name: 'IDX_51b8b26ac168fbe7d6f5653e6c', columns: ['name'] },
  { table: 'users', name: 'IDX_97672ac88f789774dd47f7c8be', columns: ['email'] },
  { table: 'users', name: 'IDX_a000cca60bcf04454e72769949', columns: ['phone'] },
  { table: 'users', name: 'IDX_ce8452770ca2e1003bfdc194fb', columns: ['prenom'] },
  { table: 'vendor_profiles', name: 'IDX_fe350603a4a45e923a9830a6f3', columns: ['shopName'] },
  { table: 'vendor_withdrawals', name: 'IDX_2b6386c267559fc4382e11e2a8', columns: ['vendorId'] },
  { table: 'vendor_withdrawals', name: 'IDX_6922910b9d659723088719440f', columns: ['createdAt'] },
  { table: 'vendor_withdrawals', name: 'IDX_ee2b776a9933fe78469a0280ab', columns: ['status'] },
  { table: 'vitrine_rayon_produits', name: 'IDX_vitrine_rayon_produits_productId', columns: ['productId'] },
  { table: 'vitrine_rayons', name: 'IDX_vitrine_rayons_isActive_sortOrder', columns: ['isActive', 'sortOrder'] },
  { table: 'wishlists', name: 'IDX_063c6f46d6cbebf35f3a5ec3d4', columns: ['productId'] },
  { table: 'wishlists', name: 'IDX_4f3c30555daa6ab0b70a1db772', columns: ['userId'] },
];

// ── 2. Index utiles manquants (déclarés aussi dans les entités) ──────
const ADDED: IndexDef[] = [
  // Catalogue : liste des produits actifs, les plus récents d'abord.
  { table: 'products', name: 'IDX_products_status_createdAt', columns: ['status', 'createdAt'] },
  // Produits d'une boutique (page boutique, tableau de bord vendeur).
  { table: 'products', name: 'IDX_products_vendorId', columns: ['vendorId'] },
  // Variantes d'un produit (clé étrangère sans index jusqu'ici).
  { table: 'product_variants', name: 'IDX_product_variants_productId', columns: ['productId'] },
  // Messages d'une conversation, du plus récent au plus ancien.
  { table: 'messages', name: 'IDX_messages_conversationId_createdAt', columns: ['conversationId', 'createdAt'] },
  // Liste admin / annuaire : boutiques par statut.
  { table: 'vendor_profiles', name: 'IDX_vendor_profiles_status', columns: ['status'] },
  // Mes notifications (liste + sondage « since »), les plus récentes d'abord.
  { table: 'notifications', name: 'IDX_notifications_userId_createdAt', columns: ['userId', 'createdAt'] },
];

const q = (id: string) => `"${id.replace(/"/g, '""')}"`;

export class AddPerformanceIndexes1791810000000 implements MigrationInterface {
  name = 'AddPerformanceIndexes1791810000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    for (const def of [...DECLARED, ...ADDED]) {
      await this.ensureIndex(queryRunner, def);
    }
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    for (const def of [...ADDED].reverse()) {
      await queryRunner.query(`DROP INDEX IF EXISTS ${q(def.name)}`);
    }
  }

  private async ensureIndex(qr: QueryRunner, def: IndexDef): Promise<void> {
    const skip = (why: string) =>
      console.log(`[AddPerformanceIndexes] ${def.name} ignoré : ${why}`);

    if (!(await qr.hasTable(def.table))) return skip(`table ${def.table} absente`);
    for (const col of def.columns) {
      if (!(await qr.hasColumn(def.table, col))) {
        return skip(`colonne ${def.table}.${col} absente`);
      }
    }

    // Un index de ce nom existe déjà ?
    const byName = await qr.query(
      `SELECT 1 FROM pg_indexes WHERE schemaname = current_schema() AND indexname = $1`,
      [def.name],
    );
    if (byName.length) return;

    // Un index équivalent existe déjà sous un autre nom ? (index complet, mêmes
    // colonnes dans le même ordre ; un index unique convient à une demande
    // non unique, pas l'inverse)
    if (!def.where) {
      const rows: Array<{ cols: string[]; isunique: boolean }> = await qr.query(
        `SELECT array_agg(a.attname::text ORDER BY k.ord) AS cols, ix.indisunique AS isunique
           FROM pg_index ix
           JOIN pg_class t ON t.oid = ix.indrelid
           JOIN pg_namespace n ON n.oid = t.relnamespace
           CROSS JOIN LATERAL unnest(ix.indkey::int2[]) WITH ORDINALITY AS k(attnum, ord)
           JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = k.attnum
          WHERE n.nspname = current_schema()
            AND t.relname = $1
            AND ix.indpred IS NULL
            AND ix.indexprs IS NULL
          GROUP BY ix.indexrelid, ix.indisunique`,
        [def.table],
      );
      const wanted = def.columns.join(',');
      const same = rows.find(
        (r) => r.cols.join(',') === wanted && (r.isunique || !def.unique),
      );
      if (same) return;
    }

    if (def.unique) {
      const dup = await qr.query(
        `SELECT 1 FROM ${q(def.table)} ${def.where ? `WHERE ${def.where}` : ''}
          GROUP BY ${def.columns.map(q).join(', ')} HAVING COUNT(*) > 1 LIMIT 1`,
      );
      if (dup.length) return skip('des doublons existent déjà (index unique impossible)');
    }

    await qr.query(
      `CREATE ${def.unique ? 'UNIQUE ' : ''}INDEX IF NOT EXISTS ${q(def.name)} ` +
        `ON ${q(def.table)} (${def.columns.map(q).join(', ')})` +
        (def.where ? ` WHERE ${def.where}` : ''),
    );
  }
}
