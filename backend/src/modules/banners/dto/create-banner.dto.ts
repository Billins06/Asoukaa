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
} from 'class-validator';
import { Transform } from 'class-transformer';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { BannerTargetType } from '../entities/home-banner.entity';
import { IsAppUrl } from '../../../common/validators/is-app-url.decorator';

const trim = ({ value }: { value: unknown }) =>
  typeof value === 'string' ? value.trim() : value;

// Vide ('' ou espaces) => null : le formulaire envoie '' pour « aucun ».
const emptyToNull = ({ value }: { value: unknown }) => {
  if (typeof value !== 'string') return value;
  const t = value.trim();
  return t === '' ? null : t;
};

// Création d'une bannière d'accueil (POST /admin/banners).
// Cohérence cible/type (id ou lien, existence) vérifiée par le service.
export class CreateBannerDto {
  @ApiProperty({ description: 'URL renvoyée par POST /upload/vitrine' })
  @IsAppUrl({ message: 'URL image invalide' })
  @MaxLength(500)
  imageUrl: string;

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

  @ApiProperty({ enum: BannerTargetType })
  @IsEnum(BannerTargetType, { message: 'Cible invalide (category, product, shop, link)' })
  targetType: BannerTargetType;

  @ApiPropertyOptional({ nullable: true, description: 'Id de la catégorie / du produit / de la boutique' })
  @IsOptional()
  @Transform(emptyToNull)
  @IsUUID('all', { message: 'targetId doit être un UUID' })
  targetId?: string | null;

  @ApiPropertyOptional({ nullable: true, description: 'Lien externe (https uniquement)' })
  @IsOptional()
  @Transform(emptyToNull)
  @IsString()
  @IsNotEmpty()
  @MaxLength(500)
  targetUrl?: string | null;

  @ApiPropertyOptional({ default: 4, minimum: 2, maximum: 30 })
  @IsOptional()
  @IsInt({ message: 'La durée doit être un nombre entier de secondes' })
  @Min(2, { message: 'La durée minimale est de 2 secondes' })
  @Max(30, { message: 'La durée maximale est de 30 secondes' })
  durationSeconds?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(100000)
  sortOrder?: number;

  @ApiPropertyOptional({ default: true })
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;

  @ApiPropertyOptional({ nullable: true, description: 'Début de visibilité (ISO 8601)' })
  @IsOptional()
  @IsDateString({}, { message: 'startsAt doit être une date ISO 8601' })
  startsAt?: string | null;

  @ApiPropertyOptional({ nullable: true, description: 'Fin de visibilité (ISO 8601)' })
  @IsOptional()
  @IsDateString({}, { message: 'endsAt doit être une date ISO 8601' })
  endsAt?: string | null;
}
