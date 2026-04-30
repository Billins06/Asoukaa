import { IsEnum, IsString, ValidateIf, IsNotEmpty } from 'class-validator';

export enum AgentReviewAction {
  APPROVE = 'approve',
  REJECT  = 'reject',
}

export class ReviewAgentDto {

  @IsNotEmpty()
  @IsEnum(AgentReviewAction)
  action: AgentReviewAction;

  @ValidateIf(o => o.action === AgentReviewAction.REJECT)
  @IsNotEmpty({ message: 'Le motif de refus est obligatoire' })
  @IsString()
  rejectionReason?: string;
}