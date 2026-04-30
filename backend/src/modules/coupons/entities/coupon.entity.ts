import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  OneToMany,
  JoinColumn,
  CreateDateColumn,
  UpdateDateColumn,
  Index,
} from 'typeorm';
import { AdminAccount } from '../../auth/entities/admin-account.entity';
import { VendorProfile } from '../../users/entities/vendor-profile.entity';

export enum CouponType {
  PERCENTAGE   = 'pourcentage',   // réduction en pourcentage (ex: 20%)
  FIXED_AMOUNT = 'prix fixe', // réduction fixe (ex: 2000 FCFA)
}

@Entity('coupons')
export class Coupon {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  // Code saisi par le client au moment du paiement
  // Ex: ASOUKAA20, PROMO500
  @Index()
  @Column({ unique: true, length: 50 })
  code: string;

  // Qui a créé ce coupon — admin ou vendeur
  // Les deux sont nullable car c'est soit l'un soit l'autre
  @Column({ nullable: true })
  createdByAdminId: string;

  @ManyToOne(() => AdminAccount, {
    nullable: true,
    onDelete: 'SET NULL',
  })
  @JoinColumn({ name: 'createdByAdminId' })
  createdByAdmin: AdminAccount;

  @Column({ nullable: true })
  createdByVendorId: string;

  @ManyToOne(() => VendorProfile, {
    nullable: true,
    onDelete: 'SET NULL',
  })
  @JoinColumn({ name: 'createdByVendorId' })
  createdByVendor: VendorProfile;

  // Si coupon limité à une boutique spécifique
  // Null = valable sur toute la plateforme
  @Column({ nullable: true })
  vendorId: string;

  @ManyToOne(() => VendorProfile, {
    nullable: true,
    onDelete: 'SET NULL',
  })
  @JoinColumn({ name: 'vendorId' })
  vendor: VendorProfile;

  @Column({
    type: 'enum',
    enum: CouponType,
  })
  type: CouponType;

  // Valeur de la réduction
  // Ex: 20 pour 20% ou 2000 pour 2000 FCFA
  @Column({ type: 'decimal', precision: 12, scale: 2 })
  value: number;

  // Montant minimum de commande pour utiliser ce coupon
  // Nullable = pas de minimum
  @Column({ nullable: true, type: 'decimal', precision: 12, scale: 2 })
  minOrderAmount: number;

  // Nombre maximum d'utilisations au total
  // Nullable = illimité
  @Column({ nullable: true })
  maxUses: number;

  // Compteur d'utilisations actuelles
  @Column({ default: 0 })
  usedCount: number;

  // Date d'expiration
  // Nullable = pas d'expiration
  @Column({ nullable: true, type: 'timestamp' })
  expiresAt: Date;

  @Column({ default: true })
  isActive: boolean;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}