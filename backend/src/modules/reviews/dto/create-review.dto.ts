import {
  IsUUID,
  IsNotEmpty,
  IsInt,
  Min,
  Max,
  IsOptional,
  IsString,
} from 'class-validator';
import { Type, Transform } from 'class-transformer';

export class CreateReviewDto {

  @IsNotEmpty()
  @IsUUID('4', { message: 'ID produit invalide' })
  productId: string;

  @IsNotEmpty()
  @IsUUID('4', { message: 'ID commande invalide' })
  orderId: string;

  @IsNotEmpty({ message: 'La note est obligatoire' })
  @IsInt({ message: 'La note doit être un entier' })
  @Min(1, { message: 'La note minimale est 1' })
  @Max(5, { message: 'La note maximale est 5' })
  @Type(() => Number)
  notation: number;

  @IsOptional()
  @IsString()
  @Transform(({ value }) => value?.trim())
  comment?: string;
}