import { IsOptional, IsString, MaxLength } from 'class-validator';
import { Transform } from 'class-transformer';

// Corps (facultatif) de PATCH /payments/:id/reviewed.
// `note` : mention libre de l'admin (ex. « Client remboursé à la main le 12/10 »).
export class MarkPaymentReviewedDto {
  @IsOptional()
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  @IsString({ message: 'La note doit être un texte' })
  @MaxLength(500, { message: 'La note ne peut pas dépasser 500 caractères' })
  note?: string;
}
