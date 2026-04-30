import {
  IsString,
  IsNotEmpty,
  MinLength,
  MaxLength,
  Matches,
} from 'class-validator';

export class ChangePasswordDto {

  @IsNotEmpty({ message: 'Le mot de passe actuel est obligatoire' })
  @IsString()
  currentPassword: string;

  @IsNotEmpty({ message: 'Le nouveau mot de passe est obligatoire' })
  @IsString()
  @MinLength(8)
  @MaxLength(64)
  @Matches(
    /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^a-zA-Z0-9]).+$/,
    {
      message:
        'Le mot de passe doit contenir au moins une majuscule, '
        + 'une minuscule, un chiffre et un caractère spécial',
    }
  )
  newPassword: string;

  @IsNotEmpty({ message: 'La confirmation est obligatoire' })
  @IsString()
  confirmPassword: string;
}