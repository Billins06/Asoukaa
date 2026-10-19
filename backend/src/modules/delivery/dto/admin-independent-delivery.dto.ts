import { IsIn, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';
import { Transform } from 'class-transformer';

const trim = ({ value }: { value: unknown }) => (typeof value === 'string' ? value.trim() : value);

/** Trancher un paiement « à vérifier » : l'argent est bien arrivé, ou non. */
export class AdminResolvePaymentDto {
  @IsIn(['paid', 'failed'], { message: 'outcome doit être « paid » ou « failed »' })
  outcome: 'paid' | 'failed';

  @IsOptional()
  @IsString()
  @MaxLength(500)
  @Transform(trim)
  note?: string;
}

/** Annulation d'une course par l'administration. */
export class AdminCancelIndependentDeliveryDto {
  @IsString()
  @MinLength(3, { message: 'Indiquez le motif (3 caractères minimum).' })
  @MaxLength(300)
  @Transform(trim)
  reason: string;
}

/** Remboursement effectué à la main (FeexPay / Mobile Money). */
export class AdminMarkRefundedDto {
  @IsOptional()
  @IsString()
  @MaxLength(500)
  @Transform(trim)
  note?: string;
}
