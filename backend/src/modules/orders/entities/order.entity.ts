import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  OneToMany,
  OneToOne,
  JoinColumn,
  CreateDateColumn,
  UpdateDateColumn,
  Index,
} from 'typeorm';
import { User } from '../../users/entities/user.entity';
import { VendorProfile } from '../../users/entities/vendor-profile.entity';
import { Address } from '../../users/entities/address.entity';
import { Coupon } from '../../coupons/entities/coupon.entity';
import { OrderItem } from './order-item.entity';

export enum OrderStatus {
  PENDING        = 'en attente',
  PREPARING      = 'en cours',
  // Le vendeur a affecté un livreur — uniquement pour le Cas A
  // (livraison avec livreur interne). N'est jamais utilisé pour le
  // retrait en boutique ou le bus/taxi.
  AGENT_ASSIGNED = 'livreur affecté',
  SHIPPED        = 'expedié',
  // Cas A uniquement : le vendeur a cliqué sur "Démarrer" après que
  // le livreur a fourni sa preuve de ramassage (photo + état du colis).
  IN_TRANSIT     = 'en transit',
  DELIVERED      = 'livré',
  CANCELLED      = 'annulé',
}

export enum OrderDeliveryMode {
  LIVRAISON = 'livraison',
  RETRAIT   = 'retrait',
}

// Mode de transport choisi par le client pour les communes du Nord
// (Alibori, Atacora, Borgou, Donga) où Asoukaa n'a pas ses propres
// livreurs : le colis part par bus ou par taxi inter-urbain. Le prix de
// livraison ne change pas selon le choix — c'est une info logistique
// pour le vendeur/l'admin, pas un facteur de tarification.
export enum OrderTransportMode {
  BUS  = 'bus',
  TAXI = 'taxi',
}

@Index(['userId'])
@Index(['vendorId'])
@Index(['status'])
@Index(['createdAt'])
@Index(['vendorId', 'status'])
// Index partiel (créé par la migration 1791600000000) : commandes en attente
// dont le rappel vendeur ou l'alerte admin reste à envoyer.
@Index('IDX_orders_awaiting_vendor_confirmation', ['createdAt'], {
  where: `"status" = 'en attente' AND ("vendorReminderSentAt" IS NULL OR "adminAlertedAt" IS NULL)`,
})
@Entity('orders')
export class Order {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  // Numéro lisible par l'humain
  // Ex: ASK-2025-00124
  @Index()
  @Column({ unique: true, length: 50 })
  orderNumber: string;

  // Le client qui a passé la commande
  @Column()
  userId: string;

  @ManyToOne(() => User, {
    onDelete: 'RESTRICT',
    // ⚠️ RESTRICT et non CASCADE car on ne veut jamais
    // supprimer des commandes quand un user est supprimé
    // Les commandes sont des données financières à conserver
  })
  @JoinColumn({ name: 'userId' })
  user: User;

  // La boutique concernée
  // Une commande = une boutique
  @Column()
  vendorId: string;

  @ManyToOne(() => VendorProfile, {
    onDelete: 'RESTRICT',
  })
  @JoinColumn({ name: 'vendorId' })
  vendor: VendorProfile;

  // Adresse de livraison choisie par le client
  // Reste obligatoire meme en mode retrait (on la garde comme
  // adresse de facturation / contact, pas de changement de schema)
  // Facultative UNIQUEMENT pour une commande 100 % livres numériques (rien à livrer).
  @Column({ type: 'uuid', nullable: true })
  addressId: string | null;

  @ManyToOne(() => Address, {
    onDelete: 'RESTRICT',
    nullable: true,
  })
  @JoinColumn({ name: 'addressId' })
  address: Address | null;

  // true = commande de livres numériques (pas de livraison, passe directement
  // à « livré » dès le paiement confirmé).
  @Column({ default: false })
  isDigital: boolean;

  // Le client se fait livrer, ou vient retirer en boutique ?
  @Column({
    type: 'enum',
    enum: OrderDeliveryMode,
    default: OrderDeliveryMode.LIVRAISON,
  })
  deliveryMode: OrderDeliveryMode;

  // Renseigné uniquement pour une commune du Nord (voir OrderTransportMode
  // ci-dessus) ; null pour toutes les autres communes.
  @Column({ type: 'varchar', nullable: true, length: 10 })
  transportMode: string | null;

  // Coupon appliqué — nullable car optionnel
  @Column({ nullable: true })
  couponId: string | null;

