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
  // Course express « négociée » (migration 1791860000000) :
  COUNTER_OFFER    = 'contre-proposition', // un livreur propose un autre prix, le client doit répondre
  AWAITING_PAYMENT = 'paiement en attente', // prix convenu, le client doit payer (Mobile Money)
}

// Délai de livraison choisi par le client (remplace l'ancienne « vitesse »).
export enum IndependentDelay {
  NORMAL  = 'normal',   // dans la journée
  URGENT  = 'urgent',   // 2 à 3 h
  EXPRESS = 'express',  // moins d'1 h
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
  agentId: string | null;

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
  adresseLivraison: string;

  // Description du colis
  // Ex: "Carton de 5kg contenant des vêtements"
  @Column({ nullable: true, type: 'text' })
  packageDescription: string | null;

  @Column({
    type: 'enum',
    enum: IndependentDeliveryStatus,
    default: IndependentDeliveryStatus.PENDING,
  })
  status: IndependentDeliveryStatus;

  // ⏳ Tarif à confirmer avec l'équipe
  // Nullable pour l'instant
  @Column({ nullable: true, type: 'decimal', precision: 12, scale: 2 })
  tarifConvenu: number | null;

  // ─── Course express négociée (migration 1791860000000) ───

  @Column({ type: 'varchar', length: 20, default: IndependentDelay.NORMAL })
  delai: IndependentDelay;

  // Notes pour le livreur (étage, contact sur place...)
  @Column({ type: 'text', nullable: true })
  notes: string | null;

  // Prix proposé par le client à la création
  @Column({ type: 'decimal', precision: 12, scale: 2, nullable: true })
  proposedPrice: number | null;

  // Contre-proposition du livreur (une seule par livreur)
  @Column({ type: 'decimal', precision: 12, scale: 2, nullable: true })
  counterPrice: number | null;

  // Livreurs dont la contre-proposition a été refusée (ils ne peuvent plus
  // répondre à cette demande). Texte « id1,id2 ».
  @Column({ type: 'text', nullable: true })
  refusedAgentIds: string | null;

  // Réservation temporaire du livreur (contre-proposition / paiement) :
  // passé ce délai, la demande redevient disponible pour tous.
  @Column({ type: 'timestamp', nullable: true })
  reservedUntil: Date | null;

  // Paiement Mobile Money (FeexPay) : 'en attente' | 'success' | 'échoué'
  @Column({ type: 'varchar', length: 20, nullable: true })
  paymentStatus: string | null;

  @Column({ type: 'varchar', length: 255, nullable: true })
  paymentRef: string | null;

  @Column({ type: 'varchar', length: 10, nullable: true })
  paymentOperator: string | null;

  @Column({ type: 'timestamp', nullable: true })
  paidAt: Date | null;

  @Column({ type: 'timestamp', nullable: true })
  paymentRequestedAt: Date | null;

  // ── Administration (migration 1791880000000) ──
  // Motif d'annulation (client, système ou administrateur).
  @Column({ type: 'text', nullable: true })
  cancelReason: string | null;

  // Remboursement d'une course PAYÉE puis annulée : 'à rembourser' puis 'remboursé'
  // (le virement se fait à la main chez FeexPay / Mobile Money).
  @Column({ type: 'varchar', length: 20, nullable: true })
  refundStatus: string | null;

  @Column({ type: 'timestamp', nullable: true })
  refundedAt: Date | null;

  // Note interne de l'administration (jamais montrée aux clients/livreurs).
  @Column({ type: 'text', nullable: true })
  adminNote: string | null;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}