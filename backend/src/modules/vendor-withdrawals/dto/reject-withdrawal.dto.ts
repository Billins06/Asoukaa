import { IsNotEmpty, IsString, MaxLength } from 'class-validator';

// [ADMIN] Refus d'une demande de retrait : le motif est OBLIGATOIRE,
// il est renvoye au vendeur dans son historique.
export class RejectWithdrawalDto {

  @IsNotEmpty({ message: 'Le motif de refus est obligatoire' })
  @IsString()
  @MaxLength(500)
  motif: string;
}
