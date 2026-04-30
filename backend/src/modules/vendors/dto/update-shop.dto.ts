import {
  IsString,
  IsOptional,
  MaxLength,
  IsUrl,
} from 'class-validator';
import { Transform } from 'class-transformer';

// Mise à jour de la boutique APRÈS validation
// Logo et bannière uniquement disponibles ici
export class UpdateShopDto {

  @IsOptional()
  @IsString()
  @MaxLength(255)
  @Transform(({ value }) => value?.trim())
  shopName?: string;

  @IsOptional()
  @IsString()
  @Transform(({ value }) => value?.trim())
  shopAddress?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  @Transform(({ value }) => value?.trim())
  activityType?: string;

  @IsOptional()
  @IsString()
  @Transform(({ value }) => value?.trim())
  description?: string;

  // ⚠️ Ces champs ne sont accessibles qu'APRÈS validation
  // Le service doit vérifier que status === 'approved'
  // avant d'autoriser la modification de ces champs
  @IsOptional()
  @IsUrl({}, { message: 'URL logo invalide' })
  @MaxLength(500)
  logoUrl?: string;

  @IsOptional()
  @IsUrl({}, { message: 'URL bannière invalide' })
  @MaxLength(500)
  bannerUrl?: string;
}