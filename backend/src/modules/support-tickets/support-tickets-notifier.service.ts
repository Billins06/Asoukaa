import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { DataSource } from 'typeorm';
import { MailService } from '../mail/mail.service';
import { NotificationsService } from '../notifications/notifications.service';
import { NotificationType } from '../notifications/entities/notification.entity';
import { previewOf } from './support-ticket.utils';

const DEFAULT_SUPPORT_EMAIL = 'contact@asoukaa.com';
const EMAIL_EXCERPT_LENGTH = 400;

export interface TicketRef {
  id:        string;
  reference: string;
  category:  string;
  subject:   string;
}

// Envoi des e-mails et notifications liés aux tickets.
// ⚠️ Rien ici ne doit JAMAIS faire échouer la requête appelante : chaque
// méthode est « fire-and-forget » et capture (puis journalise) toute erreur.
@Injectable()
export class SupportTicketsNotifier {
  private readonly logger = new Logger(SupportTicketsNotifier.name);

  constructor(
    private readonly mailService: MailService,
    private readonly notificationsService: NotificationsService,
    private readonly config: ConfigService,
    private readonly dataSource: DataSource,
  ) {}

  private supportEmail(): string {
    const configured = (this.config.get<string>('SUPPORT_TEAM_EMAIL') ?? '').trim();
    return /^[^\s@,;<>]+@[^\s@,;<>]+\.[^\s@,;<>]+$/.test(configured)
      ? configured
      : DEFAULT_SUPPORT_EMAIL;
  }

  private run(label: string, job: () => Promise<void>): void {
    void (async () => {
      try {
        await job();
      } catch (err) {
        this.logger.error(`Échec ${label} : ${(err as Error)?.message ?? err}`);
      }
    })();
  }

  // Ticket créé (kind = 'created') ou réponse d'un utilisateur sur un
  // ticket résolu / fermé (kind = 'reopened') -> e-mail à l'équipe.
  notifyTeam(params: {
    kind: 'created' | 'reopened';
    ticket: TicketRef;
    userId: string;
    orderId?: string | null;
    previousStatus?: string;
    body: string;
    attachmentCount: number;
  }): void {
    this.run('envoi e-mail équipe support', async () => {
      const [user] = await this.dataSource.query(
        `SELECT prenom, name, email, phone FROM users WHERE id = $1`,
        [params.userId],
      );
      if (!user) return;
      const roles: Array<{ role: string }> = await this.dataSource.query(
        `SELECT role FROM user_roles WHERE "userId" = $1 AND "isActive" = true`,
        [params.userId],
      );
      let orderNumber: string | null = null;
      if (params.orderId) {
        const [o] = await this.dataSource.query(
          `SELECT "orderNumber" FROM orders WHERE id = $1`,
          [params.orderId],
        );
        orderNumber = o?.orderNumber ?? null;
      }
      await this.mailService.sendSupportTicketToTeam(this.supportEmail(), {
        kind:            params.kind,
        reference:       params.ticket.reference,
        category:        params.ticket.category,
        subject:         params.ticket.subject,
        previousStatus:  params.previousStatus,
        userName:        `${user.prenom ?? ''} ${user.name ?? ''}`.trim(),
        userEmail:       user.email ?? '',
        userPhone:       user.phone ?? '',
        userRoles:       roles.map((r) => r.role),
        orderNumber,
        excerpt:         previewOf(params.body, EMAIL_EXCERPT_LENGTH),
        attachmentCount: params.attachmentCount,
      });
    });
  }

  // Réponse de l'équipe -> notification dans l'app + e-mail à l'utilisateur.
  // Aucune information sur l'admin n'est transmise.
  notifyUserOfReply(params: {
    ticket: TicketRef;
    userId: string;
    body: string;
    attachmentCount: number;
  }): void {
    this.run('notification de réponse (in-app)', async () => {
      await this.notificationsService.create({
        userId:        params.userId,
        title:         `Réponse à votre ticket ${params.ticket.reference}`,
        body:          `Équipe Asoukaa : ${previewOf(params.body, 120)}`,
        type:          NotificationType.TICKET,
        referenceId:   params.ticket.id,
        referenceType: 'support_ticket',
        // L'e-mail dédié ci-dessous remplace l'e-mail générique.
        sendEmail:     false,
      });
    });
    this.run('envoi e-mail de réponse', async () => {
      const [user] = await this.dataSource.query(
        `SELECT prenom, email FROM users WHERE id = $1`,
        [params.userId],
      );
      if (!user?.email) return;
      await this.mailService.sendSupportTicketReply(user.email, {
        prenom:          user.prenom ?? '',
        reference:       params.ticket.reference,
        subject:         params.ticket.subject,
        excerpt:         previewOf(params.body, EMAIL_EXCERPT_LENGTH),
        attachmentCount: params.attachmentCount,
      });
    });
  }
}
