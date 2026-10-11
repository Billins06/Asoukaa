import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  OneToMany,
  ManyToMany,
  JoinTable,
  JoinColumn,
  CreateDateColumn,
  UpdateDateColumn,
  Index,
} from 'typeorm';
import { VendorProfile } from '../../users/entities/vendor-profile.entity';
import { Category } from '../../categories/entities/category.entity';
import { ProductImage } from './product-image.entity';
import { ProductVariant } from './product-variant.entity';
import { ProductTag } from './product-tag.entity';
import { ProductTierPrice } from './product-tier-price.entity';

export enum ProductStatus {
  DRAFT        = 'brouillon',        // brouillon, non visible
  ACTIVE       = 'active',       // publié, visible
  INACTIVE     = 'inactive',     // désactivé par le vendeur
  OUT_OF_STOCK = 'out_of_stock', // toutes les variantes épuisées
}

@Entity('products')
export class Product {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  // Le produit appartient obligatoirement à une boutique
  @Column()
  vendorId: string;

  @ManyToOne(() => VendorProfile, {
    onDelete: 'CASCADE',
    // Si la boutique est supprimée, ses produits le sont aussi
  })
  @JoinColumn({ name: 'vendorId' })
  vendor: VendorProfile;

  @Index()
  @Column({ length: 500 })
  prod_name: string;

  @Index()
  @Column({ unique: true, length: 500 })
  slug: string;

  @Column({ type: 'text' })
  description: string;

  // Prix de référence affiché sur la fiche produit
  // Le vrai prix de vente est sur la variante
  @Column({ type: 'decimal', precision: 12, scale: 2 })
  basePrice: number;

  @Column({ nullable: true, type: 'decimal', precision: 8, scale: 2 })
  weight: number | null;

  // Ex: "30x20x10 cm"
  @Column({ type: 'varchar', nullable: true, length: 100 })
  dimensions: string | null;

  @Column({
    type: 'enum',
    enum: ProductStatus,
    default: ProductStatus.DRAFT,
  })
  status: ProductStatus;

  // Mis en avant sur la page d'accueil par l'admin
  @Column({ default: false })
  isVedette: boolean;

  // Calculé automatiquement à chaque nouvel avis approuvé
  // ⚠️ Ne jamais laisser le vendeur modifier cette valeur
  @Column({ type: 'decimal', precision: 3, scale: 2, default: 0 })
  noteMoyenne: number;

  // Compteur d'avis approuvés
  @Column({ default: 0 })
  nbreAvis: number;

  // Compteur de ventes pour le dashboard et le tri.
  // Incrementé par OrdersService.incrementProductSales() quand une commande
  // passe au statut "livré" (quantité réellement vendue, pas le nombre de
  // commandes). Avant, cette colonne existait mais n'était JAMAIS mise à
  // jour : les statistiques vendeur affichaient donc toujours zéro.
  @Column({ default: 0 })
  totalVentes: number;

  // Nombre de fois qu'un visiteur a ouvert la fiche de ce produit.
  // Incrementé par ProductsService.findOnePublic() (GET /products/:id),
  // sur le même principe best-effort que VendorProfile.visitCount.
  @Column({ type: 'int', default: 0 })
  nombreVues: number;

  // ─── Relations ─────────────────────────────────────────

  // Un produit peut appartenir à plusieurs catégories
  // ManyToMany crée automatiquement la table product_categories
  @ManyToMany(() => Category, { eager: false })
  @JoinTable({
    name: 'product_categories',
    joinColumn:        { name: 'productId',  referencedColumnName: 'id' },
    inverseJoinColumn: { name: 'categoryId', referencedColumnName: 'id' },
  })
  categories: Category[];

  @OneToMany(() => ProductImage, (image) => image.product, {
    cascade: true,
  })
  images: ProductImage[];

  @OneToMany(() => ProductVariant, (variant) => variant.product, {
    cascade: true,
  })
  variants: ProductVariant[];

  // ⚠️ PAS de cascade ici : les tags sont gérés manuellement (delete +
  // recreate via ProductTag/tagRepo) dans ProductsService.create() et
  // .update(), jamais en assignant ce tableau. Avec cascade:true,
  // ProductsService.update() chargeait ce tableau AVANT de supprimer et
  // recréer les tags "à la main", puis productRepo.save(product) recascadait
  // ce tableau désormais périmé (lignes déjà supprimées en base) : TypeORM
  // tentait de les réécrire avec productId = NULL → violation de la
  // contrainte NOT NULL et 500 sur PUT /products/:id (jamais sur la
  // création, où product.tags n'est jamais chargé au préalable).
  @OneToMany(() => ProductTag, (tag) => tag.product)
  tags: ProductTag[];

  @OneToMany(() => ProductTierPrice, (tier) => tier.product, {
    cascade: true,
  })
  tierPrices: ProductTierPrice[];

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}