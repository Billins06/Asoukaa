import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * MIGRATION DE BASE : crée tout le schéma d'Asoukaa sur une base VIDE.
 *
 * Pourquoi elle existe
 * --------------------
 * Jusqu'ici, aucune migration ne créait les tables (users, orders, products…) :
 * la première migration (1757800000000) ajoutait déjà un index sur `products`.
 * Le schéma de départ venait de `synchronize` (mode développement) et n'était
 * écrit nulle part. Sur un serveur neuf, `npm run typeorm:run` échouait donc
 * avec « relation "products" does not exist ».
 *
 * Ce que fait cette migration
 * ---------------------------
 *  - Son horodatage (1700000000000) est PLUS ANCIEN que toutes les autres :
 *    TypeORM l'exécute donc en PREMIER sur une base vide, puis rejoue les
 *    migrations existantes dans l'ordre (elles sont toutes idempotentes et ne
 *    font plus rien, car tout existe déjà).
 *  - Elle reproduit le schéma actuel = entités + migrations existantes
 *    (45 tables, 30 types enum, 93 index, 74 clés étrangères,
 *    extensions `uuid-ossp` et `pg_trgm`, séquence des numéros de commande).
 *  - Quand un objet est défini à la fois par une entité et par une
 *    migration (tables delivery_proofs, delivery_earnings, shop_follows,
 *    vendor_withdrawals, vitrine_*, email_changes, support_tickets*,
 *    featured_shops ; index de payments, conversations, messages…), c'est la
 *    version de la MIGRATION qui est utilisée (mêmes noms d'index et de
 *    contraintes, mêmes ON DELETE) : ainsi les migrations suivantes ne créent
 *    aucun doublon.
 *
 * Sécurité sur une base déjà installée (production, développement)
 * ----------------------------------------------------------------
 *  - GARDE : si la table `users` existe déjà, la migration NE FAIT RIEN
 *    (elle s'enregistre simplement comme exécutée). Aucune table, donnée ou
 *    index existant n'est touché.
 *  - Toutes les instructions sont idempotentes (IF NOT EXISTS / DO … EXCEPTION).
 *
 * Annulation (down)
 * -----------------
 *  - `down()` n'efface JAMAIS rien en production et ne supprime rien tant que
 *    d'autres migrations sont enregistrées (voir le détail dans down()).
 *
 * Entretien : ce fichier a été produit à partir de la sortie de TypeORM
 * (`createSchemaBuilder().log()` sur une base vide) puis relu. Il décrit le
 * schéma « à la date de la base de départ » : les évolutions futures se font
 * par de NOUVELLES migrations (npm run typeorm:generate), jamais en modifiant
 * celle-ci. `scripts/test-baseline.sh` rejoue la vérification complète.
 *
 * À exécuter avec : npm run typeorm:run
 */

// ── Extensions PostgreSQL ────────────────────────────────────────────────
//  - uuid-ossp : fonction uuid_generate_v4(), valeur par défaut de tous les `id`.
//  - pg_trgm   : recherche produit rapide (ILIKE '%mot%') via des index GIN.
// ⚠️ Sur un Postgres managé, le rôle de la base doit avoir le droit de créer
// des extensions (autorisé au propriétaire de la base pour ces deux
// extensions depuis PostgreSQL 13).
const EXTENSIONS: string[] = [
  `CREATE EXTENSION IF NOT EXISTS "uuid-ossp"`,
  `CREATE EXTENSION IF NOT EXISTS pg_trgm`,
];

// ── Séquences ────────────────────────────────────────────────────────────
//  - orders_number_seq : numéro de commande (voir OrdersService.generateOrderNumber).
//  - support_tickets_number_seq : numéro lisible des tickets (TCK-000042).
const SEQUENCES: string[] = [
  `CREATE SEQUENCE IF NOT EXISTS orders_number_seq START WITH 1`,
  `CREATE SEQUENCE IF NOT EXISTS "support_tickets_number_seq"`,
];

// ── Types enum (listes de valeurs fixes) ─────────────────────────────────
// Exécutés dans un bloc DO … EXCEPTION : un type déjà présent est ignoré.
const ENUMS: string[] = [
  // ======================================================================
  // COMPTES ET IDENTITÉ
  // ======================================================================
  `CREATE TYPE "public"."user_roles_role_enum" AS ENUM('client', 'vendor', 'delivery_agent')`,
  `CREATE TYPE "public"."admin_accounts_role_enum" AS ENUM('admin', 'superadmin')`,
  `CREATE TYPE "public"."otp_codes_type_enum" AS ENUM('email_verification', 'réinitialisation du mot de passe')`,
  `CREATE TYPE "public"."activity_logs_action_enum" AS ENUM('Connexion utilisateur', 'Échec de connexion utilisateur', 'Inscription utilisateur', 'Réinitialisation du mot de passe utilisateur', 'Connexion administrateur', 'Échec de connexion administrateur', 'Demande de changement d''e-mail', 'Adresse e-mail modifiée', 'E-mail annulé — compte potentiellement compromis', 'Alerte de sécurité acquittée', 'Utilisateur bloqué', 'Utilisateur débloqué', 'Utilisateur créé par admin', 'Utilisateur modifié par admin', 'Administrateur créé', 'Administrateur désactivé', 'Demande vendeur soumise', 'Vendeur approuvé', 'Vendeur rejeté', 'Vendeur bloqué', 'Vendeur débloqué', 'Demande livreur soumise', 'Livreur approuvé', 'Livreur rejeté', 'Livreur bloqué', 'Livreur débloqué', 'Produit créé', 'Produit mis à jour', 'Produit supprimé', 'Statut du produit modifié', 'Boutique vendeur mise à jour', 'Commande créée', 'Statut de la commande modifié', 'Commande annulée', 'Litige ouvert sur une commande', 'Commande non confirmée par le vendeur (alerte)', 'Preuve de livraison soumise', 'Paiement réussi', 'Échec du paiement', 'Demande de remboursement', 'Remboursement effectué', 'Retrait vendeur : numéro Mobile Money inhabituel', 'Livraison assignée', 'Statut de livraison modifié', 'Catégorie créée', 'Catégorie mise à jour', 'Catégorie supprimée', 'Coupon créé', 'Coupon désactivé', 'Partenaire ajouté', 'Partenaire modifié', 'Partenaire supprimé', 'Fournisseur créé', 'Fournisseur modifié', 'Fournisseur supprimé', 'Avis approuvé', 'Avis rejeté', 'Taux de commission modifié', 'Réponse à un ticket support', 'Statut d''un ticket support modifié', 'Ticket support assigné')`,
  `CREATE TYPE "public"."activity_logs_actortype_enum" AS ENUM('client', 'vendor', 'delivery_agent', 'admin', 'superadmin', 'system')`,
  `CREATE TYPE "public"."activity_logs_result_enum" AS ENUM('success', 'failure')`,

  // ======================================================================
  // BOUTIQUES, VENDEURS ET PARTENAIRES
  // ======================================================================
  `CREATE TYPE "public"."vendor_profiles_paymentmethod_enum" AS ENUM('mobile_money', 'bank')`,
  `CREATE TYPE "public"."vendor_profiles_status_enum" AS ENUM('en attente', 'approuvé', 'rejeté', 'bloqué')`,
  `CREATE TYPE "public"."vendor_withdrawals_status_enum" AS ENUM('en attente', 'payé', 'rejeté')`,
  `CREATE TYPE "public"."fournisseurs_currency_enum" AS ENUM('XOF', 'NGN', 'USD', 'EUR', 'GHS', 'CNY')`,

  // ======================================================================
  // CATALOGUE PRODUITS
  // ======================================================================
  `CREATE TYPE "public"."products_status_enum" AS ENUM('brouillon', 'active', 'inactive', 'out_of_stock')`,
  `CREATE TYPE "public"."reviews_status_enum" AS ENUM('en attente', 'approuvé', 'rejeté')`,

  // ======================================================================
  // VITRINE DE LA PAGE D'ACCUEIL
  // ======================================================================
  `CREATE TYPE "public"."vitrine_rayons_type_enum" AS ENUM('flash', 'tendance', 'succes', 'libre')`,

  // ======================================================================
  // PANIER, COMMANDES ET PAIEMENTS
  // ======================================================================
  `CREATE TYPE "public"."coupons_type_enum" AS ENUM('pourcentage', 'prix fixe')`,
  `CREATE TYPE "public"."orders_deliverymode_enum" AS ENUM('livraison', 'retrait')`,
  `CREATE TYPE "public"."orders_status_enum" AS ENUM('en attente', 'en cours', 'livreur affecté', 'expedié', 'en transit', 'livré', 'annulé')`,
  `CREATE TYPE "public"."payments_method_enum" AS ENUM('mobile_money', 'card', 'cash_on_delivery')`,
  `CREATE TYPE "public"."payments_operator_enum" AS ENUM('MTN', 'Moov', 'Wave', 'Visa', 'Mastercard')`,
  `CREATE TYPE "public"."payments_status_enum" AS ENUM('en attente', 'success', 'échoué', 'remboursé')`,
  `CREATE TYPE "public"."refunds_status_enum" AS ENUM('en attente', 'approuvé', 'rejetté', 'traité')`,
  `CREATE TYPE "public"."commissions_status_enum" AS ENUM('en attente', 'payé')`,

  // ======================================================================
  // LIVRAISON
  // ======================================================================
  `CREATE TYPE "public"."delivery_agent_profiles_availability_enum" AS ENUM('Temps_plein', 'Temps_partiel')`,
  `CREATE TYPE "public"."delivery_agent_profiles_status_enum" AS ENUM('en attente', 'approuvé', 'rejeté', 'bloqué')`,
  `CREATE TYPE "public"."delivery_agent_profiles_vehicletype_enum" AS ENUM('moto', 'voiture', 'tricycle', 'velo')`,
  `CREATE TYPE "public"."deliveries_status_enum" AS ENUM('en attente', 'assigné', 'récupéré', 'en cours de livraison', 'livré', 'livraison echouée')`,
  `CREATE TYPE "public"."delivery_proofs_role_enum" AS ENUM('livreur', 'vendeur', 'client')`,
  `CREATE TYPE "public"."delivery_proofs_stage_enum" AS ENUM('ramassage_livreur', 'remise_client', 'retrait_boutique', 'remise_transporteur', 'reception_client')`,
  `CREATE TYPE "public"."delivery_earnings_status_enum" AS ENUM('en attente', 'payé')`,
  `CREATE TYPE "public"."independent_deliveries_status_enum" AS ENUM('en attente', 'accepté', 'en cours de livraison', 'livré', 'annulée')`,

  // ======================================================================
  // MESSAGERIE, NOTIFICATIONS ET SUPPORT
  // ======================================================================
  `CREATE TYPE "public"."notifications_type_enum" AS ENUM('commande', 'livraison', 'paiement', 'avis', 'stock', 'validation', 'system', 'chat', 'ticket')`,
];

// ── Tables ───────────────────────────────────────────────────────────────
// Clés étrangères volontairement absentes ici : elles sont ajoutées à la fin
// (FOREIGN_KEYS) pour ne dépendre d'aucun ordre de création.
const TABLES: string[] = [
  // ======================================================================
  // COMPTES ET IDENTITÉ
  // ======================================================================
  // users : comptes des clients, vendeurs et livreurs (identité, mot de passe haché, sécurité, présence).
  `CREATE TABLE IF NOT EXISTS "users" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "email" character varying(255) NOT NULL,
    "phone" character varying(20) NOT NULL,
    "passwordHash" character varying(255) NOT NULL,
    "prenom" character varying(100) NOT NULL,
    "name" character varying(100) NOT NULL,
    "avatarUrl" character varying(500),
    "isVerified" boolean NOT NULL DEFAULT false,
    "isActive" boolean NOT NULL DEFAULT true,
    "tokensValidAfter" TIMESTAMP,
    "securityAlertAt" TIMESTAMP,
    "securityAlertReason" character varying(255),
    "securityAlertAckedAt" TIMESTAMP WITH TIME ZONE,
    "lastSeenAt" TIMESTAMP WITH TIME ZONE,
    "notificationPrefs" jsonb NOT NULL DEFAULT '{}',
    "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
    "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "UQ_97672ac88f789774dd47f7c8be3" UNIQUE ("email"),
    CONSTRAINT "UQ_a000cca60bcf04454e727699490" UNIQUE ("phone"),
    CONSTRAINT "PK_a3ffb1c0c8416b9fc6f907b7433" PRIMARY KEY ("id")
  )`,
  // user_roles : rôles d'un compte (client, vendeur, livreur) : un compte peut en cumuler plusieurs.
  `CREATE TABLE IF NOT EXISTS "user_roles" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "userId" uuid NOT NULL,
    "role" "public"."user_roles_role_enum" NOT NULL,
    "isActive" boolean NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "UQ_5f9286e6c25594c6b88c108db77" UNIQUE ("userId", "role"),
    CONSTRAINT "PK_8acd5cf26ebd158416f477de799" PRIMARY KEY ("id")
  )`,
  // addresses : carnet d'adresses de livraison des utilisateurs (avec position GPS facultative).
  `CREATE TABLE IF NOT EXISTS "addresses" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "userId" uuid NOT NULL,
    "label" character varying(100) NOT NULL,
    "nom_destinataire" character varying(200) NOT NULL,
    "phone_destinataire" character varying(20) NOT NULL,
    "quartier" text NOT NULL,
    "ville" character varying(100) NOT NULL,
    "country" character varying(100) NOT NULL DEFAULT 'Bénin',
    "latitude" double precision,
    "longitude" double precision,
    "isDefault" boolean NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "PK_745d8f43d3af10ab8247465e450" PRIMARY KEY ("id")
  )`,
  // admin_accounts : comptes de l'équipe d'administration (admin et superadmin), séparés des utilisateurs.
  `CREATE TABLE IF NOT EXISTS "admin_accounts" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "prenom" character varying(100) NOT NULL,
    "name" character varying(100) NOT NULL,
    "email" character varying(255) NOT NULL,
    "passwordHash" character varying(255),
    "role" "public"."admin_accounts_role_enum" NOT NULL DEFAULT 'admin',
    "isActive" boolean NOT NULL DEFAULT true,
    "isPasswordSet" boolean NOT NULL DEFAULT false,
    "invitationToken" character varying(255),
    "invitationExpiresAt" TIMESTAMP,
    "createdById" uuid,
    "lastLoginAt" TIMESTAMP,
    "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
    "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "UQ_05a0a0da9626f51206e41eda9df" UNIQUE ("email"),
    CONSTRAINT "PK_79fb3604ed15538685183d8df5f" PRIMARY KEY ("id")
  )`,
  // otp_codes : codes à usage unique (vérification d'e-mail, réinitialisation de mot de passe).
  `CREATE TABLE IF NOT EXISTS "otp_codes" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "userId" uuid NOT NULL,
    "code" character varying(255) NOT NULL,
    "type" "public"."otp_codes_type_enum" NOT NULL,
    "isUsed" boolean NOT NULL DEFAULT false,
    "attempts" integer NOT NULL DEFAULT '0',
    "expiresAt" TIMESTAMP NOT NULL,
    "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "PK_9d0487965ac1837d57fec4d6a26" PRIMARY KEY ("id")
  )`,
  // email_changes : demandes de changement d'e-mail sécurisé (code, essais, jeton d'annulation).
  `CREATE TABLE IF NOT EXISTS "email_changes" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "userId" uuid NOT NULL,
    "oldEmail" character varying(255) NOT NULL,
    "newEmail" character varying(255) NOT NULL,
    "codeHash" character varying(255) NOT NULL,
    "attempts" integer NOT NULL DEFAULT 0,
    "sendCount" integer NOT NULL DEFAULT 1,
    "codeExpiresAt" TIMESTAMP NOT NULL,
    "lastSentAt" TIMESTAMP NOT NULL,
    "status" character varying(20) NOT NULL DEFAULT 'pending',
    "revertTokenHash" character varying(64),
    "revertExpiresAt" TIMESTAMP,
    "confirmedAt" TIMESTAMP,
    "revertedAt" TIMESTAMP,
    "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "PK_email_changes" PRIMARY KEY ("id")
  )`,
  // activity_logs : journal d'activité : qui a fait quoi, quand, avec quel résultat (audit).
  `CREATE TABLE IF NOT EXISTS "activity_logs" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "actorId" character varying,
    "actorType" "public"."activity_logs_actortype_enum" NOT NULL,
    "action" "public"."activity_logs_action_enum" NOT NULL,
    "entityType" character varying(50),
    "entityId" character varying,
    "oldValue" jsonb,
    "newValue" jsonb,
    "ipAddress" character varying(45),
    "result" "public"."activity_logs_result_enum" NOT NULL DEFAULT 'success',
    "errorMessage" text,
    "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "PK_f25287b6140c5ba18d38776a796" PRIMARY KEY ("id")
  )`,

  // ======================================================================
  // BOUTIQUES, VENDEURS ET PARTENAIRES
  // ======================================================================
  // vendor_profiles : profils vendeurs / boutiques (documents, statut de validation, paiement, visites).
  `CREATE TABLE IF NOT EXISTS "vendor_profiles" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "userId" uuid NOT NULL,
    "shopName" character varying(255) NOT NULL,
    "shopAddress" text NOT NULL,
    "activityType" character varying(100) NOT NULL,
    "categoryIds" uuid array NOT NULL DEFAULT '{}',
    "description" text NOT NULL,
    "logoUrl" character varying(500),
    "bannerUrl" character varying(500),
    "idDocumentUrl" character varying(500),
    "selfieUrl" character varying(500),
    "sampleProductUrls" text array NOT NULL DEFAULT '{}',
    "status" "public"."vendor_profiles_status_enum" NOT NULL DEFAULT 'en attente',
    "motifRefus" text,
    "termsAccepted" boolean NOT NULL DEFAULT false,
    "fraudPenaltiesAccepted" boolean NOT NULL DEFAULT false,
    "submissionCount" integer NOT NULL DEFAULT '1',
    "submittedAt" TIMESTAMP,
    "reviewedById" uuid,
    "reviewedAt" TIMESTAMP,
    "paymentMethod" "public"."vendor_profiles_paymentmethod_enum",
    "paymentDetails" text,
    "minWithdrawalAmount" numeric(12,2) NOT NULL DEFAULT '0',
    "visitCount" integer NOT NULL DEFAULT '0',
    "shopVisible" boolean NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
    "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "UQ_658558b7f3a6163382505c8009e" UNIQUE ("userId"),
    CONSTRAINT "UQ_fe350603a4a45e923a9830a6f30" UNIQUE ("shopName"),
    CONSTRAINT "REL_658558b7f3a6163382505c8009" UNIQUE ("userId"),
    CONSTRAINT "PK_bcb47b1a47f4f1447447eaf73a1" PRIMARY KEY ("id")
  )`,
  // shop_follows : abonnements des utilisateurs aux boutiques (bouton « Suivre la boutique »).
  `CREATE TABLE IF NOT EXISTS "shop_follows" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "userId" uuid NOT NULL,
    "vendorId" uuid NOT NULL,
    "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "PK_shop_follows" PRIMARY KEY ("id"),
    CONSTRAINT "UQ_shop_follows_user_vendor" UNIQUE ("userId", "vendorId")
  )`,
  // featured_shops : « Meilleures boutiques » de l'accueil, choisies à la main par l'admin.
  `CREATE TABLE IF NOT EXISTS "featured_shops" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "vendorId" uuid NOT NULL,
    "position" integer NOT NULL DEFAULT 0,
    "isActive" boolean NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
    "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "PK_featured_shops" PRIMARY KEY ("id"),
    CONSTRAINT "UQ_featured_shops_vendorId" UNIQUE ("vendorId")
  )`,
  // vendor_withdrawals : demandes de retrait des gains des vendeurs (validées et payées à la main par l'admin).
  `CREATE TABLE IF NOT EXISTS "vendor_withdrawals" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "vendorId" uuid NOT NULL,
    "montant" numeric(12,2) NOT NULL,
    "status" "public"."vendor_withdrawals_status_enum" NOT NULL DEFAULT 'en attente',
    "paymentMethod" character varying(50) NOT NULL,
    "mobileNumber" character varying(20) NOT NULL,
    "noteAdmin" text,
    "paidAt" TIMESTAMP,
    "processedById" uuid,
    "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
    "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "PK_vendor_withdrawals" PRIMARY KEY ("id")
  )`,
  // partners : partenaires affichés sur la plateforme (logo, site web).
  `CREATE TABLE IF NOT EXISTS "partners" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "part_name" character varying(255) NOT NULL,
    "part_logoUrl" character varying(500),
    "part_websiteUrl" character varying(500),
    "description" text,
    "isActive" boolean NOT NULL DEFAULT true,
    "createdById" uuid,
    "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
    "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "PK_998645b20820e4ab99aeae03b41" PRIMARY KEY ("id")
  )`,
  // fournisseurs : fournisseurs référencés par l'administration.
  `CREATE TABLE IF NOT EXISTS "fournisseurs" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "four_name" character varying(255) NOT NULL,
    "contactPerson" character varying(200) NOT NULL,
    "four_email" character varying(255),
    "four_phone" character varying(20) NOT NULL,
    "four_country" character varying(100) NOT NULL,
    "four_ville" character varying(100) NOT NULL,
    "currency" "public"."fournisseurs_currency_enum" NOT NULL DEFAULT 'XOF',
    "delaiLivraison" integer DEFAULT '1',
    "isActive" boolean NOT NULL DEFAULT true,
    "notes" text,
    "createdById" uuid,
    "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
    "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "PK_f1c487e8db913a007d534049f22" PRIMARY KEY ("id")
  )`,

  // ======================================================================
  // CATALOGUE PRODUITS
  // ======================================================================
  // categories : arbre des catégories de produits (parent / enfants).
  `CREATE TABLE IF NOT EXISTS "categories" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "parentId" uuid,
    "name" character varying(255) NOT NULL,
    "slug" character varying(255) NOT NULL,
    "imageUrl" character varying(500),
    "level" integer NOT NULL DEFAULT '1',
    "sortOrder" integer NOT NULL DEFAULT '0',
    "isActive" boolean NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
    "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "UQ_420d9f679d41281f282f5bc7d09" UNIQUE ("slug"),
    CONSTRAINT "PK_24dbc6126a28ff948da33e97d3b" PRIMARY KEY ("id")
  )`,
  // products : produits des boutiques (prix de base, statut, compteurs de vues et de ventes).
  `CREATE TABLE IF NOT EXISTS "products" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "vendorId" uuid NOT NULL,
    "prod_name" character varying(500) NOT NULL,
    "slug" character varying(500) NOT NULL,
    "description" text NOT NULL,
    "basePrice" numeric(12,2) NOT NULL,
    "weight" numeric(8,2),
    "dimensions" character varying(100),
    "status" "public"."products_status_enum" NOT NULL DEFAULT 'brouillon',
    "isVedette" boolean NOT NULL DEFAULT false,
    "noteMoyenne" numeric(3,2) NOT NULL DEFAULT '0',
    "nbreAvis" integer NOT NULL DEFAULT '0',
    "totalVentes" integer NOT NULL DEFAULT '0',
    "nombreVues" integer NOT NULL DEFAULT '0',
    "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
    "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "UQ_464f927ae360106b783ed0b4106" UNIQUE ("slug"),
    CONSTRAINT "PK_0806c755e0aca124e67c0cf6d7d" PRIMARY KEY ("id")
  )`,
  // product_categories : liaison produit <-> catégories (un produit peut être dans plusieurs catégories).
  `CREATE TABLE IF NOT EXISTS "product_categories" (
    "productId" uuid NOT NULL,
    "categoryId" uuid NOT NULL,
    CONSTRAINT "PK_e65c1adebf00d61f1c84a4f3950" PRIMARY KEY ("productId", "categoryId")
  )`,
  // product_images : photos et vidéos d'un produit.
  `CREATE TABLE IF NOT EXISTS "product_images" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "productId" uuid NOT NULL,
    "url" character varying(500) NOT NULL,
    "isPrimary" boolean NOT NULL DEFAULT false,
    "isVideo" boolean NOT NULL DEFAULT false,
    "sortOrder" integer NOT NULL DEFAULT '0',
    CONSTRAINT "PK_1974264ea7265989af8392f63a1" PRIMARY KEY ("id")
  )`,
  // product_variants : variantes d'un produit (couleur, taille, modèle) avec prix et stock.
  `CREATE TABLE IF NOT EXISTS "product_variants" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "productId" uuid NOT NULL,
    "sku" character varying(100) NOT NULL,
    "color" character varying(100),
    "size" character varying(50),
    "model" character varying(100),
    "price" numeric(12,2) NOT NULL,
    "stockQuantity" integer NOT NULL DEFAULT '0',
    "lowStockAlert" integer NOT NULL DEFAULT '5',
    "imageUrl" character varying(500),
    "isActive" boolean NOT NULL DEFAULT true,
    CONSTRAINT "UQ_46f236f21640f9da218a063a866" UNIQUE ("sku"),
    CONSTRAINT "PK_281e3f2c55652d6a22c0aa59fd7" PRIMARY KEY ("id")
  )`,
  // product_tags : mots-clés d'un produit (utilisés par la recherche).
  `CREATE TABLE IF NOT EXISTS "product_tags" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "productId" uuid NOT NULL,
    "tag" character varying(100) NOT NULL,
    CONSTRAINT "PK_e96bca3cd7a592009f2c9dc6f3e" PRIMARY KEY ("id")
  )`,
  // product_tier_prices : prix dégressifs selon la quantité commandée.
  `CREATE TABLE IF NOT EXISTS "product_tier_prices" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "productId" uuid NOT NULL,
    "minQuantity" integer NOT NULL,
    "maxQuantity" character varying,
    "price" numeric(12,2) NOT NULL,
    CONSTRAINT "PK_0e5bd0c0e19b40710e76dbdfcc1" PRIMARY KEY ("id")
  )`,
  // wishlists : favoris des utilisateurs.
  `CREATE TABLE IF NOT EXISTS "wishlists" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "userId" uuid NOT NULL,
    "productId" uuid NOT NULL,
    "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "UQ_5629f2896ea05ee200f7a96af40" UNIQUE ("userId", "productId"),
    CONSTRAINT "PK_d0a37f2848c5d268d315325f359" PRIMARY KEY ("id")
  )`,
  // reviews : avis et notes laissés par les clients sur les produits.
  `CREATE TABLE IF NOT EXISTS "reviews" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "userId" uuid NOT NULL,
    "productId" uuid NOT NULL,
    "orderId" uuid NOT NULL,
    "notation" integer NOT NULL,
    "comment" text,
    "status" "public"."reviews_status_enum" NOT NULL DEFAULT 'en attente',
    "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
    "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "UQ_9007ffba411fd471dfe233dabfb" UNIQUE ("userId", "productId"),
    CONSTRAINT "PK_231ae565c273ee700b283f15c1d" PRIMARY KEY ("id")
  )`,

  // ======================================================================
  // VITRINE DE LA PAGE D'ACCUEIL
  // ======================================================================
  // vitrine_rayons : rayons de l'accueil (ventes flash, tendances, succès, rayons libres).
  `CREATE TABLE IF NOT EXISTS "vitrine_rayons" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "nom" character varying(120) NOT NULL,
    "type" "public"."vitrine_rayons_type_enum" NOT NULL DEFAULT 'libre',
    "imageUrl" character varying(500),
    "sortOrder" integer NOT NULL DEFAULT 0,
    "isActive" boolean NOT NULL DEFAULT true,
    "startsAt" TIMESTAMP WITH TIME ZONE,
    "endsAt" TIMESTAMP WITH TIME ZONE,
    "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
    "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "PK_vitrine_rayons" PRIMARY KEY ("id")
  )`,
  // vitrine_rayon_produits : produits ordonnés de chaque rayon de la vitrine.
  `CREATE TABLE IF NOT EXISTS "vitrine_rayon_produits" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "rayonId" uuid NOT NULL,
    "productId" uuid NOT NULL,
    "sortOrder" integer NOT NULL DEFAULT 0,
    CONSTRAINT "PK_vitrine_rayon_produits" PRIMARY KEY ("id"),
    CONSTRAINT "UQ_vitrine_rayon_produits_rayon_product" UNIQUE ("rayonId", "productId")
  )`,
  // vitrine_bandeau : bandeau d'accueil (titre, sous-titre, image).
  `CREATE TABLE IF NOT EXISTS "vitrine_bandeau" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "titre" character varying(120) NOT NULL,
    "sousTitre" character varying(200),
    "imageUrl" character varying(500),
    "isActive" boolean NOT NULL DEFAULT true,
    "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "PK_vitrine_bandeau" PRIMARY KEY ("id")
  )`,

  // ======================================================================
  // PANIER, COMMANDES ET PAIEMENTS
  // ======================================================================
  // carts : paniers (un par utilisateur).
  `CREATE TABLE IF NOT EXISTS "carts" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "userId" uuid NOT NULL,
    "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
    "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "UQ_69828a178f152f157dcf2f70a89" UNIQUE ("userId"),
    CONSTRAINT "REL_69828a178f152f157dcf2f70a8" UNIQUE ("userId"),
    CONSTRAINT "PK_b5f695a59f5ebb50af3c8160816" PRIMARY KEY ("id")
  )`,
  // cart_items : lignes de panier (variante, quantité, prix au moment de l'ajout).
  `CREATE TABLE IF NOT EXISTS "cart_items" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "cartId" uuid NOT NULL,
    "variantId" uuid NOT NULL,
    "quantity" integer NOT NULL,
    "unitPrice" numeric(12,2) NOT NULL,
    "priceChanged" boolean NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "UQ_b6efb56bc53b16c85d8c987e621" UNIQUE ("cartId", "variantId"),
    CONSTRAINT "PK_6fccf5ec03c172d27a28a82928b" PRIMARY KEY ("id")
  )`,
  // coupons : codes promotionnels créés par l'admin ou un vendeur.
  `CREATE TABLE IF NOT EXISTS "coupons" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "code" character varying(50) NOT NULL,
    "createdByAdminId" uuid,
    "createdByVendorId" uuid,
    "vendorId" uuid,
    "type" "public"."coupons_type_enum" NOT NULL,
    "value" numeric(12,2) NOT NULL,
    "minOrderAmount" numeric(12,2),
    "maxUses" numeric,
    "usedCount" integer NOT NULL DEFAULT '0',
    "expiresAt" TIMESTAMP,
    "isActive" boolean NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
    "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "UQ_e025109230e82925843f2a14c48" UNIQUE ("code"),
    CONSTRAINT "PK_d7ea8864a0150183770f3e9a8cb" PRIMARY KEY ("id")
  )`,
  // coupon_usages : utilisations de coupons (un coupon ne sert qu'une fois par utilisateur).
  `CREATE TABLE IF NOT EXISTS "coupon_usages" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "couponId" uuid NOT NULL,
    "userId" uuid NOT NULL,
    "orderId" uuid NOT NULL,
    "usedAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "UQ_803698570aee440e55af7d6a54e" UNIQUE ("couponId", "userId"),
    CONSTRAINT "PK_01ff9a1cac559c4ae2e4179d0a3" PRIMARY KEY ("id")
  )`,
  // orders : commandes (une par boutique) : statut, mode de livraison, totaux, rappels de confirmation.
  `CREATE TABLE IF NOT EXISTS "orders" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "orderNumber" character varying(50) NOT NULL,
    "userId" uuid NOT NULL,
    "vendorId" uuid NOT NULL,
    "addressId" uuid NOT NULL,
    "deliveryMode" "public"."orders_deliverymode_enum" NOT NULL DEFAULT 'livraison',
    "transportMode" character varying(10),
    "couponId" uuid,
    "status" "public"."orders_status_enum" NOT NULL DEFAULT 'en attente',
    "instructions" text,
    "subtotal" numeric(12,2) NOT NULL,
    "fraisLivraison" numeric(12,2) NOT NULL DEFAULT '0',
    "rabais" numeric(12,2) NOT NULL DEFAULT '0',
    "montantCommission" numeric(12,2) NOT NULL DEFAULT '0',
    "total" numeric(12,2) NOT NULL,
    "motifAnnulation" text,
    "expedieAt" TIMESTAMP,
    "disputeOuverte" boolean NOT NULL DEFAULT false,
    "confirmationAutomatique" boolean NOT NULL DEFAULT false,
    "vendorReminderSentAt" TIMESTAMP WITH TIME ZONE,
    "adminAlertedAt" TIMESTAMP WITH TIME ZONE,
    "handoverCode" character varying(16),
    "handoverFailedAttempts" integer NOT NULL DEFAULT '0',
    "handoverLockedUntil" TIMESTAMP WITH TIME ZONE,
    "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
    "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "UQ_59b0c3b34ea0fa5562342f24143" UNIQUE ("orderNumber"),
    CONSTRAINT "PK_710e2d4957aa5878dfe94e4ac2f" PRIMARY KEY ("id")
  )`,
  // order_items : lignes de commande (variante, quantité, prix unitaire figé).
  `CREATE TABLE IF NOT EXISTS "order_items" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "orderId" uuid NOT NULL,
    "variantId" uuid NOT NULL,
    "quantity" integer NOT NULL,
    "unitPrice" numeric(12,2) NOT NULL,
    CONSTRAINT "PK_005269d8574e6fac0493715c308" PRIMARY KEY ("id")
  )`,
  // payments : paiements des commandes (Mobile Money, carte, espèces) et référence de groupe multi-boutiques.
  `CREATE TABLE IF NOT EXISTS "payments" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "orderId" uuid NOT NULL,
    "method" "public"."payments_method_enum" NOT NULL,
    "operator" "public"."payments_operator_enum",
    "status" "public"."payments_status_enum" NOT NULL DEFAULT 'en attente',
    "providerRef" character varying(255),
    "montant" numeric(12,2) NOT NULL,
    "groupRef" character varying(64),
    "paidAt" TIMESTAMP,
    "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "UQ_af929a5f2a400fdb6913b4967e1" UNIQUE ("orderId"),
    CONSTRAINT "REL_af929a5f2a400fdb6913b4967e" UNIQUE ("orderId"),
    CONSTRAINT "PK_197ab7af18c93fbb0c9b28b4a59" PRIMARY KEY ("id")
  )`,
  // refunds : demandes de remboursement et leur traitement par l'admin.
  `CREATE TABLE IF NOT EXISTS "refunds" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "paymentId" uuid NOT NULL,
    "orderId" uuid NOT NULL,
    "montantRemb" numeric(12,2) NOT NULL,
    "motif" text NOT NULL,
    "motifRejet" text,
    "status" "public"."refunds_status_enum" NOT NULL DEFAULT 'en attente',
    "dateDemande" TIMESTAMP NOT NULL DEFAULT now(),
    "processedAt" TIMESTAMP,
    "processedById" uuid,
    "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "REL_a276dea330e561499e4a6e1b30" UNIQUE ("paymentId"),
    CONSTRAINT "PK_5106efb01eeda7e49a78b869738" PRIMARY KEY ("id")
  )`,
  // commissions : commissions de la plateforme sur chaque commande et part du vendeur.
  `CREATE TABLE IF NOT EXISTS "commissions" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "orderId" uuid NOT NULL,
    "vendorId" uuid NOT NULL,
    "totalCommande" numeric(12,2) NOT NULL,
    "taux" numeric(5,2) NOT NULL,
    "montantCommission" numeric(12,2) NOT NULL,
    "commissionVendor" numeric(12,2) NOT NULL,
    "status" "public"."commissions_status_enum" NOT NULL DEFAULT 'en attente',
    "paidAt" TIMESTAMP,
    "processedById" uuid,
    "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
    "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "UQ_f5414c93004f4c88046110d9bd8" UNIQUE ("orderId"),
    CONSTRAINT "REL_f5414c93004f4c88046110d9bd" UNIQUE ("orderId"),
    CONSTRAINT "PK_2701379966e2e670bb5ff0ae78e" PRIMARY KEY ("id")
  )`,

  // ======================================================================
  // LIVRAISON
  // ======================================================================
  // delivery_zones : zones de livraison (commune, département, frais).
  `CREATE TABLE IF NOT EXISTS "delivery_zones" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "commune" character varying(100) NOT NULL,
    "departement" character varying(100) NOT NULL,
    "fraisLivraison" numeric(10,2) NOT NULL DEFAULT '0',
    "isActive" boolean NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
    "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "PK_88bc4c12be62436a61930cf34a9" PRIMARY KEY ("id")
  )`,
  // delivery_agent_profiles : profils des livreurs (véhicule, documents, statut, taux de gain).
  `CREATE TABLE IF NOT EXISTS "delivery_agent_profiles" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "userId" uuid NOT NULL,
    "vehicleType" "public"."delivery_agent_profiles_vehicletype_enum" NOT NULL,
    "availability" "public"."delivery_agent_profiles_availability_enum" NOT NULL,
    "isAvailableNow" boolean NOT NULL DEFAULT false,
    "ville" character varying(100) NOT NULL,
    "quartier" character varying(100) NOT NULL,
    "preciseAddress" text NOT NULL,
    "idDocumentUrl" character varying(500),
    "selfieUrl" character varying(500),
    "vehiclePhotoUrl" character varying(500),
    "licensePlate" character varying(50) NOT NULL,
    "termsAccepted" boolean NOT NULL DEFAULT false,
    "fraudPenaltiesAccepted" boolean NOT NULL DEFAULT false,
    "status" "public"."delivery_agent_profiles_status_enum" NOT NULL DEFAULT 'en attente',
    "motifRefus" text,
    "reviewedById" uuid,
    "reviewedAt" TIMESTAMP,
    "noteMoyenne" numeric(3,2) NOT NULL DEFAULT '0',
    "tauxDeReussite" numeric(5,2) NOT NULL DEFAULT '0',
    "totalLivraisons" integer NOT NULL DEFAULT '0',
    "earningsRate" numeric(5,2),
    "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
    "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "UQ_02bfffef8b0481e5263f40d6949" UNIQUE ("userId"),
    CONSTRAINT "REL_02bfffef8b0481e5263f40d694" UNIQUE ("userId"),
    CONSTRAINT "PK_9ef2ef51b30b69eae7e269660c3" PRIMARY KEY ("id")
  )`,
  // deliveries : livraisons liées à une commande (livreur, étapes, position GPS).
  `CREATE TABLE IF NOT EXISTS "deliveries" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "orderId" uuid NOT NULL,
    "agentId" uuid,
    "pickupAddress" text NOT NULL,
    "adresseLivraison" text NOT NULL,
    "latitude" double precision,
    "longitude" double precision,
    "status" "public"."deliveries_status_enum" NOT NULL DEFAULT 'en attente',
    "instructions" text,
    "pickedUpAt" TIMESTAMP,
    "deliveredAt" TIMESTAMP,
    "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
    "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "UQ_f7433e3639e213f901e22cf8640" UNIQUE ("orderId"),
    CONSTRAINT "REL_f7433e3639e213f901e22cf864" UNIQUE ("orderId"),
    CONSTRAINT "PK_a6ef225c5c5f0974e503bfb731f" PRIMARY KEY ("id")
  )`,
  // delivery_proofs : preuves de livraison immuables (photo, QR, GPS, signature) à chaque étape.
  `CREATE TABLE IF NOT EXISTS "delivery_proofs" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "orderId" uuid NOT NULL,
    "deliveryId" uuid,
    "role" "delivery_proofs_role_enum" NOT NULL,
    "stage" "delivery_proofs_stage_enum" NOT NULL,
    "photoUrl" varchar(500),
    "etatColis" text,
    "qrScanValue" varchar(255),
    "latitude" double precision,
    "longitude" double precision,
    "signatureData" text,
    "createdByUserId" uuid NOT NULL,
    "createdAt" timestamp NOT NULL DEFAULT now(),
    CONSTRAINT "PK_delivery_proofs" PRIMARY KEY ("id")
  )`,
  // delivery_earnings : gains des livreurs par livraison (part livreur / part plateforme).
  `CREATE TABLE IF NOT EXISTS "delivery_earnings" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "deliveryId" uuid NOT NULL,
    "agentId" uuid NOT NULL,
    "fraisLivraison" numeric(12,2) NOT NULL,
    "taux" numeric(5,2) NOT NULL,
    "montantLivreur" numeric(12,2) NOT NULL,
    "montantPlateforme" numeric(12,2) NOT NULL,
    "status" "public"."delivery_earnings_status_enum" NOT NULL DEFAULT 'en attente',
    "paidAt" TIMESTAMP,
    "processedById" uuid,
    "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
    "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "UQ_delivery_earnings_deliveryId" UNIQUE ("deliveryId"),
    CONSTRAINT "PK_delivery_earnings" PRIMARY KEY ("id")
  )`,
  // independent_deliveries : livraisons indépendantes demandées par un utilisateur, hors commande.
  `CREATE TABLE IF NOT EXISTS "independent_deliveries" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "requesterId" uuid NOT NULL,
    "agentId" uuid,
    "pickupAddress" text NOT NULL,
    "adresseLivraison" text NOT NULL,
    "packageDescription" text,
    "status" "public"."independent_deliveries_status_enum" NOT NULL DEFAULT 'en attente',
    "tarifConvenu" numeric(12,2),
    "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
    "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "PK_e718a104814e84b98bfec2bc9bf" PRIMARY KEY ("id")
  )`,

  // ======================================================================
  // MESSAGERIE, NOTIFICATIONS ET SUPPORT
  // ======================================================================
  // conversations : conversations entre un client et une boutique.
  `CREATE TABLE IF NOT EXISTS "conversations" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "clientId" uuid NOT NULL,
    "vendorId" uuid NOT NULL,
    "productId" uuid,
    "isArchived" boolean NOT NULL DEFAULT false,
    "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
    "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "UQ_60a88a14bf597185dc21af2d3f6" UNIQUE ("clientId", "vendorId"),
    CONSTRAINT "PK_ee34f4f7ced4ec8681f26bf04ef" PRIMARY KEY ("id")
  )`,
  // messages : messages d'une conversation (texte, image, modération, lu / non lu).
  `CREATE TABLE IF NOT EXISTS "messages" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "conversationId" uuid NOT NULL,
    "senderId" uuid NOT NULL,
    "content" text,
    "imageUrl" character varying(500),
    "isBlocked" boolean NOT NULL DEFAULT false,
    "blockReason" character varying(255),
    "isReported" boolean NOT NULL DEFAULT false,
    "isRead" boolean NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "PK_18325f38ae6de43878487eff986" PRIMARY KEY ("id")
  )`,
  // notifications : notifications envoyées aux utilisateurs et aux admins.
  `CREATE TABLE IF NOT EXISTS "notifications" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "userId" uuid,
    "adminId" uuid,
    "title" character varying(255) NOT NULL,
    "body" text NOT NULL,
    "type" "public"."notifications_type_enum" NOT NULL,
    "referenceId" character varying,
    "referenceType" character varying(50),
    "isRead" boolean NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "PK_6a72c3c0f683f6462415e653c3a" PRIMARY KEY ("id")
  )`,
  // support_tickets : tickets de support (numéro lisible, catégorie, statut, admin assigné).
  `CREATE TABLE IF NOT EXISTS "support_tickets" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "number" integer NOT NULL DEFAULT nextval('support_tickets_number_seq'),
    "userId" uuid NOT NULL,
    "category" character varying(30) NOT NULL,
    "subject" character varying(150) NOT NULL,
    "status" character varying(20) NOT NULL DEFAULT 'ouvert',
    "orderId" uuid,
    "assignedAdminId" uuid,
    "lastMessageAt" TIMESTAMP NOT NULL DEFAULT now(),
    "closedAt" TIMESTAMP,
    "userHasUnread" boolean NOT NULL DEFAULT false,
    "adminHasUnread" boolean NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
    "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "PK_support_tickets" PRIMARY KEY ("id"),
    CONSTRAINT "UQ_support_tickets_number" UNIQUE ("number")
  )`,
  // support_ticket_messages : fil de discussion d'un ticket de support.
  `CREATE TABLE IF NOT EXISTS "support_ticket_messages" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "ticketId" uuid NOT NULL,
    "authorId" uuid NOT NULL,
    "authorType" character varying(10) NOT NULL,
    "body" character varying(4000) NOT NULL,
    "attachments" jsonb NOT NULL DEFAULT '[]',
    "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT "PK_support_ticket_messages" PRIMARY KEY ("id")
  )`,
];

// La séquence du numéro de ticket appartient à la colonne : supprimée avec la table.
const APRES_TABLES: string[] = [
  `ALTER SEQUENCE "support_tickets_number_seq" OWNED BY "support_tickets"."number"`,
];

// ── Index ────────────────────────────────────────────────────────────────
// Inclut les index « partiels » (WHERE …) et les index trigram (GIN) créés
// par les migrations.
const INDEXES: string[] = [
  // ======================================================================
  // COMPTES ET IDENTITÉ
  // ======================================================================
  // users
  `CREATE INDEX IF NOT EXISTS "IDX_51b8b26ac168fbe7d6f5653e6c" ON "users" ("name")`,
  `CREATE INDEX IF NOT EXISTS "IDX_97672ac88f789774dd47f7c8be" ON "users" ("email")`,
  `CREATE INDEX IF NOT EXISTS "IDX_a000cca60bcf04454e72769949" ON "users" ("phone")`,
  `CREATE INDEX IF NOT EXISTS "IDX_ce8452770ca2e1003bfdc194fb" ON "users" ("prenom")`,
  `CREATE INDEX IF NOT EXISTS "IDX_users_security_alert" ON "users" ("securityAlertAt") WHERE "securityAlertAt" IS NOT NULL`,
  // user_roles
  `CREATE INDEX IF NOT EXISTS "IDX_472b25323af01488f1f66a06b6" ON "user_roles" ("userId")`,
  // addresses
  `CREATE INDEX IF NOT EXISTS "IDX_95c93a584de49f0b0e13f75363" ON "addresses" ("userId")`,
  // admin_accounts
  `CREATE INDEX IF NOT EXISTS "IDX_05a0a0da9626f51206e41eda9d" ON "admin_accounts" ("email")`,
  `CREATE INDEX IF NOT EXISTS "IDX_0cf69d77e55602fc5a3a03285e" ON "admin_accounts" ("name")`,
  `CREATE INDEX IF NOT EXISTS "IDX_f3e8f14f60909edd8ccbe51cb8" ON "admin_accounts" ("prenom")`,
  // otp_codes
  `CREATE INDEX IF NOT EXISTS "IDX_51f6c167908c125bef1f18fe7b" ON "otp_codes" ("userId")`,
  `CREATE INDEX IF NOT EXISTS "IDX_699c852115b1842430dd2ec0fa" ON "otp_codes" ("userId", "type", "isUsed")`,
  `CREATE INDEX IF NOT EXISTS "IDX_7516487afe3800dd744fee1e86" ON "otp_codes" ("expiresAt")`,
  // email_changes
  `CREATE INDEX IF NOT EXISTS "IDX_email_changes_revertTokenHash" ON "email_changes" ("revertTokenHash")`,
  `CREATE INDEX IF NOT EXISTS "IDX_email_changes_userId" ON "email_changes" ("userId")`,
  `CREATE UNIQUE INDEX IF NOT EXISTS "UQ_email_changes_one_pending_per_user" ON "email_changes" ("userId") WHERE "status" = 'pending'`,
  // activity_logs
  `CREATE INDEX IF NOT EXISTS "IDX_110bb0d32b7f65be46be37e257" ON "activity_logs" ("actorId")`,
  `CREATE INDEX IF NOT EXISTS "IDX_377463c364326082e86ce68ed3" ON "activity_logs" ("entityId")`,
  `CREATE INDEX IF NOT EXISTS "IDX_879e2d305a025dadfe9929c47d" ON "activity_logs" ("action")`,
  `CREATE INDEX IF NOT EXISTS "IDX_95355d75c728050aae956cf016" ON "activity_logs" ("createdAt")`,

  // ======================================================================
  // BOUTIQUES, VENDEURS ET PARTENAIRES
  // ======================================================================
  // vendor_profiles
  `CREATE INDEX IF NOT EXISTS "IDX_fe350603a4a45e923a9830a6f3" ON "vendor_profiles" ("shopName")`,
  `CREATE INDEX IF NOT EXISTS "IDX_vendor_profiles_status" ON "vendor_profiles" ("status")`,
  // shop_follows
  `CREATE INDEX IF NOT EXISTS "IDX_shop_follows_vendorId" ON "shop_follows" ("vendorId")`,
  // featured_shops
  `CREATE INDEX IF NOT EXISTS "IDX_featured_shops_isActive_position" ON "featured_shops" ("isActive", "position")`,
  // vendor_withdrawals
  `CREATE INDEX IF NOT EXISTS "IDX_vendor_withdrawals_createdAt" ON "vendor_withdrawals" ("createdAt")`,
  `CREATE INDEX IF NOT EXISTS "IDX_vendor_withdrawals_status" ON "vendor_withdrawals" ("status")`,
  `CREATE INDEX IF NOT EXISTS "IDX_vendor_withdrawals_vendorId" ON "vendor_withdrawals" ("vendorId")`,
  `CREATE UNIQUE INDEX IF NOT EXISTS "UQ_vendor_withdrawals_one_pending" ON "vendor_withdrawals" ("vendorId") WHERE "status" = 'en attente'`,

  // ======================================================================
  // CATALOGUE PRODUITS
  // ======================================================================
  // categories
  `CREATE INDEX IF NOT EXISTS "IDX_420d9f679d41281f282f5bc7d0" ON "categories" ("slug")`,
  `CREATE INDEX IF NOT EXISTS "IDX_8b0be371d28245da6e4f4b6187" ON "categories" ("name")`,
  // products
  `CREATE INDEX IF NOT EXISTS "IDX_05b74ed0488ecb76ae5dab37ac" ON "products" ("prod_name")`,
  `CREATE INDEX IF NOT EXISTS "IDX_464f927ae360106b783ed0b410" ON "products" ("slug")`,
  `CREATE INDEX IF NOT EXISTS "idx_products_prod_name_trgm" ON "products" USING gin ("prod_name" gin_trgm_ops)`,
  `CREATE INDEX IF NOT EXISTS "IDX_products_status_createdAt" ON "products" ("status", "createdAt")`,
  `CREATE INDEX IF NOT EXISTS "IDX_products_vendorId" ON "products" ("vendorId")`,
  // product_categories
  `CREATE INDEX IF NOT EXISTS "IDX_6156a79599e274ee9d83b1de13" ON "product_categories" ("productId")`,
  `CREATE INDEX IF NOT EXISTS "IDX_fdef3adba0c284fd103d0fd369" ON "product_categories" ("categoryId")`,
  // product_images
  `CREATE INDEX IF NOT EXISTS "IDX_b367708bf720c8dd62fc683316" ON "product_images" ("productId")`,
  // product_variants
  `CREATE INDEX IF NOT EXISTS "IDX_46f236f21640f9da218a063a86" ON "product_variants" ("sku")`,
  `CREATE INDEX IF NOT EXISTS "IDX_product_variants_productId" ON "product_variants" ("productId")`,
  // product_tags
  `CREATE INDEX IF NOT EXISTS "IDX_bbc3fefb51e1b20fb586580133" ON "product_tags" ("tag")`,
  `CREATE INDEX IF NOT EXISTS "idx_product_tags_tag_trgm" ON "product_tags" USING gin ("tag" gin_trgm_ops)`,
  // wishlists
  `CREATE INDEX IF NOT EXISTS "IDX_063c6f46d6cbebf35f3a5ec3d4" ON "wishlists" ("productId")`,
  `CREATE INDEX IF NOT EXISTS "IDX_4f3c30555daa6ab0b70a1db772" ON "wishlists" ("userId")`,
  // reviews
  `CREATE INDEX IF NOT EXISTS "IDX_7b06c23cf52ca8aea0dcaf0ee2" ON "reviews" ("status")`,
  `CREATE INDEX IF NOT EXISTS "IDX_7ed5659e7139fc8bc039198cc1" ON "reviews" ("userId")`,
  `CREATE INDEX IF NOT EXISTS "IDX_a6b3c434392f5d10ec17104366" ON "reviews" ("productId")`,

  // ======================================================================
  // VITRINE DE LA PAGE D'ACCUEIL
  // ======================================================================
  // vitrine_rayons
  `CREATE INDEX IF NOT EXISTS "IDX_vitrine_rayons_isActive_sortOrder" ON "vitrine_rayons" ("isActive", "sortOrder")`,
  // vitrine_rayon_produits
  `CREATE INDEX IF NOT EXISTS "IDX_vitrine_rayon_produits_productId" ON "vitrine_rayon_produits" ("productId")`,

  // ======================================================================
  // PANIER, COMMANDES ET PAIEMENTS
  // ======================================================================
  // carts
  `CREATE INDEX IF NOT EXISTS "IDX_69828a178f152f157dcf2f70a8" ON "carts" ("userId")`,
  // cart_items
  `CREATE INDEX IF NOT EXISTS "IDX_5a27845bc2d79be6f1fa3d2c03" ON "cart_items" ("variantId")`,
  `CREATE INDEX IF NOT EXISTS "IDX_edd714311619a5ad0952504583" ON "cart_items" ("cartId")`,
  // coupons
  `CREATE INDEX IF NOT EXISTS "IDX_e025109230e82925843f2a14c4" ON "coupons" ("code")`,
  // coupon_usages
  `CREATE INDEX IF NOT EXISTS "IDX_803698570aee440e55af7d6a54" ON "coupon_usages" ("couponId", "userId")`,
  `CREATE INDEX IF NOT EXISTS "IDX_a7b422cc0dbf863671255eaad5" ON "coupon_usages" ("couponId")`,
  `CREATE INDEX IF NOT EXISTS "IDX_f526503f2419217d16794648f2" ON "coupon_usages" ("userId")`,
  // orders
  `CREATE INDEX IF NOT EXISTS "IDX_14dffab8aee1ce044f8e8e5423" ON "orders" ("vendorId", "status")`,
  `CREATE INDEX IF NOT EXISTS "IDX_151b79a83ba240b0cb31b2302d" ON "orders" ("userId")`,
  `CREATE INDEX IF NOT EXISTS "IDX_1f4b9818a08b822a31493fdee9" ON "orders" ("createdAt")`,
  `CREATE INDEX IF NOT EXISTS "IDX_4fc5a9360e2b4e795f02344ae7" ON "orders" ("vendorId")`,
  `CREATE INDEX IF NOT EXISTS "IDX_59b0c3b34ea0fa5562342f2414" ON "orders" ("orderNumber")`,
  `CREATE INDEX IF NOT EXISTS "IDX_775c9f06fc27ae3ff8fb26f2c4" ON "orders" ("status")`,
  `CREATE INDEX IF NOT EXISTS "IDX_orders_awaiting_vendor_confirmation" ON "orders" ("createdAt") WHERE "status" = 'en attente' AND ("vendorReminderSentAt" IS NULL OR "adminAlertedAt" IS NULL)`,
  // order_items
  `CREATE INDEX IF NOT EXISTS "IDX_516736b9807228bb17b2d0a3e2" ON "order_items" ("variantId")`,
  `CREATE INDEX IF NOT EXISTS "IDX_f1d359a55923bb45b057fbdab0" ON "order_items" ("orderId")`,
  // payments
  `CREATE INDEX IF NOT EXISTS "IDX_32b41cdb985a296213e9a928b5" ON "payments" ("status")`,
  `CREATE INDEX IF NOT EXISTS "IDX_684d092a3d90f53057424fc1ec" ON "payments" ("providerRef")`,
  `CREATE INDEX IF NOT EXISTS "IDX_payments_groupRef" ON "payments" ("groupRef")`,
  // refunds
  `CREATE INDEX IF NOT EXISTS "IDX_605cf4d367799f3e5cfb9f6822" ON "refunds" ("orderId")`,
  `CREATE INDEX IF NOT EXISTS "IDX_90c78d3c32a3346772edf34e73" ON "refunds" ("status")`,
  // commissions
  `CREATE INDEX IF NOT EXISTS "IDX_87a59dece25a9e3b3a9b1758ca" ON "commissions" ("createdAt")`,
  `CREATE INDEX IF NOT EXISTS "IDX_a4fdb3d46dc59b3b32a5440db9" ON "commissions" ("status")`,
  `CREATE INDEX IF NOT EXISTS "IDX_fa1f9e7b7627cacd0edd8f1cd2" ON "commissions" ("vendorId")`,

  // ======================================================================
  // LIVRAISON
  // ======================================================================
  // delivery_zones
  `CREATE UNIQUE INDEX IF NOT EXISTS "IDX_ec3d83f811dece724baa7055c0" ON "delivery_zones" ("commune")`,
  // deliveries
  `CREATE INDEX IF NOT EXISTS "IDX_3235c9c06d9d3028a11ec8081d" ON "deliveries" ("status")`,
  `CREATE INDEX IF NOT EXISTS "IDX_43a0308abeb6f1e56e4da75191" ON "deliveries" ("agentId")`,
  `CREATE INDEX IF NOT EXISTS "IDX_9b9637db555f7f7355ddf0e36d" ON "deliveries" ("agentId", "status")`,
  `CREATE INDEX IF NOT EXISTS "IDX_f7433e3639e213f901e22cf864" ON "deliveries" ("orderId")`,
  // delivery_proofs
  `CREATE INDEX IF NOT EXISTS "IDX_delivery_proofs_deliveryId" ON "delivery_proofs" ("deliveryId")`,
  `CREATE INDEX IF NOT EXISTS "IDX_delivery_proofs_orderId" ON "delivery_proofs" ("orderId")`,
  `CREATE INDEX IF NOT EXISTS "IDX_delivery_proofs_stage" ON "delivery_proofs" ("stage")`,
  // delivery_earnings
  `CREATE INDEX IF NOT EXISTS "IDX_delivery_earnings_agentId" ON "delivery_earnings" ("agentId")`,
  `CREATE INDEX IF NOT EXISTS "IDX_delivery_earnings_status" ON "delivery_earnings" ("status")`,

  // ======================================================================
  // MESSAGERIE, NOTIFICATIONS ET SUPPORT
  // ======================================================================
  // conversations
  `CREATE INDEX IF NOT EXISTS "IDX_conversations_vendorId" ON "conversations" ("vendorId")`,
  // messages
  `CREATE INDEX IF NOT EXISTS "IDX_messages_conversation_unread" ON "messages" ("conversationId") WHERE "isRead" = false`,
  `CREATE INDEX IF NOT EXISTS "IDX_messages_conversationId_createdAt" ON "messages" ("conversationId", "createdAt")`,
  // notifications
  `CREATE INDEX IF NOT EXISTS "IDX_4509d5b418f7eb05ac668d5056" ON "notifications" ("adminId")`,
  `CREATE INDEX IF NOT EXISTS "IDX_692a909ee0fa9383e7859f9b40" ON "notifications" ("userId")`,
  `CREATE INDEX IF NOT EXISTS "IDX_notifications_userId_createdAt" ON "notifications" ("userId", "createdAt")`,
  // support_tickets
  `CREATE INDEX IF NOT EXISTS "IDX_support_tickets_status_lastMessageAt" ON "support_tickets" ("status", "lastMessageAt")`,
  `CREATE INDEX IF NOT EXISTS "IDX_support_tickets_userId_lastMessageAt" ON "support_tickets" ("userId", "lastMessageAt")`,
  // support_ticket_messages
  `CREATE INDEX IF NOT EXISTS "IDX_support_ticket_messages_authorId_createdAt" ON "support_ticket_messages" ("authorId", "createdAt")`,
  `CREATE INDEX IF NOT EXISTS "IDX_support_ticket_messages_ticketId_createdAt" ON "support_ticket_messages" ("ticketId", "createdAt")`,
];

// ── Clés étrangères ──────────────────────────────────────────────────────
// Exécutées dans un bloc DO … EXCEPTION : une contrainte déjà présente est ignorée.
const FOREIGN_KEYS: string[] = [
  // ======================================================================
  // COMPTES ET IDENTITÉ
  // ======================================================================
  `ALTER TABLE "user_roles" ADD CONSTRAINT "FK_472b25323af01488f1f66a06b67"
    FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE NO ACTION`,
  `ALTER TABLE "addresses" ADD CONSTRAINT "FK_95c93a584de49f0b0e13f753630"
    FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE NO ACTION`,
  `ALTER TABLE "admin_accounts" ADD CONSTRAINT "FK_94534985d2d7c803413dadf17c6"
    FOREIGN KEY ("createdById") REFERENCES "admin_accounts"("id") ON DELETE NO ACTION ON UPDATE NO ACTION`,
  `ALTER TABLE "otp_codes" ADD CONSTRAINT "FK_51f6c167908c125bef1f18fe7bc"
    FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE NO ACTION`,
  `ALTER TABLE "email_changes" ADD CONSTRAINT "FK_email_changes_user"
    FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE`,

  // ======================================================================
  // BOUTIQUES, VENDEURS ET PARTENAIRES
  // ======================================================================
  `ALTER TABLE "vendor_profiles" ADD CONSTRAINT "FK_658558b7f3a6163382505c8009e"
    FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE NO ACTION`,
  `ALTER TABLE "vendor_profiles" ADD CONSTRAINT "FK_0906591540ce08ce2e1053f4dd8"
    FOREIGN KEY ("reviewedById") REFERENCES "admin_accounts"("id") ON DELETE NO ACTION ON UPDATE NO ACTION`,
  `ALTER TABLE "shop_follows" ADD CONSTRAINT "FK_shop_follows_user"
    FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE`,
  `ALTER TABLE "shop_follows" ADD CONSTRAINT "FK_shop_follows_vendor"
    FOREIGN KEY ("vendorId") REFERENCES "vendor_profiles"("id") ON DELETE CASCADE`,
  `ALTER TABLE "featured_shops" ADD CONSTRAINT "FK_featured_shops_vendor"
    FOREIGN KEY ("vendorId") REFERENCES "vendor_profiles"("id") ON DELETE CASCADE`,
  `ALTER TABLE "vendor_withdrawals" ADD CONSTRAINT "FK_vendor_withdrawals_vendor"
    FOREIGN KEY ("vendorId") REFERENCES "vendor_profiles"("id") ON DELETE RESTRICT`,
  `ALTER TABLE "vendor_withdrawals" ADD CONSTRAINT "FK_vendor_withdrawals_processedBy"
    FOREIGN KEY ("processedById") REFERENCES "admin_accounts"("id") ON DELETE SET NULL`,
  `ALTER TABLE "partners" ADD CONSTRAINT "FK_60d4e119975e0d1f568e330b8ea"
    FOREIGN KEY ("createdById") REFERENCES "admin_accounts"("id") ON DELETE NO ACTION ON UPDATE NO ACTION`,
  `ALTER TABLE "fournisseurs" ADD CONSTRAINT "FK_a2632d79c8d60dd7167be224c36"
    FOREIGN KEY ("createdById") REFERENCES "admin_accounts"("id") ON DELETE NO ACTION ON UPDATE NO ACTION`,

  // ======================================================================
  // CATALOGUE PRODUITS
  // ======================================================================
  `ALTER TABLE "categories" ADD CONSTRAINT "FK_9a6f051e66982b5f0318981bcaa"
    FOREIGN KEY ("parentId") REFERENCES "categories"("id") ON DELETE SET NULL ON UPDATE NO ACTION`,
  `ALTER TABLE "products" ADD CONSTRAINT "FK_6b00af9e9c38a1673f594de74f4"
    FOREIGN KEY ("vendorId") REFERENCES "vendor_profiles"("id") ON DELETE CASCADE ON UPDATE NO ACTION`,
  `ALTER TABLE "product_categories" ADD CONSTRAINT "FK_6156a79599e274ee9d83b1de139"
    FOREIGN KEY ("productId") REFERENCES "products"("id") ON DELETE CASCADE ON UPDATE CASCADE`,
  `ALTER TABLE "product_categories" ADD CONSTRAINT "FK_fdef3adba0c284fd103d0fd3697"
    FOREIGN KEY ("categoryId") REFERENCES "categories"("id") ON DELETE CASCADE ON UPDATE CASCADE`,
  `ALTER TABLE "product_images" ADD CONSTRAINT "FK_b367708bf720c8dd62fc6833161"
    FOREIGN KEY ("productId") REFERENCES "products"("id") ON DELETE CASCADE ON UPDATE NO ACTION`,
  `ALTER TABLE "product_variants" ADD CONSTRAINT "FK_f515690c571a03400a9876600b5"
    FOREIGN KEY ("productId") REFERENCES "products"("id") ON DELETE CASCADE ON UPDATE NO ACTION`,
  `ALTER TABLE "product_tags" ADD CONSTRAINT "FK_d11be11255b8eeb5d761023e6bc"
    FOREIGN KEY ("productId") REFERENCES "products"("id") ON DELETE CASCADE ON UPDATE NO ACTION`,
  `ALTER TABLE "product_tier_prices" ADD CONSTRAINT "FK_75f2963f44e7fb2eab7b1193378"
    FOREIGN KEY ("productId") REFERENCES "products"("id") ON DELETE CASCADE ON UPDATE NO ACTION`,
  `ALTER TABLE "wishlists" ADD CONSTRAINT "FK_4f3c30555daa6ab0b70a1db772c"
    FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE NO ACTION`,
  `ALTER TABLE "wishlists" ADD CONSTRAINT "FK_063c6f46d6cbebf35f3a5ec3d4e"
    FOREIGN KEY ("productId") REFERENCES "products"("id") ON DELETE CASCADE ON UPDATE NO ACTION`,
  `ALTER TABLE "reviews" ADD CONSTRAINT "FK_7ed5659e7139fc8bc039198cc1f"
    FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE NO ACTION`,
  `ALTER TABLE "reviews" ADD CONSTRAINT "FK_a6b3c434392f5d10ec171043666"
    FOREIGN KEY ("productId") REFERENCES "products"("id") ON DELETE CASCADE ON UPDATE NO ACTION`,
  `ALTER TABLE "reviews" ADD CONSTRAINT "FK_53a68dc905777554b7f702791fa"
    FOREIGN KEY ("orderId") REFERENCES "orders"("id") ON DELETE RESTRICT ON UPDATE NO ACTION`,

  // ======================================================================
  // VITRINE DE LA PAGE D'ACCUEIL
  // ======================================================================
  `ALTER TABLE "vitrine_rayon_produits" ADD CONSTRAINT "FK_vitrine_rayon_produits_rayon"
    FOREIGN KEY ("rayonId") REFERENCES "vitrine_rayons"("id") ON DELETE CASCADE`,
  `ALTER TABLE "vitrine_rayon_produits" ADD CONSTRAINT "FK_vitrine_rayon_produits_product"
    FOREIGN KEY ("productId") REFERENCES "products"("id") ON DELETE CASCADE`,

  // ======================================================================
  // PANIER, COMMANDES ET PAIEMENTS
  // ======================================================================
  `ALTER TABLE "carts" ADD CONSTRAINT "FK_69828a178f152f157dcf2f70a89"
    FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE NO ACTION`,
  `ALTER TABLE "cart_items" ADD CONSTRAINT "FK_edd714311619a5ad09525045838"
    FOREIGN KEY ("cartId") REFERENCES "carts"("id") ON DELETE CASCADE ON UPDATE NO ACTION`,
  `ALTER TABLE "cart_items" ADD CONSTRAINT "FK_5a27845bc2d79be6f1fa3d2c036"
    FOREIGN KEY ("variantId") REFERENCES "product_variants"("id") ON DELETE CASCADE ON UPDATE NO ACTION`,
  `ALTER TABLE "coupons" ADD CONSTRAINT "FK_77eb2294f585dfe12eefd71c0d0"
    FOREIGN KEY ("createdByAdminId") REFERENCES "admin_accounts"("id") ON DELETE SET NULL ON UPDATE NO ACTION`,
  `ALTER TABLE "coupons" ADD CONSTRAINT "FK_326cf73daa0e26d19a8c988935b"
    FOREIGN KEY ("createdByVendorId") REFERENCES "vendor_profiles"("id") ON DELETE SET NULL ON UPDATE NO ACTION`,
  `ALTER TABLE "coupons" ADD CONSTRAINT "FK_f204fd3f2e1f0ea4772d6138776"
    FOREIGN KEY ("vendorId") REFERENCES "vendor_profiles"("id") ON DELETE SET NULL ON UPDATE NO ACTION`,
  `ALTER TABLE "coupon_usages" ADD CONSTRAINT "FK_a7b422cc0dbf863671255eaad57"
    FOREIGN KEY ("couponId") REFERENCES "coupons"("id") ON DELETE CASCADE ON UPDATE NO ACTION`,
  `ALTER TABLE "coupon_usages" ADD CONSTRAINT "FK_f526503f2419217d16794648f29"
    FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE NO ACTION`,
  `ALTER TABLE "coupon_usages" ADD CONSTRAINT "FK_131640403c2fdd7a65ab7218873"
    FOREIGN KEY ("orderId") REFERENCES "orders"("id") ON DELETE RESTRICT ON UPDATE NO ACTION`,
  `ALTER TABLE "orders" ADD CONSTRAINT "FK_151b79a83ba240b0cb31b2302d1"
    FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE NO ACTION`,
  `ALTER TABLE "orders" ADD CONSTRAINT "FK_4fc5a9360e2b4e795f02344ae75"
    FOREIGN KEY ("vendorId") REFERENCES "vendor_profiles"("id") ON DELETE RESTRICT ON UPDATE NO ACTION`,
  `ALTER TABLE "orders" ADD CONSTRAINT "FK_37636d260931dcf46d11892f614"
    FOREIGN KEY ("addressId") REFERENCES "addresses"("id") ON DELETE RESTRICT ON UPDATE NO ACTION`,
  `ALTER TABLE "orders" ADD CONSTRAINT "FK_c26db6c65929ecfeab91073e80c"
    FOREIGN KEY ("couponId") REFERENCES "coupons"("id") ON DELETE SET NULL ON UPDATE NO ACTION`,
  `ALTER TABLE "order_items" ADD CONSTRAINT "FK_f1d359a55923bb45b057fbdab0d"
    FOREIGN KEY ("orderId") REFERENCES "orders"("id") ON DELETE CASCADE ON UPDATE NO ACTION`,
  `ALTER TABLE "order_items" ADD CONSTRAINT "FK_516736b9807228bb17b2d0a3e2a"
    FOREIGN KEY ("variantId") REFERENCES "product_variants"("id") ON DELETE RESTRICT ON UPDATE NO ACTION`,
  `ALTER TABLE "payments" ADD CONSTRAINT "FK_af929a5f2a400fdb6913b4967e1"
    FOREIGN KEY ("orderId") REFERENCES "orders"("id") ON DELETE RESTRICT ON UPDATE NO ACTION`,
  `ALTER TABLE "refunds" ADD CONSTRAINT "FK_a276dea330e561499e4a6e1b309"
    FOREIGN KEY ("paymentId") REFERENCES "payments"("id") ON DELETE RESTRICT ON UPDATE NO ACTION`,
  `ALTER TABLE "refunds" ADD CONSTRAINT "FK_605cf4d367799f3e5cfb9f68229"
    FOREIGN KEY ("orderId") REFERENCES "orders"("id") ON DELETE RESTRICT ON UPDATE NO ACTION`,
  `ALTER TABLE "refunds" ADD CONSTRAINT "FK_049a26d01ed08f25835e71181d1"
    FOREIGN KEY ("processedById") REFERENCES "admin_accounts"("id") ON DELETE NO ACTION ON UPDATE NO ACTION`,
  `ALTER TABLE "commissions" ADD CONSTRAINT "FK_f5414c93004f4c88046110d9bd8"
    FOREIGN KEY ("orderId") REFERENCES "orders"("id") ON DELETE RESTRICT ON UPDATE NO ACTION`,
  `ALTER TABLE "commissions" ADD CONSTRAINT "FK_fa1f9e7b7627cacd0edd8f1cd2e"
    FOREIGN KEY ("vendorId") REFERENCES "vendor_profiles"("id") ON DELETE RESTRICT ON UPDATE NO ACTION`,
  `ALTER TABLE "commissions" ADD CONSTRAINT "FK_936f3fc57d5287c48b2148757e6"
    FOREIGN KEY ("processedById") REFERENCES "admin_accounts"("id") ON DELETE NO ACTION ON UPDATE NO ACTION`,

  // ======================================================================
  // LIVRAISON
  // ======================================================================
  `ALTER TABLE "delivery_agent_profiles" ADD CONSTRAINT "FK_02bfffef8b0481e5263f40d6949"
    FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE NO ACTION`,
  `ALTER TABLE "delivery_agent_profiles" ADD CONSTRAINT "FK_10b075608939ffb1c7aecb99878"
    FOREIGN KEY ("reviewedById") REFERENCES "admin_accounts"("id") ON DELETE NO ACTION ON UPDATE NO ACTION`,
  `ALTER TABLE "deliveries" ADD CONSTRAINT "FK_f7433e3639e213f901e22cf8640"
    FOREIGN KEY ("orderId") REFERENCES "orders"("id") ON DELETE RESTRICT ON UPDATE NO ACTION`,
  `ALTER TABLE "deliveries" ADD CONSTRAINT "FK_43a0308abeb6f1e56e4da751910"
    FOREIGN KEY ("agentId") REFERENCES "delivery_agent_profiles"("id") ON DELETE SET NULL ON UPDATE NO ACTION`,
  `ALTER TABLE "delivery_proofs" ADD CONSTRAINT "FK_delivery_proofs_order"
    FOREIGN KEY ("orderId") REFERENCES "orders"("id") ON DELETE RESTRICT`,
  `ALTER TABLE "delivery_proofs" ADD CONSTRAINT "FK_delivery_proofs_delivery"
    FOREIGN KEY ("deliveryId") REFERENCES "deliveries"("id") ON DELETE RESTRICT`,
  `ALTER TABLE "delivery_proofs" ADD CONSTRAINT "FK_delivery_proofs_created_by"
    FOREIGN KEY ("createdByUserId") REFERENCES "users"("id") ON DELETE RESTRICT`,
  `ALTER TABLE "delivery_earnings" ADD CONSTRAINT "FK_delivery_earnings_delivery"
    FOREIGN KEY ("deliveryId") REFERENCES "deliveries"("id") ON DELETE RESTRICT`,
  `ALTER TABLE "delivery_earnings" ADD CONSTRAINT "FK_delivery_earnings_agent"
    FOREIGN KEY ("agentId") REFERENCES "delivery_agent_profiles"("id") ON DELETE RESTRICT`,
  `ALTER TABLE "delivery_earnings" ADD CONSTRAINT "FK_delivery_earnings_processedBy"
    FOREIGN KEY ("processedById") REFERENCES "admin_accounts"("id") ON DELETE SET NULL`,
  `ALTER TABLE "independent_deliveries" ADD CONSTRAINT "FK_1e92d7467609e49f3879a2aa14f"
    FOREIGN KEY ("requesterId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE NO ACTION`,
  `ALTER TABLE "independent_deliveries" ADD CONSTRAINT "FK_b9bdc70a802db93ee7de69114cb"
    FOREIGN KEY ("agentId") REFERENCES "delivery_agent_profiles"("id") ON DELETE SET NULL ON UPDATE NO ACTION`,

  // ======================================================================
  // MESSAGERIE, NOTIFICATIONS ET SUPPORT
  // ======================================================================
  `ALTER TABLE "conversations" ADD CONSTRAINT "FK_2882c536d4eecfd496132b20eeb"
    FOREIGN KEY ("clientId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE NO ACTION`,
  `ALTER TABLE "conversations" ADD CONSTRAINT "FK_cba6cfb0ba3c5e3281d3832aa3b"
    FOREIGN KEY ("vendorId") REFERENCES "vendor_profiles"("id") ON DELETE CASCADE ON UPDATE NO ACTION`,
  `ALTER TABLE "conversations" ADD CONSTRAINT "FK_1fbaa33ad249de15b683ffcb110"
    FOREIGN KEY ("productId") REFERENCES "products"("id") ON DELETE SET NULL ON UPDATE NO ACTION`,
  `ALTER TABLE "messages" ADD CONSTRAINT "FK_e5663ce0c730b2de83445e2fd19"
    FOREIGN KEY ("conversationId") REFERENCES "conversations"("id") ON DELETE CASCADE ON UPDATE NO ACTION`,
  `ALTER TABLE "messages" ADD CONSTRAINT "FK_2db9cf2b3ca111742793f6c37ce"
    FOREIGN KEY ("senderId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE NO ACTION`,
  `ALTER TABLE "notifications" ADD CONSTRAINT "FK_692a909ee0fa9383e7859f9b406"
    FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE NO ACTION`,
  `ALTER TABLE "notifications" ADD CONSTRAINT "FK_4509d5b418f7eb05ac668d50564"
    FOREIGN KEY ("adminId") REFERENCES "admin_accounts"("id") ON DELETE CASCADE ON UPDATE NO ACTION`,
  `ALTER TABLE "support_tickets" ADD CONSTRAINT "FK_support_tickets_user"
    FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE`,
  `ALTER TABLE "support_tickets" ADD CONSTRAINT "FK_support_tickets_order"
    FOREIGN KEY ("orderId") REFERENCES "orders"("id") ON DELETE SET NULL`,
  `ALTER TABLE "support_tickets" ADD CONSTRAINT "FK_support_tickets_admin"
    FOREIGN KEY ("assignedAdminId") REFERENCES "admin_accounts"("id") ON DELETE SET NULL`,
  `ALTER TABLE "support_ticket_messages" ADD CONSTRAINT "FK_support_ticket_messages_ticket"
    FOREIGN KEY ("ticketId") REFERENCES "support_tickets"("id") ON DELETE CASCADE`,
];

// Tables à supprimer par down() (des plus récentes aux plus anciennes ;
// CASCADE règle de toute façon les dépendances).
const NOMS_DES_TABLES: string[] = [
  'support_ticket_messages',
  'support_tickets',
  'notifications',
  'messages',
  'conversations',
  'independent_deliveries',
  'delivery_earnings',
  'delivery_proofs',
  'deliveries',
  'delivery_agent_profiles',
  'delivery_zones',
  'commissions',
  'refunds',
  'payments',
  'order_items',
  'orders',
  'coupon_usages',
  'coupons',
  'cart_items',
  'carts',
  'vitrine_bandeau',
  'vitrine_rayon_produits',
  'vitrine_rayons',
  'reviews',
  'wishlists',
  'product_tier_prices',
  'product_tags',
  'product_variants',
  'product_images',
  'product_categories',
  'products',
  'categories',
  'fournisseurs',
  'partners',
  'vendor_withdrawals',
  'featured_shops',
  'shop_follows',
  'vendor_profiles',
  'activity_logs',
  'email_changes',
  'otp_codes',
  'admin_accounts',
  'addresses',
  'user_roles',
  'users',
];

const NOM_MIGRATION = 'BaselineSchema1700000000000';

export class BaselineSchema1700000000000 implements MigrationInterface {
  name = NOM_MIGRATION;

  public async up(queryRunner: QueryRunner): Promise<void> {
    // ── GARDE : base déjà installée ? ──────────────────────
    // `to_regclass` renvoie NULL si la table n'existe pas. Si `users`
    // existe, le schéma est déjà là (créé par un ancien synchronize ou par
    // une installation antérieure) : on ne touche à RIEN.
    const lignes: { present: boolean }[] = await queryRunner.query(
      `SELECT to_regclass('public.users') IS NOT NULL AS "present"`,
    );
    if (lignes[0]?.present) {
      queryRunner.connection.logger.logMigration(
        `${NOM_MIGRATION} : la table "users" existe déjà, le schéma est supposé installé - aucune modification.`,
      );
      return;
    }

    // ── Base vide : on construit le schéma complet ─────────
    for (const sql of EXTENSIONS) await queryRunner.query(sql);
    for (const sql of SEQUENCES) await queryRunner.query(sql);
    for (const sql of ENUMS) await this.ignorerSiExiste(queryRunner, sql);
    for (const sql of TABLES) await queryRunner.query(sql);
    for (const sql of APRES_TABLES) await queryRunner.query(sql);
    for (const sql of INDEXES) await queryRunner.query(sql);
    for (const sql of FOREIGN_KEYS) {
      await this.ignorerSiExiste(queryRunner, sql);
    }
  }

  /**
   * Annulation PRUDENTE de la base de départ.
   *
   * ⚠️ TypeORM annule « la dernière migration enregistrée ». Sur une base déjà
   * installée, la base de départ est enregistrée EN DERNIER (elle s'est
   * exécutée sans rien faire) : un `typeorm:revert` tomberait donc d'abord ici.
   *  1. Si d'autres migrations sont enregistrées : on ne fait RIEN (il n'y a
   *     rien de réel à annuler) ; relancer `typeorm:revert` annulera alors la
   *     vraie dernière migration.
   *  2. Si c'est la seule migration enregistrée : on REFUSE en production
   *     (NODE_ENV=production), et ailleurs on exige BASELINE_DOWN_CONFIRM=OUI,
   *     car cela supprime TOUTES les tables et leurs données.
   */
  public async down(queryRunner: QueryRunner): Promise<void> {
    // Nom de la table où TypeORM note les migrations déjà exécutées
    // (« typeorm_migrations » dans src/database/data-source.ts).
    const tableMigrations = (
      queryRunner.connection.options as { migrationsTableName?: string }
    ).migrationsTableName ?? 'migrations';
    const autres: { n: string }[] = await queryRunner.query(
      `SELECT count(*)::text AS "n" FROM "${tableMigrations}" WHERE "name" <> $1`,
      [NOM_MIGRATION],
    );
    if (Number(autres[0]?.n ?? '0') > 0) {
      queryRunner.connection.logger.logMigration(
        `${NOM_MIGRATION} : d'autres migrations sont enregistrées, rien à supprimer ici. Relancez la commande pour annuler la migration précédente.`,
      );
      return;
    }

    if (process.env.NODE_ENV === 'production') {
      throw new Error(
        `${NOM_MIGRATION}.down() refusé : NODE_ENV=production. Cette annulation supprimerait toutes les tables.`,
      );
    }
    if (process.env.BASELINE_DOWN_CONFIRM !== 'OUI') {
      throw new Error(
        `${NOM_MIGRATION}.down() supprimerait TOUTES les tables et leurs données. ` +
          `Si c'est bien voulu (base de test), relancez avec BASELINE_DOWN_CONFIRM=OUI.`,
      );
    }

    for (const table of NOMS_DES_TABLES) {
      await queryRunner.query(`DROP TABLE IF EXISTS "${table}" CASCADE`);
    }
    for (const sql of ENUMS) {
      const nom = /CREATE TYPE "public"\."(\w+)"/.exec(sql)?.[1];
      if (nom) await queryRunner.query(`DROP TYPE IF EXISTS "public"."${nom}"`);
    }
    await queryRunner.query(`DROP SEQUENCE IF EXISTS orders_number_seq`);
    // Les extensions (uuid-ossp, pg_trgm) ne sont pas retirées : d'autres bases
    // ou objets peuvent s'en servir.
  }

  /**
   * Exécute une instruction CREATE TYPE / ALTER TABLE … ADD CONSTRAINT en
   * ignorant l'erreur « existe déjà » (PostgreSQL n'a pas de IF NOT EXISTS
   * pour ces deux cas).
   */
  private async ignorerSiExiste(
    queryRunner: QueryRunner,
    sql: string,
  ): Promise<void> {
    await queryRunner.query(`
      DO $$ BEGIN
        ${sql};
      EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL;
      END $$;
    `);
  }
}
