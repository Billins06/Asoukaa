import { IsOptional, IsNumber, Min, IsBoolean } from 'class-validator';

export class UpdateDeliveryZoneDto {

  @IsOptional()
  @IsNumber()
  @Min(0)
  fraisLivraison?: number;

  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}
