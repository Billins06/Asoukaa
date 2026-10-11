import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  Generated,
  ManyToOne,
  JoinColumn,
  CreateDateColumn,
  UpdateDateColumn,
  Index,
  Unique,
} from 'typeorm';
import { User } from '../../users/entities/user.entity';

// Ticket de support ouvert par un utilisateur (acheteur, vendeur, livreur).
// Table créée par la migration 1791300000000-AddSupportTickets.
// `number` vient d'une séquence Postgres (affiché « TCK-000042 »).
@Index('IDX_support_tickets_userId_lastMessageAt', ['userId', 'lastMessageAt'])
@Index('IDX_support_tickets_status_lastMessageAt', ['status', 'lastMessageAt'])
@Unique('UQ_support_tickets_number', ['number'])
@Entity('support_tickets')
export class SupportTicket {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Generated('increment')
  @Column({ type: 'int' })
  number: number;

  @Column({ type: 'uuid' })
  userId: string;

  @ManyToOne(() => User, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'userId' })
  user: User;

  @Column({ type: 'varchar', length: 30 })
  category: string;

  @Column({ type: 'varchar', length: 150 })
  subject: string;

  // 'ouvert' | 'en_cours' | 'resolu' | 'ferme' (voir TicketStatus)
  @Column({ type: 'varchar', length: 20, default: 'ouvert' })
  status: string;

  // Commande concernée (facultative) : l'utilisateur doit en être l'acheteur,
  // le vendeur ou le livreur (contrôlé à la création).
  @Column({ type: 'uuid', nullable: true })
  orderId: string | null;

  // Compte admin qui s'est assigné le ticket (jamais montré à l'utilisateur).
  @Column({ type: 'uuid', nullable: true })
  assignedAdminId: string | null;

  @Column({ type: 'timestamp', default: () => 'now()' })
  lastMessageAt: Date;

  @Column({ type: 'timestamp', nullable: true })
  closedAt: Date | null;

  // Réponse de l'équipe pas encore lue par l'utilisateur.
  @Column({ type: 'boolean', default: false })
  userHasUnread: boolean;

  // Message de l'utilisateur pas encore traité par l'équipe.
  @Column({ type: 'boolean', default: true })
  adminHasUnread: boolean;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
