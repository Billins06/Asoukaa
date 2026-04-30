import { IsEnum, IsNotEmpty } from 'class-validator';
import { ReviewStatus } from '../entities/review.entity';

export class ModerateReviewDto {

  @IsNotEmpty()
  @IsEnum(ReviewStatus, { message: 'Statut invalide' })
  status: ReviewStatus;
}