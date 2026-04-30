import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  Index,
} from 'typeorm';

export enum ActorType {
  CLIENT         = 'client',
  VENDOR         = 'vendor',
  DELIVERY_AGENT = 'delivery_agent',
  ADMIN          = 'admin',
  SUPERADMIN     = 'superadmin',
  SYSTEM         = 'system', // actions automatiques du système
}

export enum LogResult {
  SUCCESS = 'success',
  FAILURE = 'failure',
}

// Liste des actions loguées
export enum LogAction {
  // Authentification
  USER_LOGIN              = 'Connexion utilisateur',
  USER_LOGIN_FAILED       = 'Échec de connexion utilisateur',
  USER_REGISTER           = 'Inscription utilisateur',
  USER_PASSWORD_RESET     = 'Réinitialisation du mot de passe utilisateur',
  ADMIN_LOGIN             = 'Connexion administrateur',
  ADMIN_LOGIN_FAILED      = 'Échec de connexion administrateur',

  // Gestion utilisateurs
  USER_BLOCKED            = 'Utilisateur bloqué',
  USER_UNBLOCKED          = 'Utilisateur débloqué',
  ADMIN_CREATED           = 'Administrateur créé',
  ADMIN_DEACTIVATED       = 'Administrateur désactivé',

  // Vendeurs & Livreurs
  VENDOR_SUBMITTED        = 'Demande vendeur soumise',
  VENDOR_APPROVED         = 'Vendeur approuvé',
  VENDOR_REJECTED         = 'Vendeur rejeté',
  VENDOR_BLOCKED          = 'Vendeur bloqué',
  AGENT_SUBMITTED         = 'Demande livreur soumise',
  AGENT_APPROVED          = 'Livreur approuvé',
  AGENT_REJECTED          = 'Livreur rejeté',
  AGENT_BLOCKED           = 'Livreur bloqué',

  // Produits
  PRODUCT_CREATED         = 'Produit créé',
  PRODUCT_UPDATED         = 'Produit mis à jour',
  PRODUCT_DELETED         = 'Produit supprimé',
  PRODUCT_STATUS_CHANGED  = 'Statut du produit modifié',

  // Commandes
  ORDER_CREATED           = 'Commande créée',
  ORDER_STATUS_CHANGED    = 'Statut de la commande modifié',
  ORDER_CANCELLED         = 'Commande annulée',

  // Paiements
  PAYMENT_SUCCESS         = 'Paiement réussi',
  PAYMENT_FAILED          = 'Échec du paiement',
  REFUND_REQUESTED        = 'Demande de remboursement',
  REFUND_PROCESSED        = 'Remboursement effectué',

  // Livraisons
  DELIVERY_ASSIGNED       = 'Livraison assignée',
  DELIVERY_STATUS_CHANGED = 'Statut de livraison modifié',

  // Catégories
  CATEGORY_CREATED        = 'Catégorie créée',
  CATEGORY_UPDATED        = 'Catégorie mise à jour',
  CATEGORY_DELETED        = 'Catégorie supprimée',

  // Coupons
  COUPON_CREATED          = 'Coupon créé',
  COUPON_DEACTIVATED      = 'Coupon désactivé',

  // Avis
  REVIEW_APPROVED         = 'Avis approuvé',
  REVIEW_REJECTED         = 'Avis rejeté',

  // Commission
  COMMISSION_RATE_CHANGED = 'Taux de commission modifié',
}

@Entity('activity_logs')
export class ActivityLog {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  // Qui a fait l'action — null si action système automatique
  @Index()
  @Column({ nullable: true })
  actorId: string;

  @Column({
    type: 'enum',
    enum: ActorType,
  })
  actorType: ActorType;

  // Ce qui a été fait
  @Index()
  @Column({
    type: 'enum',
    enum: LogAction,
  })
  action: LogAction;

  // Sur quelle entité — ex: 'vendor', 'order', 'product'
  @Column({ nullable: true, length: 50 })
  entityType: string;

  // ID de l'entité concernée
  @Index()
  @Column({ nullable: true })
  entityId: string;

  // Valeur AVANT la modification
  // Ex: { status: 'pending' }
  // ⚠️ Ne jamais stocker de données sensibles ici
  // (mot de passe, token, données bancaires)
  @Column({ nullable: true, type: 'jsonb' })
  oldValue: Record<string, any>;

  // Valeur APRÈS la modification
  // Ex: { status: 'approved' }
  @Column({ nullable: true, type: 'jsonb' })
  newValue: Record<string, any>;

  // Adresse IP de l'acteur
  @Column({ nullable: true, length: 45 })
  ipAddress: string;

  @Column({
    type: 'enum',
    enum: LogResult,
    default: LogResult.SUCCESS,
  })
  result: LogResult;

  // Détails supplémentaires si échec
  // Ex: message d'erreur
  @Column({ nullable: true, type: 'text' })
  errorMessage: string;

  // ⚠️ Pas de UpdateDateColumn ici —
  // un log ne doit JAMAIS être modifié après création
  @Index()
  @CreateDateColumn()
  createdAt: Date;
}