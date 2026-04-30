import {
  IsString,
  IsNotEmpty,
  MaxLength,
} from 'class-validator';
import { Transform } from 'class-transformer';

export class LoginDto {

  // Accepte email OU numéro de téléphone
  // La vérification du format se fait dans le service
  @IsNotEmpty({ message: 'L\'identifiant est obligatoire' })
  @IsString()
  @MaxLength(255)
  @Transform(({ value }) => value?.toLowerCase().trim())
  identifier: string;

  @IsNotEmpty({ message: 'Le mot de passe est obligatoire' })
  @IsString()
  @MaxLength(64)
  password: string;
}