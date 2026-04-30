import {
  IsArray,
  IsUUID,
  ArrayMinSize,
  IsOptional,
  IsBoolean,
} from 'class-validator';

export class MarkNotificationsReadDto {

  // Tableau d'IDs à marquer comme lus
  @IsArray()
  @IsUUID('4', { each: true })
  @ArrayMinSize(1)
  ids: string[];
}

// Pour marquer TOUTES les notifications comme lues
export class MarkAllReadDto {
  @IsOptional()
  @IsBoolean()
  markAll?: boolean;
}