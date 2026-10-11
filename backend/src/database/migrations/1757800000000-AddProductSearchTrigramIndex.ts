import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Index trigram pour la recherche produit.
 *
 * ⚠️ ProductsService.findAll() filtre avec `product.prod_name ILIKE '%terme%'`
 * et `pt.tag ILIKE '%terme%'`. Un ILIKE avec joker EN TÊTE ne peut utiliser
 * aucun index B-tree : Postgres scanne intégralement `products` (et
 * `product_tags`) à chaque recherche, sur une route publique et non
 * authentifiée. L'extension pg_trgm + un index GIN rendent ce motif
 * indexable.
 *
 * À exécuter avec : npm run typeorm:run
 */
export class AddProductSearchTrigramIndex1757800000000
  implements MigrationInterface
{
  name = 'AddProductSearchTrigramIndex1757800000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`CREATE EXTENSION IF NOT EXISTS pg_trgm`);

    await queryRunner.query(`
      CREATE INDEX IF NOT EXISTS idx_products_prod_name_trgm
      ON products USING gin ("prod_name" gin_trgm_ops)
    `);

    await queryRunner.query(`
      CREATE INDEX IF NOT EXISTS idx_product_tags_tag_trgm
      ON product_tags USING gin ("tag" gin_trgm_ops)
    `);

    // Séquence des numéros de commande (voir OrdersService.generateOrderNumber).
    // Créée aussi au démarrage du module, mais on la pose ici pour que le
    // schéma soit complet en environnement piloté par migrations.
    await queryRunner.query(
      `CREATE SEQUENCE IF NOT EXISTS orders_number_seq START WITH 1`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX IF EXISTS idx_product_tags_tag_trgm`);
    await queryRunner.query(`DROP INDEX IF EXISTS idx_products_prod_name_trgm`);
    // L'extension et la séquence ne sont pas supprimées : d'autres objets
    // peuvent en dépendre, et supprimer la séquence ferait repartir la
    // numérotation des commandes à zéro.
  }
}
