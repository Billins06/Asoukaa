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

  // ─── Sécurité du compte (changement d'e-mail annulé par le propriétaire) ───

  // Tout jeton JWT émis AVANT cette date est refusé par JwtStrategy : c'est
  // ce qui « déconnecte tous les appareils » quand le propriétaire signale
  // un changement d'e-mail frauduleux. null = aucune révocation en cours.
  // ⚠️ `type` explicite obligatoire sur une colonne `X | null` (voir le
  // commentaire de vendor-profile.entity.ts).
  @Column({ type: 'timestamp', nullable: true })
  tokensValidAfter: Date | null;

  // Alerte sécurité visible par l'administration : renseignée quand le
  // propriétaire a répondu « Ce n'est pas moi » à un changement d'e-mail.
  @Column({ type: 'timestamp', nullable: true })
  securityAlertAt: Date | null;

  @Column({ type: 'varchar', length: 255, nullable: true })
  securityAlertReason: string | null;

  // ─── Présence « En ligne / Vu à … » ───

  // Dernière activité de l'utilisateur (POST /presence/ping et connexion).
  // « En ligne » = moins de 2 minutes, calculé côté serveur : voir
  // modules/presence/presence.util.ts. Seuls { lastSeenAt, isOnline } sont
  // exposés aux autres utilisateurs.
  @Column({ type: 'timestamptz', nullable: true })
  lastSeenAt: Date | null;

  // ─── Préférences de notification ───

  // Clés booléennes réglées par l'utilisateur (orders, messages, payments,
  // promotions, newOrders, newDeliveries). Une clé absente = valeur par
  // défaut du profil (voir modules/notifications/notification-preferences.ts).
  // select:false → jamais chargé ni renvoyé par erreur avec l'utilisateur ;
  // lu explicitement par NotificationsService.
  @Column({ type: 'jsonb', default: () => "'{}'", select: false })
  notificationPrefs: Record<string, boolean>;

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