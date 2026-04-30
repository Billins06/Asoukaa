import {
  IsUUID,
  IsNotEmpty,
  IsString,
  IsNumber,
  IsPositive,
} from 'class-validator';
import { Type } from 'class-transformer';

export class RequestRefundDto {

  @IsNotEmpty()
  @IsUUID('4')
  orderId: string;

  @IsNotEmpty({ message: 'Le motif de remboursement est obligatoire' })
  @IsString()
  motif: string;

  @IsNotEmpty()
  @IsNumber()
  @IsPositive()
  @Type(() => Number)
  montantRemb: number;
}