import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  JoinColumn,
  CreateDateColumn,
  Unique,
} from 'typeorm';
import { User } from './user.entity';

// Les 3 rôles possibles pour un utilisateur
export enum UserRoleEnum {
  CLIENT         = 'client',
  VENDOR         = 'vendor',         
  DELIVERY_AGENT = 'delivery_agent',  
}

// ⚠️ Contrainte unique : un utilisateur ne peut pas avoir
// deux fois le même rôle
@Unique(['userId', 'role'])
@Entity('user_roles')
export class UserRole {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  // Colonne qui stocke la clé étrangère
  @Column()
  userId: string;

  @ManyToOne(() => User, (user) => user.roles, {
    onDelete: 'CASCADE',  // si le user est supprimé, ses rôles le sont aussi
  })
  @JoinColumn({ name: 'userId' })
  user: User;

  @Column({
    type: 'enum',
    enum: UserRoleEnum,
  })
  role: UserRoleEnum;

  @Column({ default: true })
  isActive: boolean;

  @CreateDateColumn()
  createdAt: Date;
}