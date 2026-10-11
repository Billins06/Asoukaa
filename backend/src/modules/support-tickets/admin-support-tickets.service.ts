import {
  Injectable,
  BadRequestException,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Brackets, DataSource, In, Repository } from 'typeorm';

import { SupportTicket } from './entities/support-ticket.entity';
import { SupportTicketMessage } from './entities/support-ticket-message.entity';
import { ReplySupportTicketDto } from './dto/reply-support-ticket.dto';
import { SupportTicketsNotifier } from './support-tickets-notifier.service';
import {
  TICKET_STATUSES,
  TicketAuthorType,
  TicketStatus,
  formatTicketNumber,
} from './support-ticket.constants';
import {
  cleanBody,
  escapeLike,
  normalizeAttachments,
  normalizeCategory,
  parseTicketNumber,
  previewOf,
} from './support-ticket.utils';
import { UploadService } from '../upload/upload.service';
import { AdminAccount } from '../auth/entities/admin-account.entity';
import { ActivityLogService } from '../../common/services/activity-log.service';
import { ActorType, LogAction } from '../../common/entities/activity-log.entity';
import { stripSecrets } from '../../common/utils/strip-secrets.util';

export interface AdminActor {
  id:   string;
  role: string; // 'admin' | 'superadmin'
}

// Tickets de support — côté BACK-OFFICE (admin / superadmin uniquement,
// garde appliquée par le contrôleur).
@Injectable()
export class AdminSupportTicketsService {
  constructor(
    @InjectRepository(SupportTicket)
    private readonly ticketRepo: Repository<SupportTicket>,
    @InjectRepository(SupportTicketMessage)
    private readonly messageRepo: Repository<SupportTicketMessage>,
    @InjectRepository(AdminAccount)
    private readonly adminRepo: Repository<AdminAccount>,
    private readonly dataSource: DataSource,
    private readonly uploadService: UploadService,
    private readonly notifier: SupportTicketsNotifier,
    private readonly logService: ActivityLogService,
  ) {}

  // ─────────────────────────────────────────────────────
  // LISTE (filtres status, category, search)
  // ─────────────────────────────────────────────────────
  async list(
    filters: { status?: string; category?: string; search?: string },
    page: number,
    limit: number,
  ) {
    const qb = this.ticketRepo
      .createQueryBuilder('t')
      .innerJoinAndSelect('t.user', 'u');

    if (filters.status) {
      if (!TICKET_STATUSES.includes(filters.status)) {
        throw new BadRequestException(`Statut invalide. Valeurs acceptées : ${TICKET_STATUSES.join(', ')}`);
      }
      qb.andWhere('t.status = :status', { status: filters.status });
    }
    if (filters.category) {
      const category = normalizeCategory(filters.category);
      if (!category) throw new BadRequestException('Catégorie invalide');
      qb.andWhere('t.category = :category', { category });
    }
    const search = (filters.search ?? '').trim().slice(0, 100);
    if (search) {
      const like = `%${escapeLike(search)}%`;
      const num = parseTicketNumber(search);
      qb.andWhere(
        new Brackets((b) => {
          b.where('t.subject ILIKE :like', { like }).orWhere('u.email ILIKE :like', { like });
          if (num !== null) b.orWhere('t.number = :num', { num });
        }),
      );
    }

    const [rows, total] = await qb
      .orderBy('t.lastMessageAt', 'DESC')
      .addOrderBy('t.id', 'DESC')
      .skip((page - 1) * limit)
      .take(limit)
      .getManyAndCount();

    const lasts = await this.loadLastMessages(rows.map((t) => t.id));
    const admins = await this.loadAdminNames(rows.map((t) => t.assignedAdminId));

    return {
      data: rows.map((t) => {
        const last = lasts.get(t.id);
        return {
          id:             t.id,
          number:         t.number,
          reference:      formatTicketNumber(t.number),
          category:       t.category,
          subject:        t.subject,
          status:         t.status,
          orderId:        t.orderId,
          adminHasUnread: t.adminHasUnread,
          assignedAdmin:  t.assignedAdminId
            ? { id: t.assignedAdminId, name: admins.get(t.assignedAdminId) ?? null }
            : null,
          user: {
            id:     t.user.id,
            prenom: t.user.prenom,
            name:   t.user.name,
            email:  t.user.email,
          },
          lastMessage: last
            ? {
                authorType:      last.authorType,
                preview:         previewOf(last.body),
                attachmentCount: last.attachmentCount,
                createdAt:       last.createdAt,
              }
            : null,
          createdAt:     t.createdAt,
          lastMessageAt: t.lastMessageAt,
          closedAt:      t.closedAt,
        };
      }),
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
    };
  }

