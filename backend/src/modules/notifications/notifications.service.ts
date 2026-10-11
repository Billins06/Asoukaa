import {
  Injectable,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, In }   from 'typeorm';
import { MailService }      from '../mail/mail.service';
import { EmailCategory }    from '../mail/templates/base-layout.template';

import {
  Notification,
  NotificationType,
} from './entities/notification.entity';
import { User }         from '../users/entities/user.entity';
import { UserRole }     from '../users/entities/user-role.entity';
import { AdminAccount } from '../auth/entities/admin-account.entity';
import {
  NotificationPrefKey,
  NotificationPreferences,
  NOTIFICATION_PREF_KEYS,
  PREF_DEFAULTS,
  mergePrefs,
  profileForRoles,
} from './notification-preferences';

import {
  MarkNotificationsReadDto,
} from './dto/mark-read.dto';

// Interface pour créer une notification depuis un autre module
interface CreateNotificationParams {
  userId?:        string;
  adminId?:       string;
  title:          string;
  body:           string;
  type:           NotificationType;
  referenceId?:   string;
  referenceType?: string;
  sendEmail?:     boolean;
  // Préférence de l'utilisateur qui gouverne cette notification (voir
  // isAllowed). Si absente, la clé est déduite du TYPE quand il est sans
  // ambiguïté (chat → messages, paiement → payments) ; sinon la notification
  // est TOUJOURS envoyée.
  prefKey?:       NotificationPrefKey;
}

// ─────────────────────────────────────────────────────
// TABLE DE CORRESPONDANCE type de notification → préférence
// ─────────────────────────────────────────────────────
// Seuls les types SANS AMBIGUÏTÉ sont mappés ici. Les types ORDER et
// DELIVERY servent à la fois l'acheteur, le vendeur et le livreur : leur clé
// est donnée explicitement (prefKey) par les helpers notify*() ci-dessous.
//   CHAT     → messages
//   PAYMENT  → payments
// RÈGLE ABSOLUE : tout type absent de cette table (ORDER, DELIVERY, REVIEW,
// STOCK, VALIDATION, SYSTEM, et tout type ajouté plus tard : tickets
// d'assistance, commande en retard, sécurité, compte bloqué, alertes
// admin...) est TOUJOURS envoyé, sauf si l'appelant passe un prefKey.
const PREF_KEY_BY_TYPE: Partial<Record<NotificationType, NotificationPrefKey>> = {
  [NotificationType.CHAT]:    'messages',
  [NotificationType.PAYMENT]: 'payments',
};

@Injectable()
export class NotificationsService {

  constructor(
    @InjectRepository(Notification)
    private readonly notificationRepo: Repository<Notification>,

    @InjectRepository(User)
    private readonly userRepo: Repository<User>,

    @InjectRepository(AdminAccount)
    private readonly adminRepo: Repository<AdminAccount>,

    @InjectRepository(UserRole)
    private readonly userRoleRepo: Repository<UserRole>,

    private readonly mailService: MailService,
  ) {}

  // ─────────────────────────────────────────────────────
  // CRÉER UNE NOTIFICATION (méthode publique pour les autres modules)
  // ─────────────────────────────────────────────────────
  // Renvoie null (rien créé, aucun e-mail) quand le destinataire a désactivé
  // la préférence correspondante : voir isAllowed().
  async create(params: CreateNotificationParams): Promise<Notification | null> {

    // ⚠️ Au moins un destinataire requis
    if (!params.userId && !params.adminId) {
      throw new BadRequestException(
        'Une notification doit avoir un destinataire (user ou admin)'
      );
    }

    // 🔕 Point CENTRAL d'application des préférences : si l'utilisateur a
    // coupé cette catégorie, on ne crée ni la notification ni l'e-mail lié.
    // (Les notifications d'admin ne sont jamais filtrées.)
    if (
      params.userId
      && !(await this.isAllowed(params.userId, params.type, params.prefKey))
    ) {
      return null;
    }

    const notification              = this.notificationRepo.create();
    notification.userId             = params.userId        ?? null;
    notification.adminId            = params.adminId       ?? null;
    notification.title              = params.title;
    notification.body               = params.body;
    notification.type               = params.type;
    notification.referenceId        = params.referenceId   ?? null;
    notification.referenceType      = params.referenceType ?? null;
    notification.isRead             = false;

    await this.notificationRepo.save(notification);

    // Envoyer par email si demandé
    if (params.sendEmail) {
      await this.sendEmailNotification(notification);
    }

    return notification;
  }

