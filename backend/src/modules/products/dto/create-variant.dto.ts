import {
  IsString,
  IsNotEmpty,
  IsOptional,
  IsNumber,
  IsPositive,
  IsInt,
  Min,
  MaxLength,
  IsUrl,
} from 'class-validator';
import { Transform, Type } from 'class-transformer';

export class CreateVariantDto {

  @IsNotEmpty({ message: 'Le SKU est obligatoire' })
  @IsString()
  @MaxLength(100)
  @Transform(({ value }) => value?.trim().toUpperCase())
  sku: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  color?: string;

  @IsOptional()
  @IsString()
  @MaxLength(50)
  size?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  model?: string;

  @IsNotEmpty({ message: 'Le prix est obligatoire' })
  @IsNumber()
  @IsPositive({ message: 'Le prix doit être positif' })
  @Type(() => Number)
  price: number;

  @IsNotEmpty({ message: 'Le stock est obligatoire' })
  @IsInt()
  @Min(0, { message: 'Le stock ne peut pas être négatif' })
  @Type(() => Number)
  stockQuantity: number;

  // Seuil d'alerte stock faible
  @IsOptional()
  @IsInt()
  @Min(0)
  @Type(() => Number)
  lowStockAlert?: number;

  @IsOptional()
  @IsUrl({}, { message: 'URL image variante invalide' })
  @MaxLength(500)
  imageUrl?: string;
}