import {
  IsEnum,
  IsNotEmpty,
  IsString,
  ValidateIf,
  MaxLength,
  Matches,
} from 'class-validator';
import { PaymentMethod } from '../../users/entities/vendor-profile.entity';

export class UpdatePaymentSettingsDto {

  @IsNotEmpty()
  @IsEnum(PaymentMethod, { message: 'Méthode de paiement invalide' })
  paymentMethod: PaymentMethod;

  // Champs Mobile Money — obligatoires si paymentMethod = mobile_money
  @ValidateIf(o => o.paymentMethod === PaymentMethod.MOBILE_MONEY)
  @IsNotEmpty({ message: 'L\'opérateur est obligatoire pour Mobile Money' })
  @IsString()
  operator?: string; // MTN, Moov, Wave...

  @ValidateIf(o => o.paymentMethod === PaymentMethod.MOBILE_MONEY)
  @IsNotEmpty({ message: 'Le numéro Mobile Money est obligatoire' })
  @Matches(/^(\+?[0-9]{8,15})$/, { message: 'Numéro Mobile Money invalide' })
  mobileNumber?: string;

  // Champs Banque — obligatoires si paymentMethod = bank
  @ValidateIf(o => o.paymentMethod === PaymentMethod.BANK)
  @IsNotEmpty({ message: 'Le nom de la banque est obligatoire' })
  @IsString()
  @MaxLength(100)
  bankName?: string;

  @ValidateIf(o => o.paymentMethod === PaymentMethod.BANK)
  @IsNotEmpty({ message: 'Le numéro de compte est obligatoire' })
  @IsString()
  @MaxLength(50)
  accountNumber?: string;

  // Obligatoire dans les deux cas
  @IsNotEmpty({ message: 'Le nom du titulaire est obligatoire' })
  @IsString()
  @MaxLength(200)
  holderName: string;
}