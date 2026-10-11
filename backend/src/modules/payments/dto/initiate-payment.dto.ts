import {
  IsEnum,
  IsNotEmpty,
  IsUUID,
  IsOptional,
  IsString,
  IsArray,
  ArrayMinSize,
  ValidateIf,
  Matches,
  MaxLength,
} from 'class-validator';
import {
  PaymentMethod,
  PaymentOperator,
} from '../entities/payment.entity';

export class InitiatePaymentDto {

  // Cas normal : une seule commande (une boutique).
  @ValidateIf(o => !o.orderIds || o.orderIds.length === 0)
  @IsNotEmpty({ message: 'ID commande invalide' })
  @IsUUID('4', { message: 'ID commande invalide' })
  orderId?: string;

  // Cas panier multi-boutiques : plusieurs commandes créées ensemble
  // (une par boutique) mais un seul paiement client. Fourni à la place
  // de orderId.
  @IsOptional()
  @IsArray()
  @ArrayMinSize(2, { message: 'orderIds doit contenir au moins 2 commandes' })
  @IsUUID('4', { each: true, message: 'ID commande invalide dans orderIds' })
  orderIds?: string[];

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