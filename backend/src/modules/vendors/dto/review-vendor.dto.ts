import {
  IsEnum,
  IsString,
  ValidateIf,
  IsNotEmpty,
} from 'class-validator';

export enum VendorReviewAction {
  APPROVE = 'approve',
  REJECT  = 'reject',
}

export class ReviewVendorDto {

  @IsNotEmpty()
  @IsEnum(VendorReviewAction, { message: 'Action invalide' })
  action: VendorReviewAction;

  // Motif obligatoire UNIQUEMENT en cas de refus
  @ValidateIf(o => o.action === VendorReviewAction.REJECT)
  @IsNotEmpty({ message: 'Le motif de refus est obligatoire' })
  @IsString()
  rejectionReason?: string;
}