  @ManyToOne(() => Coupon, {
    nullable: true,
    onDelete: 'SET NULL',
  })
  @JoinColumn({ name: 'couponId' })
  coupon: Coupon;

  @Column({
    type: 'enum',
    enum: OrderStatus,
    default: OrderStatus.PENDING,
  })
  status: OrderStatus;

  // Instructions laissées par le client
  // Ex: "Sonner deux fois", "Laisser chez le gardien"
  @Column({ nullable: true, type: 'text' })
  instructions: string | null;

  // ─── Calculs financiers ────────────────────────────────

  // Somme des articles sans frais
  @Column({ type: 'decimal', precision: 12, scale: 2 })
  subtotal: number;

  @Column({ type: 'decimal', precision: 12, scale: 2, default: 0 })
  fraisLivraison: number;

  // Montant de la réduction coupon
  @Column({ type: 'decimal', precision: 12, scale: 2, default: 0 })
  rabais: number;

  // Commission prélevée par Asoukaa
  @Column({ type: 'decimal', precision: 12, scale: 2, default: 0 })
  montantCommission: number;

  // Total final payé par le client
  @Column({ type: 'decimal', precision: 12, scale: 2 })
  total: number;

  // Raison de l'annulation si applicable
  @Column({ nullable: true, type: 'text' })
  motifAnnulation: string | null;

  // ─── Cas C : livraison bus/taxi (zone Nord) ────────────
  // Ces trois champs ne servent qu'au chemin bus/taxi ; ils restent à
  // leur valeur par défaut (null / false) pour les Cas A et B.

  // Horodatage posé par le serveur au moment exact du passage à
  // "Expédiée" — jamais fourni par le client, jamais modifiable par
  // lui. Sert de point de départ au délai de 3 jours de confirmation
  // automatique (voir OrderTransportMode ci-dessus).
  @Column({ nullable: true, type: 'timestamp' })
  expedieAt: Date | null;

  // Le client a contesté la réception dans le délai de 3 jours —
  // bloque la confirmation automatique et la libération du paiement
  // au vendeur, en attente d'un arbitrage côté admin.
  @Column({ type: 'boolean', default: false })
  disputeOuverte: boolean;

  // true si le passage à "Livrée" vient de l'expiration du délai de
  // 3 jours (faute de réaction du client), false si le client a
  // confirmé lui-même avec une preuve. Sert uniquement au reporting /
  // à la traçabilité.
  @Column({ type: 'boolean', default: false })
  confirmationAutomatique: boolean;

  // ─── Relations ─────────────────────────────────────────

  // ─── Délai de confirmation vendeur ─────────────────────
  // Posés UNIQUEMENT par OrderConfirmationService (planificateur), de façon
  // atomique : servent aussi de verrou pour qu'un rappel / une alerte ne
  // parte qu'une seule fois. Jamais modifiables par un client ou un vendeur.

  // Rappel envoyé au vendeur (commande payée non confirmée après
  // ORDER_REMINDER_HOURS, 24 h par défaut).
  @Column({ type: 'timestamptz', nullable: true })
  vendorReminderSentAt: Date | null;

  // Admins alertés (toujours non confirmée après ORDER_ADMIN_ALERT_HOURS,
  // 48 h par défaut).
  @Column({ type: 'timestamptz', nullable: true })
  adminAlertedAt: Date | null;

  // ─── Code de remise (« QR de preuve ») ─────────────────
  // Code aléatoire propre à la commande (voir
  // common/utils/handover-code.util.ts). Connu du seul client propriétaire
  // (GET /orders/me/:id -> handoverCode) ; le livreur (remise à domicile) ou le
  // vendeur (retrait en boutique) doit le saisir / scanner.
  // ⚠️ `select: false` : ces colonnes ne sont JAMAIS chargées par défaut, donc
  // jamais renvoyées dans une réponse vendeur / livreur / admin. Pour les lire :
  // addSelect explicite (voir OrdersService.ensureHandoverCode).
  @Column({ type: 'varchar', length: 16, nullable: true, select: false })
  handoverCode: string | null;

  // Essais ratés de saisie du code ; au 3e raté, handoverLockedUntil bloque
  // la validation quelques minutes.
  @Column({ type: 'int', default: 0, select: false })
  handoverFailedAttempts: number;

  @Column({ type: 'timestamptz', nullable: true, select: false })
  handoverLockedUntil: Date | null;

  @OneToMany(() => OrderItem, (item) => item.order, {
    cascade: true,
  })
  items: OrderItem[];

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}