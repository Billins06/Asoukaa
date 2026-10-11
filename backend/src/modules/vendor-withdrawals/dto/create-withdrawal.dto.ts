import {
  IsNotEmpty,
  IsNumber,
  IsPositive,
  IsString,
  MaxLength,
  Matches,
} from 'class-validator';

// Demande de retrait creee par le VENDEUR lui-meme.
// Le vendorId n'est JAMAIS accepte depuis le client : il est deduit du
// token (req.user.id -> VendorProfile.userId) cote service.
export class CreateWithdrawalDto {

  @IsNotEmpty({ message: 'Le montant est obligatoire' })
  @IsNumber({ maxDecimalPlaces: 2 }, { message: 'Montant invalide' })
  @IsPositive({ message: 'Le montant doit être supérieur à 0' })
  montant: number;

  // Operateur Mobile Money (MTN, Moov, Wave...)
  @IsNotEmpty({ message: 'L\'opérateur Mobile Money est obligatoire' })
  @IsString()
  @MaxLength(50)
  paymentMethod: string;

  @IsNotEmpty({ message: 'Le numéro Mobile Money est obligatoire' })
  @Matches(/^(\+?[0-9]{8,15})$/, { message: 'Numéro Mobile Money invalide' })
  mobileNumber: string;
}
