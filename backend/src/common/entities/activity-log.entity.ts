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

  // Changement d'e-mail (identifiant de connexion) — voir EmailChangeService.
  // ⚠️ Ces valeurs vivent aussi dans l'enum Postgres activity_logs_action_enum :
  // la migration AddEmailChange les y ajoute (ALTER TYPE ... ADD VALUE).
  EMAIL_CHANGE_REQUESTED  = "Demande de changement d'e-mail",
  EMAIL_CHANGE_CONFIRMED  = 'Adresse e-mail modifiée',
  // Gravité élevée : le propriétaire dit ne PAS être à l'origine du changement
  EMAIL_CHANGE_REVERTED   = 'E-mail annulé — compte potentiellement compromis',
  // Un admin a pris connaissance d'une alerte « Ce n'est pas moi » (valeur
  // ajoutée à l'enum Postgres par la migration 1791700000000-AddSecurityAlertAck).
  SECURITY_ALERT_ACKED    = 'Alerte de sécurité acquittée',

  // Gestion utilisateurs
  USER_BLOCKED            = 'Utilisateur bloqué',
  USER_UNBLOCKED          = 'Utilisateur débloqué',
  USER_CREATED_BY_ADMIN   = 'Utilisateur créé par admin',
  USER_UPDATED_BY_ADMIN   = 'Utilisateur modifié par admin',
  ADMIN_CREATED           = 'Administrateur créé',
  ADMIN_DEACTIVATED       = 'Administrateur désactivé',

  // Vendeurs & Livreurs
  VENDOR_SUBMITTED        = 'Demande vendeur soumise',
  VENDOR_APPROVED         = 'Vendeur approuvé',
  VENDOR_REJECTED         = 'Vendeur rejeté',
  VENDOR_BLOCKED          = 'Vendeur bloqué',
  VENDOR_UNBLOCKED        = 'Vendeur débloqué',
  AGENT_SUBMITTED         = 'Demande livreur soumise',
  AGENT_APPROVED          = 'Livreur approuvé',
  AGENT_REJECTED          = 'Livreur rejeté',
  AGENT_BLOCKED           = 'Livreur bloqué',
  AGENT_UNBLOCKED         = 'Livreur débloqué',

  // Produits
  PRODUCT_CREATED         = 'Produit créé',
  PRODUCT_UPDATED         = 'Produit mis à jour',
  PRODUCT_DELETED         = 'Produit supprimé',
  PRODUCT_STATUS_CHANGED  = 'Statut du produit modifié',

  // Boutiques Vendeurs
  VENDOR_SHOP_UPDATED     = 'Boutique vendeur mise à jour',

  // Commandes
  ORDER_CREATED           = 'Commande créée',
  ORDER_STATUS_CHANGED    = 'Statut de la commande modifié',
  ORDER_CANCELLED         = 'Commande annulée',
  ORDER_DISPUTE_OPENED    = 'Litige ouvert sur une commande',
  // Alerte système : commande payée toujours pas confirmée par le vendeur après
  // ORDER_ADMIN_ALERT_HOURS. ⚠️ Valeur aussi ajoutée à activity_logs_action_enum
  // par la migration 1791600000000-AddOrderConfirmationReminders.
  ORDER_CONFIRMATION_OVERDUE = 'Commande non confirmée par le vendeur (alerte)',

  // Preuves de livraison (Cas A/B/C — voir DeliveryProof)
  DELIVERY_PROOF_SUBMITTED = 'Preuve de livraison soumise',

  // Paiements
  PAYMENT_SUCCESS         = 'Paiement réussi',
  PAYMENT_FAILED          = 'Échec du paiement',
  REFUND_REQUESTED        = 'Demande de remboursement',
  REFUND_PROCESSED        = 'Remboursement effectué',
  // ⚠️ Valeur aussi ajoutée à activity_logs_action_enum par la migration
  // 1791840000000-AddPaymentReviewed.
  PAYMENT_REVIEWED        = 'Paiement reçu examiné par un administrateur',

  // Alerte sécurité : un vendeur demande un retrait vers un numéro Mobile Money
  // différent de son dernier retrait / de celui de sa fiche. ⚠️ Valeur aussi
  // ajoutée à activity_logs_action_enum par la migration
  // 1791820000010-AddWithdrawalNumberAlertLogAction.
  VENDOR_WITHDRAWAL_NUMBER_ALERT = 'Retrait vendeur : numéro Mobile Money inhabituel',

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

  // Partenaires
  PARTNER_CREATED         = 'Partenaire ajouté',
  PARTNER_UPDATED         = 'Partenaire modifié',
  PARTNER_DELETED         = 'Partenaire supprimé',

  // Fournisseurs
  FOURNISSEUR_CREATED     = 'Fournisseur créé',
  FOURNISSEUR_UPDATED     = 'Fournisseur modifié',
  FOURNISSEUR_DELETED     = 'Fournisseur supprimé',

  // Avis
  REVIEW_APPROVED         = 'Avis approuvé',
  REVIEW_REJECTED         = 'Avis rejeté',

  // Commission
  COMMISSION_RATE_CHANGED = 'Taux de commission modifié',

  // Tickets de support — ces valeurs vivent aussi dans l'enum Postgres
  // activity_logs_action_enum (migration AddSupportTickets).
  SUPPORT_TICKET_REPLIED         = 'Réponse à un ticket support',
  SUPPORT_TICKET_STATUS_CHANGED  = "Statut d'un ticket support modifié",
  SUPPORT_TICKET_ASSIGNED        = 'Ticket support assigné',
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