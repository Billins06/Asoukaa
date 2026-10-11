import {
  IsEmail,
  IsString,
  IsOptional,
  IsEnum,
  MinLength,
  MaxLength,
  Matches,
  IsNotEmpty,
} from 'class-validator';
import { Transform } from 'class-transformer';
import { UserRoleEnum } from '../entities/user-role.entity';

// ⚠️ Réservé aux admins (POST /users) : crée un compte directement
// (isVerified=true, isActive=true) sans passer par l'OTP d'inscription,
// puisque c'est l'admin qui vouche pour ce compte.
export class AdminCreateUserDto {

  @IsNotEmpty({ message: 'Le prénom est obligatoire' })
  @IsString()
  @MaxLength(100)
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
  @Transform(({ value }) => value?.toLowerCase().trim())
  email: string;

  @IsNotEmpty({ message: 'Le téléphone est obligatoire' })
  @IsString()
  @Matches(/^(\+?[0-9]{8,15})$/, { message: 'Format de téléphone invalide' })
  phone: string;

  @IsNotEmpty({ message: 'Le mot de passe est obligatoire' })
  @IsString()
  @MinLength(8, { message: 'Le mot de passe doit contenir au moins 8 caractères' })
  @MaxLength(64, { message: 'Le mot de passe ne peut pas dépasser 64 caractères' })
  @Matches(
    /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^a-zA-Z0-9]).+$/,
    { message: 'Le mot de passe doit contenir au moins une majuscule, une minuscule, un chiffre et un caractère spécial' }
  )
  password: string;

  // Rôle initial du compte (client par défaut). Un admin ne peut assigner
  // ici que les rôles "marketplace" classiques — pas ADMIN/SUPERADMIN,
  // qui passent par le module Admins dédié (CreateAdminDto).
  @IsOptional()
  @IsEnum(UserRoleEnum, { message: 'Rôle invalide' })
  role?: UserRoleEnum;
}
