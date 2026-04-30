import {
  IsString,
  IsNotEmpty,
  IsOptional,
  MaxLength,
  IsUrl,
  IsBoolean,
} from 'class-validator';
import { Transform } from 'class-transformer';

export class CreatePartnerDto {

  @IsNotEmpty({ message: 'Le nom est obligatoire' })
  @IsString()
  @MaxLength(255)
  @Transform(({ value }) => value?.trim())
  part_name: string;

  @IsOptional()
  @IsUrl({}, { message: 'URL logo invalide' })
  @MaxLength(500)
  part_logoUrl?: string;

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