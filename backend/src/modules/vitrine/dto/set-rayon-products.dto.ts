import {
  IsArray,
  ArrayMaxSize,
  ArrayUnique,
  IsUUID,
} from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

// Remplacement complet de la liste des produits d'un rayon
// (PUT /admin/vitrine/rayons/:id/products). L'ordre du tableau devient
// l'ordre d'affichage (sortOrder). Tableau vide = rayon vidé.
export class SetRayonProductsDto {
  @ApiProperty({ type: [String], description: 'Ids produits dans l\'ordre voulu (max 200)' })
  @IsArray()
  @ArrayMaxSize(200, { message: 'Un rayon ne peut pas contenir plus de 200 produits' })
  @ArrayUnique({ message: 'La liste contient des produits en double' })
  @IsUUID('all', { each: true, message: 'Chaque id produit doit être un UUID' })
  productIds: string[];
}
