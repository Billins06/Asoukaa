import { PartialType } from '@nestjs/swagger';
import { CreateAddressDto } from './create-address.dto';

// PartialType rend tous les champs de CreateAddressDto optionnels
// Évite de dupliquer tout le code
export class UpdateAddressDto extends PartialType(CreateAddressDto) {}
