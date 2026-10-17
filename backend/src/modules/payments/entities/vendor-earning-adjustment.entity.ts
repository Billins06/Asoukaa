import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  JoinColumn,
  CreateDateColumn,
  Index,
} from 'typeorm';
import { Refund } from './refund.entity';
import { Commission } from './commission.entity';
import { Order } from '../../orders/entities/order.entity';
import { VendorProfile } from '../../users/entities/vendor-profile.entity';

// Reprise sur les gains d'un vendeur suite à un remboursement CLIENT approuvé.
//
// Image : le vendeur a une « tirelire » (ses gains). Quand le client est
// remboursé, on reprend dans la tirelire la part qui lui avait été créditée
// pour cette commande. Cette table est le « carnet » de ces reprises : une
// ligne par remboursement approuvé, jamais modifiée ni supprimée ensuite.
//
// Règles :
//  - UNE seule ligne par remboursement (index unique sur refundId) : relancer
//    l'approbation ne peut jamais reprendre deux fois ;
//  - la ligne `commissions` d'origine n'est PAS modifiée (traçabilité) : le
//    solde = gains − reprises, calculé à la demande (voir
//    VendorWithdrawalsService.computeBalance) ;
//  - montantVendeur = 0 quand la commande n'avait jamais été livrée (un gain
//    non livré n'est pas dans la tirelire : rien à reprendre).
@Index('UQ_vendor_earning_adjustments_refund', ['refundId'], { unique: true })
@Index('IDX_vendor_earning_adjustments_vendor', ['vendorId'])
@Index('IDX_vendor_earning_adjustments_order', ['orderId'])
@Entity('vendor_earning_adjustments')
export class VendorEarningAdjustment {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  refundId: string;

  @ManyToOne(() => Refund, { onDelete: 'RESTRICT' })
  @JoinColumn({ name: 'refundId' })
  refund: Refund;

  @Column()
  orderId: string;

  @ManyToOne(() => Order, { onDelete: 'RESTRICT' })
  @JoinColumn({ name: 'orderId' })
  order: Order;

  // Peut être absent si la commande n'avait pas de ligne de commission.
  @Column({ type: 'uuid', nullable: true })
  commissionId: string | null;

  @ManyToOne(() => Commission, { nullable: true, onDelete: 'RESTRICT' })
  @JoinColumn({ name: 'commissionId' })
  commission: Commission | null;

  @Column()
  vendorId: string;

  @ManyToOne(() => VendorProfile, { onDelete: 'RESTRICT' })
  @JoinColumn({ name: 'vendorId' })
  vendor: VendorProfile;

  // Montant remboursé au client (refunds.montantRemb) et total payé de la
  // commande (payments.montant) au moment de l'approbation.
  @Column({ type: 'decimal', precision: 12, scale: 2 })
  montantRembourse: number;

  @Column({ type: 'decimal', precision: 12, scale: 2 })
  totalPaye: number;

  // Proportion remboursée = montantRembourse / totalPaye (0 à 1, 6 décimales).
  @Column({ type: 'decimal', precision: 8, scale: 6 })
  proportion: number;

  // Montant REPRIS au vendeur (proportion × commissions.commissionVendor).
  @Column({ type: 'decimal', precision: 12, scale: 2, default: 0 })
  montantVendeur: number;

  // Part de commission RENDUE par la plateforme (proportion ×
  // commissions.montantCommission). Information comptable : n'entre pas dans
  // le solde du vendeur.
  @Column({ type: 'decimal', precision: 12, scale: 2, default: 0 })
  montantCommission: number;

  // Explication lisible (ex. « commande non livrée : aucun gain à reprendre »).
  @Column({ type: 'text', nullable: true })
  note: string | null;

  @CreateDateColumn()
  createdAt: Date;
}
