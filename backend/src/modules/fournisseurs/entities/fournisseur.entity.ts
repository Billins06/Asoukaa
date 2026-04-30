import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  ManyToOne,
  JoinColumn,
} from 'typeorm';
import { AdminAccount } from '../../auth/entities/admin-account.entity';

export enum Currency {
  XOF = 'XOF', // FCFA — devise de référence
  NGN = 'NGN', // Naira nigérian
  USD = 'USD', // Dollar américain
  EUR = 'EUR', // Euro
  GHS = 'GHS', // Cedi ghanéen
  CNY = 'CNY', // Yuan chinois
}

@Entity('fournisseurs')
export class Fournisseur {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ length: 255 })
  four_name: string;

  // Nom du responsable chez le fournisseur
  @Column({ length: 200 })
  contactPerson: string;

  @Column({ nullable: true, length: 255 })
  four_email: string;

  @Column({ length: 20 })
  four_phone: string;

  @Column({ length: 100 })
  four_country: string;

  @Column({ length: 100 })
  four_ville: string;

  // Devise dans laquelle ce fournisseur facture
  @Column({
    type: 'enum',
    enum: Currency,
    default: Currency.XOF,
  })
  currency: Currency;

  // Délai moyen de livraison en jours
  @Column({ default: 1 })
  delaiLivraison: number;

  @Column({ default: true })
  isActive: boolean;

  // Notes internes visibles uniquement par l'admin
  @Column({ nullable: true, type: 'text' })
  notes: string;

  // Traçabilité — quel admin a créé ce fournisseur
  @Column({ nullable: true })
  createdById: string;

  @ManyToOne(() => AdminAccount, { nullable: true })
  @JoinColumn({ name: 'createdById' })
  createdBy: AdminAccount;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}