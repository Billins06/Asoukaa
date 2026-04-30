import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  JoinColumn,
} from 'typeorm';
import { Product } from './product.entity';

@Entity('product_tier_prices')
export class ProductTierPrice {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  productId: string;

  @ManyToOne(() => Product, (product) => product.tierPrices, {
    onDelete: 'CASCADE',
  })
  @JoinColumn({ name: 'productId' })
  product: Product;

  // Quantité minimale pour ce palier
  @Column()
  minQuantity: number;

  // Quantité maximale — null = illimité (dernier palier)
  @Column({ nullable: true })
  maxQuantity: number;

  // Prix appliqué pour ce palier
  @Column({ type: 'decimal', precision: 12, scale: 2 })
  price: number;
}