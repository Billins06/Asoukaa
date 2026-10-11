import {
  IsEmail,
  IsString,
  IsOptional,
  MaxLength,
  Matches,
} from 'class-validator';
import { Transform } from 'class-transformer';

// ⚠️ Réservé aux admins (PATCH /users/:id) : modification partielle des
// informations d'identité d'un utilisateur. Le blocage/déblocage reste
// géré séparément par /users/:id/block et /users/:id/unblock, et le mot
// de passe n'est jamais modifiable ici (l'utilisateur garde la main sur
// le sien via /users/me/password).
export class AdminUpdateUserDto {

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
  @IsEmail({}, { message: 'Format email invalide' })
  @MaxLength(255)
  @Transform(({ value }) => value?.toLowerCase().trim())
  email?: string;

  @IsOptional()
  @Matches(/^(\+?[0-9]{8,15})$/, { message: 'Format de téléphone invalide' })
  phone?: string;
}
