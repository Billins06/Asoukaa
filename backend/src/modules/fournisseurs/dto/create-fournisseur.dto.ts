import {
  IsString,
  IsNotEmpty,
  IsOptional,
  IsEnum,
  IsInt,
  IsPositive,
  MaxLength,
  IsEmail,
  Matches,
} from 'class-validator';
import { Transform, Type } from 'class-transformer';
import { Currency } from '../entities/fournisseur.entity';

export class CreateFournisseurDto {

  @IsNotEmpty({ message: 'Le nom est obligatoire' })
  @IsString()
  @MaxLength(255)
  @Transform(({ value }) => value?.trim())
  four_name: string;

  @IsNotEmpty({ message: 'Le nom du contact est obligatoire' })
  @IsString()
  @MaxLength(200)
  @Transform(({ value }) => value?.trim())
  contactPerson: string;

  @IsOptional()
  @IsEmail({}, { message: 'Format email invalide' })
  @MaxLength(255)
  @Transform(({ value }) => value?.toLowerCase().trim())
  four_email?: string;

  @IsNotEmpty({ message: 'Le téléphone est obligatoire' })
  @Matches(/^(\+?[0-9]{8,15})$/, { message: 'Format téléphone invalide' })
  four_phone: string;

  @IsNotEmpty({ message: 'Le pays est obligatoire' })
  @IsString()
  @MaxLength(100)
  four_country: string;

  @IsNotEmpty({ message: 'La ville est obligatoire' })
  @IsString()
  @MaxLength(100)
  four_ville: string;

  @IsNotEmpty()
  @IsEnum(Currency, { message: 'Devise invalide' })
  currency: Currency;

  @IsOptional()
  @IsInt()
  @IsPositive()
  @Type(() => Number)
  delaiLivraison?: number;

  @IsOptional()
  @IsString()
  @Transform(({ value }) => value?.trim())
  notes?: string;
}