import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  JoinColumn,
  CreateDateColumn,
  Unique,
} from 'typeorm';
import { User } from '../../users/entities/user.entity';
import { Product } from '../../products/entities/product.entity';

// Pas de doublons — un produit ne peut être
// qu'une seule fois dans la wishlist d'un utilisateur
@Unique(['userId', 'productId'])
@Entity('wishlists')
export class Wishlist {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  userId: string;

  @ManyToOne(() => User, {
    onDelete: 'CASCADE',
    // Si l'utilisateur est supprimé sa wishlist l'est aussi
  })
  @JoinColumn({ name: 'userId' })
  user: User;

  @Column()
  productId: string;

  @ManyToOne(() => Product, {
    onDelete: 'CASCADE',
    // Si le produit est supprimé il disparaît
    // automatiquement de toutes les wishlists
  })
  @JoinColumn({ name: 'productId' })
  product: Product;

  @CreateDateColumn()
  createdAt: Date;
}