import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  JoinColumn,
  CreateDateColumn,
  Unique,
} from 'typeorm';
import { Cart }           from './cart.entity';
import { ProductVariant } from '../../products/entities/product-variant.entity';

@Unique(['cartId', 'variantId'])
@Entity('cart_items')
export class CartItem {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  cartId: string;

  @ManyToOne(() => Cart, (cart) => cart.items, {
    onDelete: 'CASCADE',
  })
  @JoinColumn({ name: 'cartId' })
  cart: Cart;

  @Column()
  variantId: string;

  @ManyToOne(() => ProductVariant, {
    onDelete: 'CASCADE',
    eager: true,
  })
  @JoinColumn({ name: 'variantId' })
  variant: ProductVariant;

  @Column({ type: 'int' })
  quantity: number;

  // Prix figé au moment de l'ajout au panier
  @Column({ type: 'decimal', precision: 12, scale: 2 })
  unitPrice: number;

  // Devient true si le vendeur change son prix
  // après que le client a ajouté au panier
  @Column({ default: false })
  priceChanged: boolean;

  @CreateDateColumn()
  createdAt: Date;
}