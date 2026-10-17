import { IsEnum, IsNotEmpty, IsString, MaxLength } from 'class-validator';

// Issue d'un litige ouvert par le client (livraison bus/taxi « expediée »,
// voir OrdersService.openDispute) :
//  - 'rejete' : litige non fondé → le litige est clos, la commande reprend son
//    cours (confirmation automatique 3 jours après l'expédition, ou
//    confirmation du client) ;
//  - 'fonde'  : litige fondé → la commande est ANNULÉE (annulation admin :
//    stock restitué, remboursement manuel à faire si un paiement a réussi).
export enum DisputeDecision {
  REJECTED = 'rejete',
  FOUNDED  = 'fonde',
}

export class AdminCloseDisputeDto {

  @IsNotEmpty({ message: 'La décision est obligatoire (rejete ou fonde)' })
  @IsEnum(DisputeDecision, { message: 'Décision invalide (rejete ou fonde)' })
  decision: DisputeDecision;

  @IsNotEmpty({ message: 'Le motif / la note de clôture est obligatoire' })
  @IsString()
  @MaxLength(1000)
  note: string;
}
