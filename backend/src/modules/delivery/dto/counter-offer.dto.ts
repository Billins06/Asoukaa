import { IsInt, Min, Max } from 'class-validator';
import { Type } from 'class-transformer';
import { INDEPENDENT_MIN_PRICE, INDEPENDENT_MAX_PRICE } from './create-independent-delivery.dto';

export class CounterOfferDto {
  @Type(() => Number)
  @IsInt({ message: 'Le prix doit être un nombre entier (FCFA)' })
  @Min(INDEPENDENT_MIN_PRICE, { message: `Le prix minimum est de ${INDEPENDENT_MIN_PRICE} F` })
  @Max(INDEPENDENT_MAX_PRICE, { message: `Le prix maximum est de ${INDEPENDENT_MAX_PRICE} F` })
  price: number;
}
