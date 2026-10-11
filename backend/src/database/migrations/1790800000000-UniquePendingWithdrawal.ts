import { MigrationInterface, QueryRunner } from 'typeorm';

// Garde-fou anti double-demande de retrait.
//
// Le service vérifie déjà "une seule demande en attente par vendeur", mais
// cette vérification est une lecture suivie d'une écriture, sans verrou :
// deux requêtes simultanées (double tap sur le bouton, ou renvoi réseau)
// passent toutes les deux le contrôle et créent deux demandes. Sur de
// l'argent réel, cela revient à demander deux fois le même solde.
//
// Un index unique partiel rend ce scénario impossible au niveau de la base
// elle-même : la deuxième insertion échoue, quoi qu'il arrive au-dessus.
export class UniquePendingWithdrawal1790800000000
  implements MigrationInterface
{
  name = 'UniquePendingWithdrawal1790800000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    // Au cas où des doublons existeraient déjà : on ne garde en attente que
    // la demande la plus récente de chaque vendeur, les autres sont
    // rejetées avec un motif explicite plutôt que supprimées (trace
    // financière conservée).
    await queryRunner.query(`
      UPDATE "vendor_withdrawals" w
      SET "status" = 'rejeté',
          "noteAdmin" = COALESCE("noteAdmin", '') ||
            ' [Rejet automatique : demande en double]'
      WHERE w."status" = 'en attente'
        AND EXISTS (
          SELECT 1 FROM "vendor_withdrawals" plus_recent
          WHERE plus_recent."vendorId" = w."vendorId"
            AND plus_recent."status" = 'en attente'
            AND (
              plus_recent."createdAt" > w."createdAt"
              -- égalité de createdAt : on départage par id, sinon deux
              -- demandes simultanées seraient toutes deux rejetées
              OR (plus_recent."createdAt" = w."createdAt" AND plus_recent.id > w.id)
            )
        )
    `);

    await queryRunner.query(`
      CREATE UNIQUE INDEX IF NOT EXISTS "UQ_vendor_withdrawals_one_pending"
      ON "vendor_withdrawals" ("vendorId")
      WHERE "status" = 'en attente'
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      DROP INDEX IF EXISTS "UQ_vendor_withdrawals_one_pending"
    `);
  }
}
