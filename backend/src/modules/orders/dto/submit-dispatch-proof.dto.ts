import { IsNotEmpty, IsString, MaxLength } from 'class-validator';

// Cas C — bus/taxi (zone Nord) : le vendeur photographie le colis /
// le transporteur au moment de la remise et déclare son état.
// Déclenche le passage à "Expédiée" et démarre le délai de 3 jours de
// confirmation automatique.
export class SubmitDispatchProofDto {

  @IsNotEmpty({ message: 'La photo du colis/transporteur est obligatoire' })
  @IsString()
  @MaxLength(500)
  photoUrl: string;

  @IsNotEmpty({ message: 'L\'état du colis est obligatoire' })
  @IsString()
  @MaxLength(500)
  etatColis: string;
}
