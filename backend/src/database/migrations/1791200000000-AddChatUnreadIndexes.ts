import { MigrationInterface, QueryRunner } from 'typeorm';

// Index de la messagerie :
//  - messages (conversationId) WHERE isRead = false : le décompte des
//    messages non lus (pastille de la liste des conversations et badge
//    global) ne parcourt plus tout l'historique d'une conversation ;
//  - conversations (vendorId) : la liste des conversations côté vendeur.
//    La contrainte unique (clientId, vendorId) ne sert que les recherches
//    par clientId en tête.
// Voir src/modules/chat/.
export class AddChatUnreadIndexes1791200000000 implements MigrationInterface {
  name = 'AddChatUnreadIndexes1791200000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `CREATE INDEX IF NOT EXISTS "IDX_messages_conversation_unread" ON "messages" ("conversationId") WHERE "isRead" = false`,
    );
    await queryRunner.query(
      `CREATE INDEX IF NOT EXISTS "IDX_conversations_vendorId" ON "conversations" ("vendorId")`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_conversations_vendorId"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_messages_conversation_unread"`);
  }
}
