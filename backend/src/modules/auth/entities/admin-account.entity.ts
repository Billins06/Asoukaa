import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  JoinColumn,
  CreateDateColumn,
  UpdateDateColumn,
  Index,
} from 'typeorm';

export enum AdminRole {
  ADMIN      = 'admin',
  SUPERADMIN = 'superadmin',
}

@Entity('admin_accounts')
export class AdminAccount {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Index()
  @Column({ length: 100 })
  prenom: string;

  @Index()
  @Column({ length: 100 })
  name: string;

  @Index()
  @Column({ unique: true, length: 255 })
  email: string;

  // ⚠️ PRODUCTION : ne jamais retourner ce champ dans les réponses API
  // Nullable car le mot de passe est défini APRÈS la création du compte
  // (via le lien d'invitation reçu par email)
  @Column({ nullable: true, length: 255 })
  passwordHash: string;

  @Column({
    type: 'enum',
    enum: AdminRole,
    default: AdminRole.ADMIN,
  })
  role: AdminRole;

  @Column({ default: true })
  isActive: boolean;

  // false tant que l'admin n'a pas défini son mot de passe
  // via le lien d'invitation
  @Column({ default: false })
  isPasswordSet: boolean;

  // Token envoyé par email pour activer le compte
  // ⚠️ PRODUCTION : ce token doit être hashé en base
  // et supprimé après utilisation
  @Column({ type: 'varchar', nullable: true, length: 255 })
  invitationToken: string | null;

  @Column({ nullable: true, type: 'timestamp' })
  invitationExpiresAt: Date | null;

  // Qui a créé cet admin (auto-référence)
  // Nullable car le tout premier superadmin n'a pas de créateur
  @Column({ nullable: true })
  createdById: string;

  @ManyToOne(() => AdminAccount, { nullable: true })
  @JoinColumn({ name: 'createdById' })
  createdBy: AdminAccount;

  @Column({ nullable: true, type: 'timestamp' })
  lastLoginAt: Date;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
