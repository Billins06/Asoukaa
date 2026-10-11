import {
  IsString,
  IsIn,
  IsOptional,
  IsUUID,
  IsArray,
  ArrayMaxSize,
  MinLength,
  MaxLength,
} from 'class-validator';
import { Transform } from 'class-transformer';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { TICKET_CATEGORIES } from '../support-ticket.constants';
import { normalizeCategory } from '../support-ticket.utils';

const trim = ({ value }: { value: unknown }) =>
  typeof value === 'string' ? value.trim() : value;

// POST /support-tickets
export class CreateSupportTicketDto {
  @ApiProperty({ example: 'Colis non reçu', minLength: 3, maxLength: 150 })
  @Transform(trim)
  @IsString({ message: 'Le sujet est obligatoire' })
  @MinLength(3, { message: 'Le sujet doit contenir au moins 3 caractères' })
  @MaxLength(150, { message: 'Le sujet ne peut pas dépasser 150 caractères' })
  subject: string;

  @ApiProperty({ minLength: 1, maxLength: 4000 })
  @Transform(trim)
  @IsString({ message: 'Le message est obligatoire' })
  @MinLength(1, { message: 'Le message ne peut pas être vide' })
  @MaxLength(4000, { message: 'Le message ne peut pas dépasser 4000 caractères' })
  message: string;

  @ApiProperty({ enum: TICKET_CATEGORIES })
  @Transform(({ value }) => normalizeCategory(value) ?? value)
  @IsIn(TICKET_CATEGORIES as unknown as string[], {
    message: `Catégorie invalide. Valeurs acceptées : ${TICKET_CATEGORIES.join(', ')}`,
  })
  category: string;

  @ApiPropertyOptional({ description: 'Commande concernée (dont vous êtes acheteur, vendeur ou livreur)' })
  @IsOptional()
  @IsUUID('all', { message: 'Identifiant de commande invalide' })
  orderId?: string;

  @ApiPropertyOptional({ description: 'URLs renvoyées par POST /upload/tickets (3 max)', type: [String] })
  @IsOptional()
  @IsArray({ message: 'Les pièces jointes doivent être une liste d\'URL' })
  @ArrayMaxSize(3, { message: 'Maximum 3 images par message' })
  @IsString({ each: true, message: 'URL d\'image invalide' })
  @MaxLength(500, { each: true, message: 'URL d\'image invalide' })
  attachments?: string[];
}
