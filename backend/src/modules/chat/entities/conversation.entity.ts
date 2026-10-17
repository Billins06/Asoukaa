import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  OneToMany,
  JoinColumn,
  CreateDateColumn,
  UpdateDateColumn,
  Unique,
  Index,
} from 'typeorm';
import { User } from '../../users/entities/user.entity';
import { VendorProfile } from '../../users/entities/vendor-profile.entity';
import { Product } from '../../products/entities/product.entity';
import { Message } from './message.entity';

// Un client ne peut avoir qu'une seule conversation avec un vendeur
// (comme sur WhatsApp avec un contact) : la contrainte ne porte plus
// sur le produit, qui n'est qu'une référence affichée dans la discussion.
@Unique(['clientId', 'vendorId'])
// Liste des conversations côté vendeur (migration 1791200000000) — déclaré ici
// pour que DB_SYNCHRONIZE=true ne le supprime pas.
@Index('IDX_conversations_vendorId', ['vendorId'])
@Entity('conversations')
export class Conversation {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  clientId: string;

  @ManyToOne(() => User, {
    onDelete: 'CASCADE',
  })
  @JoinColumn({ name: 'clientId' })
  client: User;

  @Column()
  vendorId: string;

  @ManyToOne(() => VendorProfile, {
    onDelete: 'CASCADE',
  })
  @JoinColumn({ name: 'vendorId' })
  vendor: VendorProfile;

  // Contexte optionnel — sur quel produit porte la discussion
  @Column({ nullable: true })
  productId: string | null;

  @ManyToOne(() => Product, {
    nullable: true,
    onDelete: 'SET NULL',
  })
  @JoinColumn({ name: 'productId' })
  product: Product;

  @Column({ default: false })
  isArchived: boolean;

  @OneToMany(() => Message, (message) => message.conversation, {
    cascade: true,
  })
  messages: Message[];

  // Mis à jour à chaque nouveau message
  // Utile pour trier les conversations par activité récente
  @UpdateDateColumn()
  updatedAt: Date;

  @CreateDateColumn()
  createdAt: Date;
}