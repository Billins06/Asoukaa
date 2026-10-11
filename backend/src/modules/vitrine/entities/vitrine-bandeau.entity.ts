import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  UpdateDateColumn,
} from 'typeorm';

// Bandeau d'accueil de la vitrine (grande bannière en haut de l'appli).
// ⚠️ Une seule ligne est utilisée : PUT /admin/vitrine/bandeau crée la
// ligne si elle n'existe pas, sinon met à jour la plus récente.
@Entity('vitrine_bandeau')
export class VitrineBandeau {

  @PrimaryGeneratedColumn('uuid', { primaryKeyConstraintName: 'PK_vitrine_bandeau' })
  id: string;

  @Column({ type: 'varchar', length: 120 })
  titre: string;

  @Column({ type: 'varchar', length: 200, nullable: true })
  sousTitre: string | null;

  // Image du bandeau (upload type "vitrine").
  @Column({ type: 'varchar', length: 500, nullable: true })
  imageUrl: string | null;

  @Column({ type: 'boolean', default: true })
  isActive: boolean;

  @UpdateDateColumn()
  updatedAt: Date;
}
