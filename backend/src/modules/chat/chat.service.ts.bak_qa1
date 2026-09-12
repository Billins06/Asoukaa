import {
  Injectable,
  NotFoundException,
  ForbiddenException,
  BadRequestException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository }       from 'typeorm';

import { Conversation } from './entities/conversation.entity';
import { Message }      from './entities/message.entity';
import { User }         from '../users/entities/user.entity';
import { VendorProfile } from '../users/entities/vendor-profile.entity';
import { Product }      from '../products/entities/product.entity';

import { CreateConversationDto } from './dto/create-conversation.dto';
import { SendMessageDto }        from './dto/send-message.dto';

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
  ) {}

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
    // (unique sur clientId + vendorId + productId)
    const existing = await this.conversationRepo.findOne({
      where: {
        clientId,
        vendorId:  dto.vendorId,
        productId: dto.productId || undefined,
      },
    });

    if (existing) {
      return existing; // Retourner la conversation existante
    }

    // Créer la conversation
    const conversation             = this.conversationRepo.create();
    conversation.clientId          = clientId;
    conversation.vendorId          = dto.vendorId;
    conversation.productId         = dto.productId ?? null;
    conversation.isArchived        = false;

    return this.conversationRepo.save(conversation);
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
      relations: ['vendor'],
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
      if (c.client) {
        const { passwordHash, ...userSafe } = c.client as any;
        (c as any).client = userSafe;
      }
      if (c.vendor?.user) {
        const { passwordHash, ...userSafe } = c.vendor.user as any;
        (c.vendor as any).user = userSafe;
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

    const [messages, total] = await this.messageRepo.findAndCount({
      where: { conversationId },
      order: { createdAt: 'DESC' },
      skip:  (page - 1) * limit,
      take:  limit,
    });

    // Marquer les messages non lus comme lus
    // (uniquement ceux envoyés par l'autre participant)
    await this.messageRepo.update(
      {
        conversationId,
        isRead: false,
        // On cible les messages PAS envoyés par moi
        // (on ne marque pas mes propres messages comme lus
        //  par moi-même)
      },
      { isRead: true },
    );

    return {
      data:  messages.reverse(), // Les plus anciens en premier pour l'affichage
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
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

    const safe = conversations.map(c => {
      if (c.client) {
        const { passwordHash, ...userSafe } = c.client as any;
        (c as any).client = userSafe;
      }
      if (c.vendor?.user) {
        const { passwordHash, ...userSafe } = c.vendor.user as any;
        (c.vendor as any).user = userSafe;
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
        const { passwordHash, ...userSafe } = m.sender as any;
        (m as any).sender = userSafe;
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