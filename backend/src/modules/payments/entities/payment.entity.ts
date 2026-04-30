import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  OneToOne,
  JoinColumn,
  CreateDateColumn,
  Index,
} from 'typeorm';
import { Order } from '../../orders/entities/order.entity';

export enum PaymentMethod {
  MOBILE_MONEY     = 'mobile_money',
  CARD             = 'card',
  CASH_ON_DELIVERY = 'cash_on_delivery',
}

export enum PaymentOperator {
  MTN        = 'MTN',
  MOOV       = 'Moov',
  WAVE       = 'Wave',
  VISA       = 'Visa',
  MASTERCARD = 'Mastercard',
}

export enum PaymentStatus {
  PENDING  = 'en attente',   // en attente de confirmation
  SUCCESS  = 'success',   // paiement confirmé
  FAILED   = 'échoué',    // paiement échoué
  REFUNDED  = 'remboursé',  // remboursé
}

@Entity('payments')
export class Payment {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  // Une commande = un seul paiement
  @Column({ unique: true })
  orderId: string;

  @OneToOne(() => Order, {
    onDelete: 'RESTRICT',
    // ⚠️ RESTRICT car un paiement est une donnée
    // financière — ne jamais supprimer automatiquement
  })
  @JoinColumn({ name: 'orderId' })
  order: Order;

  @Column({
    type: 'enum',
    enum: PaymentMethod,
  })
  method: PaymentMethod;

  // Nullable car pas d'opérateur pour cash on delivery
  @Column({
    type: 'enum',
    enum: PaymentOperator,
    nullable: true,
  })
  operator: PaymentOperator;

  @Column({
    type: 'enum',
    enum: PaymentStatus,
    default: PaymentStatus.PENDING,
  })
  status: PaymentStatus;

  // Référence donnée par l'opérateur de paiement
  // Ex: référence MTN Mobile Money, ID transaction Stripe
  // ⚠️ PRODUCTION : cette référence sert à vérifier
  // le paiement côté opérateur en cas de litige
  @Index()
  @Column({ nullable: true, length: 255 })
  providerRef: string;

  @Column({ type: 'decimal', precision: 12, scale: 2 })
  montant: number;

  // Rempli uniquement quand status = 'success'
  @Column({ nullable: true, type: 'timestamp' })
  paidAt: Date;

  @CreateDateColumn()
  createdAt: Date;
}