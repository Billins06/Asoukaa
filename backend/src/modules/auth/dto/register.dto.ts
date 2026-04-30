import {
  IsEmail,
  IsString,
  MinLength,
  MaxLength,
  Matches,
  IsNotEmpty,
} from 'class-validator';
import { Transform } from 'class-transformer';

export class RegisterDto {

  @IsNotEmpty({ message: 'Le prénom est obligatoire' })
  @IsString()
  @MaxLength(100, { message: 'Le prénom ne peut pas dépasser 100 caractères' })
  // Transform → supprime les espaces inutiles avant/après
  @Transform(({ value }) => value?.trim())
  prenom: string;

  @IsNotEmpty({ message: 'Le nom est obligatoire' })
  @IsString()
  @MaxLength(100)
  @Transform(({ value }) => value?.trim())
  name: string;

  @IsNotEmpty({ message: 'L\'email est obligatoire' })
  @IsEmail({}, { message: 'Format email invalide' })
  @MaxLength(255)
  // Transform → met en minuscules pour éviter les doublons
  // Ex: "Jean@Gmail.COM" et "jean@gmail.com" = même email
  @Transform(({ value }) => value?.toLowerCase().trim())
  email: string;

  @IsNotEmpty({ message: 'Le téléphone est obligatoire' })
  @IsString()
  // Regex Bénin et pays voisins : accepte +229, +225, +221, etc.
  // ou numéro local à 8 chiffres
  @Matches(/^(\+?[0-9]{8,15})$/, {
    message: 'Format de téléphone invalide',
  })
  phone: string;

  @IsNotEmpty({ message: 'Le mot de passe est obligatoire' })
  @IsString()
  @MinLength(8, { message: 'Le mot de passe doit contenir au moins 8 caractères' })
  @MaxLength(64, { message: 'Le mot de passe ne peut pas dépasser 64 caractères' })
  // ⚠️ PRODUCTION : exiger au moins une majuscule, un chiffre et un caractère spécial
  @Matches(
    /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^a-zA-Z0-9]).+$/,
    { message: 'Le mot de passe doit contenir au moins une majuscule, une minuscule, un chiffre et un caractère spécial' }
  )
  password: string;
}