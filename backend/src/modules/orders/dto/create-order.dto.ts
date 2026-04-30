import {
  IsUUID,
  IsOptional,
  IsString,
  IsNotEmpty,
} from 'class-validator';
import { Transform } from 'class-transformer';

export class CreateOrderDto {

  @IsNotEmpty({ message: 'L\'adresse de livraison est obligatoire' })
  @IsUUID('4', { message: 'ID adresse invalide' })
  addressId: string;

  // Instructions laissées par le client
  @IsOptional()
  @IsString()
  @Transform(({ value }) => value?.trim())
  instructions?: string;

  // Coupon optionnel
  @IsOptional()
  @IsString()
  @Transform(({ value }) => value?.trim().toUpperCase())
  couponCode?: string;
}