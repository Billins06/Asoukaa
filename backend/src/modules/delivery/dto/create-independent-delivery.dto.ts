import {
  IsString,
  IsNotEmpty,
  IsOptional,
  IsEnum,
  IsInt,
  Min,
  Max,
  MaxLength,
} from 'class-validator';
import { Transform, Type } from 'class-transformer';
import { IndependentDelay } from '../entities/independent-delivery.entity';

export const INDEPENDENT_MIN_PRICE = 500;
export const INDEPENDENT_MAX_PRICE = 500000;

export class CreateIndependentDeliveryDto {

  @IsNotEmpty({ message: 'L\'adresse de départ est obligatoire' })
  @IsString()
  @MaxLength(500)
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  pickupAddress: string;

  @IsNotEmpty({ message: 'L\'adresse de destination est obligatoire' })
  @IsString()
  @MaxLength(500)
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  adresseLivraison: string;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  packageDescription?: string;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  notes?: string;

  @IsEnum(IndependentDelay, { message: 'Délai invalide (normal, urgent ou express)' })
  delai: IndependentDelay;

  @Type(() => Number)
  @IsInt({ message: 'Le prix doit être un nombre entier (FCFA)' })
  @Min(INDEPENDENT_MIN_PRICE, { message: `Le prix minimum est de ${INDEPENDENT_MIN_PRICE} F` })
  @Max(INDEPENDENT_MAX_PRICE, { message: `Le prix maximum est de ${INDEPENDENT_MAX_PRICE} F` })
  proposedPrice: number;
}
