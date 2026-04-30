import {
  IsString,
  IsNotEmpty,
  MinLength,
  MaxLength,
  Matches,
} from 'class-validator';

export class SetAdminPasswordDto {

  // Token reçu par email
  @IsNotEmpty({ message: 'Le token est obligatoire' })
  @IsString()
  invitationToken: string;

  @IsNotEmpty({ message: 'Le mot de passe est obligatoire' })
  @IsString()
  @MinLength(8)
  @MaxLength(64)
  @Matches(
    /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^a-zA-Z0-9]).+$/,
    { message: 'Le mot de passe doit contenir au moins une majuscule, une minuscule, un chiffre et un caractère spécial' }
  )
  password: string;

  @IsNotEmpty()
  @IsString()
  confirmPassword: string;
}