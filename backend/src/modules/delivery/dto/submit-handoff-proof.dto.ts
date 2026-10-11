import {
  IsNotEmpty,
  IsString,
  IsNumber,
  Min,
  Max,
  MaxLength,
} from 'class-validator';

// Cas A — preuve de remise finale au client : le livreur scanne le QR
// code du client, sa position GPS est capturée au même instant (même
// action, pour prouver qu'il est bien avec le client), et le client
// signe directement sur l'écran du livreur. Déclenche "Livrée".
export class SubmitHandoffProofDto {

  @IsNotEmpty({ message: 'Le scan du QR code du client est obligatoire' })
  @IsString()
  @MaxLength(255)
  qrScanValue: string;

  @IsNotEmpty({ message: 'La position GPS est obligatoire' })
  @IsNumber()
  @Min(-90)
  @Max(90)
  latitude: number;

  @IsNotEmpty({ message: 'La position GPS est obligatoire' })
  @IsNumber()
  @Min(-180)
  @Max(180)
  longitude: number;

  @IsNotEmpty({ message: 'La signature du client est obligatoire' })
  @IsString()
  signatureData: string;
}
