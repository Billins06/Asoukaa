import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  Index,
} from 'typeorm';

// Tarif de livraison fixe par commune du Bénin.
// Alimenté au démarrage avec les 77 communes (frais à 0 par défaut) ;
// les frais réels sont ensuite définis par l'admin via l'écran de gestion.
@Entity('delivery_zones')
export class DeliveryZone {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Index({ unique: true })
  @Column({ length: 100 })
  commune: string;

  @Column({ length: 100 })
  departement: string;

  @Column({ type: 'decimal', precision: 10, scale: 2, default: 0 })
  fraisLivraison: number;

  // Permet de désactiver temporairement une zone (ex: non desservie)
  // sans supprimer la ligne.
  @Column({ default: true })
  isActive: boolean;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
