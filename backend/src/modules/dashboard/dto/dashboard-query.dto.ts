import {
  IsOptional,
  IsDateString,
  IsEnum,
  IsInt,
  Min,
  Max,
} from 'class-validator';
import { Type } from 'class-transformer';

export enum DashboardPeriod {
  TODAY  = 'today',
  WEEK   = 'week',
  MONTH  = 'month',
  YEAR   = 'year',
}

export class DashboardQueryDto {

  @IsOptional()
  @IsEnum(DashboardPeriod, { message: 'Période invalide' })
  period?: DashboardPeriod;

  @IsOptional()
  @IsDateString()
  startDate?: string;

  @IsOptional()
  @IsDateString()
  endDate?: string;

  // Nombre de lignes des classements (top produits / top vendeurs).
  // ⚠️ Doit être déclaré ici : ces routes reçoivent déjà ce DTO en @Query(),
  // et la validation globale (forbidNonWhitelisted) rejetait donc tout
  // `?limit=` avec une erreur 400.
  @IsOptional()
  @Type(() => Number)
  @IsInt({ message: 'limit doit être un entier' })
  @Min(1,  { message: 'limit doit être au moins 1' })
  @Max(50, { message: 'limit ne peut pas dépasser 50' })
  limit?: number;
}