  // ─────────────────────────────────────────────────────
  // STATS (compte par statut)
  // ─────────────────────────────────────────────────────
  async stats() {
    const rows: Array<{ status: string; n: number }> = await this.dataSource.query(
      `SELECT status, COUNT(*)::int AS n FROM support_tickets GROUP BY status`,
    );
    const [{ unread }] = await this.dataSource.query(
      `SELECT COUNT(*)::int AS unread FROM support_tickets
       WHERE "adminHasUnread" = true AND status <> $1`,
      [TicketStatus.FERME],
    );
    const out: Record<string, number> = {
      ouvert: 0, en_cours: 0, resolu: 0, ferme: 0,
    };
    for (const r of rows) out[r.status] = (out[r.status] ?? 0) + r.n;
    const total = Object.values(out).reduce((a, b) => a + b, 0);
    return { ...out, total, adminUnread: unread };
  }

  // ─────────────────────────────────────────────────────
  // DÉTAIL (messages + infos utilisateur + commande)
  // ─────────────────────────────────────────────────────
  async getOne(id: string) {
    const ticket = await this.ticketRepo
      .createQueryBuilder('t')
      .innerJoinAndSelect('t.user', 'u')
      .leftJoinAndSelect('u.roles', 'r')
      .where('t.id = :id', { id })
      .getOne();
    if (!ticket) throw new NotFoundException('Ticket introuvable');

    // Horodatage du dernier message AVANT de charger les messages (texte :
    // précision microseconde, pas de conversion de fuseau).
    let seenAt: string | null = null;
    if (ticket.adminHasUnread) {
      const [row] = await this.dataSource.query(
        `SELECT "lastMessageAt"::text AS ts FROM support_tickets WHERE id = $1`,
        [id],
      );
      seenAt = row?.ts ?? null;
    }

    const messages = await this.messageRepo.find({
      where: { ticketId: id },
      order: { createdAt: 'ASC', id: 'ASC' },
      take: 1000,
    });

    // Consulter le détail = lu côté équipe. Conditionnel : un nouveau message
    // de l'utilisateur arrivé depuis la lecture garde le « non lu ».
    // SQL direct : ne modifie pas `updatedAt`. La réponse reflète la valeur
    // d'avant la mise à jour.
    if (ticket.adminHasUnread && seenAt) {
      await this.dataSource.query(
        `UPDATE support_tickets SET "adminHasUnread" = false
         WHERE id = $1 AND "lastMessageAt" <= $2::timestamp`,
        [id, seenAt],
      );
    }

    const adminIds = [
      ticket.assignedAdminId,
      ...messages.filter((m) => m.authorType === TicketAuthorType.ADMIN).map((m) => m.authorId),
    ];
    const admins = await this.loadAdminNames(adminIds);

    let order: { id: string; orderNumber: string; status: string } | null = null;
    if (ticket.orderId) {
      const [o] = await this.dataSource.query(
        `SELECT id, "orderNumber", status FROM orders WHERE id = $1`,
        [ticket.orderId],
      );
      order = o ?? null;
    }

    const u = ticket.user;
    return stripSecrets({
      id:             ticket.id,
      number:         ticket.number,
      reference:      formatTicketNumber(ticket.number),
      category:       ticket.category,
      subject:        ticket.subject,
      status:         ticket.status,
      orderId:        ticket.orderId,
      order,
      adminHasUnread: ticket.adminHasUnread,
      userHasUnread:  ticket.userHasUnread,
      assignedAdmin:  ticket.assignedAdminId
        ? { id: ticket.assignedAdminId, name: admins.get(ticket.assignedAdminId) ?? null }
        : null,
      user: {
        id:        u.id,
        prenom:    u.prenom,
        name:      u.name,
        email:     u.email,
        phone:     u.phone,
        avatarUrl: u.avatarUrl ?? null,
        isActive:  u.isActive,
        roles:     (u.roles ?? []).filter((r) => r.isActive !== false).map((r) => r.role),
      },
      createdAt:     ticket.createdAt,
      updatedAt:     ticket.updatedAt,
      lastMessageAt: ticket.lastMessageAt,
      closedAt:      ticket.closedAt,
      messages: messages.map((m) => {
        const fromAdmin = m.authorType === TicketAuthorType.ADMIN;
        return {
          id:          m.id,
          authorType:  m.authorType,
          authorName:  fromAdmin
            ? (admins.get(m.authorId) ?? 'Administrateur')
            : `${u.prenom ?? ''} ${u.name ?? ''}`.trim(),
          body:        m.body,
          attachments: m.attachments ?? [],
          createdAt:   m.createdAt,
        };
      }),
    });
  }

