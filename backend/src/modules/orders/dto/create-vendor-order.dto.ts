import {
  IsString,
  IsNotEmpty,
  IsArray,
  IsUUID,
  IsInt,
  Min,
  ArrayMinSize,
  ValidateNested,
  IsOptional,
  IsEnum,
  Matches,
  MaxLength,
  ValidateIf,
} from 'class-validator';
import { Type } from 'class-transformer';
import { OrderDeliveryMode, OrderTransportMode } from '../entities/order.entity';

export class VendorOrderItemDto {
  @IsNotEmpty({ message: 'La variante est obligatoire' })
  @IsUUID('4', { message: 'ID de variante invalide' })
  variantId: string;

  @IsInt({ message: 'La quantité doit être un nombre entier' })
  @Min(1, { message: 'La quantité doit être au moins 1' })
  quantity: number;
}

// ⚠️ Réservé aux vendeurs (POST /orders/vendor-initiated) : permet à un
// vendeur de créer une commande pour un client déjà inscrit sur l'app
// (vente téléphonique/en boutique). La commande est créée SANS paiement :
// c'est ensuite au client de payer via le bouton "Payer la commande"
// (Mobile Money), voir OrdersService.createVendorInitiated.
// Le client DOIT déjà avoir un compte (recherché par téléphone) — voir
// GET /orders/vendor/find-client.
export class CreateVendorOrderDto {

  // Le client est désigné par son id (renvoyé par GET /orders/vendor/find-client
  // — seule façon de choisir un client SANS commande antérieure chez ce
  // vendeur, dont le téléphone est masqué) OU par son numéro complet.
  @IsOptional()
  @IsUUID('4', { message: 'ID client invalide' })
  clientId?: string;

  @ValidateIf((o) => !o.clientId)
  @IsNotEmpty({ message: 'Le téléphone du client est obligatoire' })
  @Matches(/^(\+?[0-9]{8,15})$/, { message: 'Format de téléphone invalide' })
  clientPhone?: string;

  @IsArray()
  @ArrayMinSize(1, { message: 'Au moins un article est requis' })
  @ValidateNested({ each: true })
  @Type(() => VendorOrderItemDto)
  items: VendorOrderItemDto[];

  // Adresse existante du client (renvoyée par GET /orders/vendor/find-client).
  // Sinon fournir newAddressVille + newAddressQuartier pour lui en créer une.
  @IsOptional()
  @IsUUID('4', { message: 'ID adresse invalide' })
  addressId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  newAddressLabel?: string;

  @IsOptional()
  @IsString()
  newAddressQuartier?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  newAddressVille?: string;

  @IsOptional()
  @IsEnum(OrderDeliveryMode, { message: 'Mode de livraison invalide' })
  deliveryMode?: OrderDeliveryMode;

  // Uniquement pour une commune du Nord (voir OrderTransportMode) : bus ou
  // taxi, choisi par le vendeur au nom du client — même champ/sémantique
  // que CreateOrderDto (checkout client), voir
  // OrdersService.getFraisLivraisonForCommune.
  @IsOptional()
  @IsEnum(OrderTransportMode, { message: 'Mode de transport invalide' })
  transportMode?: OrderTransportMode;

  @IsOptional()
  @IsString()
  instructions?: string;
}
