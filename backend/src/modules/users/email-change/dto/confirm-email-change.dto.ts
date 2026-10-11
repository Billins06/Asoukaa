import { IsNotEmpty, IsString, Length, Matches } from 'class-validator';
import { Transform } from 'class-transformer';

export class ConfirmEmailChangeDto {

  @IsNotEmpty({ message: 'Le code est obligatoire' })
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  @IsString()
  @Length(6, 6, { message: 'Le code doit contenir exactement 6 chiffres' })
  @Matches(/^[0-9]{6}$/, { message: 'Le code ne doit contenir que des chiffres' })
  code: string;
}
