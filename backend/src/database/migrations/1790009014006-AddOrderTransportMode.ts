import { MigrationInterface, QueryRunner } from 'typeorm';

// Mode de transport (bus/taxi) choisi par le client au paiement, pour les
// commandes livrées dans une commune du Nord (Alibori, Atacora, Borgou,
// Donga) où Asoukaa n'a pas de livreur propre. Nul pour toutes les autres
// communes. Le prix de livraison ne dépend pas de ce choix.
export class AddOrderTransportMode1790009014006
  implements MigrationInterface
{
  name = 'AddOrderTransportMode1790009014006';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "orders"
      ADD COLUMN IF NOT EXISTS "transportMode" varchar(10)
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "orders" DROP COLUMN IF EXISTS "transportMode"
    `);
  }
}
