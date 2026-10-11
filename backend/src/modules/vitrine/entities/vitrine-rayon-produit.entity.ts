import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  JoinColumn,
  Unique,
  Index,
} from 'typeorm';
import { VitrineRayon } from './vitrine-rayon.entity';
import { Product }      from '../../products/entities/product.entity';

// Produit placé dans un rayon de la vitrine, à une position donnée.
// Un produit ne figure qu'une fois par rayon (UNIQUE rayonId + productId).
// La liste est remplacée en bloc par l'admin (PUT
// /admin/vitrine/rayons/:id/products) : l'ordre du tableau = sortOrder.
// ⚠️ Noms de contraintes identiques à la migration 1790900000000-AddVitrine.ts.
@Unique('UQ_vitrine_rayon_produits_rayon_product', ['rayonId', 'productId'])
@Index('IDX_vitrine_rayon_produits_productId', ['productId'])
@Entity('vitrine_rayon_produits')
export class VitrineRayonProduit {

  @PrimaryGeneratedColumn('uuid', { primaryKeyConstraintName: 'PK_vitrine_rayon_produits' })
  id: string;

  @Column({ type: 'uuid' })
  rayonId: string;

  @ManyToOne(() => VitrineRayon, (rayon) => rayon.produits, {
    onDelete: 'CASCADE',
    // Supprimer un rayon retire simplement ses lignes de placement
  })
  @JoinColumn({ name: 'rayonId', foreignKeyConstraintName: 'FK_vitrine_rayon_produits_rayon' })
  rayon: VitrineRayon;

  @Column({ type: 'uuid' })
  productId: string;

  @ManyToOne(() => Product, {
    onDelete: 'CASCADE',
    // Un produit supprimé disparaît de tous les rayons
  })
  @JoinColumn({ name: 'productId', foreignKeyConstraintName: 'FK_vitrine_rayon_produits_product' })
  product: Product;

  // Position du produit dans le rayon (0 = premier).
  @Column({ type: 'int', default: 0 })
  sortOrder: number;
}
