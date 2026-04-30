import {
  Equals,
  IsBoolean,
  IsEnum,
  IsNotEmpty,
  IsString,
  Matches,
  MaxLength,
} from 'class-validator';
import { Transform } from 'class-transformer';
import {
  Availability,
  VehicleType,
} from '../../users/entities/delivery-agent-profile.entity';

export class SubmitAgentProfileDto {
  @IsNotEmpty()
  @IsEnum(VehicleType, { message: "Type d'engin invalide" })
  vehicleType: VehicleType;

  @IsNotEmpty()
  @IsEnum(Availability, { message: 'Disponibilite invalide' })
  availability: Availability;

  @IsNotEmpty({ message: 'La ville est obligatoire' })
  @IsString()
  @MaxLength(100)
  @Transform(({ value }) => value?.trim())
  ville: string;

  @IsNotEmpty({ message: 'Le quartier est obligatoire' })
  @IsString()
  @MaxLength(100)
  @Transform(({ value }) => value?.trim())
  quartier: string;

  @IsNotEmpty({ message: "L'adresse precise est obligatoire" })
  @IsString()
  @Transform(({ value }) => value?.trim())
  preciseAddress: string;

  @IsNotEmpty({ message: "La piece d'identite est obligatoire" })
  @IsString()
  @MaxLength(500)
  idDocumentUrl: string;

  @IsNotEmpty({ message: 'Le selfie est obligatoire' })
  @IsString()
  @MaxLength(500)
  selfieUrl: string;

  @IsNotEmpty({ message: "La photo de l'engin est obligatoire" })
  @IsString()
  @MaxLength(500)
  vehiclePhotoUrl: string;

  @IsNotEmpty({ message: 'Le numero de plaque est obligatoire' })
  @IsString()
  @MaxLength(50)
  @Matches(/^[A-Z0-9\s\-]{3,20}$/i, { message: 'Numero de plaque invalide' })
  licensePlate: string;

  @IsBoolean()
  @Equals(true, { message: "Vous devez accepter les conditions d'utilisation" })
  termsAccepted: boolean;

  @IsBoolean()
  @Equals(true, { message: 'Vous devez accepter les penalites en cas de fraude' })
  fraudPenaltiesAccepted: boolean;
}
