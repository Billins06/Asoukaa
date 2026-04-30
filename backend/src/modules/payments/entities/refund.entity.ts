import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  OneToOne,
  JoinColumn,
  CreateDateColumn,
  UpdateDateColumn,
} from 'typeorm';
import { Payment } from './payment.entity';
import { Order } from '../../orders/entities/order.entity';
import { AdminAccount } from '../../auth/entities/admin-account.entity';

export enum RefundStatus {
  PENDING   = 'en attente',   // demande soumise
  APPROVED  = 'approuvé',  // approuvée par l'admin
  REJECTED  = 'rejetté',  // refusée par l'admin
  PROCESSED = 'traité', // remboursement effectué
}

@Entity('refunds')
export class Refund {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  // Lié au paiement concerné
  @Column()
  paymentId: string;

  @OneToOne(() => Payment, {
    onDelete: 'RESTRICT',
  })
  @JoinColumn({ name: 'paymentId' })
  payment: Payment;

  // Lié à la commande concernée
  @Column()
  orderId: string;

  @ManyToOne(() => Order, {
    onDelete: 'RESTRICT',
  })
  @JoinColumn({ name: 'orderId' })
  order: Order;

  // Montant à rembourser
  // Peut être inférieur au total si remboursement partiel
  @Column({ type: 'decimal', precision: 12, scale: 2 })
  montantRemb: number;

  // Raison du remboursement
  // Ex: "Produit non conforme", "Commande annulée"
  @Column({ type: 'text' })
  motif: string;

  @Column({
    type: 'enum',
    enum: RefundStatus,
    default: RefundStatus.PENDING,
  })
  status: RefundStatus;

  // Date de la demande
  @CreateDateColumn()
  dateDemande: Date;

  // Date de traitement par l'admin
  @Column({ nullable: true, type: 'timestamp' })
  processedAt: Date;

  // Quel admin a traité le remboursement
  @Column({ nullable: true })
  processedById: string;

  @ManyToOne(() => AdminAccount, { nullable: true })
  @JoinColumn({ name: 'processedById' })
  processedBy: AdminAccount;

  @UpdateDateColumn()
  updatedAt: Date;
}