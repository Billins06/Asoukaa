import { IsBoolean, IsNotEmpty } from 'class-validator';

export class UpdateAgentAvailabilityDto {

  // Le livreur met à jour sa disponibilité en temps réel
  @IsNotEmpty()
  @IsBoolean({ message: 'La disponibilité doit être true ou false' })
  isAvailableNow: boolean;
}