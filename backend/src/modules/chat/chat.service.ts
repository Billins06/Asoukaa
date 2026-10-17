import { toPublicVendor } from '../products/public-vendor.util';
import { toPresence }      from '../presence/presence.util';
import {
  Injectable,
  NotFoundException,
  ForbiddenException,
  BadRequestException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, Not }  from 'typeorm';

import { Conversation } from './entities/conversation.entity';
import { Message }      from './entities/message.entity';
import { User }         from '../users/entities/user.entity';
import { VendorProfile, VendorStatus } from '../users/entities/vendor-profile.entity';
import { Product }      from '../products/entities/product.entity';

import { CreateConversationDto } from './dto/create-conversation.dto';
import { SendMessageDto }        from './dto/send-message.dto';
import { NotificationsService }  from '../notifications/notifications.service';
import { UploadService, UploadType } from '../upload/upload.service';

@Injectable()
export class ChatService {

  constructor(
    @InjectRepository(Conversation)
    private readonly conversationRepo: Repository<Conversation>,

    @InjectRepository(Message)
    private readonly messageRepo: Repository<Message>,

    @InjectRepository(VendorProfile)
    private readonly vendorRepo: Repository<VendorProfile>,

    @InjectRepository(Product)
    private readonly productRepo: Repository<Product>,

    private readonly notificationsService: NotificationsService,

    private readonly uploadService: UploadService,
  ) {}

  // ─────────────────────────────────────────────────────
  // INDICATEUR "EN TRAIN D'ÉCRIRE" (en mémoire, pas en base :
  // c'est une information éphémère, pas la peine de la persister
  // ni de la répliquer entre plusieurs instances du serveur)
  // ─────────────────────────────────────────────────────
  private readonly typingState = new Map<
    string,
    { userId: string; expiresAt: number }
  >();
  private static readonly TYPING_TTL_MS = 7000; // > l'intervalle de polling (5s) côté client

  async setTyping(userId: string, conversationId: string): Promise<void> {
    const conversation = await this.conversationRepo.findOne({
      where:     { id: conversationId },
      relations: ['vendor'],
    });
    if (!conversation) throw new NotFoundException('Conversation introuvable');

    const isClient = conversation.clientId === userId;
    const isVendor = conversation.vendor.userId === userId;
    if (!isClient && !isVendor) {
      throw new ForbiddenException('Accès refusé');
    }

    this.typingState.set(conversationId, {
      userId,
      expiresAt: Date.now() + ChatService.TYPING_TTL_MS,
    });
  }

  private isOtherParticipantTyping(userId: string, conversationId: string): boolean {
    const entry = this.typingState.get(conversationId);
    if (!entry) return false;
    return entry.userId !== userId && entry.expiresAt > Date.now();
  }

  // ─────────────────────────────────────────────────────
  // PRÉSENCE DE L'AUTRE PARTICIPANT (« En ligne / Vu à … »)
  // ─────────────────────────────────────────────────────
  // { id, lastSeenAt, isOnline } : UNIQUEMENT l'identifiant et les deux
  // champs de présence, aucune autre donnée du compte. isOnline est calculé
  // ici (dernière activité de moins de 2 minutes), voir presence.util.ts.
  private async loadOtherUser(otherUserId: string) {
    const other = await this.conversationRepo.manager.findOne(User, {
      where:  { id: otherUserId },
      select: { id: true, lastSeenAt: true },
    });
    return other
      ? { id: other.id, ...toPresence(other.lastSeenAt) }
      : null;
  }

