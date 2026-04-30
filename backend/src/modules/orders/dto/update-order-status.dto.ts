import {
  IsEnum,
  IsOptional,
  IsString,
  ValidateIf,
  IsNotEmpty,
} from 'class-validator';
import { OrderStatus } from '../entities/order.entity';

export class UpdateOrderStatusDto {

  @IsNotEmpty()
  @IsEnum(OrderStatus, { message: 'Statut invalide' })
  status: OrderStatus;

  // Motif obligatoire uniquement si annulation
  @ValidateIf(o => o.status === OrderStatus.CANCELLED)
  @IsNotEmpty({ message: 'Le motif d\'annulation est obligatoire' })
  @IsString()
  motifAnnulation?: string;
}