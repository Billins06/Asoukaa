import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  JoinColumn,
  CreateDateColumn,
  UpdateDateColumn,
} from 'typeorm';
import { User } from '../../users/entities/user.entity';
import { DeliveryAgentProfile } from '../../users/entities/delivery-agent-profile.entity';

export enum IndependentDeliveryStatus {
  PENDING    = 'en attente',    // demande soumise, en attente d'un livreur
  ACCEPTED   = 'accepté',   // un livreur a accepté
  IN_TRANSIT = 'en cours de livraison', // en cours de livraison
  DELIVERED  = 'livré',  // livré avec succès
  CANCELLED  = 'annulée',  // annulée par le client ou le livreur
}

@Entity('independent_deliveries')
export class IndependentDelivery {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  // Le client qui fait la demande de livraison
  @Column()
  requesterId: string;

  @ManyToOne(() => User, {
    onDelete: 'RESTRICT',
  })
  @JoinColumn({ name: 'requesterId' })
  requester: User;

  // Nullable — sera rempli quand un livreur accepte
  @Column({ nullable: true })
  agentId: string;

  @ManyToOne(() => DeliveryAgentProfile, {
    nullable: true,
    onDelete: 'SET NULL',
  })
  @JoinColumn({ name: 'agentId' })
  agent: DeliveryAgentProfile;

  // Adresse de départ du colis
  @Column({ type: 'text' })
  pickupAddress: string;

  // Adresse de destination
  @Column({ type: 'text' })
  deliveryAddress: string;

  // Description du colis
  // Ex: "Carton de 5kg contenant des vêtements"
  @Column({ nullable: true, type: 'text' })
  packageDescription: string;

  @Column({
    type: 'enum',
    enum: IndependentDeliveryStatus,
    default: IndependentDeliveryStatus.PENDING,
  })
  status: IndependentDeliveryStatus;

  // ⏳ Tarif à confirmer avec l'équipe
  // Nullable pour l'instant
  @Column({ nullable: true, type: 'decimal', precision: 12, scale: 2 })
  tarifConvenu: number;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}