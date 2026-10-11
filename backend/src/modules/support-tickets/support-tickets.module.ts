import { Module }        from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { SupportTicketsController }      from './support-tickets.controller';
import { AdminSupportTicketsController } from './admin-support-tickets.controller';
import { SupportTicketsService }         from './support-tickets.service';
import { AdminSupportTicketsService }    from './admin-support-tickets.service';
import { SupportTicketsNotifier }        from './support-tickets-notifier.service';
import { SupportTicket }                 from './entities/support-ticket.entity';
import { SupportTicketMessage }          from './entities/support-ticket-message.entity';
import { AdminAccount }                  from '../auth/entities/admin-account.entity';
import { NotificationsModule }           from '../notifications/notifications.module';
import { UploadModule }                  from '../upload/upload.module';

// Tickets de support : l'utilisateur (acheteur / vendeur / livreur) écrit à
// l'équipe, l'équipe répond depuis le back-office. Circuit SÉPARÉ des
// remboursements (payments/refund) : aucun lien automatique entre les deux.
// MailModule et CommonModule (ActivityLogService) sont @Global.
@Module({
  imports: [
    TypeOrmModule.forFeature([SupportTicket, SupportTicketMessage, AdminAccount]),
    NotificationsModule,
    UploadModule,
  ],
  controllers: [SupportTicketsController, AdminSupportTicketsController],
  providers:   [SupportTicketsService, AdminSupportTicketsService, SupportTicketsNotifier],
})
export class SupportTicketsModule {}