  // ─────────────────────────────────────────────────────
  // CRÉER UNE CONVERSATION
  // ─────────────────────────────────────────────────────
  async createConversation(
    clientId: string,
    dto:      CreateConversationDto,
  ) {
    // Vérifier que le vendeur existe
    const vendor = await this.vendorRepo.findOne({
      where: { id: dto.vendorId },
    });

    if (!vendor) throw new NotFoundException('Boutique introuvable');

    // ⚠️ Un vendeur ne peut pas discuter avec lui-même
    if (vendor.userId === clientId) {
      throw new BadRequestException(
        'Vous ne pouvez pas discuter avec votre propre boutique'
      );
    }

    // Vérifier le produit si fourni
    if (dto.productId) {
      const product = await this.productRepo.findOne({
        where: { id: dto.productId },
      });
      if (!product) throw new NotFoundException('Produit introuvable');
    }

    // Vérifier si une conversation existe déjà
    // (unique sur clientId + vendorId : une seule discussion par boutique,
    // quel que soit le nombre de produits évoqués — comme sur WhatsApp
    // avec un contact. Le produit n'est qu'une référence affichée dans
    // la discussion, pas une clé de dédoublonnage.)
    const existing = await this.conversationRepo.findOne({
      where: {
        clientId,
        vendorId: dto.vendorId,
      },
    });

    if (existing) {
      // Si un nouveau produit est évoqué, on met à jour la référence
      // affichée pour refléter le dernier produit discuté.
      if (dto.productId && existing.productId !== dto.productId) {
        existing.productId = dto.productId;
        await this.conversationRepo.save(existing);
      }
      // Conversation existante + présence du vendeur (otherUser).
      return { ...existing, otherUser: await this.loadOtherUser(vendor.userId) };
    }

    // Une NOUVELLE conversation ne peut être ouverte qu'avec une boutique
    // approuvée (pas en attente, refusée ou bloquée). Une conversation déjà
    // existante reste consultable (renvoyée ci-dessus).
    if (vendor.status !== VendorStatus.APPROVED) {
      throw new ForbiddenException(
        'Cette boutique n\'est pas disponible pour le moment.'
      );
    }

    // Boutique masquée par son vendeur : pas de NOUVELLE conversation
    // (le propriétaire est déjà exclu plus haut ; une conversation existante
    // reste consultable, voir le retour anticipé ci-dessus).
    if (vendor.shopVisible === false) {
      throw new ForbiddenException('Cette boutique est momentanément indisponible');
    }

    // Créer la conversation
    const conversation             = this.conversationRepo.create();
    conversation.clientId          = clientId;
    conversation.vendorId          = dto.vendorId;
    conversation.productId         = dto.productId ?? null;
    conversation.isArchived        = false;

    const created = await this.conversationRepo.save(conversation);
    return { ...created, otherUser: await this.loadOtherUser(vendor.userId) };
  }

  // ─────────────────────────────────────────────────────
  // ENVOYER UN MESSAGE
  // ─────────────────────────────────────────────────────
  async sendMessage(
    senderId:       string,
    conversationId: string,
    dto:            SendMessageDto,
  ) {
    // 1. Vérifier que la conversation existe
    const conversation = await this.conversationRepo.findOne({
      where:     { id: conversationId },
      relations: ['vendor', 'client'],
    });

    if (!conversation) throw new NotFoundException('Conversation introuvable');

    // 2. Vérifier que l'expéditeur est bien un participant
    // (soit le client, soit l'utilisateur lié au vendeur)
    const isClient = conversation.clientId === senderId;
    const isVendor = conversation.vendor.userId === senderId;

    if (!isClient && !isVendor) {
      throw new ForbiddenException(
        'Vous n\'êtes pas autorisé à envoyer un message dans cette conversation'
      );
    }

    // 3. Vérifier qu'au moins content OU imageUrl est fourni
    if (!dto.content && !dto.imageUrl) {
      throw new BadRequestException(
        'Le message doit contenir du texte ou une image'
      );
    }

    // 3 bis. L'image d'un message doit provenir de NOTRE stockage de chat
    // (POST /upload/chat). Sans ce contrôle, n'importe quelle URL externe
    // (pixel espion, contenu malveillant) s'afficherait dans l'appli de
    // l'autre participant. Échec → 400, avant toute écriture en base.
    if (dto.imageUrl) {
      this.uploadService.assertIsOwnUploadUrl(dto.imageUrl, UploadType.CHAT);
    }

    // 4. Appliquer le filtrage anti-contournement
    let isBlocked   = false;
    let blockReason: string | null = null;

    if (dto.content) {
      const filter = this.detectBlockedContent(dto.content);
      if (filter.blocked) {
        isBlocked   = true;
        blockReason = filter.reason;
      }
    }

    // 5. Créer le message
    const message              = this.messageRepo.create();
    message.conversationId     = conversationId;
    message.senderId           = senderId;
    message.content            = dto.content  ?? null;
    message.imageUrl           = dto.imageUrl ?? null;
    message.isBlocked          = isBlocked;
    message.blockReason        = blockReason;
    message.isReported         = false;
    message.isRead             = false;

    await this.messageRepo.save(message);

    // 6. Mettre à jour updatedAt de la conversation
    // pour pouvoir trier par activité récente
    conversation.updatedAt = new Date();
    await this.conversationRepo.save(conversation);

    // 7. Si message bloqué → informer l'expéditeur sans révéler trop
    if (isBlocked) {
      return {
        message: 'Votre message contient des informations interdites '
               + 'et n\'a pas été envoyé.',
        warning: 'Toute tentative de contournement de la plateforme '
               + 'peut entraîner la suspension de votre compte.',
        blocked: true,
      };
    }

    // 8. Notifier l'autre participant (best-effort : ne doit jamais faire
    // échouer l'envoi du message si la notification plante)
    try {
      const receiverId  = isClient ? conversation.vendor.userId : conversation.clientId;
      const senderName  = isClient
        ? conversation.client.prenom
        : conversation.vendor.shopName;
      await this.notificationsService.notifyNewMessage(
        receiverId,
        senderName,
        conversationId,
      );
    } catch (error) {
      console.error('Erreur notification nouveau message:', error.message);
    }

    return {
      message: 'Message envoyé',
      data:    message,
    };
  }

