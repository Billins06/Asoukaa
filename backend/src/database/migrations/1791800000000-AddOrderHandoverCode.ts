import { MigrationInterface, QueryRunner } from 'typeorm';
import { randomInt } from 'crypto';

// Code de remise aléatoire par commande (remplace le « QR = numéro de commande »,
// facile à deviner — voir src/common/utils/handover-code.util.ts).
//
// Contenu :
//  - orders.handoverCode            varchar(16) NULL  : code secret de la commande ;
//  - orders.handoverFailedAttempts  int NOT NULL = 0  : essais ratés de saisie du code ;
//  - orders.handoverLockedUntil     timestamptz NULL  : blocage temporaire (3 essais ratés) ;
//  - remplissage des commandes existantes NON terminées (ni « livré » ni « annulé »).
//
// Les codes du remplissage sont générés ICI, en Node, avec crypto.randomInt
// (aucune extension Postgres nécessaire : pgcrypto n'est pas installée par les
// migrations du projet, et random() de SQL n'est pas cryptographique).
//
// Idempotente : ADD COLUMN IF NOT EXISTS ; le remplissage ne touche que les
// lignes dont le code est encore NULL, donc rejouable sans écraser un code.
const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; // sans 0/O/1/I/L
const LENGTH   = 8;
const BATCH    = 500;

function newCode(): string {
  let c = '';
  for (let i = 0; i < LENGTH; i++) c += ALPHABET[randomInt(ALPHABET.length)];
  return c;
}

export class AddOrderHandoverCode1791800000000 implements MigrationInterface {
  name = 'AddOrderHandoverCode1791800000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "orders"
      ADD COLUMN IF NOT EXISTS "handoverCode" VARCHAR(16),
      ADD COLUMN IF NOT EXISTS "handoverFailedAttempts" INTEGER NOT NULL DEFAULT 0,
      ADD COLUMN IF NOT EXISTS "handoverLockedUntil" TIMESTAMPTZ
    `);

    // Commandes non terminées sans code : on leur en donne un.
    for (;;) {
      const rows: Array<{ id: string }> = await queryRunner.query(`
        SELECT "id" FROM "orders"
        WHERE "handoverCode" IS NULL
          AND "status" NOT IN ('livré', 'annulé')
        LIMIT ${BATCH}
      `);
      if (!rows.length) break;

      const ids   = rows.map((r) => r.id);
      const codes = rows.map(() => newCode());

      await queryRunner.query(
        `
        UPDATE "orders" o
        SET "handoverCode" = v."code"
        FROM (
          SELECT UNNEST($1::uuid[]) AS "id", UNNEST($2::text[]) AS "code"
        ) v
        WHERE o."id" = v."id" AND o."handoverCode" IS NULL
        `,
        [ids, codes],
      );

      // Garde-fou : si une ligne n'a pas pu être mise à jour (ne devrait pas
      // arriver), on sort plutôt que de boucler indéfiniment.
      if (rows.length < BATCH) break;
    }
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "orders"
      DROP COLUMN IF EXISTS "handoverLockedUntil",
      DROP COLUMN IF EXISTS "handoverFailedAttempts",
      DROP COLUMN IF EXISTS "handoverCode"
    `);
  }
}
