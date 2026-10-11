import { IsDateString, IsNotEmpty } from 'class-validator';

// Purge manuelle des logs : supprime tout ce qui est antérieur à beforeDate
// (date ISO 8601, ex. "2026-01-31" ou "2026-01-31T00:00:00Z").
export class PurgeLogsDto {
  @IsNotEmpty({ message: 'beforeDate est obligatoire' })
  @IsDateString({}, { message: 'beforeDate doit être une date ISO 8601 valide' })
  beforeDate: string;
}
