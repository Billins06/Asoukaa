import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  JoinColumn,
  CreateDateColumn,
  Index,
} from 'typeorm';
import { User } from './user.entity';

@Index(['userId'])
@Entity('addresses')
export class Address {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  userId: string;

  @ManyToOne(() => User, (user) => user.addresses, {
    onDelete: 'CASCADE',
  })
  @JoinColumn({ name: 'userId' })
  user: User;

  // Ex: "Maison", "Bureau", "Chez maman"
  @Column({ length: 100 })
  label: string;

  // Nom de la personne à livrer (peut différer du nom du compte)
  @Column({ length: 200 })
  nom_destinataire: string;

  @Column({ length: 20 })
  phone_destinataire: string;

  @Column({ type: 'text' })
  quartier: string;

  @Column({ length: 100 })
  ville: string;

  @Column({ length: 100, default: 'Bénin' })
  country: string;

  // Position GPS partagée par le client (bouton "Partager ma
  // localisation" au paiement) — optionnelle, permet au livreur de
  // retrouver le client précisément plutôt que de se fier uniquement
  // au texte de l'adresse.
  @Column({ type: 'double precision', nullable: true })
  latitude: number | null;

  @Column({ type: 'double precision', nullable: true })
  longitude: number | null;

  // Une seule adresse peut être marquée comme principale
  // ⚠️ PRODUCTION : quand on met isDefault = true sur une adresse,
  // il faut mettre isDefault = false sur toutes les autres adresses
  // du même utilisateur. À gérer dans le service, pas ici.
  @Column({ default: false })
  isDefault: boolean;

  @CreateDateColumn()
  createdAt: Date;
}