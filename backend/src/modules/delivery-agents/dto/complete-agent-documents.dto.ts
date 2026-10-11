import { IsOptional, IsString, MaxLength } from 'class-validator';

export class CompleteAgentDocumentsDto {
  @IsOptional()
  @IsString()
  @MaxLength(500)
  idDocumentUrl?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  selfieUrl?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  vehiclePhotoUrl?: string;
}
