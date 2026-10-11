import {
  IsArray,
  ArrayMaxSize,
  ArrayUnique,
  IsBoolean,
  IsUUID,
} from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

// POST /admin/vitrine/best-shops
export class AddFeaturedShopDto {
  @ApiProperty({ description: 'Id du profil vendeur (vendor_profiles.id)' })
  @IsUUID('all', { message: 'vendorId doit être un UUID' })
  vendorId: string;
}

// PATCH /admin/vitrine/best-shops/:id
export class UpdateFeaturedShopDto {
  @ApiProperty({ description: 'true = affichée sur l\'accueil, false = masquée' })
  @IsBoolean({ message: 'isActive doit être un booléen' })
  isActive: boolean;
}

// PUT /admin/vitrine/best-shops/order
export class ReorderFeaturedShopsDto {
  @ApiProperty({ type: [String], description: 'TOUS les ids featured_shops, dans le nouvel ordre' })
  @IsArray({ message: 'ids doit être un tableau' })
  @ArrayMaxSize(20, { message: 'Maximum 20 boutiques' })
  @ArrayUnique({ message: 'La liste contient des identifiants en double' })
  @IsUUID('all', { each: true, message: 'Chaque id doit être un UUID' })
  ids: string[];
}
