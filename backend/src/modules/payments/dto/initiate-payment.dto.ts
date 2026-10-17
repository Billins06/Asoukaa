import {
  IsEnum,
  IsIn,
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

  // ⚠️ Pour l'instant SEUL Mobile Money est géré de bout en bout (stock,
  // commission, vendeur). `cash_on_delivery` et `card` restent dans l'enum
  // PaymentMethod (des données existantes peuvent les contenir) mais ne sont
  // plus acceptés EN ENTRÉE.
  @IsNotEmpty({ message: 'La méthode de paiement est obligatoire' })
  @IsEnum(PaymentMethod, { message: 'Méthode de paiement invalide' })
  @IsIn([PaymentMethod.MOBILE_MONEY], {
    message:
      'Seul le paiement par Mobile Money (MTN ou Moov) est disponible pour le moment. '
      + 'Le paiement à la livraison et par carte ne sont pas encore ouverts.',
  })
  method: PaymentMethod;

  // Opérateur obligatoire si Mobile Money
  @ValidateIf(o => o.method === PaymentMethod.MOBILE_MONEY)
  @IsNotEmpty({ message: 'L\'opérateur est obligatoire pour Mobile Money' })
  @IsEnum(PaymentOperator, { message: 'Opérateur invalide' })
  @IsIn([PaymentOperator.MTN, PaymentOperator.MOOV], {
    message:
      'Opérateur non pris en charge : seuls MTN et Moov sont disponibles pour le moment.',
  })
  operator?: PaymentOperator;

  // Numéro de téléphone pour Mobile Money
  @ValidateIf(o => o.method === PaymentMethod.MOBILE_MONEY)
  @IsNotEmpty({ message: 'Le numéro de téléphone est obligatoire' })
  @Matches(/^(\+?[0-9]{8,15})$/, { message: 'Numéro de téléphone invalide' })
  phoneNumber?: string;
}