  // ─────────────────────────────────────────────────────
  // MES CONVERSATIONS
  // ─────────────────────────────────────────────────────
  async getMyConversations(userId: string, page = 1, limit = 20) {
    // L'utilisateur peut être client OU vendeur dans une conversation
    const vendor = await this.vendorRepo.findOne({
      where: { userId },
    });

    const query = this.conversationRepo
      .createQueryBuilder('conv')
      .leftJoinAndSelect('conv.client',  'client')
      .leftJoinAndSelect('conv.vendor',  'vendor')
      .leftJoinAndSelect('vendor.user',  'vendorUser')
      .leftJoinAndSelect('conv.product', 'product')
      .where('conv.clientId = :userId', { userId });

    if (vendor) {
      query.orWhere('conv.vendorId = :vendorId', { vendorId: vendor.id });
    }

    query
      .orderBy('conv.updatedAt', 'DESC')
      .skip((page - 1) * limit)
      .take(limit);

    const [conversations, total] = await query.getManyAndCount();

    // Masquer les données sensibles
    const safe = conversations.map(c => {
      // Présence de l'AUTRE participant : le vendeur si je suis le client,
      // sinon le client. { id, lastSeenAt, isOnline } uniquement — calculé
      // avant que client / vendor soient réduits à leur liste blanche.
      const otherSrc: any = c.clientId === userId ? c.vendor?.user : c.client;
      (c as any).otherUser = otherSrc
        ? { id: otherSrc.id, ...toPresence(otherSrc.lastSeenAt) }
        : null;

      // Liste blanche : l'autre participant n'a besoin que de l'identité
      // affichable (jamais e-mail, téléphone, hash, champs de sécurité...).
      if (c.client) {
        const cl = c.client as any;
        (c as any).client = {
          id:        cl.id,
          prenom:    cl.prenom,
          name:      cl.name,
          avatarUrl: cl.avatarUrl,
        };
      }
      // Fiche publique de la boutique uniquement (ni documents, ni
      // paiement, ni e-mail/téléphone du compte vendeur).
      if (c.vendor) {
        (c as any).vendor = toPublicVendor(c.vendor);
      }
      return c;
    });

    // Enrichir chaque conversation avec un aperçu du dernier message
    // et le nombre de messages non lus (envoyés par l'AUTRE participant)
    // — indispensable pour afficher une liste de conversations utile
    // (aperçu + badge non-lus) dans l'écran "Messages".
    const withPreview = await Promise.all(
      safe.map(async (c) => {
        // Un message bloqué par le filtre anti-contournement n'est visible
        // que par son expéditeur : jamais en aperçu ni en non-lu chez
        // le destinataire.
        const lastMessage = await this.messageRepo.findOne({
          where:  [
            { conversationId: c.id, isBlocked: false },
            { conversationId: c.id, senderId: userId },
          ],
          order:  { createdAt: 'DESC' },
        });

        const unreadCount = await this.messageRepo.count({
          where: {
            conversationId: c.id,
            isRead:         false,
            isBlocked:      false,
            senderId:       Not(userId),
          },
        });

        return {
          ...c,
          lastMessage: lastMessage
            ? {
                content:   lastMessage.content,
                imageUrl:  lastMessage.imageUrl,
                createdAt: lastMessage.createdAt,
                senderId:  lastMessage.senderId,
              }
            : null,
          unreadCount,
        };
      }),
    );

    return {
      data:  withPreview,
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
    };
  }

