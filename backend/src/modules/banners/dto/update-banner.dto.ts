import {
  IsString,
  MaxLength,
  IsOptional,
  IsEnum,
  IsInt,
  Min,
  Max,
  IsBoolean,
  IsDateString,
  IsUUID,
  IsNotEmpty,
  ValidateIf,
  IsArray,
  ArrayMinSize,
  ArrayMaxSize,
  ArrayUnique,
} from 'class-validator';
import { Transform } from 'class-transformer';
import { ApiPropertyOptional, ApiProperty } from '@nestjs/swagger';
import { BannerTargetType } from '../entities/home-banner.entity';
import { IsAppUrl } from '../../../common/validators/is-app-url.decorator';

const emptyToNull = ({ value }: { value: unknown }) => {
  if (typeof value !== 'string') return value;
  const t = value.trim();
  return t === '' ? null : t;
};

// Modification partielle (PATCH /admin/banners/:id).
// ⚠️ titre / sousTitre / targetId / targetUrl / startsAt / endsAt acceptent
// null (= vider). Les champs NOT NULL en base utilisent @ValidateIf(!== undefined)
// pour que null soit refusé au lieu de produire un UPDATE ... SET x = NULL.
export class UpdateBannerDto {
  @ApiPropertyOptional()
  @ValidateIf((o) => o.imageUrl !== undefined)
  @IsAppUrl({ message: 'URL image invalide' })
  @MaxLength(500)
  imageUrl?: string;

  @ApiPropertyOptional({ nullable: true })
  @IsOptional()
  @Transform(emptyToNull)
  @IsString()
  @MaxLength(120)
  titre?: string | null;

  @ApiPropertyOptional({ nullable: true })
  @IsOptional()
  @Transform(emptyToNull)
  @IsString()
  @MaxLength(200)
  sousTitre?: string | null;

  @ApiPropertyOptional({ enum: BannerTargetType })
  @ValidateIf((o) => o.targetType !== undefined)
  @IsEnum(BannerTargetType, { message: 'Cible invalide (category, product, shop, link)' })
  targetType?: BannerTargetType;

  @ApiPropertyOptional({ nullable: true })
  @IsOptional()
  @Transform(emptyToNull)
  @IsUUID('all', { message: 'targetId doit être un UUID' })
  targetId?: string | null;

  @ApiPropertyOptional({ nullable: true })
  @IsOptional()
  @Transform(emptyToNull)
  @IsString()
  @IsNotEmpty()
  @MaxLength(500)
  targetUrl?: string | null;

  @ApiPropertyOptional({ minimum: 2, maximum: 30 })
  @ValidateIf((o) => o.durationSeconds !== undefined)
  @IsInt({ message: 'La durée doit être un nombre entier de secondes' })
  @Min(2, { message: 'La durée minimale est de 2 secondes' })
  @Max(30, { message: 'La durée maximale est de 30 secondes' })
  durationSeconds?: number;

  @ApiPropertyOptional()
  @ValidateIf((o) => o.sortOrder !== undefined)
  @IsInt()
  @Min(0)
  @Max(100000)
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

// PUT /admin/banners/order
export class ReorderBannersDto {
  @ApiProperty({ type: [String], description: 'Ids des bannières dans le nouvel ordre' })
  @IsArray({ message: 'ids doit être un tableau' })
  @ArrayMinSize(1)
  @ArrayMaxSize(200)
  @ArrayUnique({ message: 'La liste contient des identifiants en double' })
  @IsUUID('all', { each: true, message: 'Chaque id doit être un UUID' })
  ids: string[];
}
