import {
  IsString,
  IsNotEmpty,
  IsEnum,
  IsNumber,
  IsPositive,
  IsOptional,
  IsInt,
  Min,
  MaxLength,
  IsDateString,
  IsUUID,
  Max,
} from 'class-validator';
import { Transform, Type } from 'class-transformer';
import { CouponType } from '../entities/coupon.entity';

export class CreateCouponDto {

  @IsNotEmpty({ message: 'Le code est obligatoire' })
  @IsString()
  @MaxLength(50)
  @Transform(({ value }) => value?.trim().toUpperCase())
  code: string;

  @IsNotEmpty()
  @IsEnum(CouponType, { message: 'Type de coupon invalide' })
  type: CouponType;

  @IsNotEmpty({ message: 'La valeur est obligatoire' })
  @IsNumber()
  @IsPositive()
  // ⚠️ Si type = percentage, vérifier dans le service que value <= 100
  @Type(() => Number)
  value: number;

  @IsOptional()
  @IsNumber()
  @IsPositive()
  @Type(() => Number)
  minOrderAmount?: number;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Type(() => Number)
  maxUses?: number;

  @IsOptional()
  @IsDateString({}, { message: 'Format de date invalide' })
  expiresAt?: string;

  // Si renseigné = coupon limité à cette boutique
  // Si null = valable sur toute la plateforme
  @IsOptional()
  @IsUUID('4')
  vendorId?: string;
}