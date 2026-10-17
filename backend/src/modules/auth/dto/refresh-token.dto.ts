import { IsNotEmpty, IsString, MaxLength } from 'class-validator';

export class RefreshTokenDto {
  @IsNotEmpty({ message: 'Le jeton de rafraîchissement est obligatoire' })
  @IsString({ message: 'Le jeton de rafraîchissement doit être une chaîne' })
  @MaxLength(4096)
  refreshToken: string;
}
