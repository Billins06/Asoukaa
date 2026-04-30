import { IsEmail, IsNotEmpty, IsEnum } from 'class-validator';
import { Transform } from 'class-transformer';
import { OtpType } from '../entities/otp-code.entity';

export class ResendOtpDto {

  @IsNotEmpty()
  @IsEmail()
  @Transform(({ value }) => value?.toLowerCase().trim())
  email: string;

  @IsNotEmpty()
  @IsEnum(OtpType)
  type: OtpType;
}