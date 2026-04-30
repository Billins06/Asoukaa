import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  OneToOne,
  ManyToOne,
  JoinColumn,
  CreateDateColumn,
  UpdateDateColumn,
} from 'typeorm';
import { Order } from '../../orders/entities/order.entity';
import { VendorProfile } from '../../users/entities/vendor-profile.entity';
import { AdminAccount } from '../../auth/entities/admin-account.entity';

export enum CommissionStatus {
  PENDING = 'en attente', // commission calculée, reversement pas encore fait
  PAID    = 'payé',    // montant reversé au vendeur
}

@Entity('commissions')
export class Commission {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  // Une commission par commande
  @Column({ unique: true })
  orderId: string;

  @OneToOne(() => Order, {
    onDelete: 'RESTRICT',
  })
  @JoinColumn({ name: 'orderId' })
  order: Order;

  @Column()
  vendorId: string;

  @ManyToOne(() => VendorProfile, {
    onDelete: 'RESTRICT',
  })
  @JoinColumn({ name: 'vendorId' })
  vendor: VendorProfile;

  // Montant total de la commande
  @Column({ type: 'decimal', precision: 12, scale: 2 })
  totalCommande: number;

  // Taux de commission en pourcentage
  // Ex: 10.00 = 10%
  // Peut varier selon le vendeur ou la catégorie
  @Column({ type: 'decimal', precision: 5, scale: 2 })
  taux: number;

  // Montant prélevé par Asoukaa
  // Calculé : orderTotal * rate / 100
  @Column({ type: 'decimal', precision: 12, scale: 2 })
  montantCommission: number;

  // Montant reversé au vendeur
  // Calculé : orderTotal - commissionAmount
  @Column({ type: 'decimal', precision: 12, scale: 2 })
  commissionVendor: number;

  @Column({
    type: 'enum',
    enum: CommissionStatus,
    default: CommissionStatus.PENDING,
  })
  status: CommissionStatus;

  // Rempli quand le reversement est effectué
  @Column({ nullable: true, type: 'timestamp' })
  paidAt: Date;

  // Quel admin a validé le reversement
  @Column({ nullable: true })
  processedById: string;

  @ManyToOne(() => AdminAccount, { nullable: true })
  @JoinColumn({ name: 'processedById' })
  processedBy: AdminAccount;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}   