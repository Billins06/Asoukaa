import {
  Injectable,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, In }   from 'typeorm';
import { MailerService }    from '@nestjs-modules/mailer';

import {
  Notification,
  NotificationType,
} from './entities/notification.entity';
import { User }         from '../users/entities/user.entity';
import { AdminAccount } from '../auth/entities/admin-account.entity';

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
}

@Injectable()
export class NotificationsService {

  constructor(
    @InjectRepository(Notification)
    private readonly notificationRepo: Repository<Notification>,

    @InjectRepository(User)
    private readonly userRepo: Repository<User>,

    @InjectRepository(AdminAccount)
    private readonly adminRepo: Repository<AdminAccount>,

    private readonly mailerService: MailerService,
  ) {}

  // ─────────────────────────────────────────────────────
  // CRÉER UNE NOTIFICATION (méthode publique pour les autres modules)
  // ─────────────────────────────────────────────────────
  async create(params: CreateNotificationParams): Promise<Notification> {

    // ⚠️ Au moins un destinataire requis
    if (!params.userId && !params.adminId) {
      throw new BadRequestException(
        'Une notification doit avoir un destinataire (user ou admin)'
      );
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

      await this.mailerService.sendMail({
        to:      email,
        subject: notification.title,
        html: `
          <p>Bonjour ${prenom},</p>
          <p>${notification.body}</p>
          <p>Connectez-vous à votre compte pour plus de détails.</p>
          <hr/>
          <p style="color:#888;font-size:12px;">
            Vous recevez cet email car vous êtes inscrit(e) sur Asoukaa.
          </p>
        `,
      });

    } catch (error) {
      // ⚠️ Ne JAMAIS bloquer l'app si l'email échoue
      console.error('Erreur envoi email notification:', error.message);
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
      type:          NotificationType.DELIVERY,
      referenceId:   deliveryId,
      referenceType: 'delivery',
      sendEmail:     true,
    });
  }

  async notifyNewMessage(receiverId: string, senderName: string, conversationId: string) {
    return this.create({
      userId:        receiverId,
      title:         `💬 Nouveau message de ${senderName}`,
      body:          'Vous avez reçu un nouveau message.',
      type:          NotificationType.CHAT,
      referenceId:   conversationId,
      referenceType: 'conversation',
      sendEmail:     false,
    });
  }
}