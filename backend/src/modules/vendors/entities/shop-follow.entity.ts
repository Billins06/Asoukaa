import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  JoinColumn,
  CreateDateColumn,
  Unique,
  Index,
} from 'typeorm';
import { User }          from '../../users/entities/user.entity';
import { VendorProfile } from '../../users/entities/vendor-profile.entity';

// Abonnement d'un utilisateur à une boutique ("Suivre la boutique").
// Un utilisateur ne peut suivre une même boutique qu'une seule fois
// (contrainte UNIQUE userId + vendorId). Index sur vendorId pour le
// COUNT des abonnés dans VendorsService.getShopStats.
// ⚠️ Les noms de contraintes/index sont explicites et identiques à ceux
// de la migration 1790400000000-AddShopFollows.ts (pas de dérive si
// DB_SYNCHRONIZE=true en développement).
@Unique('UQ_shop_follows_user_vendor', ['userId', 'vendorId'])
@Index('IDX_shop_follows_vendorId', ['vendorId'])
@Entity('shop_follows')
export class ShopFollow {

  @PrimaryGeneratedColumn('uuid', { primaryKeyConstraintName: 'PK_shop_follows' })
  id: string;

  @Column()
  userId: string;

  @ManyToOne(() => User, {
    onDelete: 'CASCADE',
    // Si l'utilisateur est supprimé, ses abonnements le sont aussi
  })
  @JoinColumn({ name: 'userId', foreignKeyConstraintName: 'FK_shop_follows_user' })
  user: User;

  @Column()
  vendorId: string;

  @ManyToOne(() => VendorProfile, {
    onDelete: 'CASCADE',
    // Si la boutique est supprimée, ses abonnés disparaissent avec elle
  })
  @JoinColumn({ name: 'vendorId', foreignKeyConstraintName: 'FK_shop_follows_vendor' })
  vendor: VendorProfile;

  @CreateDateColumn()
  createdAt: Date;
}
