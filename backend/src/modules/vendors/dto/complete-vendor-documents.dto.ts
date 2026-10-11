import { ArrayMaxSize, IsArray, IsOptional, MaxLength } from 'class-validator';
import { IsAppUrl } from '../../../common/validators/is-app-url.decorator';

export class CompleteVendorDocumentsDto {
  @IsOptional()
  @IsAppUrl({ message: 'URL de la pièce d\'identité invalide' })
  @MaxLength(500)
  idDocumentUrl?: string;

  @IsOptional()
  @IsAppUrl({ message: 'URL du selfie invalide' })
  @MaxLength(500)
  selfieUrl?: string;

  @IsOptional()
  @IsArray()
  @ArrayMaxSize(5, { message: 'Maximum 5 photos de produits' })
  @IsAppUrl({ each: true, message: 'URL de photo produit invalide' })
  @MaxLength(500, { each: true })
  sampleProductUrls?: string[];
}
