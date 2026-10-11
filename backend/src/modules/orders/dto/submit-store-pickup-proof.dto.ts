import { IsNotEmpty, IsString, MaxLength } from 'class-validator';

// Cas B — retrait en boutique : le vendeur scanne le QR code affiché
// sur le téléphone du client venu récupérer sa commande. Déclenche
// directement le passage à "Livrée" (pas d'étape "Expédiée" pour ce
// chemin, le client repart avec le colis immédiatement).
export class SubmitStorePickupProofDto {

  @IsNotEmpty({ message: 'Le scan du QR code du client est obligatoire' })
  @IsString()
  @MaxLength(255)
  qrScanValue: string;
}
