import { IsNotEmpty, IsString, MaxLength } from 'class-validator';

// Cas A — preuve de ramassage : le livreur photographie le colis chez
// le vendeur et déclare son état. Déclenche automatiquement le
// passage de la commande à "Expédiée".
export class SubmitPickupProofDto {

  // URL renvoyée par POST /upload/proofs (jamais une URL externe —
  // voir UploadService.assertIsOwnUploadUrl).
  @IsNotEmpty({ message: 'La photo du colis est obligatoire' })
  @IsString()
  @MaxLength(500)
  photoUrl: string;

  @IsNotEmpty({ message: 'L\'état du colis est obligatoire' })
  @IsString()
  @MaxLength(500)
  etatColis: string;
}
