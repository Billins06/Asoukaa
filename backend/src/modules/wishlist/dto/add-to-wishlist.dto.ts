import { IsUUID, IsNotEmpty } from 'class-validator';

export class AddToWishlistDto {

  @IsNotEmpty({ message: 'L\'ID du produit est obligatoire' })
  @IsUUID('4', { message: 'ID produit invalide' })
  productId: string;
}