import { IsUUID, IsNotEmpty, IsOptional } from 'class-validator';

export class CreateConversationDto {

  @IsNotEmpty()
  @IsUUID('4', { message: 'ID vendeur invalide' })
  vendorId: string;

  @IsOptional()
  @IsUUID('4', { message: 'ID produit invalide' })
  productId?: string;
}