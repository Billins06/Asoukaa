import {
  Equals,
  IsBoolean,
  IsNotEmpty,
  IsString,
  MaxLength,
} from 'class-validator';
import { Transform } from 'class-transformer';

export class SubmitVendorProfileDto {
  @IsNotEmpty({ message: "Le nom de la boutique est obligatoire" })
  @IsString()
  @MaxLength(255)
  @Transform(({ value }) => value?.trim())
  shopName: string;

  @IsNotEmpty({ message: "L'adresse de la boutique est obligatoire" })
  @IsString()
  @Transform(({ value }) => value?.trim())
  shopAddress: string;

  @IsNotEmpty({ message: "Le type d'activite est obligatoire" })
  @IsString()
  @MaxLength(100)
  @Transform(({ value }) => value?.trim())
  activityType: string;

  @IsNotEmpty({ message: 'La description est obligatoire' })
  @IsString()
  @Transform(({ value }) => value?.trim())
  description: string;

  @IsNotEmpty({ message: "La piece d'identite est obligatoire" })
  @IsString()
  @MaxLength(500)
  idDocumentUrl: string;

  @IsNotEmpty({ message: 'Le selfie est obligatoire' })
  @IsString()
  @MaxLength(500)
  selfieUrl: string;

  @IsNotEmpty({ message: 'Les produits exemples sont obligatoires' })
  @IsString({ each: true })
  @MaxLength(500, { each: true })
  sampleProductUrls: string[];

  @IsBoolean()
  @Equals(true, { message: "Vous devez accepter les conditions d'utilisation" })
  termsAccepted: boolean;

  @IsBoolean()
  @Equals(true, { message: 'Vous devez accepter les penalites en cas de fraude' })
  fraudPenaltiesAccepted: boolean;
}
