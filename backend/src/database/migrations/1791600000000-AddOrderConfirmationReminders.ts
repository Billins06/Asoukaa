import { MigrationInterface, QueryRunner } from 'typeorm';

// Délai de confirmation vendeur (voir src/modules/orders/order-confirmation.service.ts) :
// quand une commande payée n'est toujours pas confirmée par le vendeur,
//  - il reçoit un rappel (vendorReminderSentAt) après ORDER_REMINDER_HOURS (24 h),
//  - l'admin est alerté (adminAlertedAt) après ORDER_ADMIN_ALERT_HOURS (48 h).
// Les deux colonnes servent aussi de verrou : chaque rappel/alerte n'est
// émis qu'une seule fois (UPDATE conditionnel ... WHERE colonne IS NULL).
//
// Contenu :
//  - orders.vendorReminderSentAt / orders.adminAlertedAt (timestamptz, nullable) ;
//  - index partiel : le planificateur ne parcourt que les commandes « en attente »
//    pour lesquelles un rappel ou une alerte reste à envoyer ;
//  - 1 nouvelle valeur de l'enum activity_logs_action_enum (journal d'activité :
//    alerte admin « commande non confirmée par le vendeur »).
// Le type de notification réutilise 'commande' (déjà dans l'enum) : aucune
// valeur à ajouter côté notifications.
// Idempotente : peut être rejouée sans erreur.
export class AddOrderConfirmationReminders1791600000000
  implements MigrationInterface
{
  name = 'AddOrderConfirmationReminders1791600000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "orders"
      ADD COLUMN IF NOT EXISTS "vendorReminderSentAt" TIMESTAMPTZ,
      ADD COLUMN IF NOT EXISTS "adminAlertedAt" TIMESTAMPTZ
    `);

    // Index partiel : uniquement les commandes en attente dont le rappel
    // vendeur OU l'alerte admin n'est pas encore parti(e).
    await queryRunner.query(`
      CREATE INDEX IF NOT EXISTS "IDX_orders_awaiting_vendor_confirmation"
      ON "orders" ("createdAt")
      WHERE "status" = 'en attente'
        AND ("vendorReminderSentAt" IS NULL OR "adminAlertedAt" IS NULL)
    `);

    // ⚠️ ADD VALUE ne peut pas être annulé par down() — voir la note ci-dessous.
    // Même technique que 1791000000000-AddEmailChange : DO ... IF EXISTS pour
    // ne pas échouer si l'enum porte un autre nom ; ADD VALUE IF NOT EXISTS
    // est autorisé dans une transaction (PostgreSQL >= 12) tant que la valeur
    // n'est pas utilisée dans cette même transaction (c'est le cas ici).
    await queryRunner.query(`
      DO $$ BEGIN
        IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'activity_logs_action_enum') THEN
          ALTER TYPE "activity_logs_action_enum" ADD VALUE IF NOT EXISTS 'Commande non confirmée par le vendeur (alerte)';
        END IF;
      END $$;
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `DROP INDEX IF EXISTS "IDX_orders_awaiting_vendor_confirmation"`,
    );
    await queryRunner.query(`
      ALTER TABLE "orders"
      DROP COLUMN IF EXISTS "adminAlertedAt",
      DROP COLUMN IF EXISTS "vendorReminderSentAt"
    `);
    // La valeur ajoutée à activity_logs_action_enum N'est PAS retirée :
    // Postgres ne sait pas supprimer une valeur d'enum, et des lignes du
    // journal peuvent déjà l'utiliser. Elle est sans effet.
  }
}