  // ─────────────────────────────────────────────────────
  // PRÉFÉRENCES DE NOTIFICATION
  // ─────────────────────────────────────────────────────

  /**
   * Cette notification doit-elle être envoyée à cet utilisateur ?
   *
   * À utiliser avant TOUT envoi lié à une préférence (notification in-app,
   * e-mail de suivi ou promotionnel envoyé hors de create()).
   *
   *  - `prefKey` explicite, sinon clé déduite du type (CHAT → messages,
   *    PAYMENT → payments). Sans clé : renvoie TOUJOURS true (sécurité,
   *    changement d'e-mail, compte bloqué, support, alertes admin, types
   *    futurs...). Ne jamais « mapper » un type de sécurité.
   *  - Valeur enregistrée par l'utilisateur si elle existe, sinon la valeur
   *    par défaut de son profil (voir notification-preferences.ts).
   *  - En cas d'erreur (base indisponible...), renvoie true : on préfère
   *    notifier à tort que rater une notification.
   */
  async isAllowed(
    userId:   string,
    type:     NotificationType,
    prefKey?: NotificationPrefKey,
  ): Promise<boolean> {
    const key = prefKey ?? PREF_KEY_BY_TYPE[type];
    if (!key) return true;

    try {
      const stored = await this.loadStoredPrefs(userId);
      if (stored === undefined) return true; // destinataire inconnu
      const value = stored?.[key];
      if (typeof value === 'boolean') return value;

      // Clé jamais réglée : valeur par défaut du profil. Les rôles ne sont
      // lus que si le défaut peut différer (messages / promotions).
      if (PREF_DEFAULTS.client[key] === PREF_DEFAULTS.pro[key]) {
        return PREF_DEFAULTS.client[key];
      }
      return mergePrefs(null, await this.profileOf(userId))[key];
    } catch (error) {
      console.error('Erreur lecture préférences notification:', error?.message);
      return true;
    }
  }

  // Préférences complètes (toutes les clés) fusionnées avec les défauts.
  async getPreferences(userId: string): Promise<NotificationPreferences> {
    const stored = await this.loadStoredPrefs(userId);
    if (stored === undefined) {
      throw new NotFoundException('Utilisateur introuvable');
    }
    return mergePrefs(stored, await this.profileOf(userId));
  }

  // Met à jour seulement les clés booléennes reçues (corps partiel déjà
  // validé par le DTO) et renvoie les préférences complètes.
  async updatePreferences(
    userId: string,
    patch:  Partial<NotificationPreferences>,
  ): Promise<NotificationPreferences> {
    const clean: Record<string, boolean> = {};
    for (const key of NOTIFICATION_PREF_KEYS) {
      if (typeof patch?.[key] === 'boolean') clean[key] = patch[key] as boolean;
    }

    // Fusion jsonb côté base : deux PUT simultanés sur des clés différentes
    // ne s'écrasent pas.
    const rows = await this.userRepo.query(
      `UPDATE "users"
          SET "notificationPrefs" = COALESCE("notificationPrefs", '{}'::jsonb) || $2::jsonb
        WHERE "id" = $1
        RETURNING "id"`,
      [userId, JSON.stringify(clean)],
    );
    // pg renvoie [lignes, nombre] pour UPDATE ... RETURNING
    const affected = Array.isArray(rows?.[0]) ? rows[0] : rows;
    if (!affected?.length) {
      throw new NotFoundException('Utilisateur introuvable');
    }

    return this.getPreferences(userId);
  }

