import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  JoinColumn,
} from 'typeorm';
import { Order } from './order.entity';
import { ProductVariant } from '../../products/entities/product-variant.entity';

@Entity('order_items')
export class OrderItem {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  orderId: string;

  @ManyToOne(() => Order, (order) => order.items, {
    onDelete: 'CASCADE',
  })
  @JoinColumn({ name: 'orderId' })
  order: Order;

  @Column()
  variantId: string;

  @ManyToOne(() => ProductVariant, {
    onDelete: 'RESTRICT',
    // ⚠️ RESTRICT car on ne veut jamais perdre
    // la référence d'un produit dans une commande existante
    // même si le produit est supprimé plus tard
  })
  @JoinColumn({ name: 'variantId' })
  variant: ProductVariant;

  @Column()
  quantity: number;

  // Prix copié au moment de la commande
  // Ce prix ne changera JAMAIS même si le vendeur
  // modifie son prix plus tard
  @Column({ type: 'decimal', precision: 12, scale: 2 })
  unitPrice: number;
}