import { IsBoolean, IsNotEmpty, IsOptional, MaxLength } from 'class-validator';
import { IsAppUrl } from '../../../common/validators/is-app-url.decorator';

// POST /products/:id/images. Avant, le corps était typé « en ligne » dans le
// contrôleur, donc NON validé : n'importe quelle chaîne était enregistrée comme
// URL d'image (y compris `javascript:...`).
// Ici : URL http(s) uniquement (IsAppUrl), 500 caractères max (taille de la
// colonne). Le service vérifie en plus que le fichier vient de NOTRE stockage
// (UploadService.assertIsOwnUploadUrl : type « products », ou
// « product-videos » pour une vidéo).
export class AddProductImageDto {

  @IsNotEmpty({ message: 'L\'URL de l\'image est obligatoire' })
  @IsAppUrl({ message: 'URL image invalide (http ou https uniquement)' })
  @MaxLength(500)
  imageUrl: string;

  @IsOptional()
  @IsBoolean()
  isPrimary?: boolean;

  @IsOptional()
  @IsBoolean()
  isVideo?: boolean;
}
