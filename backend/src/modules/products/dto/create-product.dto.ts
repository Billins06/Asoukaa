import {
  IsString,
  IsNotEmpty,
  IsOptional,
  IsNumber,
  IsPositive,
  IsEnum,
  IsBoolean,
  IsInt,
  Max,
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

  // 0 F est autorisé pour un livre numérique gratuit ; pour un produit
  // physique le prix doit rester strictement positif (contrôlé dans
  // ProductsService.create/update, qui connaît le type du produit).
  @IsNotEmpty({ message: 'Le prix de base est obligatoire' })
  @IsNumber({}, { message: 'Le prix doit être un nombre' })
  @Min(0, { message: 'Le prix ne peut pas être négatif' })
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

  // ─── Livre numérique (PDF) ─────────────────────────────
  // isDigital ne peut être défini qu'à la CRÉATION (un produit ne change pas de nature).
  @IsOptional()
  @IsBoolean()
  isDigital?: boolean;

  @IsOptional()
  @IsString()
  @MaxLength(200)
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  author?: string;

  @IsOptional()
  @IsInt({ message: 'Le nombre de pages doit être un nombre entier' })
  @Min(1, { message: 'Le nombre de pages doit être au moins 1' })
  @Max(20000)
  @Type(() => Number)
  pageCount?: number;

  @IsOptional()
  @IsString()
  @MaxLength(50)
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  language?: string;

  // Chemin du PDF renvoyé par POST /upload/ebooks (champ `path`) — jamais une URL.
  @IsOptional()
  @IsString()
  @MaxLength(500)
  filePath?: string;

  // Tags pour la recherche
  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  @MaxLength(100, { each: true })
  tags?: string[];
}