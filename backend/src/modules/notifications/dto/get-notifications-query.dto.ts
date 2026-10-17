import { ApiPropertyOptional } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsISO8601, IsOptional, IsString } from 'class-validator';

/**
 * Paramètres de GET /notifications. Tous optionnels.
 * (ValidationPipe global : whitelist + forbidNonWhitelisted → tout autre
 * paramètre est refusé.)
 */
export class GetNotificationsQueryDto {
  @ApiPropertyOptional({ description: "'true' = seulement les non lues" })
  @IsOptional()
  @IsString()
  unread?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  page?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  limit?: string;

  @ApiPropertyOptional({
    description:
      "Date ISO 8601 (ex. 2026-10-13T10:15:30.123Z) : ne renvoie que les "
      + "notifications créées STRICTEMENT après cet instant. Absent = comportement habituel.",
  })
  @IsOptional()
  // Dans une URL, un « + » (décalage +01:00) arrive décodé en espace : on le
  // rétablit avant la validation.
  @Transform(({ value }) =>
    typeof value === 'string'
      ? value.trim().replace(/ (\d{2}:?\d{2})$/, '+$1')
      : value,
  )
  @IsISO8601(
    { strict: true, strictSeparator: true },
    { message: 'since doit être une date ISO 8601 valide (ex. 2026-10-13T10:15:30.123Z)' },
  )
  since?: string;
}
