import { IsNotEmpty, IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';
import { Transform } from 'class-transformer';

// Corps de POST /payments/refunds/digital (admin) : remboursement d'un livre
// numérique après un ticket d'assistance (fichier défectueux ou jamais téléchargé).
export class AdminRefundDigitalDto {
  @IsNotEmpty()
  @IsUUID('4', { message: 'ID commande invalide' })
  orderId: string;

  @IsNotEmpty({ message: 'Le motif est obligatoire' })
  @IsString()
  @MaxLength(500)
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  motif: string;

  // Ticket d'assistance à l'origine de la demande (preuve que le client a
  // signalé le problème dans les 24 h, même si l'admin traite plus tard).
  @IsOptional()
  @IsUUID('4', { message: 'ID ticket invalide' })
  ticketId?: string;
}
