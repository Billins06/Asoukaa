import {
  ArrayMaxSize,
  ArrayMinSize,
  Equals,
  IsArray,
  IsBoolean,
  IsNotEmpty,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
} from 'class-validator';
import { Transform } from 'class-transformer';
import { IsAppUrl } from '../../../common/validators/is-app-url.decorator';

export class SubmitVendorProfileDto {
  @IsNotEmpty({ message: "Le nom de la boutique est obligatoire" })
  @IsString()
  @MaxLength(255)
  @Transform(({ value }) => value?.trim())
  shopName: string;

  @IsNotEmpty({ message: "L'adresse de la boutique est obligatoire" })
  @IsString()
  @MaxLength(500)
  @Transform(({ value }) => value?.trim())
  shopAddress: string;

  // Ancien champ texte libre : encore accepté pour les anciennes versions
  // de l'appli (utilisé seulement si categoryIds est absent). Le service
  // exige l'un ou l'autre.
  @IsOptional()
  @IsString()
  @MaxLength(100)
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  activityType?: string;

  // Catégories de la plateforme (1 à 5), simple étiquette de la boutique.
  @IsOptional()
  @IsArray()
  @ArrayMinSize(1, { message: 'Choisissez au moins une catégorie' })
  @ArrayMaxSize(5, { message: 'Vous pouvez choisir 5 catégories au maximum' })
  @IsUUID('all', { each: true, message: 'Chaque catégorie doit être un identifiant valide' })
  categoryIds?: string[];

  @IsNotEmpty({ message: 'La description est obligatoire' })
  @IsString()
  @MaxLength(2000)
  @Transform(({ value }) => value?.trim())
  description: string;

  @IsOptional()
  @IsAppUrl({ message: 'URL de la pièce d\'identité invalide' })
  @MaxLength(500)
  idDocumentUrl?: string;

  @IsOptional()
  @IsAppUrl({ message: 'URL du selfie invalide' })
  @MaxLength(500)
  selfieUrl?: string;

  @IsOptional()
  @IsArray()
  @ArrayMaxSize(5, { message: 'Maximum 5 photos de produits' })
  @IsAppUrl({ each: true, message: 'URL de photo produit invalide' })
  @MaxLength(500, { each: true })
  sampleProductUrls?: string[];

  @IsBoolean()
  @Equals(true, { message: "Vous devez accepter les conditions d'utilisation" })
  termsAccepted: boolean;

  @IsBoolean()
  @Equals(true, { message: 'Vous devez accepter les penalites en cas de fraude' })
  fraudPenaltiesAccepted: boolean;
}