  // ─────────────────────────────────────────────────────
  // COMPTEUR DE DISCUSSIONS NON LUES (badge de l'onglet "Messages")
  // Une seule requête agrégée : pas de boucle par conversation.
  // Même définition de "non lu" que getMyConversations : messages
  // isRead = false envoyés par l'AUTRE participant, dans les
  // conversations où l'utilisateur est client OU vendeur.
  // ─────────────────────────────────────────────────────
  async getUnreadCount(userId: string): Promise<{ conversations: number; messages: number }> {
    const qb = this.messageRepo.createQueryBuilder('m');
    const vendorIds = qb
      .subQuery()
      .select('v.id')
      .from(VendorProfile, 'v')
      .where('v.userId = :userId')
      .getQuery();

    const row = await qb
      .select('COUNT(DISTINCT "m"."conversationId")', 'conversations')
      .addSelect('COUNT("m"."id")', 'messages')
      .innerJoin('m.conversation', 'c')
      .where('m.isRead = false')
      .andWhere('m.senderId != :userId')
      .andWhere('m.isBlocked = false')
      .andWhere(`(c.clientId = :userId OR c.vendorId IN ${vendorIds})`)
      .setParameter('userId', userId)
      .getRawOne();

    return {
      conversations: parseInt(row?.conversations ?? '0', 10) || 0,
      messages:      parseInt(row?.messages ?? '0', 10) || 0,
    };
  }

  // ─────────────────────────────────────────────────────
  // MESSAGES D'UNE CONVERSATION
  // ─────────────────────────────────────────────────────
  async getMessages(
    userId:         string,
    conversationId: string,
    page:           number = 1,
    limit:          number = 50,
  ) {
    // Vérifier l'accès à la conversation
    const conversation = await this.conversationRepo.findOne({
      where:     { id: conversationId },
      relations: ['vendor'],
    });

    if (!conversation) throw new NotFoundException('Conversation introuvable');

    const isClient = conversation.clientId === userId;
    const isVendor = conversation.vendor.userId === userId;

    if (!isClient && !isVendor) {
      throw new ForbiddenException('Accès refusé');
    }

    // Les messages bloqués par le filtre anti-contournement ne sont
    // visibles que par leur expéditeur (il voit ce qu'il a tenté d'envoyer) :
    // le destinataire ne les reçoit jamais.
    const [messages, total] = await this.messageRepo.findAndCount({
      where: [
        { conversationId, isBlocked: false },
        { conversationId, senderId: userId },
      ],
      order: { createdAt: 'DESC' },
      skip:  (page - 1) * limit,
      take:  limit,
    });

    // Marquer les messages non lus comme lus
    // (uniquement ceux envoyés par l'autre participant :
    //  le filtre senderId: Not(userId) est indispensable ici,
    //  sinon mes propres messages non lus par le destinataire
    //  se retrouvent marqués "lus" dès que je recharge moi-même
    //  la conversation)
    await this.messageRepo.update(
      {
        conversationId,
        isRead:   false,
        senderId: Not(userId),
      },
      { isRead: true },
    );

    return {
      data:  messages.reverse(), // Les plus anciens en premier pour l'affichage
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
      otherIsTyping: this.isOtherParticipantTyping(userId, conversationId),
      // Présence de l'autre participant : { id, lastSeenAt, isOnline }.
      otherUser: await this.loadOtherUser(
        isClient ? conversation.vendor.userId : conversation.clientId,
      ),
    };
  }

