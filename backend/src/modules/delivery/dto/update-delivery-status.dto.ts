import { IsEnum, IsNotEmpty } from 'class-validator';
import { DeliveryStatus } from '../entities/delivery.entity';

export class UpdateDeliveryStatusDto {

  @IsNotEmpty()
  @IsEnum(DeliveryStatus, { message: 'Statut de livraison invalide' })
  status: DeliveryStatus;
}