  // undefined = utilisateur introuvable ; {} = rien de réglé.
  private async loadStoredPrefs(
    userId: string,
  ): Promise<Record<string, unknown> | undefined> {
    const row = await this.userRepo
      .createQueryBuilder('u')
      .select('u.id', 'id')
      .addSelect('u.notificationPrefs', 'prefs')
      .where('u.id = :userId', { userId })
      .getRawOne();
    if (!row) return undefined;
    const prefs = row.prefs;
    return prefs && typeof prefs === 'object' && !Array.isArray(prefs) ? prefs : {};
  }

  private async profileOf(userId: string) {
    const roles = await this.userRoleRepo.find({
      where:  { userId, isActive: true },
      select: { role: true },
    });
    return profileForRoles(roles.map((r) => r.role));
  }

  // ─────────────────────────────────────────────────────
  // MES NOTIFICATIONS (utilisateur connecté)
  // ─────────────────────────────────────────────────────
  async getMyNotifications(
    userId:   string,
    onlyUnread: boolean = false,
    page:     number = 1,
    limit:    number = 20,
  ) {
    const where: any = { userId };
    if (onlyUnread) where.isRead = false;

    const [notifications, total] = await this.notificationRepo.findAndCount({
      where,
      order: { createdAt: 'DESC' },
      skip:  (page - 1) * limit,
      take:  limit,
    });

    return {
      data:  notifications,
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
    };
  }

