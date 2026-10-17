import { IsOptional, IsString, MaxLength } from 'class-validator';
import { Transform } from 'class-transformer';

// Corps (facultatif) de PATCH /payments/refunds/:id/reject.
// Le champ s'appelle `motif` : c'est exactement ce que le site admin envoie
// (refunds-actions.ts → rejectRefundAction). Il est limité en longueur car il
// est enregistré et repris tel quel dans l'e-mail envoyé au client.
export class RejectRefundDto {
  @IsOptional()
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  @IsString({ message: 'Le motif doit être un texte' })
  @MaxLength(500, { message: 'Le motif ne peut pas dépasser 500 caractères' })
  motif?: string;
}
