import {
  IsString,
  IsOptional,
  MaxLength,
  Matches,
} from 'class-validator';
import { IsAppUrl } from '../../../common/validators/is-app-url.decorator';
import { Transform } from 'class-transformer';

// Tous les champs sont optionnels car c'est une mise à jour partielle
export class UpdateProfileDto {

  @IsOptional()
  @IsString()
  @MaxLength(100)
  @Transform(({ value }) => value?.trim())
  prenom?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  @Transform(({ value }) => value?.trim())
  name?: string;

  @IsOptional()
  @Matches(/^(\+?[0-9]{8,15})$/, { message: 'Format de téléphone invalide' })
  phone?: string;

  // ⚠️ L'URL de l'avatar est gérée par l'upload
  // Ce champ ne devrait pas être modifiable directement par le client
  // L'upload se fait via une route séparée
  // null (ou chaîne vide) = supprimer la photo de profil. @IsOptional laisse
  // passer null/undefined sans appliquer IsAppUrl ; la chaîne vide est
  // convertie en null avant validation.
  @IsOptional()
  @Transform(({ value }) => (value === '' ? null : value))
  @IsAppUrl({ message: 'URL avatar invalide' })
  @MaxLength(500)
  avatarUrl?: string | null;
}