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
  // Livre numérique à 0 F : aucun paiement réel (jamais proposé au client).
  FREE             = 'free',
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

@Index(['status'])
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
  operator: PaymentOperator | null;

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

  // Panier réparti sur plusieurs boutiques -> une commande par boutique,
  // mais UN SEUL paiement pour le client. On crée quand même une ligne
  // Payment par commande (orderId reste unique en base), mais toutes les
  // lignes issues du même paiement client partagent ce groupRef pour
  // pouvoir toutes les confirmer/échouer ensemble.
  // ⚠️ `type: 'varchar'` explicite : avec le type TS `string | null`,
  // TypeScript émet `design:type = Object` et TypeORM ne peut plus déduire
  // le type de colonne → DataTypeNotSupportedError au démarrage.
  // Tout champ `X | null` doit déclarer son type SQL.
  @Index()
  @Column({ type: 'varchar', length: 64, nullable: true })
  groupRef: string | null;

  // Rempli uniquement quand status = 'success'
  @Column({ nullable: true, type: 'timestamp' })
  paidAt: Date;

  // « Paiements à examiner » : renseignés quand un admin a traité le dossier
  // (migration 1791840000000). Un paiement avec reviewedAt sort de la liste.
  // select:false = jamais renvoyé par les lectures normales (note interne de l'admin).
  @Column({ nullable: true, type: 'timestamp', select: false })
  reviewedAt: Date | null;

  @Column({ type: 'uuid', nullable: true, select: false })
  reviewedBy: string | null;

  @Column({ type: 'varchar', length: 500, nullable: true, select: false })
  reviewNote: string | null;

  @CreateDateColumn()
  createdAt: Date;
}