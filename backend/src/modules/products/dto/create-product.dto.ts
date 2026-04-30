import {
  IsString,
  IsNotEmpty,
  IsOptional,
  IsNumber,
  IsPositive,
  IsEnum,
  IsArray,
  IsUUID,
  MaxLength,
  Min,
  ArrayMinSize,
  ArrayMaxSize,
} from 'class-validator';
import { Transform, Type } from 'class-transformer';
import { ProductStatus } from '../entities/product.entity';

export class CreateProductDto {

  @IsNotEmpty({ message: 'Le nom du produit est obligatoire' })
  @IsString()
  @MaxLength(500)
  @Transform(({ value }) => value?.trim())
  prod_name: string;

  @IsNotEmpty({ message: 'La description est obligatoire' })
  @IsString()
  @Transform(({ value }) => value?.trim())
  description: string;

  @IsNotEmpty({ message: 'Le prix de base est obligatoire' })
  @IsNumber({}, { message: 'Le prix doit être un nombre' })
  @IsPositive({ message: 'Le prix doit être positif' })
  @Type(() => Number)
  basePrice: number;

  @IsOptional()
  @IsNumber()
  @IsPositive()
  @Type(() => Number)
  weight?: number;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  dimensions?: string;

  // Si non fourni → défaut DRAFT dans l'entité
  @IsOptional()
  @IsEnum(ProductStatus, { message: 'Statut invalide' })
  status?: ProductStatus;

  // Au moins une catégorie obligatoire
  @IsArray()
  @IsUUID('4', { each: true, message: 'ID catégorie invalide' })
  @ArrayMinSize(1, { message: 'Au moins une catégorie est requise' })
  categoryIds: string[];

  // Tags pour la recherche
  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  @MaxLength(100, { each: true })
  tags?: string[];
}