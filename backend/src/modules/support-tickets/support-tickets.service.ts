import {
  Injectable,
  BadRequestException,
  NotFoundException,
  HttpException,
  HttpStatus,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { DataSource, Repository } from 'typeorm';

import { SupportTicket } from './entities/support-ticket.entity';
import { SupportTicketMessage } from './entities/support-ticket-message.entity';
import { CreateSupportTicketDto } from './dto/create-support-ticket.dto';
import { ReplySupportTicketDto } from './dto/reply-support-ticket.dto';
import { SupportTicketsNotifier } from './support-tickets-notifier.service';
import {
  ADMIN_DISPLAY_NAME,
  TICKET_LIMITS,
  TicketAuthorType,
  TicketStatus,
  formatTicketNumber,
} from './support-ticket.constants';
import {
  cleanBody,
  cleanSubject,
  normalizeAttachments,
  normalizeCategory,
  previewOf,
} from './support-ticket.utils';
import { UploadService } from '../upload/upload.service';

// Tickets de support — côté UTILISATEUR (acheteur, vendeur, livreur).
// Chaque requête est filtrée sur `userId` : aucun utilisateur ne peut voir
// ni modifier le ticket d'un autre. Les horodatages « maintenant » et les
// fenêtres de temps sont calculés par Postgres (NOW()), jamais par Node.
@Injectable()
export class SupportTicketsService {
  constructor(
    @InjectRepository(SupportTicket)
    private readonly ticketRepo: Repository<SupportTicket>,
    @InjectRepository(SupportTicketMessage)
    private readonly messageRepo: Repository<SupportTicketMessage>,
    private readonly dataSource: DataSource,
    private readonly uploadService: UploadService,
    private readonly notifier: SupportTicketsNotifier,
  ) {}

  // ─────────────────────────────────────────────────────
  // CRÉER UN TICKET (+ premier message)
  // ─────────────────────────────────────────────────────
  async createTicket(userId: string, dto: CreateSupportTicketDto) {
    const subject = cleanSubject(dto.subject);
    const body = cleanBody(dto.message);
    const category = normalizeCategory(dto.category);
    if (!category) throw new BadRequestException('Catégorie invalide');
    const attachments = normalizeAttachments(this.uploadService, dto.attachments);

    if (dto.orderId) await this.assertOrderAccess(userId, dto.orderId);

    const ticketId = await this.dataSource.transaction(async (manager) => {
      // Verrou par utilisateur : deux créations simultanées ne peuvent pas
      // dépasser les limites ensemble.
      await manager.query(`SELECT pg_advisory_xact_lock(hashtext($1))`, [`support-ticket-user:${userId}`]);

      const [{ recent, active }] = await manager.query(
        `SELECT
           COUNT(*) FILTER (WHERE "createdAt" > NOW() - INTERVAL '1 hour')::int AS recent,
           COUNT(*) FILTER (WHERE status IN ($2, $3))::int AS active
         FROM support_tickets WHERE "userId" = $1`,
        [userId, TicketStatus.OUVERT, TicketStatus.EN_COURS],
      );
      if (recent >= TICKET_LIMITS.NEW_TICKETS_PER_HOUR) {
        throw new HttpException(
          `Vous avez atteint la limite de ${TICKET_LIMITS.NEW_TICKETS_PER_HOUR} nouveaux tickets par heure. Réessayez plus tard.`,
          HttpStatus.TOO_MANY_REQUESTS,
        );
      }
      if (active >= TICKET_LIMITS.MAX_OPEN_TICKETS) {
        throw new BadRequestException(
          `Vous avez déjà ${TICKET_LIMITS.MAX_OPEN_TICKETS} tickets en cours. Attendez une réponse de l'équipe avant d'en ouvrir un nouveau.`,
        );
      }

      const ticket = await manager.getRepository(SupportTicket).save(
        manager.getRepository(SupportTicket).create({
          userId,
          category,
          subject,
          status: TicketStatus.OUVERT,
          orderId: dto.orderId ?? null,
          userHasUnread: false,
          adminHasUnread: true,
        }),
      );
      await manager.getRepository(SupportTicketMessage).save(
        manager.getRepository(SupportTicketMessage).create({
          ticketId: ticket.id,
          authorId: userId,
          authorType: TicketAuthorType.USER,
          body,
          attachments,
        }),
      );
      return ticket.id;
    });

    // Relecture : `number` est attribué par la séquence de la base.
    const ticket = await this.ticketRepo.findOneOrFail({ where: { id: ticketId } });
    const reference = formatTicketNumber(ticket.number);

    this.notifier.notifyTeam({
      kind: 'created',
      ticket: { id: ticket.id, reference, category, subject },
      userId,
      orderId: ticket.orderId,
      body,
      attachmentCount: attachments.length,
    });

    return this.mapTicketDetail(ticket, await this.loadMessages(ticket.id), true);
  }

  // ─────────────────────────────────────────────────────
  // MES TICKETS (liste paginée)
  // ─────────────────────────────────────────────────────
  async listMine(userId: string, page: number, limit: number) {
    const [rows, total] = await this.ticketRepo.findAndCount({
      where: { userId },
      order: { lastMessageAt: 'DESC', id: 'DESC' },
      skip: (page - 1) * limit,
      take: limit,
    });

    const lasts = await this.loadLastMessages(rows.map((t) => t.id));

    return {
      data: rows.map((t) => {
        const last = lasts.get(t.id);
        return {
          id:            t.id,
          number:        t.number,
          reference:     formatTicketNumber(t.number),
          category:      t.category,
          subject:       t.subject,
          status:        t.status,
          lastMessageAt: t.lastMessageAt,
          hasUnread:     t.userHasUnread,
          lastMessage:   last
            ? {
                authorType:      last.authorType,
                preview:         previewOf(last.body),
                attachmentCount: last.attachmentCount,
                createdAt:       last.createdAt,
              }
            : null,
        };
      }),
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
    };
  }

  // ─────────────────────────────────────────────────────
  // DÉTAIL D'UN DE MES TICKETS (marque comme lu)
  // ─────────────────────────────────────────────────────
  async getMine(userId: string, id: string) {
    const ticket = await this.ticketRepo.findOne({ where: { id, userId } });
    if (!ticket) throw new NotFoundException('Ticket introuvable');

    // Horodatage du dernier message AVANT de charger les messages (texte :
    // garde la précision à la microseconde, sans conversion de fuseau).
    let seenAt: string | null = null;
    if (ticket.userHasUnread) {
      const [row] = await this.dataSource.query(
        `SELECT "lastMessageAt"::text AS ts FROM support_tickets WHERE id = $1 AND "userId" = $2`,
        [id, userId],
      );
      seenAt = row?.ts ?? null;
    }

    const messages = await this.loadMessages(id);

    if (ticket.userHasUnread && seenAt) {
      // SQL direct : consulter un ticket ne doit pas modifier `updatedAt`.
      // Conditionnel : si une réponse de l'équipe est arrivée depuis la lecture
      // ("lastMessageAt" a bougé), le « non lu » est conservé.
      await this.dataSource.query(
        `UPDATE support_tickets SET "userHasUnread" = false
         WHERE id = $1 AND "userId" = $2 AND "lastMessageAt" <= $3::timestamp`,
        [id, userId, seenAt],
      );
    }

    const canReply = await this.canReply(id);
    return this.mapTicketDetail({ ...ticket, userHasUnread: false } as SupportTicket, messages, canReply);
  }

  // ─────────────────────────────────────────────────────
  // RÉPONDRE À UN DE MES TICKETS
  // ─────────────────────────────────────────────────────
  async addUserMessage(userId: string, id: string, dto: ReplySupportTicketDto) {
    const body = cleanBody(dto.message);
    const attachments = normalizeAttachments(this.uploadService, dto.attachments);

    const result = await this.dataSource.transaction(async (manager) => {
      await manager.query(`SELECT pg_advisory_xact_lock(hashtext($1))`, [`support-message-user:${userId}`]);

      // Verrou de ligne : une réponse et un changement de statut admin
      // simultanés ne s'écrasent pas.
      const rows = await manager.query(
        `SELECT id, number, category, subject, status, "orderId",
                ("closedAt" IS NOT NULL AND "closedAt" > NOW() - INTERVAL '${TICKET_LIMITS.REOPEN_WINDOW_DAYS} days') AS "recentlyClosed"
         FROM support_tickets WHERE id = $1 AND "userId" = $2 FOR UPDATE`,
        [id, userId],
      );
      const ticket = rows[0];
      if (!ticket) throw new NotFoundException('Ticket introuvable');

      const previousStatus: string = ticket.status;
      if (previousStatus === TicketStatus.FERME && !ticket.recentlyClosed) {
        throw new BadRequestException('Ce ticket est fermé, ouvrez-en un nouveau');
      }

      const [{ n }] = await manager.query(
        `SELECT COUNT(*)::int AS n FROM support_ticket_messages
         WHERE "authorType" = $2 AND "authorId" = $1 AND "createdAt" > NOW() - INTERVAL '1 hour'`,
        [userId, TicketAuthorType.USER],
      );
      if (n >= TICKET_LIMITS.MESSAGES_PER_HOUR) {
        throw new HttpException(
          `Vous avez atteint la limite de ${TICKET_LIMITS.MESSAGES_PER_HOUR} messages par heure. Réessayez plus tard.`,
          HttpStatus.TOO_MANY_REQUESTS,
        );
      }

      const message = await manager.getRepository(SupportTicketMessage).save(
        manager.getRepository(SupportTicketMessage).create({
          ticketId: id,
          authorId: userId,
          authorType: TicketAuthorType.USER,
          body,
          attachments,
        }),
      );

      // résolu / fermé (≤ 7 j) -> rouvert ; ouvert / en_cours inchangé.
      const reopened = previousStatus === TicketStatus.RESOLU || previousStatus === TicketStatus.FERME;
      const newStatus = reopened ? TicketStatus.OUVERT : previousStatus;
      await manager.query(
        `UPDATE support_tickets
         SET status = $2, "closedAt" = CASE WHEN $3::boolean THEN NULL ELSE "closedAt" END,
             "lastMessageAt" = NOW(), "adminHasUnread" = true, "updatedAt" = NOW()
         WHERE id = $1`,
        [id, newStatus, reopened],
      );

      return { ticket, message, previousStatus, newStatus, reopened };
    });

    if (result.reopened) {
      this.notifier.notifyTeam({
        kind: 'reopened',
        ticket: {
          id,
          reference: formatTicketNumber(result.ticket.number),
          category: result.ticket.category,
          subject: result.ticket.subject,
        },
        userId,
        orderId: result.ticket.orderId,
        previousStatus: result.previousStatus,
        body,
        attachmentCount: attachments.length,
      });
    }

    return {
      message: this.mapMessage(result.message),
      ticket: {
        id,
        status: result.newStatus,
        lastMessageAt: result.message.createdAt,
      },
    };
  }

  // ─────────────────────────────────────────────────────
  // NOMBRE DE TICKETS AVEC RÉPONSE NON LUE (badge)
  // ─────────────────────────────────────────────────────
  async unreadCount(userId: string) {
    const tickets = await this.ticketRepo.count({ where: { userId, userHasUnread: true } });
    return { tickets };
  }

  // ─── Helpers privés ───────────────────────────────────

  // L'utilisateur doit être acheteur, vendeur ou livreur de la commande.
  // Même réponse (404 sans détail) que la commande n'existe pas ou ne soit
  // pas la sienne : pas d'énumération possible.
  private async assertOrderAccess(userId: string, orderId: string): Promise<void> {
    const rows = await this.dataSource.query(
      `SELECT o.id FROM orders o
       LEFT JOIN vendor_profiles vp ON vp.id = o."vendorId"
       LEFT JOIN deliveries d ON d."orderId" = o.id
       LEFT JOIN delivery_agent_profiles dap ON dap.id = d."agentId"
       WHERE o.id = $1 AND (o."userId" = $2 OR vp."userId" = $2 OR dap."userId" = $2)
       LIMIT 1`,
      [orderId, userId],
    );
    if (!rows.length) throw new NotFoundException('Commande introuvable');
  }

  private async canReply(ticketId: string): Promise<boolean> {
    const [row] = await this.dataSource.query(
      `SELECT (status <> $2 OR ("closedAt" IS NOT NULL AND "closedAt" > NOW() - INTERVAL '${TICKET_LIMITS.REOPEN_WINDOW_DAYS} days')) AS "canReply"
       FROM support_tickets WHERE id = $1`,
      [ticketId, TicketStatus.FERME],
    );
    return !!row?.canReply;
  }

  private loadMessages(ticketId: string): Promise<SupportTicketMessage[]> {
    return this.messageRepo.find({
      where: { ticketId },
      order: { createdAt: 'ASC', id: 'ASC' },
      take: 1000,
    });
  }

  private async loadLastMessages(ticketIds: string[]) {
    const map = new Map<string, { authorType: string; body: string; createdAt: Date; attachmentCount: number }>();
    if (!ticketIds.length) return map;
    const rows = await this.dataSource.query(
      `SELECT DISTINCT ON (m."ticketId") m."ticketId", m."authorType", m.body, m."createdAt",
              jsonb_array_length(m.attachments)::int AS "attachmentCount"
       FROM support_ticket_messages m
       WHERE m."ticketId" = ANY($1::uuid[])
       ORDER BY m."ticketId", m."createdAt" DESC, m.id DESC`,
      [ticketIds],
    );
    for (const r of rows) map.set(r.ticketId, r);
    return map;
  }

  // Message vu par l'utilisateur : l'identité de l'admin n'est JAMAIS
  // exposée (ni authorId, ni nom, ni e-mail) — seulement « Équipe Asoukaa ».
  private mapMessage(m: SupportTicketMessage) {
    const fromAdmin = m.authorType === TicketAuthorType.ADMIN;
    return {
      id:          m.id,
      authorType:  m.authorType,
      authorName:  fromAdmin ? ADMIN_DISPLAY_NAME : 'Vous',
      isMine:      !fromAdmin,
      body:        m.body,
      attachments: m.attachments ?? [],
      createdAt:   m.createdAt,
    };
  }

  private async mapTicketDetail(t: SupportTicket, messages: SupportTicketMessage[], canReply: boolean) {
    let orderNumber: string | null = null;
    if (t.orderId) {
      const [o] = await this.dataSource.query(`SELECT "orderNumber" FROM orders WHERE id = $1`, [t.orderId]);
      orderNumber = o?.orderNumber ?? null;
    }
    return {
      id:            t.id,
      number:        t.number,
      reference:     formatTicketNumber(t.number),
      category:      t.category,
      subject:       t.subject,
      status:        t.status,
      orderId:       t.orderId,
      orderNumber,
      hasUnread:     t.userHasUnread,
      canReply,
      createdAt:     t.createdAt,
      updatedAt:     t.updatedAt,
      lastMessageAt: t.lastMessageAt,
      closedAt:      t.closedAt,
      messages:      messages.map((m) => this.mapMessage(m)),
    };
  }
}
