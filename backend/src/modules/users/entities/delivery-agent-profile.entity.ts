import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  OneToOne,
  JoinColumn,
  ManyToOne,
  CreateDateColumn,
  UpdateDateColumn,
} from 'typeorm';
import { User } from './user.entity';
import { AdminAccount } from '../../auth/entities/admin-account.entity';

export enum VehicleType {
  MOTO     = 'moto',
  VOITURE  = 'voiture',
  TRICYCLE = 'tricycle',
  VELO     = 'velo',
}

export enum Availability {
  FULL_TIME = 'Temps_plein',
  PART_TIME = 'Temps_partiel',
}

export enum AgentStatus {
  PENDING  = 'en attente',   // vient de soumettre sa demande
  APPROVED = 'approuvé',  // validé par l'admin
  REJECTED = 'rejeté',  // refusé, peut re-soumettre
  BLOCKED  = 'bloqué',   // bloqué définitivement
}

@Entity('delivery_agent_profiles')
export class DeliveryAgentProfile {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  // Un utilisateur = un seul profil livreur
  @Column({ unique: true })
  userId: string;

  @OneToOne(() => User, {
    onDelete: 'CASCADE',
  })
  @JoinColumn({ name: 'userId' })
  user: User;

  // ─── Informations professionnelles ─────────────────────

  @Column({
    type: 'enum',
    enum: VehicleType,
  })
  vehicleType: VehicleType;

  @Column({
    type: 'enum',
    enum: Availability,
  })
  availability: Availability;

  // Disponible en ce moment pour prendre une livraison ?
  // Mis à jour en temps réel par le livreur depuis l'app
  @Column({ default: false })
  isAvailableNow: boolean;

  // ─── Localisation ──────────────────────────────────────

  @Column({ length: 100 })
  ville: string;

  @Column({ length: 100 })
  quartier: string;

  @Column({ type: 'text' })
  preciseAddress: string;

  // ─── Documents de vérification ─────────────────────────

  @Column({ length: 500 })
  idDocumentUrl: string;

  @Column({ length: 500 })
  selfieUrl: string;

  @Column({ length: 500 })
  vehiclePhotoUrl: string;

  @Column({ length: 50 })
  licensePlate: string;

  // ─── Conditions ────────────────────────────────────────

  @Column({ default: false })
  termsAccepted: boolean;

  @Column({ default: false })
  fraudPenaltiesAccepted: boolean;

  // ─── Validation ────────────────────────────────────────

  @Column({
    type: 'enum',
    enum: AgentStatus,
    default: AgentStatus.PENDING,
  })
  status: AgentStatus;

  @Column({ nullable: true, type: 'text' })
  motifRefus: string | null;

  @Column({ nullable: true })
  reviewedById: string;

  @ManyToOne(() => AdminAccount, { nullable: true })
  @JoinColumn({ name: 'reviewedById' })
  reviewedBy: AdminAccount;

  @Column({ type: 'timestamp', nullable: true })
  reviewedAt: Date;

  // ─── Statistiques (calculées automatiquement) ──────────

  // Note moyenne donnée par les clients (ex: 4.75)
  @Column({ type: 'decimal', precision: 3, scale: 2, default: 0 })
  noteMoyenne: number;

  // Pourcentage de livraisons réussies (ex: 94.50 %)
  @Column({ type: 'decimal', precision: 5, scale: 2, default: 0 })
  tauxDeReussite: number;

  // Nombre total de livraisons effectuées
  @Column({ default: 0 })
  totalLivraisons: number;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}