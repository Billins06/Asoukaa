import { IsNotEmpty, IsString, MaxLength } from 'class-validator';

// Cas C — le client confirme lui-même avoir reçu le colis à l'arrivée
// (gare, ou remise par le taxi), avec une photo. Déclenche "Livrée".
export class SubmitReceptionProofDto {

  @IsNotEmpty({ message: 'La photo du colis reçu est obligatoire' })
  @IsString()
  @MaxLength(500)
  photoUrl: string;
}
