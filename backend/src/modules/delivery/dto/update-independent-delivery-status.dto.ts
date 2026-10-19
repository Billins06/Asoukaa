import { IsIn, IsNotEmpty } from 'class-validator';
import { IndependentDeliveryStatus } from '../entities/independent-delivery.entity';

// Le livreur ne peut que démarrer le trajet ou marquer « livré » :
// l'annulation d'une course payée passe par le support (remboursement).
export class UpdateIndependentDeliveryStatusDto {

  @IsNotEmpty({ message: 'Le statut est obligatoire' })
  @IsIn(
    [IndependentDeliveryStatus.IN_TRANSIT, IndependentDeliveryStatus.DELIVERED],
    { message: 'Statut invalide : « en cours de livraison » ou « livré » uniquement' },
  )
  status: IndependentDeliveryStatus;
}
