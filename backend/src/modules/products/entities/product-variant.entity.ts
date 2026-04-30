import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  JoinColumn,
  Index,
} from 'typeorm';
import { Product } from './product.entity';

@Entity('product_variants')
export class ProductVariant {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  productId: string;

  @ManyToOne(() => Product, (product) => product.variants, {
    onDelete: 'CASCADE',
  })
  @JoinColumn({ name: 'productId' })
  product: Product;

  // Code unique de référence de la variante
  // Ex: "NIKE-AIR-40-BLANC"
  @Index()
  @Column({ unique: true, length: 100 })
  sku: string;

  @Column({ nullable: true, length: 100 })
  color: string;

  @Column({ nullable: true, length: 50 })
  size: string;

  @Column({ nullable: true, length: 100 })
  model: string;

  // Prix propre à cette variante
  // Peut différer du basePrice du produit
  @Column({ type: 'decimal', precision: 12, scale: 2 })
  price: number;

  // ⚠️ C'est ICI que vit le stock, pas sur le produit
  @Column({ default: 0 })
  stockQuantity: number;

  // Seuil d'alerte stock faible
  // Ex: quand stockQuantity < lowStockAlert → notifier le vendeur
  @Column({ default: 5 })
  lowStockAlert: number;

  // Image propre à cette variante
  // Ex: photo du modèle rouge, photo du modèle bleu
  @Column({ nullable: true, length: 500 })
  imageUrl: string;

  @Column({ default: true })
  isActive: boolean;
}