import { IsEmail, IsNotEmpty, IsString, Matches, MaxLength } from 'class-validator';
import { Transform } from 'class-transformer';

export class RequestEmailChangeDto {

  // Normalisée (trim + minuscules) AVANT validation, comme VerifyOtpDto.
  // 255 = taille de la colonne users.email.
  @IsNotEmpty({ message: 'La nouvelle adresse email est obligatoire' })
  @Transform(({ value }) =>
    typeof value === 'string' ? value.trim().toLowerCase() : value,
  )
  @IsString({ message: 'Format email invalide' })
  @MaxLength(255, { message: "L'adresse email est trop longue (255 caractères maximum)" })
  @IsEmail({}, { message: 'Format email invalide' })
  // Garde-fou en plus d'IsEmail : refuse espaces, guillemets, chevrons,
  // parenthèses, virgules, points-virgules, deux-points et antislash, qui
  // permettraient des adresses exotiques (injection d'en-têtes SMTP,
  // « nom <adresse> », listes d'adresses) dans le champ « à » du mail.
  @Matches(/^[^\s"<>(),;:\\]+@[^\s"<>(),;:\\]+$/, { message: 'Format email invalide' })
  newEmail: string;

  // Plafond de longueur : évite d'envoyer une chaîne énorme à bcrypt.
  @IsNotEmpty({ message: 'Le mot de passe actuel est obligatoire' })
  @IsString()
  @MaxLength(200)
  currentPassword: string;
}
