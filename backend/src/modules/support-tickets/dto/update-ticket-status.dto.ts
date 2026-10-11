import { IsIn } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';
import { TICKET_STATUSES } from '../support-ticket.constants';

// PATCH /admin/support-tickets/:id/status
export class UpdateTicketStatusDto {
  @ApiProperty({ enum: TICKET_STATUSES })
  @IsIn(TICKET_STATUSES, {
    message: `Statut invalide. Valeurs acceptées : ${TICKET_STATUSES.join(', ')}`,
  })
  status: string;
}
