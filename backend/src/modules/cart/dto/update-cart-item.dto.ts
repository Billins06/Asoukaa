import { IsInt, IsPositive, IsNotEmpty } from 'class-validator';
import { Type } from 'class-transformer';

export class UpdateCartItemDto {

  @IsNotEmpty()
  @IsInt()
  @IsPositive({ message: 'La quantité doit être supérieure à 0' })
  @Type(() => Number)
  quantity: number;
}