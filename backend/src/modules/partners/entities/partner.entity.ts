import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  ManyToOne,
  JoinColumn,
} from 'typeorm';
import { AdminAccount } from '../../auth/entities/admin-account.entity';

@Entity('partners')
export class Partner {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ length: 255 })
  part_name: string;

  // ⚠️ PRODUCTION : valider que l'URL est bien une image
  // avant de l'enregistrer (type MIME, taille max)
  @Column({ nullable: true, type:'varchar', length: 500 })
  part_logoUrl: string | null;

  @Column({ nullable: true, type:'varchar', length: 500 })
  part_websiteUrl: string | null;

  @Column({ nullable: true, type: 'text' })
  description: string | null;

  @Column({ default: true })
  isActive: boolean;

  // Qui a créé ce partenaire (traçabilité)
  @Column({ nullable: true })
  createdById: string;

  @ManyToOne(() => AdminAccount, { nullable: true })
  @JoinColumn({ name: 'createdById' })
  createdBy: AdminAccount;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}