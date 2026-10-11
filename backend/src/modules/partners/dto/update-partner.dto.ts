import {
  IsString,
  IsOptional,
  MaxLength,
  IsBoolean,
  IsUrl,
} from 'class-validator';
import { IsAppUrl } from '../../../common/validators/is-app-url.decorator';
import { Transform } from 'class-transformer';

export class UpdatePartnerDto {

  @IsOptional()
  @IsString()
  @MaxLength(255)
  @Transform(({ value }) => value?.trim())
  part_name?: string;

  @IsOptional()
  @IsAppUrl({ message: 'URL logo invalide' })
  @MaxLength(500)
  part_logoUrl?: string;

  // part_websiteUrl est un site externe saisi par un admin (jamais une URL
  // renvoyee par le service d'upload de l'appli) : @IsAppUrl (qui accepte
  // exprès les URL sans TLD type localhost) n'a pas lieu d'etre ici, on
  // garde la validation stricte habituelle.
  @IsOptional()
  @IsUrl({}, { message: 'URL site web invalide' })
  @MaxLength(500)
  part_websiteUrl?: string;

  @IsOptional()
  @IsString()
  @Transform(({ value }) => value?.trim())
  description?: string;

  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}
