import sys

def patch(path, old, new, expect=1):
    with open(path, encoding='utf-8') as f:
        content = f.read()
    count = content.count(old)
    if count != expect:
        print(f"MISMATCH ({count} != {expect}): {path}")
        print(repr(old[:200]))
        sys.exit(1)
    content = content.replace(old, new)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"OK: {path} ({count})")

path = "src/modules/payments/dto/initiate-payment.dto.ts"
patch(
    path,
    """import {
  IsEnum,
  IsNotEmpty,
  IsUUID,
  IsOptional,
  IsString,
  ValidateIf,
  Matches,
  MaxLength,
} from 'class-validator';
import {
  PaymentMethod,
  PaymentOperator,
} from '../entities/payment.entity';

export class InitiatePaymentDto {

  @IsNotEmpty()
  @IsUUID('4', { message: 'ID commande invalide' })
  orderId: string;""",
    """import {
  IsEnum,
  IsNotEmpty,
  IsUUID,
  IsOptional,
  IsString,
  IsArray,
  ArrayMinSize,
  ValidateIf,
  Matches,
  MaxLength,
} from 'class-validator';
import {
  PaymentMethod,
  PaymentOperator,
} from '../entities/payment.entity';

export class InitiatePaymentDto {

  // Cas normal : une seule commande (une boutique).
  @ValidateIf(o => !o.orderIds || o.orderIds.length === 0)
  @IsNotEmpty({ message: 'ID commande invalide' })
  @IsUUID('4', { message: 'ID commande invalide' })
  orderId?: string;

  // Cas panier multi-boutiques : plusieurs commandes créées ensemble
  // (une par boutique) mais un seul paiement client. Fourni à la place
  // de orderId.
  @IsOptional()
  @IsArray()
  @ArrayMinSize(2, { message: 'orderIds doit contenir au moins 2 commandes' })
  @IsUUID('4', { each: true, message: 'ID commande invalide dans orderIds' })
  orderIds?: string[];""",
)
print("PART4 DONE")
