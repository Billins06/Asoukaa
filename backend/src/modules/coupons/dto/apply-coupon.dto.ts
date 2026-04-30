import { IsString, IsNotEmpty, MaxLength } from 'class-validator';
import { Transform } from 'class-transformer';

export class ApplyCouponDto {

  @IsNotEmpty({ message: 'Le code coupon est obligatoire' })
  @IsString()
  @MaxLength(50)
  @Transform(({ value }) => value?.trim().toUpperCase())
  code: string;
}