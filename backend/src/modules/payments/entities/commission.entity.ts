import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  OneToOne,
  ManyToOne,
  JoinColumn,
  CreateDateColumn,
  UpdateDateColumn,
  Index,
} from 'typeorm';
import { Order } from '../../orders/entities/order.entity';
import { VendorProfile } from '../../users/entities/vendor-profile.entity';
import { AdminAccount } from '../../auth/entities/admin-account.entity';

export enum CommissionStatus {
  PENDING = 'en attente', // commission calculée, reversement pas encore fait
  PAID    = 'payé',    // montant reversé au vendeur
}

@Index(['vendorId'])
@Index(['status'])
@Index(['createdAt'])
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

  // Base de calcul de la commission = produits APRÈS remise (subtotal − rabais),
  // SANS les frais de livraison (qui reviennent au livreur et à la plateforme,
  // jamais au vendeur). Ce n'est donc plus le total payé par le client.
  @Column({ type: 'decimal', precision: 12, scale: 2 })
  totalCommande: number;

  // Taux de commission en pourcentage
  // Ex: 10.00 = 10%
  // Peut varier selon le vendeur ou la catégorie
  @Column({ type: 'decimal', precision: 5, scale: 2 })
  taux: number;

  // Mode de calcul utilisé pour CETTE commande : 'percent' (taux ci-dessus) ou
  // 'fixed' (montant fixe par commande ; `taux` est alors le pourcentage
  // équivalent, à titre d'information).
  @Column({ type: 'varchar', length: 10, default: 'percent' })
  typeCommission: string;

  // Montant prélevé par Asoukaa
  // Calculé : totalCommande (base produits) * taux / 100
  @Column({ type: 'decimal', precision: 12, scale: 2 })
  montantCommission: number;

  // Montant reversé au vendeur
  // Calculé : totalCommande (base produits) - montantCommission
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

  // Date à partir de laquelle le gain peut être retiré par le vendeur.
  // null = disponible dès que la commande est « livrée » (produits physiques).
  // Livre numérique : paiement + 24 h (le client a 24 h pour signaler un souci).
  @Column({ nullable: true, type: 'timestamp' })
  availableAt: Date | null;

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