import {
  IsString,
  IsNotEmpty,
  IsOptional,
  IsUUID,
  IsBoolean,
  IsInt,
  Min,
  MaxLength,
} from 'class-validator';
import { IsAppUrl } from '../../../common/validators/is-app-url.decorator';
import { Transform } from 'class-transformer';

export class CreateCategoryDto {

  @IsNotEmpty({ message: 'Le nom est obligatoire' })
  @IsString()
  @MaxLength(255)
  @Transform(({ value }) => value?.trim())
  name: string;

  // Nullable = catégorie racine (niveau 1)
  // ⚠️ Le service doit vérifier que le parent
  // n'est pas déjà au niveau 3 (sinon on dépasserait 3 niveaux)
  @IsOptional()
  @IsUUID('4', { message: 'parentId invalide' })
  parentId?: string;

  @IsOptional()
  @IsAppUrl({ message: 'URL image invalide' })
  @MaxLength(500)
  imageUrl?: string;

  @IsOptional()
  @IsInt()
  @Min(0)
  sortOrder?: number;

  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}