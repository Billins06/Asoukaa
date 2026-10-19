import { IsIn, IsNotEmpty, Matches } from 'class-validator';

export class PayIndependentDeliveryDto {
  @IsNotEmpty({ message: 'L\'opérateur est obligatoire' })
  @IsIn(['MTN', 'Moov'], { message: 'Opérateur non pris en charge : MTN ou Moov uniquement' })
  operator: 'MTN' | 'Moov';

  @IsNotEmpty({ message: 'Le numéro de téléphone est obligatoire' })
  @Matches(/^(\+?[0-9]{8,15})$/, { message: 'Numéro de téléphone invalide' })
  phoneNumber: string;
}
