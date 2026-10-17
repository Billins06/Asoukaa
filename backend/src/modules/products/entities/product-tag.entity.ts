import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  JoinColumn,
  Index,
} from 'typeorm';
import { Product } from './product.entity';

// Recherche par étiquette (trigrammes GIN, migration 1757800000000) : géré par
// migration — TypeORM ne doit ni le créer ni le supprimer.
@Index('idx_product_tags_tag_trgm', ['tag'], { synchronize: false } as any)
@Entity('product_tags')
export class ProductTag {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  productId: string;

  @ManyToOne(() => Product, (product) => product.tags, {
    onDelete: 'CASCADE',
  })
  @JoinColumn({ name: 'productId' })
  product: Product;

  // Ex: "nike", "running", "sport", "chaussure"
  @Index()
  @Column({ length: 100 })
  tag: string;
}