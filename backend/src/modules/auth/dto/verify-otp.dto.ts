import {
  IsString,
  Matches,
  IsNotEmpty,
  Length,
  IsEnum,
  IsEmail,
} from 'class-validator';
import { Transform } from 'class-transformer';
import { OtpType } from '../entities/otp-code.entity';

export class VerifyOtpDto {

  @IsNotEmpty()
  @IsEmail({}, { message: 'Format email invalide' })
  @Transform(({ value }) => value?.toLowerCase().trim())
  email: string;

  @IsNotEmpty({ message: 'Le code OTP est obligatoire' })
  @IsString()
  // Le code fait exactement 6 chiffres
  @Length(6, 6, { message: 'Le code OTP doit contenir exactement 6 chiffres' })
  @Matches(/^[0-9]{6}$/, { message: 'Le code OTP ne doit contenir que des chiffres' })
  code: string;

  @IsNotEmpty()
  @IsEnum(OtpType, { message: 'Type OTP invalide' })
  type: OtpType;
}