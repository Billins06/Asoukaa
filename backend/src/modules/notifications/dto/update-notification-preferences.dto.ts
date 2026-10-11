import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsBoolean, ValidateIf } from 'class-validator';

// Corps PARTIEL : seules les clés envoyées sont modifiées. Toute autre clé
// est rejetée (ValidationPipe global : whitelist + forbidNonWhitelisted) et
// seules des valeurs booléennes true/false sont acceptées (null aussi refusé).
const MSG = 'doit être un booléen (true ou false)';
const notUndefined = (_: unknown, value: unknown) => value !== undefined;

export class UpdateNotificationPreferencesDto {
  @ApiPropertyOptional({ description: 'Commandes & livraisons (acheteur)' })
  @ValidateIf(notUndefined)
  @IsBoolean({ message: `orders ${MSG}` })
  orders?: boolean;

  @ApiPropertyOptional({ description: 'Messages de chat' })
  @ValidateIf(notUndefined)
  @IsBoolean({ message: `messages ${MSG}` })
  messages?: boolean;

  @ApiPropertyOptional({ description: 'Paiements, retraits, gains' })
  @ValidateIf(notUndefined)
  @IsBoolean({ message: `payments ${MSG}` })
  payments?: boolean;

  @ApiPropertyOptional({ description: 'Promotions & offres' })
  @ValidateIf(notUndefined)
  @IsBoolean({ message: `promotions ${MSG}` })
  promotions?: boolean;

  @ApiPropertyOptional({ description: 'Nouvelles commandes reçues (vendeur)' })
  @ValidateIf(notUndefined)
  @IsBoolean({ message: `newOrders ${MSG}` })
  newOrders?: boolean;

  @ApiPropertyOptional({ description: 'Nouvelles livraisons proposées (livreur)' })
  @ValidateIf(notUndefined)
  @IsBoolean({ message: `newDeliveries ${MSG}` })
  newDeliveries?: boolean;
}
