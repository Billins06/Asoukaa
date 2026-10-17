import {
  IsUUID,
  IsNotEmpty,
  IsString,
  IsNumber,
  IsPositive,
  IsOptional,
} from 'class-validator';
import { Type } from 'class-transformer';

export class RequestRefundDto {

  @IsNotEmpty()
  @IsUUID('4')
  orderId: string;

  @IsNotEmpty({ message: 'Le motif de remboursement est obligatoire' })
  @IsString()
  motif: string;

  // Le montant est fixé par le serveur (livrée : part du vendeur ; annulée :
  // total payé hors livraison) : la valeur envoyée est ignorée.
  @IsOptional()
  @IsNumber()
  @IsPositive()
  @Type(() => Number)
  montantRemb?: number;
}