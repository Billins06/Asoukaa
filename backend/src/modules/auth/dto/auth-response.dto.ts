import { Exclude, Expose, Type } from 'class-transformer';

// DTO de réponse pour un utilisateur
// @Expose() = inclus dans la réponse
// @Exclude() = exclu de la réponse (sécurité)
@Exclude()
export class UserInResponseDto {

  @Expose()
  id: string;

  @Expose()
  prenom: string;

  @Expose()
  name: string;

  @Expose()
  email: string;

  @Expose()
  phone: string;

  @Expose()
  avatarUrl: string;

  @Expose()
  isVerified: boolean;

  @Expose()
  isActive: boolean;

  @Expose()
  createdAt: Date;

  // ⚠️ passwordHash n'est PAS ici → jamais exposé
  // ⚠️ les tokens non plus
}

// Réponse complète après login/register
export class AuthResponseDto {
  accessToken: string;
  refreshToken: string;

  @Type(() => UserInResponseDto)
  user: UserInResponseDto;
}