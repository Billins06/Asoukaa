import { IsNotEmpty, IsString, MaxLength } from 'class-validator';

// Cas C — le client conteste avoir reçu le colis, dans le délai de
// 3 jours suivant l'expédition. Bloque la confirmation automatique et
// la libération du paiement au vendeur, en attente d'un arbitrage
// côté admin.
export class OpenDisputeDto {

  @IsNotEmpty({ message: 'Le motif de la contestation est obligatoire' })
  @IsString()
  @MaxLength(1000)
  motif: string;
}
