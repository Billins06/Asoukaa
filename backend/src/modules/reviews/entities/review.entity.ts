import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  JoinColumn,
  CreateDateColumn,
  UpdateDateColumn,
  Unique,
} from 'typeorm';
import { User } from '../../users/entities/user.entity';
import { Product } from '../../products/entities/product.entity';
import { Order } from '../../orders/entities/order.entity';

export enum ReviewStatus {
  PENDING  = 'en attente',  // en attente de modération
  APPROVED = 'approuvé', // approuvé par l'admin
  REJECTED = 'rejeté', // rejeté par l'admin
}

// Un client ne peut laisser qu'un seul avis par produit acheté
// La contrainte porte sur user + product (pas sur order)
// car un client peut acheter le même produit plusieurs fois
// mais ne peut laisser qu'un seul avis au total
@Unique(['userId', 'productId'])
@Entity('reviews')
export class Review {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  userId: string;

  // Seul un vrai acheteur peut noter
  @ManyToOne(() => User, {
    onDelete: 'RESTRICT',
  })
  @JoinColumn({ name: 'userId' })
  user: User;

  @Column()
  productId: string;

  @ManyToOne(() => Product, {
    onDelete: 'CASCADE',
    // Si le produit est supprimé ses avis le sont aussi
  })
  @JoinColumn({ name: 'productId' })
  product: Product;

  // Preuve d'achat — vérifie que le client a bien acheté
  @Column()
  orderId: string;

  @ManyToOne(() => Order, {
    onDelete: 'RESTRICT',
  })
  @JoinColumn({ name: 'orderId' })
  order: Order;

  // Note de 1 à 5
  // ⚠️ Vérifier dans le service que rating est entre 1 et 5
  @Column({ type: 'int' })
  notation: number;

  @Column({ nullable: true, type: 'text' })
  comment: string;

  @Column({
    type: 'enum',
    enum: ReviewStatus,
    default: ReviewStatus.PENDING,
  })
  status: ReviewStatus;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}