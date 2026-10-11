import { MigrationInterface, QueryRunner } from 'typeorm';

// Tickets de support (voir src/modules/support-tickets/) :
//  - séquence support_tickets_number_seq : numéro lisible croissant (TCK-000042) ;
//  - support_tickets          : un ticket par demande (catégorie, sujet, statut,
//                               commande facultative, admin assigné, indicateurs
//                               de non-lu côté utilisateur / côté équipe) ;
//  - support_ticket_messages  : fil de discussion (auteur user ou admin,
//                               texte brut, jusqu'à 3 images) ;
//  - index (userId+lastMessageAt, status+lastMessageAt, ticketId+createdAt,
//    authorId+createdAt) ;
//  - nouvelle valeur 'ticket' de l'enum notifications_type_enum et 3 nouvelles
//    valeurs de activity_logs_action_enum (journal des actions admin).
// Idempotente : peut être rejouée sans erreur.
export class AddSupportTickets1791300000000 implements MigrationInterface {
  name = 'AddSupportTickets1791300000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`CREATE SEQUENCE IF NOT EXISTS "support_tickets_number_seq"`);

    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS "support_tickets" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "number" integer NOT NULL DEFAULT nextval('support_tickets_number_seq'),
        "userId" uuid NOT NULL,
        "category" character varying(30) NOT NULL,
        "subject" character varying(150) NOT NULL,
        "status" character varying(20) NOT NULL DEFAULT 'ouvert',
        "orderId" uuid,
        "assignedAdminId" uuid,
        "lastMessageAt" TIMESTAMP NOT NULL DEFAULT now(),
        "closedAt" TIMESTAMP,
        "userHasUnread" boolean NOT NULL DEFAULT false,
        "adminHasUnread" boolean NOT NULL DEFAULT true,
        "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
        "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
        CONSTRAINT "PK_support_tickets" PRIMARY KEY ("id"),
        CONSTRAINT "UQ_support_tickets_number" UNIQUE ("number"),
        CONSTRAINT "FK_support_tickets_user" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_support_tickets_order" FOREIGN KEY ("orderId") REFERENCES "orders"("id") ON DELETE SET NULL,
        CONSTRAINT "FK_support_tickets_admin" FOREIGN KEY ("assignedAdminId") REFERENCES "admin_accounts"("id") ON DELETE SET NULL
      )
    `);
    // La séquence appartient à la colonne : supprimée avec la table.
    await queryRunner.query(`ALTER SEQUENCE "support_tickets_number_seq" OWNED BY "support_tickets"."number"`);

    await queryRunner.query(`CREATE INDEX IF NOT EXISTS "IDX_support_tickets_userId_lastMessageAt" ON "support_tickets" ("userId", "lastMessageAt")`);
    await queryRunner.query(`CREATE INDEX IF NOT EXISTS "IDX_support_tickets_status_lastMessageAt" ON "support_tickets" ("status", "lastMessageAt")`);

    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS "support_ticket_messages" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "ticketId" uuid NOT NULL,
        "authorId" uuid NOT NULL,
        "authorType" character varying(10) NOT NULL,
        "body" character varying(4000) NOT NULL,
        "attachments" jsonb NOT NULL DEFAULT '[]',
        "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
        CONSTRAINT "PK_support_ticket_messages" PRIMARY KEY ("id"),
        CONSTRAINT "FK_support_ticket_messages_ticket" FOREIGN KEY ("ticketId") REFERENCES "support_tickets"("id") ON DELETE CASCADE
      )
    `);
    await queryRunner.query(`CREATE INDEX IF NOT EXISTS "IDX_support_ticket_messages_ticketId_createdAt" ON "support_ticket_messages" ("ticketId", "createdAt")`);
    await queryRunner.query(`CREATE INDEX IF NOT EXISTS "IDX_support_ticket_messages_authorId_createdAt" ON "support_ticket_messages" ("authorId", "createdAt")`);

    // ── Enums Postgres : nouvelles valeurs ────────────────
    // ⚠️ ADD VALUE ne peut pas être annulé par down(). Le DO ... IF EXISTS
    // évite d'échouer si un enum porte un autre nom dans une base installée
    // autrement.
    await queryRunner.query(`
      DO $$ BEGIN
        IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'notifications_type_enum') THEN
          ALTER TYPE "notifications_type_enum" ADD VALUE IF NOT EXISTS 'ticket';
        END IF;
        IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'activity_logs_action_enum') THEN
          ALTER TYPE "activity_logs_action_enum" ADD VALUE IF NOT EXISTS 'Réponse à un ticket support';
          ALTER TYPE "activity_logs_action_enum" ADD VALUE IF NOT EXISTS 'Statut d''un ticket support modifié';
          ALTER TYPE "activity_logs_action_enum" ADD VALUE IF NOT EXISTS 'Ticket support assigné';
        END IF;
      END $$;
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_support_ticket_messages_authorId_createdAt"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_support_ticket_messages_ticketId_createdAt"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "support_ticket_messages"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_support_tickets_status_lastMessageAt"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_support_tickets_userId_lastMessageAt"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "support_tickets"`);
    await queryRunner.query(`DROP SEQUENCE IF EXISTS "support_tickets_number_seq"`);
    // Les valeurs ajoutées aux enums (notifications_type_enum,
    // activity_logs_action_enum) NE sont PAS retirées : Postgres ne sait pas
    // supprimer une valeur d'enum et des lignes peuvent déjà les utiliser.
  }
}
