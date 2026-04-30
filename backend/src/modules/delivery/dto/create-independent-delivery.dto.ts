import {
  IsString,
  IsNotEmpty,
  IsOptional,
} from 'class-validator';
import { Transform } from 'class-transformer';

export class CreateIndependentDeliveryDto {

  @IsNotEmpty({ message: 'L\'adresse de départ est obligatoire' })
  @IsString()
  @Transform(({ value }) => value?.trim())
  pickupAddress: string;

  @IsNotEmpty({ message: 'L\'adresse de destination est obligatoire' })
  @IsString()
  @Transform(({ value }) => value?.trim())
  adresseLivraison: string;

  @IsOptional()
  @IsString()
  @Transform(({ value }) => value?.trim())
  packageDescription?: string;
}