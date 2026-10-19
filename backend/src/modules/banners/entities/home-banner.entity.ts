import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  Index,
} from 'typeorm';

// Où mène une bannière quand on appuie dessus.
//  - category : page des produits d'une catégorie (targetId = categories.id)
//  - product  : fiche d'un produit              (targetId = products.id)
//  - shop     : page d'une boutique             (targetId = vendor_profiles.id)
//  - link     : adresse web externe en https    (targetUrl)
export enum BannerTargetType {
  CATEGORY = 'category',
  PRODUCT  = 'product',
  SHOP     = 'shop',
  LINK     = 'link',
}

// Bannières défilantes en haut de l'accueil de l'appli, gérées par l'admin.
// Visible publiquement si isActive = true ET si maintenant est dans la
// période [startsAt, endsAt[ (null = pas de borne de ce côté) ET si la cible
// existe encore. ⚠️ Index/contraintes identiques à la migration
// 1791900000000-CreateHomeBanners.ts.
@Index('IDX_home_banners_isActive_sortOrder', ['isActive', 'sortOrder'])
@Entity('home_banners')
export class HomeBanner {

  @PrimaryGeneratedColumn('uuid', { primaryKeyConstraintName: 'PK_home_banners' })
  id: string;

  // Image de la bannière (upload type "vitrine").
  @Column({ type: 'varchar', length: 500 })
  imageUrl: string;

  @Column({ type: 'varchar', length: 120, nullable: true })
  titre: string | null;

  @Column({ type: 'varchar', length: 200, nullable: true })
  sousTitre: string | null;

  @Column({ type: 'varchar', length: 10 })
  targetType: BannerTargetType;

  // Utilisé quand targetType = category | product | shop (sinon null).
  @Column({ type: 'uuid', nullable: true })
  targetId: string | null;

  // Utilisé quand targetType = link (sinon null). https uniquement.
  @Column({ type: 'varchar', length: 500, nullable: true })
  targetUrl: string | null;

  // Durée d'affichage avant de passer à la bannière suivante (2 à 30 s).
  @Column({ type: 'int', default: 4 })
  durationSeconds: number;

  // Ordre d'affichage (croissant).
  @Column({ type: 'int', default: 0 })
  sortOrder: number;

  @Column({ type: 'boolean', default: true })
  isActive: boolean;

  // Période de visibilité (null = sans limite de ce côté).
  @Column({ type: 'timestamptz', nullable: true })
  startsAt: Date | null;

  @Column({ type: 'timestamptz', nullable: true })
  endsAt: Date | null;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
