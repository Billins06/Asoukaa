import { MigrationInterface, QueryRunner } from 'typeorm';

// Vrais réglages de profil (jusque-là de simples interrupteurs locaux) :
//  - users.lastSeenAt : dernière activité de l'utilisateur (présence « En
//    ligne / Vu à … »). NULL = jamais vu. « En ligne » est calculé côté
//    serveur : lastSeenAt dans les 2 dernières minutes ;
//  - users.notificationPrefs : préférences de notification (jsonb). Ne
//    contient QUE les clés réglées explicitement par l'utilisateur ; les
//    clés absentes prennent la valeur par défaut de son profil (voir
//    src/modules/notifications/notification-preferences.ts) ;
//  - vendor_profiles.shopVisible : « Boutique visible ». false = la boutique
//    et ses produits disparaissent des listes publiques (le propriétaire
//    garde l'accès) et elle ne peut plus recevoir de nouvelles commandes.
// Migration idempotente (IF NOT EXISTS) : on peut la rejouer sans risque.
// Voir src/modules/presence/, notifications/ et vendors/.
export class AddPresenceShopVisibleNotifPrefs1791500000000 implements MigrationInterface {
  name = 'AddPresenceShopVisibleNotifPrefs1791500000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "users" ADD COLUMN IF NOT EXISTS "lastSeenAt" TIMESTAMP WITH TIME ZONE`,
    );
    await queryRunner.query(
      `ALTER TABLE "users" ADD COLUMN IF NOT EXISTS "notificationPrefs" jsonb NOT NULL DEFAULT '{}'::jsonb`,
    );
    await queryRunner.query(
      `ALTER TABLE "vendor_profiles" ADD COLUMN IF NOT EXISTS "shopVisible" boolean NOT NULL DEFAULT true`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "vendor_profiles" DROP COLUMN IF EXISTS "shopVisible"`,
    );
    await queryRunner.query(
      `ALTER TABLE "users" DROP COLUMN IF EXISTS "notificationPrefs"`,
    );
    await queryRunner.query(
      `ALTER TABLE "users" DROP COLUMN IF EXISTS "lastSeenAt"`,
    );
  }
}