  // ─────────────────────────────────────────────────────
  // COMPTER LES NON LUES
  // ─────────────────────────────────────────────────────
  async countUnread(userId: string) {
    const count = await this.notificationRepo.count({
      where: { userId, isRead: false },
    });

    return { unreadCount: count };
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — MES NOTIFICATIONS
  // ─────────────────────────────────────────────────────
  async getAdminNotifications(
    adminId:   string,
    onlyUnread: boolean = false,
    page:     number = 1,
    limit:    number = 20,
  ) {
    const where: any = { adminId };
    if (onlyUnread) where.isRead = false;

    const [notifications, total] = await this.notificationRepo.findAndCount({
      where,
      order: { createdAt: 'DESC' },
      skip:  (page - 1) * limit,
      take:  limit,
    });

    return {
      data:  notifications,
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
    };
  }

  // ─────────────────────────────────────────────────────
  // MARQUER COMME LU
  // ─────────────────────────────────────────────────────
  async markAsRead(
    userId: string,
    dto:    MarkNotificationsReadDto,
  ) {
    // Vérifier que toutes les notifications appartiennent à cet user
    const notifications = await this.notificationRepo.find({
      where: { id: In(dto.ids), userId },
    });

    if (notifications.length !== dto.ids.length) {
      throw new BadRequestException(
        'Certaines notifications n\'existent pas ou ne vous appartiennent pas'
      );
    }

    // Mettre à jour en masse
    await this.notificationRepo.update(
      { id: In(dto.ids), userId },
      { isRead: true },
    );

    return { message: `${dto.ids.length} notification(s) marquée(s) comme lue(s)` };
  }

  // ─────────────────────────────────────────────────────
  // MARQUER TOUTES COMME LUES
  // ─────────────────────────────────────────────────────
  async markAllAsRead(userId: string) {
    const result = await this.notificationRepo.update(
      { userId, isRead: false },
      { isRead: true },
    );

    return {
      message: 'Toutes les notifications ont été marquées comme lues',
      count:   result.affected ?? 0,
    };
  }

  // ─────────────────────────────────────────────────────
  // SUPPRIMER UNE NOTIFICATION
  // ─────────────────────────────────────────────────────
  async remove(userId: string, notificationId: string) {
    const notification = await this.notificationRepo.findOne({
      where: { id: notificationId, userId },
    });

    if (!notification) {
      throw new NotFoundException('Notification introuvable');
    }

    await this.notificationRepo.remove(notification);

    return { message: 'Notification supprimée' };
  }

  // ─────────────────────────────────────────────────────
  // SUPPRIMER TOUTES LES NOTIFICATIONS LUES
  // ─────────────────────────────────────────────────────
  async removeAllRead(userId: string) {
    const result = await this.notificationRepo.delete({
      userId,
      isRead: true,
    });

    return {
      message: 'Notifications lues supprimées',
      count:   result.affected ?? 0,
    };
  }

  // ─────────────────────────────────────────────────────
  // ENVOI EMAIL (méthode privée)
  // ─────────────────────────────────────────────────────
  private async sendEmailNotification(notification: Notification): Promise<void> {
    try {
      let email: string | null = null;
      let prenom: string = '';

      // Récupérer l'email du destinataire
      if (notification.userId) {
        const user = await this.userRepo.findOne({
          where: { id: notification.userId },
        });
        if (user) {
          email  = user.email;
          prenom = user.prenom;
        }
      } else if (notification.adminId) {
        const admin = await this.adminRepo.findOne({
          where: { id: notification.adminId },
        });
        if (admin) {
          email  = admin.email;
          prenom = admin.prenom;
        }
      }

      if (!email) return;

      await this.mailService.sendNotification(email, {
        prenom,
        title:    notification.title,
        message:  notification.body,
        category: this.emailCategoryFor(notification),
        cta:      this.emailCtaFor(notification),
      });

    } catch (error) {
      // ⚠️ Ne JAMAIS bloquer l'app si l'email échoue
      console.error('Erreur envoi email notification:', error.message);
    }
  }

  // Couleur/badge de l'email selon le type de notification.
  private emailCategoryFor(notification: Notification): EmailCategory {
    switch (notification.type) {
      case NotificationType.ORDER:
      case NotificationType.PAYMENT:
        return 'commande';
      case NotificationType.DELIVERY:
        return 'livreur';
      case NotificationType.STOCK:
        return 'vendeur';
      case NotificationType.VALIDATION:
        if (notification.referenceType === 'vendor_profile')         return 'vendeur';
        if (notification.referenceType === 'delivery_agent_profile') return 'livreur';
        return 'compte';
      default:
        return 'compte';
    }
  }

  // Bouton de l'email : uniquement des liens asoukaa:// dont l'hôte est
  // géré par l'app (product, shop, order, delivery, vendor-dashboard).
  // 'order' est volontairement omis : le destinataire peut être le client
  // OU le vendeur, et asoukaa://order ouvre le suivi côté client.
  private emailCtaFor(notification: Notification): { label: string; href: string } | undefined {
    // Les admins utilisent le dashboard web, pas l'app : pas de lien profond.
    if (notification.adminId) return undefined;
    switch (notification.referenceType) {
      case 'delivery':
        return { label: 'Voir mes livraisons', href: 'asoukaa://delivery' };
      case 'vendor_profile':
        return { label: 'Accéder à mon tableau de bord', href: 'asoukaa://vendor-dashboard' };
      default:
        return undefined;
    }
  }

  // ─────────────────────────────────────────────────────
  // HELPERS PUBLICS POUR LES AUTRES MODULES
  // (créent des notifications typées rapidement)
  // ─────────────────────────────────────────────────────

  async notifyOrderConfirmed(userId: string, orderNumber: string, orderId: string) {
    return this.create({
      userId,
      title:         '✅ Commande confirmée',
      body:          `Votre commande ${orderNumber} a été confirmée.`,
      prefKey:       'orders',
      type:          NotificationType.ORDER,
      referenceId:   orderId,
      referenceType: 'order',
      sendEmail:     true,
    });
  }

  async notifyNewOrder(vendorUserId: string, orderNumber: string, orderId: string) {
    return this.create({
      userId:        vendorUserId,
      title:         '🛒 Nouvelle commande !',
      body:          `Vous avez reçu une nouvelle commande : ${orderNumber}.`,
      prefKey:       'newOrders',
      type:          NotificationType.ORDER,
      referenceId:   orderId,
      referenceType: 'order',
      sendEmail:     true,
    });
  }

  async notifyLowStock(vendorUserId: string, productName: string, variantId: string, stock: number) {
    return this.create({
      userId:        vendorUserId,
      title:         '⚠️ Stock faible',
      body:          `Le stock de "${productName}" est tombé à ${stock} unité(s).`,
      type:          NotificationType.STOCK,
      referenceId:   variantId,
      referenceType: 'product_variant',
      sendEmail:     false,
    });
  }

  async notifyVendorApproved(userId: string, vendorId: string) {
    return this.create({
      userId,
      title:         '🎉 Boutique validée !',
      body:          'Votre demande de boutique a été approuvée. Vous pouvez maintenant commencer à vendre.',
      type:          NotificationType.VALIDATION,
      referenceId:   vendorId,
      referenceType: 'vendor_profile',
      sendEmail:     true,
    });
  }

  async notifyDeliveryAssigned(agentUserId: string, deliveryId: string) {
    return this.create({
      userId:        agentUserId,
      title:         '📦 Nouvelle livraison',
      body:          'Une nouvelle livraison vous a été affectée.',
      // Pas de prefKey : une livraison AFFECTÉE est transactionnelle (le
      // livreur doit la voir), contrairement aux courses simplement proposées.
      type:          NotificationType.DELIVERY,
      referenceId:   deliveryId,
      referenceType: 'delivery',
      sendEmail:     true,
    });
  }

  // Le vendeur a démarré la livraison (startTransit) : le livreur n'est pas
  // l'auteur de cette action, il doit donc être prévenu dans l'app.
  // Pas d'email : le livreur est en mouvement, la notification in-app suffit.
  async notifyDeliveryStarted(agentUserId: string, deliveryId: string) {
    return this.create({
      userId:        agentUserId,
      title:         '🚚 Livraison démarrée',
      body:          'Le vendeur a démarré la livraison : vous pouvez partir chez le client.',
      type:          NotificationType.DELIVERY,
      referenceId:   deliveryId,
      referenceType: 'delivery',
      sendEmail:     false,
    });
  }

  // La commande que ce livreur devait livrer a été annulée : il doit arrêter
  // sa course immédiatement, donc email en plus de la notification in-app.
  async notifyDeliveryCancelled(
    agentUserId: string,
    deliveryId:  string,
    orderNumber: string,
  ) {
    return this.create({
      userId:        agentUserId,
      title:         '❌ Livraison annulée',
      body:          `La commande ${orderNumber} a été annulée : cette livraison n'est plus à effectuer.`,
      type:          NotificationType.DELIVERY,
      referenceId:   deliveryId,
      referenceType: 'delivery',
      sendEmail:     true,
    });
  }

  // Nouvelle course express (livraison indépendante, Type B) ouverte aux
  // livreurs disponibles. Pas d'email : plusieurs livreurs sont notifiés
  // pour une seule course, un email à chacun serait du spam.
  async notifyNewIndependentDelivery(agentUserId: string, deliveryId: string) {
    return this.create({
      userId:        agentUserId,
      title:         '⚡ Nouvelle course express',
      body:          'Une nouvelle demande de livraison est disponible.',
      prefKey:       'newDeliveries',
      type:          NotificationType.DELIVERY,
      referenceId:   deliveryId,
      referenceType: 'independent_delivery',
      sendEmail:     false,
    });
  }

  async notifyNewMessage(receiverId: string, senderName: string, conversationId: string) {
    return this.create({
      userId:        receiverId,
      title:         `💬 Nouveau message de ${senderName}`,
      body:          'Vous avez reçu un nouveau message.',
      prefKey:       'messages',
      type:          NotificationType.CHAT,
      referenceId:   conversationId,
      referenceType: 'conversation',
      sendEmail:     false,
    });
  }
}