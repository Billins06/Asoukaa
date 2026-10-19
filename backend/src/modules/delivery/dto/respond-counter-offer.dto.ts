import { IsBoolean } from 'class-validator';

export class RespondCounterOfferDto {
  @IsBoolean({ message: 'accept doit être true ou false' })
  accept: boolean;
}
