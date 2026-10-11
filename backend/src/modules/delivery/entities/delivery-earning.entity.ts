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
import { Delivery } from './delivery.entity';
import { DeliveryAgentProfile } from '../../users/entities/delivery-agent-profile.entity';
import { AdminAccount } from '../../auth/entities/admin-account.entity';

// Même logique que Commission (voir payments/entities/commission.entity.ts),
// côté livreur cette fois : combien le livreur gagne sur CETTE livraison,
// et si ça lui a déjà été viré ou non.
export enum DeliveryEarningStatus {
  PENDING = 'en attente',
  PAID    = 'payé',
}

@Index(['agentId'])
@Index(['status'])
@Entity('delivery_earnings')
export class DeliveryEarning {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  // Une livraison = un seul gain (calculé une fois, à la remise au client)
  @Column({ unique: true })
  deliveryId: string;

  @OneToOne(() => Delivery, {
    onDelete: 'RESTRICT',
  })
  @JoinColumn({ name: 'deliveryId' })
  delivery: Delivery;

  @Column()
  agentId: string;

  @ManyToOne(() => DeliveryAgentProfile, {
    onDelete: 'RESTRICT',
  })
  @JoinColumn({ name: 'agentId' })
  agent: DeliveryAgentProfile;

  // Frais de livraison de la commande au moment du calcul (copié depuis
  // Order.fraisLivraison — même si la commande change ensuite, ce montant
  // reste celui qui a servi de base au calcul, pour l'historique).
  @Column({ type: 'decimal', precision: 12, scale: 2 })
  fraisLivraison: number;

  // Pourcentage du livreur appliqué à CE calcul (copié depuis
  // DeliveryAgentProfile.earningsRate au moment du calcul — si l'admin
  // change le taux du livreur plus tard, l'historique n'est pas réécrit).
  @Column({ type: 'decimal', precision: 5, scale: 2 })
  taux: number;

  // Part du livreur = fraisLivraison * taux / 100
  @Column({ type: 'decimal', precision: 12, scale: 2 })
  montantLivreur: number;

  // Part de la plateforme = fraisLivraison - montantLivreur
  @Column({ type: 'decimal', precision: 12, scale: 2 })
  montantPlateforme: number;

  @Column({
    type: 'enum',
    enum: DeliveryEarningStatus,
    default: DeliveryEarningStatus.PENDING,
  })
  status: DeliveryEarningStatus;

  @Column({ type: 'timestamp', nullable: true })
  paidAt: Date | null;

  @Column({ nullable: true })
  processedById: string | null;

  @ManyToOne(() => AdminAccount, { nullable: true })
  @JoinColumn({ name: 'processedById' })
  processedBy: AdminAccount;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
