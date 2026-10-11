import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  JoinColumn,
  CreateDateColumn,
  Index,
} from 'typeorm';
import { SupportTicket } from './support-ticket.entity';

// Message d'un ticket. `authorId` est l'id d'un user OU d'un compte admin
// selon `authorType` : pas de clé étrangère (deux tables possibles).
@Index('IDX_support_ticket_messages_ticketId_createdAt', ['ticketId', 'createdAt'])
@Index('IDX_support_ticket_messages_authorId_createdAt', ['authorId', 'createdAt'])
@Entity('support_ticket_messages')
export class SupportTicketMessage {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ type: 'uuid' })
  ticketId: string;

  @ManyToOne(() => SupportTicket, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'ticketId' })
  ticket: SupportTicket;

  @Column({ type: 'uuid' })
  authorId: string;

  // 'user' | 'admin'
  @Column({ type: 'varchar', length: 10 })
  authorType: string;

  // Texte brut (balises HTML retirées), 1 à 4000 caractères.
  @Column({ type: 'varchar', length: 4000 })
  body: string;

  // Jusqu'à 3 URLs d'images (upload de type « tickets »).
  @Column({ type: 'jsonb', default: () => "'[]'" })
  attachments: string[];

  @CreateDateColumn()
  createdAt: Date;
}
