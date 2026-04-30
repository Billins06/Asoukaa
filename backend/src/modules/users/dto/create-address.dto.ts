import {
  IsString,
  IsNotEmpty,
  IsOptional,
  IsBoolean,
  MaxLength,
  Matches,
} from 'class-validator';
import { Transform } from 'class-transformer';

export class CreateAddressDto {

  @IsNotEmpty({ message: 'Le libellé est obligatoire' })
  @IsString()
  @MaxLength(100)
  @Transform(({ value }) => value?.trim())
  label: string;

  @IsNotEmpty({ message: 'Le nom du destinataire est obligatoire' })
  @IsString()
  @MaxLength(200)
  @Transform(({ value }) => value?.trim())
  nom_destinataire: string;

  @IsNotEmpty({ message: 'Le téléphone du destinataire est obligatoire' })
  @Matches(/^(\+?[0-9]{8,15})$/, { message: 'Format de téléphone invalide' })
  phone_destinataire: string;

  @IsNotEmpty({ message: 'Le quartier est obligatoire' })
  @IsString()
  @Transform(({ value }) => value?.trim())
  quartier: string;

  @IsNotEmpty({ message: 'La ville est obligatoire' })
  @IsString()
  @MaxLength(100)
  @Transform(({ value }) => value?.trim())
  ville: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  country?: string;

  @IsOptional()
  @IsBoolean()
  isDefault?: boolean;
}