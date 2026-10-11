import {
  IsString,
  IsNotEmpty,
  MaxLength,
  IsOptional,
  IsEnum,
  IsInt,
  IsBoolean,
  IsDateString,
  ValidateIf,
} from 'class-validator';
import { Transform } from 'class-transformer';
import { ApiPropertyOptional } from '@nestjs/swagger';
import { VitrineRayonType } from '../entities/vitrine-rayon.entity';
import { IsAppUrl } from '../../../common/validators/is-app-url.decorator';

const trim = ({ value }: { value: unknown }) =>
  typeof value === 'string' ? value.trim() : value;

// Modification partielle d'un rayon (PATCH /admin/vitrine/rayons/:id).
// ⚠️ imageUrl / startsAt / endsAt acceptent null (= vider le champ), d'où
// @IsOptional (qui laisse passer null). Les autres champs sont NOT NULL en
// base : @ValidateIf(!== undefined) fait échouer la validation sur null au
// lieu de laisser partir un UPDATE ... SET "nom" = NULL.
export class UpdateRayonDto {
  @ApiPropertyOptional()
  @ValidateIf((o) => o.nom !== undefined)
  @Transform(trim)
  @IsString()
  @IsNotEmpty({ message: 'Le nom du rayon ne peut pas être vide' })
  @MaxLength(120)
  nom?: string;

  @ApiPropertyOptional({ enum: VitrineRayonType })
  @ValidateIf((o) => o.type !== undefined)
  @IsEnum(VitrineRayonType, { message: 'Type de rayon invalide (flash, tendance, succes, libre)' })
  type?: VitrineRayonType;

  @ApiPropertyOptional({ nullable: true })
  @IsOptional()
  @IsAppUrl({ message: 'URL image invalide' })
  @MaxLength(500)
  imageUrl?: string | null;

  @ApiPropertyOptional()
  @ValidateIf((o) => o.sortOrder !== undefined)
  @IsInt()
  sortOrder?: number;

  @ApiPropertyOptional()
  @ValidateIf((o) => o.isActive !== undefined)
  @IsBoolean()
  isActive?: boolean;

  @ApiPropertyOptional({ nullable: true })
  @IsOptional()
  @IsDateString({}, { message: 'startsAt doit être une date ISO 8601' })
  startsAt?: string | null;

  @ApiPropertyOptional({ nullable: true })
  @IsOptional()
  @IsDateString({}, { message: 'endsAt doit être une date ISO 8601' })
  endsAt?: string | null;
}
