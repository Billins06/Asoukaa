import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  OneToMany,
  OneToOne,
  JoinColumn,
  CreateDateColumn,
  UpdateDateColumn,
  Index,
} from 'typeorm';
import { User } from '../../users/entities/user.entity';
import { VendorProfile } from '../../users/entities/vendor-profile.entity';
import { Address } from '../../users/entities/address.entity';
import { Coupon } from '../../coupons/entities/coupon.entity';
import { OrderItem } from './order-item.entity';

export enum OrderStatus {
  PENDING    = 'en attente',
  IN_PROGRESS  = 'en cours',
  SHIPPED    = 'expedié',
  DELIVERED  = 'livré',
  CANCELLED  = 'annulé',
}

@Entity('orders')
export class Order {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  // Numéro lisible par l'humain
  // Ex: ASK-2025-00124
  @Index()
  @Column({ unique: true, length: 50 })
  orderNumber: string;

  // Le client qui a passé la commande
  @Column()
  userId: string;

  @ManyToOne(() => User, {
    onDelete: 'RESTRICT',
    // ⚠️ RESTRICT et non CASCADE car on ne veut jamais
    // supprimer des commandes quand un user est supprimé
    // Les commandes sont des données financières à conserver
  })
  @JoinColumn({ name: 'userId' })
  user: User;

  // La boutique concernée
  // Une commande = une boutique
  @Column()
  vendorId: string;

  @ManyToOne(() => VendorProfile, {
    onDelete: 'RESTRICT',
  })
  @JoinColumn({ name: 'vendorId' })
  vendor: VendorProfile;

  // Adresse de livraison choisie par le client
  @Column()
  addressId: string;

  @ManyToOne(() => Address, {
    onDelete: 'RESTRICT',
  })
  @JoinColumn({ name: 'addressId' })
  address: Address;

  // Coupon appliqué — nullable car optionnel
  @Column({ nullable: true })
  couponId: string;

  @ManyToOne(() => Coupon, {
    nullable: true,
    onDelete: 'SET NULL',
  })
  @JoinColumn({ name: 'couponId' })
  coupon: Coupon;

  @Column({
    type: 'enum',
    enum: OrderStatus,
    default: OrderStatus.PENDING,
  })
  status: OrderStatus;

  // Instructions laissées par le client
  // Ex: "Sonner deux fois", "Laisser chez le gardien"
  @Column({ nullable: true, type: 'text' })
  instructions: string;

  // ─── Calculs financiers ────────────────────────────────

  // Somme des articles sans frais
  @Column({ type: 'decimal', precision: 12, scale: 2 })
  subtotal: number;

  @Column({ type: 'decimal', precision: 12, scale: 2, default: 0 })
  fraisLivraison: number;

  // Montant de la réduction coupon
  @Column({ type: 'decimal', precision: 12, scale: 2, default: 0 })
  rabais: number;

  // Commission prélevée par Asoukaa
  @Column({ type: 'decimal', precision: 12, scale: 2, default: 0 })
  montantCommission: number;

  // Total final payé par le client
  @Column({ type: 'decimal', precision: 12, scale: 2 })
  total: number;

  // Raison de l'annulation si applicable
  @Column({ nullable: true, type: 'text' })
  motifAnnulation: string;

  // ─── Relations ─────────────────────────────────────────

  @OneToMany(() => OrderItem, (item) => item.order, {
    cascade: true,
  })
  items: OrderItem[];

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}