  // ─────────────────────────────────────────────────────
  // RÉPONDRE
  // ─────────────────────────────────────────────────────
  async reply(admin: AdminActor, id: string, dto: ReplySupportTicketDto, ipAddress?: string) {
    const body = cleanBody(dto.message);
    const attachments = normalizeAttachments(this.uploadService, dto.attachments);

    const result = await this.dataSource.transaction(async (manager) => {
      const rows = await manager.query(
        `SELECT id, number, category, subject, status, "userId"
         FROM support_tickets WHERE id = $1 FOR UPDATE`,
        [id],
      );
      const ticket = rows[0];
      if (!ticket) throw new NotFoundException('Ticket introuvable');
      if (ticket.status === TicketStatus.FERME) {
        throw new BadRequestException('Ce ticket est fermé : changez son statut avant de répondre');
      }

      const message = await manager.getRepository(SupportTicketMessage).save(
        manager.getRepository(SupportTicketMessage).create({
          ticketId: id,
          authorId: admin.id,
          authorType: TicketAuthorType.ADMIN,
          body,
          attachments,
        }),
      );

      const newStatus = ticket.status === TicketStatus.OUVERT ? TicketStatus.EN_COURS : ticket.status;
      await manager.query(
        `UPDATE support_tickets
         SET status = $2, "lastMessageAt" = NOW(), "adminHasUnread" = false,
             "userHasUnread" = true, "updatedAt" = NOW()
         WHERE id = $1`,
        [id, newStatus],
      );
      return { ticket, message, oldStatus: ticket.status as string, newStatus };
    });

    this.notifier.notifyUserOfReply({
      ticket: {
        id,
        reference: formatTicketNumber(result.ticket.number),
        category:  result.ticket.category,
        subject:   result.ticket.subject,
      },
      userId: result.ticket.userId,
      body,
      attachmentCount: attachments.length,
    });

    await this.logService.log({
      actorId:    admin.id,
      actorType:  this.actorTypeOf(admin),
      action:     LogAction.SUPPORT_TICKET_REPLIED,
      entityType: 'SupportTicket',
      entityId:   id,
      oldValue:   { status: result.oldStatus },
      newValue:   { status: result.newStatus, messageId: result.message.id },
      ipAddress,
    });

    return {
      message: {
        id:          result.message.id,
        authorType:  result.message.authorType,
        authorName:  await this.adminDisplayName(admin.id),
        body:        result.message.body,
        attachments: result.message.attachments ?? [],
        createdAt:   result.message.createdAt,
      },
      ticket: {
        id,
        status:        result.newStatus,
        lastMessageAt: result.message.createdAt,
      },
    };
  }

