import {
  IsUUID,
  IsOptional,
  IsString,
  IsNotEmpty,
  IsEnum,
} from 'class-validator';
import { Transform } from 'class-transformer';
import { OrderDeliveryMode, OrderTransportMode } from '../entities/order.entity';

export class CreateOrderDto {

  // Obligatoire dès qu'il y a au moins un produit PHYSIQUE dans le panier
  // (contrôlé dans OrdersService.createFromCart) ; inutile pour un panier
  // composé uniquement de livres numériques.
  @IsOptional()
  @IsUUID('4', { message: 'ID adresse invalide' })
  addressId?: string;

  // Le client choisit d'etre livre (defaut) ou de venir retirer en boutique
  @IsOptional()
  @IsEnum(OrderDeliveryMode, { message: 'Mode de livraison invalide' })
  deliveryMode?: OrderDeliveryMode;

  // Uniquement pour une commune du Nord (voir OrderTransportMode) : bus ou
  // taxi, choisi par le client au paiement. Prix identique dans les deux cas.
  @IsOptional()
  @IsEnum(OrderTransportMode, { message: 'Mode de transport invalide' })
  transportMode?: OrderTransportMode;

  // Instructions laissées par le client
  @IsOptional()
  @IsString()
  @Transform(({ value }) => value?.trim())
  instructions?: string;

  // Coupon optionnel
  @IsOptional()
  @IsString()
  @Transform(({ value }) => value?.trim().toUpperCase())
  couponCode?: string;
}