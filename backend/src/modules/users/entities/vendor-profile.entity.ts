import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  OneToOne,
  JoinColumn,
  ManyToOne,
  CreateDateColumn,
  UpdateDateColumn,
  Index,
} from 'typeorm';
import { User } from './user.entity';
import { AdminAccount } from '../../auth/entities/admin-account.entity';

export enum VendorStatus {
  PENDING  = 'en attente',   // vient de soumettre sa demande
  APPROVED = 'approuvé',  // validé par l'admin
  REJECTED = 'rejeté',  // refusé, peut re-soumettre
  BLOCKED  = 'bloqué',   // bloqué définitivement
}

export enum PaymentMethod {
  MOBILE_MONEY = 'mobile_money',
  BANK         = 'bank',
}

@Entity('vendor_profiles')
export class VendorProfile {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  // Un utilisateur ne peut avoir qu'UNE seule boutique
  // OneToOne + unique garantit cette règle en base de données
  @Column({ unique: true })
  userId: string;

  @OneToOne(() => User, {
    onDelete: 'CASCADE',
  })
  @JoinColumn({ name: 'userId' })
  user: User;

  // ─── Informations de la boutique ───────────────────────

  @Index()
  @Column({ unique: true, length: 255 })
  shopName: string;

  @Column({ type: 'text' })
  shopAddress: string;

  @Column({ length: 100 })
  activityType: string;

  @Column({ type: 'text' })
  description: string;

  // Ajoutés UNIQUEMENT après validation
  // ⚠️ PRODUCTION : vérifier que status = 'approved'
  // avant d'autoriser l'upload du logo et de la bannière
  @Column({ nullable: true, length: 500 })
  logoUrl: string;

  @Column({ nullable: true, length: 500 })
  bannerUrl: string;

  // ─── Documents de vérification ─────────────────────────

  @Column({ length: 500 })
  idDocumentUrl: string;

  @Column({ length: 500 })
  selfieUrl: string;

  // Tableau d'URLs pour les 2-3 photos de produits exemples
  @Column({ type: 'text', array: true, default: [] })
  sampleProductUrls: string[];

  // ─── Validation ────────────────────────────────────────

  @Column({
    type: 'enum',
    enum: VendorStatus,
    default: VendorStatus.PENDING,
  })
  status: VendorStatus;

  // Rempli quand l'admin refuse la demande
  @Column({ nullable: true, type: 'text' })
  MotifRefus: string;

  // true = a lu et accepté les conditions
  @Column({ default: false })
  termsAccepted: boolean;

  // true = a accepté les pénalités en cas de fraude
  @Column({ default: false })
  fraudPenaltiesAccepted: boolean;

  // Combien de fois le vendeur a soumis sa demande
  // Utile pour détecter les abus de re-soumission
  @Column({ default: 1 })
  submissionCount: number;

  @Column({ type: 'timestamp', nullable: true })
  submittedAt: Date;

  // ─── Décision de l'admin ───────────────────────────────

  @Column({ nullable: true })
  reviewedById: string;

  // Quel admin a pris la décision
  @ManyToOne(() => AdminAccount, { nullable: true })
  @JoinColumn({ name: 'reviewedById' })
  reviewedBy: AdminAccount;

  @Column({ type: 'timestamp', nullable: true })
  reviewedAt: Date;

  // ─── Paiement (configuré après validation) ─────────────

  @Column({
    type: 'enum',
    enum: PaymentMethod,
    nullable: true,
  })
  paymentMethod: PaymentMethod;

  // ⚠️ PRODUCTION : les données bancaires sont sensibles
  // En production réelle, chiffrer ce champ avec une clé
  // ou utiliser un service tiers (Stripe Connect, etc.)
  @Column({ type: 'jsonb', nullable: true })
  paymentDetails: Record<string, any>;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}