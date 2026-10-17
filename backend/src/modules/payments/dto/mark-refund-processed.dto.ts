import { IsOptional, IsString, MaxLength } from 'class-validator';
import { Transform } from 'class-transformer';

// Corps (facultatif) de PATCH /payments/refunds/:id/processed.
// `note` : mention libre de l'admin (ex. « Remboursé par Mobile Money le
// 12/10, réf. 123456 »). Elle est enregistrée dans le journal d'activité.
export class MarkRefundProcessedDto {
  @IsOptional()
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  @IsString({ message: 'La note doit être un texte' })
  @MaxLength(500, { message: 'La note ne peut pas dépasser 500 caractères' })
  note?: string;
}
