import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsString,
  IsOptional,
  IsUUID,
  MaxLength,
} from 'class-validator';
import { IsAppUrl } from '../../../common/validators/is-app-url.decorator';
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

  // Catégories de la plateforme (1 à 5) ; prioritaire sur activityType.
  @IsOptional()
  @IsArray()
  @ArrayMinSize(1, { message: 'Choisissez au moins une catégorie' })
  @ArrayMaxSize(5, { message: 'Vous pouvez choisir 5 catégories au maximum' })
  @IsUUID('all', { each: true, message: 'Chaque catégorie doit être un identifiant valide' })
  categoryIds?: string[];

  @IsOptional()
  @IsString()
  @Transform(({ value }) => value?.trim())
  description?: string;

  // ⚠️ Ces champs ne sont accessibles qu'APRÈS validation
  // Le service doit vérifier que status === 'approved'
  // avant d'autoriser la modification de ces champs
  @IsOptional()
  @IsAppUrl({ message: 'URL logo invalide' })
  @MaxLength(500)
  logoUrl?: string;

  @IsOptional()
  @IsAppUrl({ message: 'URL bannière invalide' })
  @MaxLength(500)
  bannerUrl?: string;
}