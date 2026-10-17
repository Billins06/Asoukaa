import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  JoinColumn,
  CreateDateColumn,
  Index,
} from 'typeorm';
import { Conversation } from './conversation.entity';
import { User } from '../../users/entities/user.entity';

// Index (créés par la migration 1791810000000-AddPerformanceIndexes, et
// DÉCLARÉS ICI pour que DB_SYNCHRONIZE=true ne les supprime pas) :
//  - messages d'une conversation, du plus récent au plus ancien ;
//  - décompte des messages non lus (index partiel, migration 1791200000000).
@Index('IDX_messages_conversationId_createdAt', ['conversationId', 'createdAt'])
@Index('IDX_messages_conversation_unread', ['conversationId'], { where: '"isRead" = false' })
@Entity('messages')
export class Message {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  conversationId: string;

  @ManyToOne(() => Conversation, (conv) => conv.messages, {
    onDelete: 'CASCADE',
  })
  @JoinColumn({ name: 'conversationId' })
  conversation: Conversation;

  @Column()
  senderId: string;

  @ManyToOne(() => User, {
    onDelete: 'RESTRICT',
  })
  @JoinColumn({ name: 'senderId' })
  sender: User;

  // Nullable car le message peut être une image uniquement
  @Column({ nullable: true, type: 'text' })
  content: string | null;

  // Nullable car le message peut être du texte uniquement
  @Column({ nullable: true, type: 'varchar', length: 500 })
  imageUrl: string | null;

  // true = bloqué automatiquement par le filtre
  // Ex: numéro de téléphone détecté
  @Column({ default: false })
  isBlocked: boolean;

  // Raison du blocage automatique
  // Ex: 'phone_number_detected', 'external_link_detected'
  @Column({ nullable: true, type: 'varchar', length: 255 })
  blockReason: string | null;

  // true = signalé par l'un des participants
  @Column({ default: false })
  isReported: boolean;

  // true = lu par le destinataire
  @Column({ default: false })
  isRead: boolean;

  @CreateDateColumn()
  createdAt: Date;
}