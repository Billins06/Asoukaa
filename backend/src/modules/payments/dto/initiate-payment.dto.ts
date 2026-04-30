import {
  IsEnum,
  IsNotEmpty,
  IsUUID,
  IsOptional,
  IsString,
  ValidateIf,
  Matches,
  MaxLength,
} from 'class-validator';
import {
  PaymentMethod,
  PaymentOperator,
} from '../entities/payment.entity';

export class InitiatePaymentDto {

  @IsNotEmpty()
  @IsUUID('4', { message: 'ID commande invalide' })
  orderId: string;

  @IsNotEmpty()
  @IsEnum(PaymentMethod, { message: 'Méthode de paiement invalide' })
  method: PaymentMethod;

  // Opérateur obligatoire si Mobile Money
  @ValidateIf(o => o.method === PaymentMethod.MOBILE_MONEY)
  @IsNotEmpty({ message: 'L\'opérateur est obligatoire pour Mobile Money' })
  @IsEnum(PaymentOperator)
  operator?: PaymentOperator;

  // Numéro de téléphone pour Mobile Money
  @ValidateIf(o => o.method === PaymentMethod.MOBILE_MONEY)
  @IsNotEmpty({ message: 'Le numéro de téléphone est obligatoire' })
  @Matches(/^(\+?[0-9]{8,15})$/, { message: 'Numéro de téléphone invalide' })
  phoneNumber?: string;
}