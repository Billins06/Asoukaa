import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  JoinColumn,
  CreateDateColumn,
  Index,
} from 'typeorm';
import { User } from '../../users/entities/user.entity';
import { AdminAccount } from '../../auth/entities/admin-account.entity';

export enum NotificationType {
  ORDER      = 'commande',      // liée à une commande
  DELIVERY   = 'livraison',   // liée à une livraison
  PAYMENT    = 'paiement',    // liée à un paiement
  REVIEW     = 'avis',     // liée à un avis
  STOCK      = 'stock',      // alerte stock faible
  VALIDATION = 'validation', // validation vendeur/livreur
  SYSTEM     = 'system',     // notification système générale
  CHAT       = 'chat',       // nouveau message reçu
}

@Entity('notifications')
export class Notification {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  // Destinataire — soit un utilisateur soit un admin
  // Les deux sont nullable car c'est soit l'un soit l'autre
  @Index()
  @Column({ nullable: true })
  userId: string;

  @ManyToOne(() => User, {
    nullable: true,
    onDelete: 'CASCADE',
    // Si l'utilisateur est supprimé
    // ses notifications le sont aussi
  })
  @JoinColumn({ name: 'userId' })
  user: User;

  @Index()
  @Column({ nullable: true })
  adminId: string;

  @ManyToOne(() => AdminAccount, {
    nullable: true,
    onDelete: 'CASCADE',
  })
  @JoinColumn({ name: 'adminId' })
  admin: AdminAccount;

  @Column({ length: 255 })
  title: string;

  @Column({ type: 'text' })
  body: string;

  @Column({
    type: 'enum',
    enum: NotificationType,
  })
  type: NotificationType;

  // ID de l'élément concerné
  // Ex: id de la commande, id de la livraison
  @Column({ nullable: true })
  referenceId: string;

  // Type de l'élément concerné
  // Ex: 'order', 'delivery', 'payment'
  // Permet de construire le lien de redirection dans l'app
  @Column({ nullable: true, length: 50 })
  referenceType: string;

  @Column({ default: false })
  isRead: boolean;

  @CreateDateColumn()
  createdAt: Date;
}