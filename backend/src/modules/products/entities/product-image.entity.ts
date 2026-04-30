import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  JoinColumn,
} from 'typeorm';
import { Product } from './product.entity';

@Entity('product_images')
export class ProductImage {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  productId: string;

  @ManyToOne(() => Product, (product) => product.images, {
    onDelete: 'CASCADE',
  })
  @JoinColumn({ name: 'productId' })
  product: Product;

  @Column({ length: 500 })
  url: string;

  // Une seule image peut être marquée principale
  // ⚠️ Dans le service : quand isPrimary = true sur une image,
  // mettre isPrimary = false sur toutes les autres du même produit
  @Column({ default: false })
  isPrimary: boolean;

  // true = c'est une vidéo, false = c'est une image
  @Column({ default: false })
  isVideo: boolean;

  // Pour ordonner les images dans la galerie
  @Column({ default: 0 })
  sortOrder: number;
}