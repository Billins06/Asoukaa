import {
  IsUUID,
  IsInt,
  IsPositive,
  IsNotEmpty,
} from 'class-validator';
import { Type } from 'class-transformer';

export class AddToCartDto {

  @IsNotEmpty({ message: 'La variante est obligatoire' })
  @IsUUID('4', { message: 'ID variante invalide' })
  variantId: string;

  @IsNotEmpty()
  @IsInt({ message: 'La quantité doit être un entier' })
  @IsPositive({ message: 'La quantité doit être supérieure à 0' })
  @Type(() => Number)
  quantity: number;
}