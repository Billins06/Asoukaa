import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  OneToMany,
  CreateDateColumn,
  UpdateDateColumn,
  Index,
} from 'typeorm';
import { VitrineRayonProduit } from './vitrine-rayon-produit.entity';

// Type de rayon de la vitrine (page d'accueil de l'appli).
//  - flash    : ventes flash (souvent bornées par startsAt / endsAt)
//  - tendance : produits tendance
//  - succes   : meilleures ventes / succès du moment
//  - libre    : rayon thématique quelconque choisi par l'admin
export enum VitrineRayonType {
  FLASH    = 'flash',
  TENDANCE = 'tendance',
  SUCCES   = 'succes',
  LIBRE    = 'libre',
}

// Rayon de la vitrine, composé à la main par un admin (back-office) :
// une liste ORDONNÉE de produits (voir VitrineRayonProduit).
// Visible publiquement si isActive = true ET si maintenant est dans la
// période [startsAt, endsAt[ (null = pas de borne de ce côté).
// ⚠️ Les noms de contraintes/index sont explicites et identiques à ceux
// de la migration 1790900000000-AddVitrine.ts.
@Index('IDX_vitrine_rayons_isActive_sortOrder', ['isActive', 'sortOrder'])
@Entity('vitrine_rayons')
export class VitrineRayon {

  @PrimaryGeneratedColumn('uuid', { primaryKeyConstraintName: 'PK_vitrine_rayons' })
  id: string;

  @Column({ type: 'varchar', length: 120 })
  nom: string;

  @Column({
    type:     'enum',
    enum:     VitrineRayonType,
    enumName: 'vitrine_rayons_type_enum',
    default:  VitrineRayonType.LIBRE,
  })
  type: VitrineRayonType;

  // Image d'illustration du rayon (upload type "vitrine").
  @Column({ type: 'varchar', length: 500, nullable: true })
  imageUrl: string | null;

  // Ordre d'affichage des rayons sur la page d'accueil (croissant).
  @Column({ type: 'int', default: 0 })
  sortOrder: number;

  @Column({ type: 'boolean', default: true })
  isActive: boolean;

  // Période de visibilité (null = sans limite de ce côté).
  @Column({ type: 'timestamptz', nullable: true })
  startsAt: Date | null;

  @Column({ type: 'timestamptz', nullable: true })
  endsAt: Date | null;

  @OneToMany(() => VitrineRayonProduit, (rp) => rp.rayon)
  produits: VitrineRayonProduit[];

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
