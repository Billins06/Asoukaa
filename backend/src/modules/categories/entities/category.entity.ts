import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  OneToMany,
  JoinColumn,
  CreateDateColumn,
  UpdateDateColumn,
  Index,
} from 'typeorm';

@Entity('categories')
export class Category {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  // Auto-référence — pointe vers la même table
  // null = catégorie racine (niveau 1)
  @Column({ nullable: true })
  parentId: string;

  @ManyToOne(() => Category, (category) => category.children, {
    nullable: true,
    onDelete: 'SET NULL',
    // ⚠️ SET NULL et non CASCADE car si on supprime
    // une catégorie parente, on ne veut pas supprimer
    // toutes ses sous-catégories automatiquement
    // On préfère les rendre orphelines et les traiter manuellement
  })
  @JoinColumn({ name: 'parentId' })
  parent: Category;

  @OneToMany(() => Category, (category) => category.parent)
  children: Category[];

  @Index()
  @Column({ length: 255 })
  name: string;

  // URL propre ex: "electronique-telephones-android"
  @Index()
  @Column({ unique: true, length: 255 })
  slug: string;

  @Column({ nullable: true, length: 500 })
  imageUrl: string;

  // Niveau de profondeur : 1, 2 ou 3
  // Calculé automatiquement dans le service avant insertion
  // ⚠️ PRODUCTION : toujours vérifier que level <= 3
  // avant d'autoriser la création d'une sous-catégorie
  @Column({ default: 1 })
  level: number;

  // Pour ordonner l'affichage dans l'app
  @Column({ default: 0 })
  sortOrder: number;

  @Column({ default: true })
  isActive: boolean;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}