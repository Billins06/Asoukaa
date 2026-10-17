import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  OneToOne,
  JoinColumn,
  ManyToOne,
  CreateDateColumn,
  UpdateDateColumn,
  Index,
} from 'typeorm';
import { User } from './user.entity';
import { AdminAccount } from '../../auth/entities/admin-account.entity';

export enum VendorStatus {
  PENDING  = 'en attente',   // vient de soumettre sa demande
  APPROVED = 'approuvé',  // validé par l'admin
  REJECTED = 'rejeté',  // refusé, peut re-soumettre
  BLOCKED  = 'bloqué',   // bloqué définitivement
}

export enum PaymentMethod {
  MOBILE_MONEY = 'mobile_money',
  BANK         = 'bank',
}

// Boutiques par statut (liste admin, annuaire) — migration 1791810000000.
@Index('IDX_vendor_profiles_status', ['status'])
@Entity('vendor_profiles')
export class VendorProfile {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  // Un utilisateur ne peut avoir qu'UNE seule boutique
  // OneToOne + unique garantit cette règle en base de données
  @Column({ unique: true })
  userId: string;

  @OneToOne(() => User, {
    onDelete: 'CASCADE',
  })
  @JoinColumn({ name: 'userId' })
  user: User;

  // ─── Informations de la boutique ───────────────────────

  @Index()
  @Column({ unique: true, length: 255 })
  shopName: string;

  @Column({ type: 'text' })
  shopAddress: string;

  // Texte dérivé : noms des catégories choisies joints par ", " (tronqué à
  // 100 caractères). Conservé pour tous les écrans/anciens clients qui
  // l'affichent. Texte libre pour les vendeurs inscrits avant categoryIds.
  @Column({ length: 100 })
  activityType: string;

  // Catégories de la plateforme choisies par le vendeur (1 à 5). Simple
  // ÉTIQUETTE d'affichage : ne restreint PAS les catégories de publication.
  // [] pour les vendeurs inscrits avant cette colonne.
  @Column({ type: 'uuid', array: true, default: () => "'{}'" })
  categoryIds: string[];

  @Column({ type: 'text' })
  description: string;

  // Ajoutés UNIQUEMENT après validation
  // ⚠️ PRODUCTION : vérifier que status = 'approved'
  // avant d'autoriser l'upload du logo et de la bannière
  @Column({ nullable: true, length: 500 })
  logoUrl: string;

  @Column({ nullable: true, length: 500 })
  bannerUrl: string;

  // ─── Documents de vérification ─────────────────────────

  // ⚠️ `type: 'varchar'` OBLIGATOIRE ici (et pas seulement `length`) :
  // avec le type TS `string | null`, TypeScript émet `design:type = Object`
  // et TypeORM n'a plus rien à traduire en SQL → l'application refuse de
  // démarrer sur DataTypeNotSupportedError.
  // C'est pour ça que logoUrl/bannerUrl ci-dessus s'en passent : leur type
  // est `string` tout court. Toute colonne `X | null` SANS relation doit
  // déclarer son type SQL.
  @Column({ type: 'varchar', length: 500, nullable: true })
  idDocumentUrl: string | null;

  @Column({ type: 'varchar', length: 500, nullable: true })
  selfieUrl: string | null;

  // Tableau d'URLs pour les 2-3 photos de produits exemples
  @Column({ type: 'text', array: true, default: [] })
  sampleProductUrls: string[];

  // ─── Validation ────────────────────────────────────────

  @Column({
    type: 'enum',
    enum: VendorStatus,
    default: VendorStatus.PENDING,
  })
  status: VendorStatus;

  // Rempli quand l'admin refuse la demande
  @Column({ nullable: true, type: 'text' })
    motifRefus: string | null;

  // true = a lu et accepté les conditions
  @Column({ default: false })
  termsAccepted: boolean;

  // true = a accepté les pénalités en cas de fraude
  @Column({ default: false })
  fraudPenaltiesAccepted: boolean;

  // Combien de fois le vendeur a soumis sa demande
  // Utile pour détecter les abus de re-soumission
  @Column({ default: 1 })
  submissionCount: number;

  @Column({ type: 'timestamp', nullable: true })
  submittedAt: Date;

  // ─── Décision de l'admin ───────────────────────────────

  @Column({ nullable: true })
  reviewedById: string;

  // Quel admin a pris la décision
  @ManyToOne(() => AdminAccount, { nullable: true })
  @JoinColumn({ name: 'reviewedById' })
  reviewedBy: AdminAccount;

  @Column({ type: 'timestamp', nullable: true })
  reviewedAt: Date;

  // ─── Paiement (configuré après validation) ─────────────

  @Column({
    type: 'enum',
    enum: PaymentMethod,
    nullable: true,
  })
  paymentMethod: PaymentMethod;

  // ⚠️ PRODUCTION : les données bancaires sont chiffrées en AES-256-GCM
  // Contient la chaîne chiffrée, déchiffrer via EncryptionService
  @Column({ type: 'text', nullable: true })
  paymentDetails: string;

  // Montant minimum qu'un retrait doit atteindre POUR CE VENDEUR.
  // 0 = aucun minimum (valeur par défaut : Collins n'impose pas de seuil
  // global, mais l'admin peut en fixer un vendeur par vendeur via
  // PATCH /vendors/:id/min-withdrawal). Lu par VendorWithdrawalsService
  // à la création d'une demande de retrait.
  @Column({ type: 'decimal', precision: 12, scale: 2, default: 0 })
  minWithdrawalAmount: number;

  // ─── Statistiques publiques ─────────────────────────────

  // Nombre de fois où un acheteur a ouvert la page boutique.
  // Incrémenté par VendorsController.getPublicShop (voir GET
  // /vendors/:id/public) — remplace l'ancienne estimation inventée
  // côté Flutter (totalViews * 3 / 2).
  @Column({ type: 'int', default: 0 })
  visitCount: number;

  // « Boutique visible » (réglage du vendeur : PATCH /vendors/me/settings).
  // false → la boutique et ses produits disparaissent des listes publiques
  // (annuaire, fiche publique, recherche, produits, meilleures boutiques) et
  // elle ne reçoit plus de nouvelles commandes ni de nouveaux articles au
  // panier. Le propriétaire garde l'accès à sa boutique et à ses produits ;
  // les commandes déjà passées continuent normalement.
  @Column({ type: 'boolean', default: true })
  shopVisible: boolean;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}