import {
  IsString,
  IsOptional,
  IsArray,
  ArrayMaxSize,
  MinLength,
  MaxLength,
} from 'class-validator';
import { Transform } from 'class-transformer';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

const trim = ({ value }: { value: unknown }) =>
  typeof value === 'string' ? value.trim() : value;

// POST /support-tickets/:id/messages  et  POST /admin/support-tickets/:id/messages
export class ReplySupportTicketDto {
  @ApiProperty({ minLength: 1, maxLength: 4000 })
  @Transform(trim)
  @IsString({ message: 'Le message est obligatoire' })
  @MinLength(1, { message: 'Le message ne peut pas être vide' })
  @MaxLength(4000, { message: 'Le message ne peut pas dépasser 4000 caractères' })
  message: string;

  @ApiPropertyOptional({ description: 'URLs renvoyées par POST /upload/tickets (3 max)', type: [String] })
  @IsOptional()
  @IsArray({ message: 'Les pièces jointes doivent être une liste d\'URL' })
  @ArrayMaxSize(3, { message: 'Maximum 3 images par message' })
  @IsString({ each: true, message: 'URL d\'image invalide' })
  @MaxLength(500, { each: true, message: 'URL d\'image invalide' })
  attachments?: string[];
}
