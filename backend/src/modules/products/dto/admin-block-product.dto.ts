import { IsBoolean, IsOptional, IsString, MaxLength } from 'class-validator';
import { Transform } from 'class-transformer';

export class AdminBlockProductDto {
  @IsBoolean({ message: 'blocked doit être true ou false' })
  blocked: boolean;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  reason?: string;
}
