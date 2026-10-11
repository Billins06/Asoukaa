import { IsOptional, IsString, MaxLength } from 'class-validator';

// [ADMIN] Confirmation que le virement Mobile Money a bien ete effectue.
// La note est libre (reference du virement, remarque interne...).
export class MarkWithdrawalPaidDto {

  @IsOptional()
  @IsString()
  @MaxLength(500)
  noteAdmin?: string;
}
