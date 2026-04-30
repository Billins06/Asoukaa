import {
  IsString,
  IsOptional,
  IsUrl,
  MaxLength,
  ValidateIf,
  IsNotEmpty,
} from 'class-validator';
import { Transform } from 'class-transformer';

export class SendMessageDto {

  // Contenu texte — optionnel si image envoyée
  @IsOptional()
  @IsString()
  @MaxLength(2000, { message: 'Le message ne peut pas dépasser 2000 caractères' })
  @Transform(({ value }) => value?.trim())
  content?: string;

  // URL image — optionnelle si texte envoyé
  @IsOptional()
  @IsUrl({}, { message: 'URL image invalide' })
  @MaxLength(500)
  imageUrl?: string;

  // ⚠️ Le service doit vérifier qu'au moins
  // content ou imageUrl est fourni (pas les deux vides)
  // ⚠️ Le service doit aussi appliquer le filtrage
  // anti-contournement sur le contenu texte
}