import {
  IsString,
  IsNotEmpty,
  MaxLength,
  IsOptional,
  IsBoolean,
  ValidateIf,
} from 'class-validator';
import { Transform } from 'class-transformer';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsAppUrl } from '../../../common/validators/is-app-url.decorator';

const trim = ({ value }: { value: unknown }) =>
  typeof value === 'string' ? value.trim() : value;

// Création / mise à jour de l'unique bandeau d'accueil
// (PUT /admin/vitrine/bandeau). sousTitre / imageUrl : null = vider,
// absent = inchangé (à la création : null).
export class UpsertBandeauDto {
  @ApiProperty({ example: 'Bienvenue sur Asoukaa' })
  @Transform(trim)
  @IsString()
  @IsNotEmpty({ message: 'Le titre du bandeau est obligatoire' })
  @MaxLength(120)
  titre: string;

  @ApiPropertyOptional({ nullable: true })
  @IsOptional()
  @Transform(trim)
  @IsString()
  @MaxLength(200)
  sousTitre?: string | null;

  @ApiPropertyOptional({ nullable: true, description: 'URL renvoyée par POST /upload/vitrine' })
  @IsOptional()
  @IsAppUrl({ message: 'URL image invalide' })
  @MaxLength(500)
  imageUrl?: string | null;

  @ApiPropertyOptional({ default: true })
  @ValidateIf((o) => o.isActive !== undefined)
  @IsBoolean()
  isActive?: boolean;
}
