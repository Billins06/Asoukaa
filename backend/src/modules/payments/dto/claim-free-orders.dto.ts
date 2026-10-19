import { ArrayMaxSize, ArrayMinSize, IsArray, IsUUID } from 'class-validator';

// Corps de POST /payments/free : validation d'un ou plusieurs livres numériques
// à 0 F (aucun paiement Mobile Money à faire).
export class ClaimFreeOrdersDto {
  @IsArray()
  @ArrayMinSize(1, { message: 'Au moins une commande est requise' })
  @ArrayMaxSize(20)
  @IsUUID('4', { each: true, message: 'ID commande invalide' })
  orderIds: string[];
}
