import {
  IsOptional,
  IsDateString,
  IsEnum,
} from 'class-validator';

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
}