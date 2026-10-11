import { IsNumber, Min } from 'class-validator';

// [ADMIN] Quota minimum de retrait propre a UN vendeur.
// 0 = aucun minimum (valeur par defaut).
export class SetMinWithdrawalDto {

  @IsNumber({ maxDecimalPlaces: 2 }, { message: 'Montant invalide' })
  @Min(0, { message: 'Le minimum ne peut pas être négatif' })
  minWithdrawalAmount: number;
}
