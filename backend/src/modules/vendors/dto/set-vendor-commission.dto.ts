import { IsIn, IsNumber, Max, Min, ValidateIf } from 'class-validator';
import { Transform, Type } from 'class-transformer';

/**
 * Commission d'un vendeur :
 *  - percent : % des produits (0 à 100) ;
 *  - fixed   : montant fixe PAR COMMANDE en FCFA ;
 *  - default : retour à la commission de la plateforme (10 %).
 */
export class SetVendorCommissionDto {
  @IsIn(['percent', 'fixed', 'default'], { message: 'type doit être percent, fixed ou default' })
  type: 'percent' | 'fixed' | 'default';

  @ValidateIf((o) => o.type !== 'default')
  // Une valeur vide, blanche ou booléenne ne doit pas devenir 0 en silence.
  @Transform(({ value }) =>
    (typeof value === 'string' && value.trim() === '') || typeof value === 'boolean' || Array.isArray(value)
      ? NaN
      : value,
  )
  @Type(() => Number)
  @IsNumber({ allowNaN: false, allowInfinity: false }, { message: 'La valeur doit être un nombre' })
  @Min(0, { message: 'La valeur ne peut pas être négative' })
  @Max(10000000, { message: 'Valeur trop grande' })
  value?: number;
}
