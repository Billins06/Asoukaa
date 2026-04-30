import {
  IsInt,
  IsPositive,
  IsNumber,
  IsOptional,
  Min,
} from 'class-validator';
import { Type } from 'class-transformer';

export class CreateTierPriceDto {

  @IsInt()
  @IsPositive({ message: 'La quantité minimale doit être positive' })
  @Type(() => Number)
  minQuantity: number;

  // Nullable = dernier palier (illimité)
  @IsOptional()
  @IsInt()
  @IsPositive()
  @Type(() => Number)
  maxQuantity?: number;

  @IsNumber()
  @IsPositive({ message: 'Le prix doit être positif' })
  @Type(() => Number)
  price: number;
}