  // ─────────────────────────────────────────────────────
  // SIGNALER UN MESSAGE
  // ─────────────────────────────────────────────────────
  async reportMessage(
    userId:    string,
    messageId: string,
  ) {
    const message = await this.messageRepo.findOne({
      where:     { id: messageId },
      relations: ['conversation', 'conversation.vendor'],
    });

    if (!message) throw new NotFoundException('Message introuvable');

    // Vérifier que l'utilisateur participe à la conversation
    const isClient = message.conversation.clientId === userId;
    const isVendor = message.conversation.vendor.userId === userId;

    if (!isClient && !isVendor) {
      throw new ForbiddenException('Accès refusé');
    }

    // On ne peut pas signaler son propre message
    if (message.senderId === userId) {
      throw new BadRequestException(
        'Vous ne pouvez pas signaler votre propre message'
      );
    }

    message.isReported = true;
    await this.messageRepo.save(message);

    return {
      message: 'Message signalé. L\'équipe Asoukaa va l\'examiner.',
    };
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — CONVERSATIONS AVEC MESSAGES SIGNALÉS
  // ─────────────────────────────────────────────────────
  async getReportedConversations(page = 1, limit = 20) {
    // Trouver les conversations qui ont au moins un message signalé
    const query = this.conversationRepo
      .createQueryBuilder('conv')
      .innerJoin(
        'messages',
        'msg',
        'msg.conversationId = conv.id AND msg.isReported = true',
      )
      .leftJoinAndSelect('conv.client', 'client')
      .leftJoinAndSelect('conv.vendor', 'vendor')
      .leftJoinAndSelect('vendor.user', 'vendorUser')
      .distinct(true)
      .orderBy('conv.updatedAt', 'DESC')
      .skip((page - 1) * limit)
      .take(limit);

    const [conversations, total] = await query.getManyAndCount();

    // Liste blanche pour la modération : identité + e-mail seulement
    // (jamais passwordHash, tokensValidAfter, securityAlert*...).
    const pickUser = (u: any) =>
      u ? { id: u.id, prenom: u.prenom, name: u.name, email: u.email } : u;
    const safe = conversations.map(c => {
      if (c.client) {
        (c as any).client = pickUser(c.client);
      }
      if (c.vendor?.user) {
        (c.vendor as any).user = pickUser(c.vendor.user);
      }
      return c;
    });

    return {
      data:  safe,
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
    };
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — VOIR LES MESSAGES SIGNALÉS
  // ─────────────────────────────────────────────────────
  async getReportedMessages(conversationId: string) {
    const conversation = await this.conversationRepo.findOne({
      where: { id: conversationId },
    });

    if (!conversation) throw new NotFoundException('Conversation introuvable');

    const messages = await this.messageRepo.find({
      where:     { conversationId, isReported: true },
      relations: ['sender'],
      order:     { createdAt: 'DESC' },
    });

    return messages.map(m => {
      if (m.sender) {
        const se = m.sender as any;
        (m as any).sender = {
          id: se.id, prenom: se.prenom, name: se.name, email: se.email,
        };
      }
      return m;
    });
  }

  // ─────────────────────────────────────────────────────
  // MÉTHODE PRIVÉE — FILTRAGE ANTI-CONTOURNEMENT
  // ─────────────────────────────────────────────────────
  private detectBlockedContent(content: string): {
    blocked: boolean;
    reason:  string | null;
  } {
    const lowerContent = content.toLowerCase();

    // 1. Numéros de téléphone (8+ chiffres consécutifs ou avec espaces/tirets)
    const phoneRegex = /(\+?\d[\d\s\-\.]{7,})/;
    if (phoneRegex.test(content)) {
      return { blocked: true, reason: 'phone_number_detected' };
    }

    // 2. Liens externes (http, https, www)
    const urlRegex = /(https?:\/\/|www\.|\.com|\.fr|\.bj|\.ng)/i;
    if (urlRegex.test(content)) {
      return { blocked: true, reason: 'external_link_detected' };
    }

    // 3. Mots-clés suspects de contournement
    const suspiciousKeywords = [
      'whatsapp',
      'telegram',
      'signal app',
      'messenger',
      'instagram',
      'facebook',
      'directement',
      'hors application',
      'hors app',
      'hors site',
      'paie moi directement',
      'virement direct',
      'mobile money direct',
      'mon numéro',
      'mon numero',
      'numéro perso',
      'numero perso',
      'envoie moi sur',
      'contacte moi sur',
      'rejoins moi sur',
    ];

    for (const keyword of suspiciousKeywords) {
      if (lowerContent.includes(keyword)) {
        return { blocked: true, reason: 'suspicious_keyword' };
      }
    }

    // 4. Numéros de compte bancaire (séquences longues de chiffres)
    const accountRegex = /\b\d{10,}\b/;
    if (accountRegex.test(content)) {
      return { blocked: true, reason: 'account_number_detected' };
    }

    return { blocked: false, reason: null };
  }
}