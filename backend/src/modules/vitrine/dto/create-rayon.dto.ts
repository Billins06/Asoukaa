import {
  IsString,
  IsNotEmpty,
  MaxLength,
  IsOptional,
  IsEnum,
  IsInt,
  IsBoolean,
  IsDateString,
} from 'class-validator';
import { Transform } from 'class-transformer';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { VitrineRayonType } from '../entities/vitrine-rayon.entity';
import { IsAppUrl } from '../../../common/validators/is-app-url.decorator';

const trim = ({ value }: { value: unknown }) =>
  typeof value === 'string' ? value.trim() : value;

// Création d'un rayon de la vitrine (POST /admin/vitrine/rayons).
export class CreateRayonDto {
  @ApiProperty({ example: 'Ventes flash du week-end' })
  @Transform(trim)
  @IsString()
  @IsNotEmpty({ message: 'Le nom du rayon est obligatoire' })
  @MaxLength(120)
  nom: string;

  @ApiPropertyOptional({ enum: VitrineRayonType, default: VitrineRayonType.LIBRE })
  @IsOptional()
  @IsEnum(VitrineRayonType, { message: 'Type de rayon invalide (flash, tendance, succes, libre)' })
  type?: VitrineRayonType;

  @ApiPropertyOptional({ description: 'URL renvoyée par POST /upload/vitrine' })
  @IsOptional()
  @IsAppUrl({ message: 'URL image invalide' })
  @MaxLength(500)
  imageUrl?: string | null;

  @ApiPropertyOptional({ default: 0 })
  @IsOptional()
  @IsInt()
  sortOrder?: number;

  @ApiPropertyOptional({ default: true })
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;

  @ApiPropertyOptional({ description: 'Début de visibilité (ISO 8601), null = sans limite' })
  @IsOptional()
  @IsDateString({}, { message: 'startsAt doit être une date ISO 8601' })
  startsAt?: string | null;

  @ApiPropertyOptional({ description: 'Fin de visibilité (ISO 8601), null = sans limite' })
  @IsOptional()
  @IsDateString({}, { message: 'endsAt doit être une date ISO 8601' })
  endsAt?: string | null;
}
