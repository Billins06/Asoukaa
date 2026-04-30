import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  JoinColumn,
  CreateDateColumn,
} from 'typeorm';
import { Conversation } from './conversation.entity';
import { User } from '../../users/entities/user.entity';

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
  content: string;

  // Nullable car le message peut être du texte uniquement
  @Column({ nullable: true, length: 500 })
  imageUrl: string;

  // true = bloqué automatiquement par le filtre
  // Ex: numéro de téléphone détecté
  @Column({ default: false })
  isBlocked: boolean;

  // Raison du blocage automatique
  // Ex: 'phone_number_detected', 'external_link_detected'
  @Column({ nullable: true, length: 255 })
  blockReason: string;

  // true = signalé par l'un des participants
  @Column({ default: false })
  isReported: boolean;

  // true = lu par le destinataire
  @Column({ default: false })
  isRead: boolean;

  @CreateDateColumn()
  createdAt: Date;
}