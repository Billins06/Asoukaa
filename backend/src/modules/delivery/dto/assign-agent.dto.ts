import { IsUUID, IsNotEmpty } from 'class-validator';

export class AssignDeliveryAgentDto {

  // ⚠️ Le service doit vérifier que :
  // 1. L'utilisateur qui assigne est bien le vendeur de la commande
  // 2. Le livreur a status = 'approved' et isAvailableNow = true
  @IsNotEmpty({ message: 'L\'ID du livreur est obligatoire' })
  @IsUUID('4', { message: 'ID livreur invalide' })
  agentId: string;
}