import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  Index,
  ManyToOne,
  JoinColumn,
} from 'typeorm';
import { User } from '../entities/user.entity';

export enum EmailChangeStatus {
  PENDING   = 'pending',   // code envoyé à la nouvelle adresse, pas encore saisi
  CONFIRMED = 'confirmed', // users.email remplacé ; le lien « Ce n'est pas moi » est actif
  REVERTED  = 'reverted',  // le propriétaire a répondu « Ce n'est pas moi »
  CANCELLED = 'cancelled', // remplacée par une autre demande, trop d'essais, envoi raté...
  EXPIRED   = 'expired',   // code non saisi à temps
}

// Une seule demande « pending » par utilisateur, garantie par la base
// (index unique partiel) : deux requêtes simultanées ne peuvent pas créer
// deux demandes actives, donc « la demande en attente » est toujours sans
// ambiguïté. Les noms d'index sont ceux de la migration AddEmailChange.
@Index('UQ_email_changes_one_pending_per_user', ['userId'], {
  unique: true,
  where: `"status" = 'pending'`,
})
@Entity('email_changes')
export class EmailChange {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Index('IDX_email_changes_userId')
  @Column({ type: 'uuid' })
  userId: string;

  @ManyToOne(() => User, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'userId' })
  user: User;

  @Column({ type: 'varchar', length: 255 })
  oldEmail: string;

  @Column({ type: 'varchar', length: 255 })
  newEmail: string;

  // ⚠️ Le code à 6 chiffres n'est JAMAIS stocké en clair : hash bcrypt.
  @Column({ type: 'varchar', length: 255 })
  codeHash: string;

  // Essais ratés/consommés sur le code courant (voir MAX_ATTEMPTS du service)
  @Column({ type: 'int', default: 0 })
  attempts: number;

  // Nombre d'envois de code pour cette demande (1er envoi inclus) :
  // plafonne les « renvoyer le code » pour ne pas spammer la nouvelle adresse.
  @Column({ type: 'int', default: 1 })
  sendCount: number;

  @Column({ type: 'timestamp' })
  codeExpiresAt: Date;

  @Column({ type: 'timestamp' })
  lastSentAt: Date;

  @Column({ type: 'varchar', length: 20, default: EmailChangeStatus.PENDING })
  status: EmailChangeStatus;

  // ⚠️ SHA-256 (hex) du jeton de révocation ; le jeton brut n'existe que
  // dans l'e-mail envoyé à l'ancienne adresse. Mis à NULL une fois utilisé
  // ou invalidé. SHA-256 (et non bcrypt) car le jeton fait 256 bits
  // aléatoires : inutile de ralentir, et il faut pouvoir le retrouver par
  // simple égalité en base.
  @Index('IDX_email_changes_revertTokenHash')
  @Column({ type: 'varchar', length: 64, nullable: true })
  revertTokenHash: string | null;

  @Column({ type: 'timestamp', nullable: true })
  revertExpiresAt: Date | null;

  @Column({ type: 'timestamp', nullable: true })
  confirmedAt: Date | null;

  @Column({ type: 'timestamp', nullable: true })
  revertedAt: Date | null;

  @CreateDateColumn()
  createdAt: Date;
}
