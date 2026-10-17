import {
  IsNotEmpty,
  IsNumber,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';
import { Transform, Type } from 'class-transformer';

// POST /coupons/validate. Avant, le corps était typé « en ligne » dans le
// contrôleur, donc NON validé : `{}` renvoyait un coupon actif au hasard
// (code compris), ce qui permettait de lister les codes.
export class ValidateCouponDto {

  // Code promo saisi par le client : 1 à 50 caractères, espaces retirés,
  // mis en majuscules (comme à la création d'un coupon).
  @IsNotEmpty({ message: 'Le code est obligatoire' })
  @IsString({ message: 'Le code doit être une chaîne de caractères' })
  @Transform(({ value }) =>
    typeof value === 'string' ? value.trim().toUpperCase() : value,
  )
  @MinLength(1, { message: 'Le code est obligatoire' })
  @MaxLength(50, { message: 'Code invalide' })
  code: string;

  // Sous-total du panier affiché par l'application (aperçu de la remise).
  // Facultatif : à défaut, le serveur calcule le sous-total du panier du
  // client. La remise réellement appliquée est TOUJOURS recalculée à la
  // création de la commande.
  @IsOptional()
  @Type(() => Number)
  @IsNumber({ allowNaN: false, allowInfinity: false })
  @Min(0)
  @Max(1_000_000_000)
  subtotal?: number;
}
