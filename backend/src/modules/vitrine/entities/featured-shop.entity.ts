import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  JoinColumn,
  CreateDateColumn,
  UpdateDateColumn,
  Index,
  Unique,
} from 'typeorm';
import { VendorProfile } from '../../users/entities/vendor-profile.entity';

// Boutique mise en avant sur la page d'accueil (« Meilleures boutiques »),
// choisie MANUELLEMENT par l'admin. Une boutique ne figure qu'une fois
// (UNIQUE vendorId) ; l'ordre d'affichage est `position` (0 = première).
// ⚠️ Noms de contraintes identiques à la migration
// 1791400000000-AddFeaturedShops.ts.
@Unique('UQ_featured_shops_vendorId', ['vendorId'])
@Index('IDX_featured_shops_isActive_position', ['isActive', 'position'])
@Entity('featured_shops')
export class FeaturedShop {

  @PrimaryGeneratedColumn('uuid', { primaryKeyConstraintName: 'PK_featured_shops' })
  id: string;

  @Column({ type: 'uuid' })
  vendorId: string;

  @ManyToOne(() => VendorProfile, {
    onDelete: 'CASCADE',
    // Profil vendeur supprimé → la boutique quitte la liste.
  })
  @JoinColumn({ name: 'vendorId', foreignKeyConstraintName: 'FK_featured_shops_vendor' })
  vendor: VendorProfile;

  @Column({ type: 'int', default: 0 })
  position: number;

  // false = gardée dans la liste admin mais masquée sur l'accueil.
  @Column({ type: 'boolean', default: true })
  isActive: boolean;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
