import {
  IsString,
  IsEmail,
  IsNotEmpty,
  Length,
  MinLength,
  MaxLength,
  Matches,
} from 'class-validator';
import { Transform } from 'class-transformer';

export class ResetPasswordDto {

  @IsNotEmpty()
  @IsEmail()
  @Transform(({ value }) => value?.toLowerCase().trim())
  email: string;

  @IsNotEmpty()
  @IsString()
  @Length(6, 6)
  @Matches(/^[0-9]{6}$/)
  code: string;

  @IsNotEmpty({ message: 'Le nouveau mot de passe est obligatoire' })
  @IsString()
  @MinLength(8)
  @MaxLength(64)
  @Matches(
    /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^a-zA-Z0-9]).+$/,
    { message: 'Le mot de passe doit contenir au moins une majuscule, une minuscule, un chiffre et un caractère spécial' }
  )
  newPassword: string;

  // Confirmation du mot de passe
  // ⚠️ La vérification newPassword === confirmPassword
  // se fait dans le service, pas dans le DTO
  @IsNotEmpty({ message: 'La confirmation du mot de passe est obligatoire' })
  @IsString()
  confirmPassword: string;
}