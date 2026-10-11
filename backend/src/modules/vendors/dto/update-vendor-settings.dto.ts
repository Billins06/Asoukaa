import { ApiProperty } from '@nestjs/swagger';
import { IsBoolean } from 'class-validator';

// Réglages du vendeur : PATCH /vendors/me/settings.
// Seul « Boutique visible » existe. Pas d'« acceptation automatique » ni de
// « mode vacances » : toute autre clé est rejetée par le ValidationPipe
// global (whitelist + forbidNonWhitelisted).
export class UpdateVendorSettingsDto {
  @ApiProperty({
    description:
      'true = boutique visible des acheteurs ; false = masquée (le vendeur la voit toujours)',
  })
  @IsBoolean({ message: 'shopVisible doit être un booléen (true ou false)' })
  shopVisible: boolean;
}
