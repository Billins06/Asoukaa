import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  OneToMany,
  Index,
} from 'typeorm';
import { UserRole } from './user-role.entity';
import { Address } from './address.entity';

@Entity('users')
export class User {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Index()                     
  @Column({ unique: true, length: 255 })
  email: string;

  @Index()                         
  @Column({ unique: true, length: 20 })
  phone: string;

  // ⚠️ PRODUCTION : ne jamais retourner ce champ dans les réponses API
  // On utilisera un DTO qui l'exclut explicitement
  @Column({ length: 255 })
  passwordHash: string;

  @Index()
  @Column({ length: 100 })
  prenom: string;

  @Index()
  @Column({ length: 100 })
  name: string;

  @Column({ nullable: true, length: 500 })
  avatarUrl: string;


  @Column({ default: false })
  isVerified: boolean;

  // false = bloqué par l'admin
  @Column({ default: true })
  isActive: boolean;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;

  // Relations
  @OneToMany(() => UserRole, (userRole) => userRole.user, {
    cascade: true,    // si on supprime un user, ses rôles sont supprimés aussi
  })
  roles: UserRole[];

  @OneToMany(() => Address, (address) => address.user, {
    cascade: true,
  })
  addresses: Address[];
}