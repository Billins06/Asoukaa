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
import { DeliveryAgentProfile } from '../../users/entities/delivery-agent-profile.entity';

export enum DeliveryStatus {
  PENDING    = 'en attente',     // commande créée, pas encore de livreur
  ASSIGNED   = 'assigné',    // livreur affecté par le vendeur
  PICKED_UP  = 'récupéré',   // livreur a récupéré le colis
  IN_TRANSIT = 'en cours de livraison',  // en cours de livraison
  DELIVERED  = 'livré',   // livré avec succès
  FAILED     = 'livraison echouée',      // échec de livraison
}

@Entity('deliveries')
export class Delivery {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  // Une commande = une seule livraison
  @Column({ unique: true })
  orderId: string;

  @OneToOne(() => Order, {
    onDelete: 'RESTRICT',
    // ⚠️ RESTRICT — une livraison est une donnée
    // importante, ne jamais supprimer automatiquement
  })
  @JoinColumn({ name: 'orderId' })
  order: Order;

  // Nullable car le livreur est affecté après création
  // La livraison existe dès que la commande est créée
  @Column({ nullable: true })
  agentId: string;

  @ManyToOne(() => DeliveryAgentProfile, {
    nullable: true,
    onDelete: 'SET NULL',
    // SET NULL car si le profil livreur est supprimé
    // on veut garder l'historique de la livraison
  })
  @JoinColumn({ name: 'agentId' })
  agent: DeliveryAgentProfile;

  // Adresse du vendeur (point de départ)
  @Column({ type: 'text' })
  pickupAddress: string;

  // Adresse du client (destination)
  @Column({ type: 'text' })
  adresseLivraison: string;

  @Column({
    type: 'enum',
    enum: DeliveryStatus,
    default: DeliveryStatus.PENDING,
  })
  status: DeliveryStatus;

  // Instructions spéciales pour le livreur
  // Ex: "Appeler avant d'arriver"
  @Column({ nullable: true, type: 'text' })
  instructions: string;

  // Rempli quand le livreur récupère le colis
  @Column({ nullable: true, type: 'timestamp' })
  pickedUpAt: Date;

  // Rempli quand la livraison est confirmée
  @Column({ nullable: true, type: 'timestamp' })
  deliveredAt: Date;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}