  // ─────────────────────────────────────────────────────
  // CHANGER LE STATUT
  // ─────────────────────────────────────────────────────
  async setStatus(admin: AdminActor, id: string, status: string, ipAddress?: string) {
    if (!TICKET_STATUSES.includes(status)) {
      throw new BadRequestException(`Statut invalide. Valeurs acceptées : ${TICKET_STATUSES.join(', ')}`);
    }
    const oldStatus = await this.dataSource.transaction(async (manager) => {
      const [t] = await manager.query(`SELECT status FROM support_tickets WHERE id = $1 FOR UPDATE`, [id]);
      if (!t) throw new NotFoundException('Ticket introuvable');
      if (t.status !== status) {
        await manager.query(
          `UPDATE support_tickets
           SET status = $2,
               "closedAt" = CASE WHEN $2 = $3 THEN NOW() ELSE NULL END,
               "updatedAt" = NOW()
           WHERE id = $1`,
          [id, status, TicketStatus.FERME],
        );
      }
      return t.status as string;
    });

    if (oldStatus !== status) {
      await this.logService.log({
        actorId:    admin.id,
        actorType:  this.actorTypeOf(admin),
        action:     LogAction.SUPPORT_TICKET_STATUS_CHANGED,
        entityType: 'SupportTicket',
        entityId:   id,
        oldValue:   { status: oldStatus },
        newValue:   { status },
        ipAddress,
      });
    }
    return { id, status, previousStatus: oldStatus };
  }

  // ─────────────────────────────────────────────────────
  // S'ASSIGNER LE TICKET
  // ─────────────────────────────────────────────────────
  async assignToMe(admin: AdminActor, id: string, ipAddress?: string) {
    const [t] = await this.dataSource.query(
      `SELECT "assignedAdminId" FROM support_tickets WHERE id = $1`,
      [id],
    );
    if (!t) throw new NotFoundException('Ticket introuvable');

    await this.dataSource.query(
      `UPDATE support_tickets SET "assignedAdminId" = $2, "updatedAt" = NOW() WHERE id = $1`,
      [id, admin.id],
    );
    await this.logService.log({
      actorId:    admin.id,
      actorType:  this.actorTypeOf(admin),
      action:     LogAction.SUPPORT_TICKET_ASSIGNED,
      entityType: 'SupportTicket',
      entityId:   id,
      oldValue:   { assignedAdminId: t.assignedAdminId },
      newValue:   { assignedAdminId: admin.id },
      ipAddress,
    });
    return {
      id,
      assignedAdmin: { id: admin.id, name: await this.adminDisplayName(admin.id) },
    };
  }

  // ─── Helpers privés ───────────────────────────────────

  private actorTypeOf(admin: AdminActor): ActorType {
    return admin.role === 'superadmin' ? ActorType.SUPERADMIN : ActorType.ADMIN;
  }

  private async adminDisplayName(adminId: string): Promise<string | null> {
    const names = await this.loadAdminNames([adminId]);
    return names.get(adminId) ?? null;
  }

  private async loadAdminNames(ids: Array<string | null | undefined>): Promise<Map<string, string>> {
    const unique = Array.from(new Set(ids.filter((x): x is string => !!x)));
    const map = new Map<string, string>();
    if (!unique.length) return map;
    const admins = await this.adminRepo.find({
      where: { id: In(unique) },
      select: ['id', 'prenom', 'name'],
    });
    for (const a of admins) map.set(a.id, `${a.prenom ?? ''} ${a.name ?? ''}`.trim());
    return map;
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
}
