import { IsEnum, IsNotEmpty } from 'class-validator';
import { IndependentDeliveryStatus } from '../entities/independent-delivery.entity';

export class UpdateIndependentDeliveryStatusDto {

  @IsNotEmpty({ message: 'Le statut est obligatoire' })
  @IsEnum(IndependentDeliveryStatus, { message: 'Statut de course express invalide' })
  status: IndependentDeliveryStatus;
}
