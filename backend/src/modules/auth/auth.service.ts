import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { MailService } from '../mail/mail.service';
import { InjectRepository } from '@nestjs/typeorm';
import * as bcrypt from 'bcrypt';
import { randomInt, randomUUID } from 'crypto';
import { Repository } from 'typeorm';
import { ActivityLogService } from '../../common/services/activity-log.service';
import { TokenService } from '../../common/services/token.service';
import {
  ActorType,
  LogAction,
  LogResult,
} from '../../common/entities/activity-log.entity';
import { User } from '../users/entities/user.entity';
import { UserRole, UserRoleEnum } from '../users/entities/user-role.entity';
import { CreateAdminDto } from './dto/create-admin.dto';
import { ForgotPasswordDto } from './dto/forgot-password.dto';
import { LoginDto } from './dto/login.dto';
import { RefreshTokenDto } from './dto/refresh-token.dto';
import { RegisterDto } from './dto/register.dto';
import { ResendOtpDto } from './dto/resend-otp.dto';
import { ResetPasswordDto } from './dto/reset-password.dto';
import { SetAdminPasswordDto } from './dto/set-admin-password.dto';
import { VerifyOtpDto } from './dto/verify-otp.dto';
import { AdminAccount, AdminRole } from './entities/admin-account.entity';
import { OtpCode, OtpType } from './entities/otp-code.entity';

// Au-delà de ce nombre de tentatives échouées, le code OTP est brûlé et
// l'utilisateur doit en redemander un nouveau. Combiné au @Throttle() sur
// les routes OTP du contrôleur, cela rend le brute-force d'un code à
// 6 chiffres impraticable.
const MAX_OTP_ATTEMPTS = 5;

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);

  constructor(
    @InjectRepository(User)
    private readonly userRepo: Repository<User>,

    @InjectRepository(UserRole)
    private readonly userRoleRepo: Repository<UserRole>,

    @InjectRepository(OtpCode)
    private readonly otpRepo: Repository<OtpCode>,

    @InjectRepository(AdminAccount)
    private readonly adminRepo: Repository<AdminAccount>,

    private readonly jwtService: JwtService,
    private readonly configService: ConfigService,
    private readonly mailService: MailService,
    private readonly logService: ActivityLogService,
    private readonly tokenService: TokenService,
  ) {}

  async register(dto: RegisterDto, ip: string) {
    const emailExists = await this.userRepo.findOne({
      where: { email: dto.email },
    });
    if (emailExists) {
      throw new ConflictException('Cet email est deja utilise');
    }

    const phoneExists = await this.userRepo.findOne({
      where: { phone: dto.phone },
    });
    if (phoneExists) {
      throw new ConflictException('Ce numero de telephone est deja utilise');
    }

    const passwordHash = await bcrypt.hash(dto.password, 12);

    const user = this.userRepo.create({
      prenom: dto.prenom,
      name: dto.name,
      email: dto.email,
      phone: dto.phone,
      passwordHash,
      isVerified: false,
      isActive: true,
    });
    await this.userRepo.save(user);

    const role = this.userRoleRepo.create({
      userId: user.id,
      role: UserRoleEnum.CLIENT,
    });
    await this.userRoleRepo.save(role);

    await this.sendOtp(user, OtpType.EMAIL_VERIFICATION);

    await this.logService.log({
      actorId: user.id,
      actorType: ActorType.CLIENT,
      action: LogAction.USER_REGISTER,
      entityType: 'user',
      entityId: user.id,
      ipAddress: ip,
    });

    return {
      message: 'Inscription reussie. Verifiez votre email pour le code OTP.',
      userId: user.id,
    };
  }

  async verifyOtp(dto: VerifyOtpDto) {
    const user = await this.userRepo.findOne({
      where: { email: dto.email },
    });
    if (!user) {
      // ⚠️ Message volontairement identique à celui d'un code invalide :
      // un 404 "Utilisateur introuvable" ici permettrait de tester quelles
      // adresses email sont inscrites sur la plateforme.
      throw new BadRequestException('Code OTP invalide ou expire');
    }

    const otpRecords = await this.otpRepo.find({
      where: {
        userId: user.id,
        type: dto.type,
        isUsed: false,
      },
      order: { createdAt: 'DESC' },
    });

    if (!otpRecords.length) {
      throw new BadRequestException('Aucun code OTP valide trouve');
    }

    const otp = otpRecords[0];

    if (new Date() > otp.expiresAt) {
      throw new BadRequestException('Le code OTP a expire');
    }

    const isValid = await bcrypt.compare(dto.code, otp.code);
    if (!isValid) {
      // ⚠️ Chaque échec consomme une tentative. Au-delà de la limite, le
      // code est brûlé : sans ce compteur, 10^6 combinaisons sur 3 minutes
      // se testent en quelques secondes et permettent de prendre le
      // contrôle de n'importe quel compte via "mot de passe oublié".
      otp.attempts += 1;
      const attemptsLeft = MAX_OTP_ATTEMPTS - otp.attempts;

      if (attemptsLeft <= 0) {
        otp.isUsed = true;
        await this.otpRepo.save(otp);
        throw new BadRequestException(
          'Trop de tentatives echouees. Demandez un nouveau code OTP.',
        );
      }

      await this.otpRepo.save(otp);
      throw new BadRequestException(
        `Code OTP invalide. ${attemptsLeft} tentative(s) restante(s).`,
      );
    }

    otp.isUsed = true;
    await this.otpRepo.save(otp);

    if (dto.type === OtpType.EMAIL_VERIFICATION) {
      user.isVerified = true;
      await this.userRepo.save(user);

      // Email de bienvenue — best-effort : un échec d'envoi ne doit pas
      // faire échouer la vérification elle-même. Avant ce correctif,
      // AUCUN email n'était envoyé après une inscription client réussie
      // (seul l'OTP l'était, pas de confirmation une fois le compte
      // effectivement activé).
      try {
        await this.mailService.sendWelcome(user.email, user.prenom);
      } catch (error) {
        this.logger.error(
          `Échec envoi mail de bienvenue → ${user.email}`,
          error?.message,
        );
      }
    }

    return { message: 'Code OTP verifie avec succes' };
  }

  async login(dto: LoginDto, ip: string) {
    const user = await this.userRepo.findOne({
      where: [{ email: dto.identifier }, { phone: dto.identifier }],
      relations: ['roles'],
    });

    if (!user) {
      await this.logService.log({
        actorType: ActorType.CLIENT,
        action: LogAction.USER_LOGIN_FAILED,
        ipAddress: ip,
        result: LogResult.FAILURE,
        errorMessage: `Tentative avec identifiant: ${dto.identifier}`,
      });
      throw new UnauthorizedException('Identifiants incorrects');
    }

    // ⚠️ Le mot de passe est vérifié AVANT l'état du compte.
    // Dans l'ordre inverse, un 403 "compte bloqué" / "email non vérifié"
    // révélait à un attaquant sans mot de passe qu'une adresse est
    // bien inscrite (énumération de comptes).
    const isPasswordValid = await bcrypt.compare(
      dto.password,
      user.passwordHash,
    );
    if (!isPasswordValid) {
      await this.logService.log({
        actorId: user.id,
        actorType: ActorType.CLIENT,
        action: LogAction.USER_LOGIN_FAILED,
        entityId: user.id,
        ipAddress: ip,
        result: LogResult.FAILURE,
      });
      throw new UnauthorizedException('Identifiants incorrects');
    }

    if (!user.isActive) {
      throw new ForbiddenException('Votre compte a ete bloque');
    }

    if (!user.isVerified) {
      throw new ForbiddenException(
        'Veuillez verifier votre email avant de vous connecter',
      );
    }

    const tokens = await this.generateTokens(user);

    // Présence : une connexion réussie compte comme une activité (best-effort,
    // ne doit jamais empêcher la connexion). SQL direct pour ne pas
    // rafraîchir users.updatedAt.
    try {
      const seenAt = new Date();
      await this.userRepo.query(
        `UPDATE "users" SET "lastSeenAt" = $1 WHERE "id" = $2`,
        [seenAt, user.id],
      );
      user.lastSeenAt = seenAt;
    } catch {
      // ignoré : la présence n'est qu'un confort d'affichage
    }

    await this.logService.log({
      actorId: user.id,
      actorType: ActorType.CLIENT,
      action: LogAction.USER_LOGIN,
      entityId: user.id,
      ipAddress: ip,
    });

    // ⚠️ On ne renvoie ni le hash, ni les champs de sécurité internes
    // (révocation des sessions, alerte d'e-mail annulé) : ils n'ont rien à
    // faire côté appli et ne regardent que l'administration.
    const {
      passwordHash,
      tokensValidAfter,
      securityAlertAt,
      securityAlertReason,
      securityAlertAckedAt,
      ...userSafe
    } = user;

    return {
      ...tokens,
      user: userSafe,
    };
  }

  async forgotPassword(dto: ForgotPasswordDto) {
    const user = await this.userRepo.findOne({
      where: { email: dto.email },
    });

    // Compte bloqué (par l'admin, ou par précaution après un « Ce n'est pas
    // moi ») : aucun code n'est envoyé, MAIS la réponse reste identique à
    // celle d'une adresse inconnue pour ne rien révéler. (On ne refuse PAS
    // sur securityAlertAt : le propriétaire légitime doit pouvoir réinitialiser
    // son mot de passe après une annulation.)
    if (!user || !user.isActive) {
      return {
        message: 'Si cet email existe, vous recevrez un code OTP.',
      };
    }

    await this.sendOtp(user, OtpType.PASSWORD_RESET);

    return {
      message: 'Si cet email existe, vous recevrez un code OTP.',
    };
  }

  async resetPassword(dto: ResetPasswordDto) {
    if (dto.newPassword !== dto.confirmPassword) {
      throw new BadRequestException('Les mots de passe ne correspondent pas');
    }

    // Compte inconnu ou bloqué : même message neutre que pour un code
    // invalide, et AVANT verifyOtp pour ne pas consommer d'essais ni révéler
    // l'état du compte. Sans ce contrôle, un compte bloqué pouvait changer de
    // mot de passe par « Mot de passe oublié ».
    const target = await this.userRepo.findOne({
      where: { email: dto.email },
    });
    if (!target || !target.isActive) {
      throw new BadRequestException('Code OTP invalide ou expire');
    }

    await this.verifyOtp({
      email: dto.email,
      code: dto.code,
      type: OtpType.PASSWORD_RESET,
    });

    const user = await this.userRepo.findOne({
      where: { email: dto.email },
    });
    if (!user) {
      throw new NotFoundException('Utilisateur introuvable');
    }

    user.passwordHash = await bcrypt.hash(dto.newPassword, 12);
    // Réinitialisation = on ne sait pas qui avait la session : toutes les
    // sessions ouvertes (jetons d'accès ET de rafraîchissement émis avant cet
    // instant) sont coupées. L'utilisateur se reconnecte avec son nouveau
    // mot de passe (les nouveaux jetons, émis après, fonctionnent).
    user.tokensValidAfter = new Date();
    await this.userRepo.save(user);

    await this.logService.log({
      actorId: user.id,
      actorType: ActorType.CLIENT,
      action: LogAction.USER_PASSWORD_RESET,
      entityId: user.id,
    });

    return { message: 'Mot de passe reinitialise avec succes' };
  }

  async resendOtp(dto: ResendOtpDto) {
    const user = await this.userRepo.findOne({
      where: { email: dto.email },
    });

    if (!user) {
      return { message: 'Si cet email existe, un nouveau code sera envoye.' };
    }

    await this.otpRepo.update(
      { userId: user.id, type: dto.type, isUsed: false },
      { isUsed: true },
    );

    await this.sendOtp(user, dto.type);

    return { message: 'Nouveau code OTP envoye' };
  }

  async createAdmin(dto: CreateAdminDto, createdById: string, ip: string) {
    const exists = await this.adminRepo.findOne({
      where: { email: dto.email },
    });
    if (exists) {
      throw new ConflictException('Cet email admin est deja utilise');
    }

    const rawToken = randomUUID();
    const tokenHash = await bcrypt.hash(rawToken, 10);
    const expiresAt = new Date(Date.now() + 48 * 60 * 60 * 1000);

    const admin = this.adminRepo.create({
      prenom: dto.prenom,
      name: dto.name,
      email: dto.email,
      role: dto.role,
      isPasswordSet: false,
      invitationToken: tokenHash,
      invitationExpiresAt: expiresAt,
      createdById,
    });
    await this.adminRepo.save(admin);

    const dashboardUrl = this.configService.get<string>('FRONTEND_WEB_URL') ?? '';
    const invitationLink = `${dashboardUrl}/set-password?token=${rawToken}&email=${dto.email}`;

    await this.mailService.sendAdminInvitation(
      dto.email,
      dto.prenom,
      dto.role,
      invitationLink,
    );

    await this.logService.log({
      actorId: createdById,
      actorType: ActorType.SUPERADMIN,
      action: LogAction.ADMIN_CREATED,
      entityType: 'admin',
      entityId: admin.id,
      ipAddress: ip,
    });

    return { message: `Invitation envoyee a ${dto.email}` };
  }

  async setAdminPassword(dto: SetAdminPasswordDto, email: string) {
    if (dto.password !== dto.confirmPassword) {
      throw new BadRequestException('Les mots de passe ne correspondent pas');
    }

    const admin = await this.adminRepo.findOne({ where: { email } });
    if (!admin) {
      throw new NotFoundException('Admin introuvable');
    }

    if (admin.isPasswordSet) {
      throw new BadRequestException('Le mot de passe a deja ete defini');
    }

    if (!admin.invitationToken || !admin.invitationExpiresAt) {
      throw new BadRequestException('Invitation invalide ou deja utilisee');
    }

    if (new Date() > admin.invitationExpiresAt) {
      throw new BadRequestException("Le lien d'invitation a expire");
    }

    const isTokenValid = await bcrypt.compare(
      dto.invitationToken,
      admin.invitationToken,
    );
    if (!isTokenValid) {
      throw new BadRequestException("Token d'invitation invalide");
    }

    admin.passwordHash = await bcrypt.hash(dto.password, 12);
    admin.isPasswordSet = true;
    admin.invitationToken = null;
    admin.invitationExpiresAt = null;
    await this.adminRepo.save(admin);

    return {
      message:
        'Mot de passe defini avec succes. Vous pouvez maintenant vous connecter.',
    };
  }

  async loginAdmin(dto: LoginDto, ip: string) {
    const admin = await this.adminRepo.findOne({
      where: { email: dto.identifier },
    });

    if (!admin) {
      await this.logService.log({
        actorType: ActorType.ADMIN,
        action: LogAction.ADMIN_LOGIN_FAILED,
        ipAddress: ip,
        result: LogResult.FAILURE,
        errorMessage: `Email: ${dto.identifier}`,
      });
      throw new UnauthorizedException('Identifiants incorrects');
    }

    if (!admin.isPasswordSet || !admin.passwordHash) {
      throw new ForbiddenException(
        "Veuillez definir votre mot de passe via le lien d'invitation",
      );
    }

    // ⚠️ Comme pour login() : mot de passe d'abord, état du compte ensuite,
    // pour ne pas révéler quelles adresses correspondent à un admin.
    const isValid = await bcrypt.compare(dto.password, admin.passwordHash);
    if (!isValid) {
      await this.logService.log({
        actorId: admin.id,
        actorType: ActorType.ADMIN,
        action: LogAction.ADMIN_LOGIN_FAILED,
        entityId: admin.id,
        ipAddress: ip,
        result: LogResult.FAILURE,
      });
      throw new UnauthorizedException('Identifiants incorrects');
    }

    if (!admin.isActive) {
      throw new ForbiddenException('Ce compte admin est desactive');
    }

    admin.lastLoginAt = new Date();
    await this.adminRepo.save(admin);

    const payload = {
      sub: admin.id,
      email: admin.email,
      role: admin.role,
      type: 'admin' as const,
    };

    const accessToken = this.jwtService.sign(payload);

    await this.logService.log({
      actorId: admin.id,
      actorType:
        admin.role === AdminRole.SUPERADMIN
          ? ActorType.SUPERADMIN
          : ActorType.ADMIN,
      action: LogAction.ADMIN_LOGIN,
      entityId: admin.id,
      ipAddress: ip,
    });

    const { passwordHash, invitationToken, ...adminSafe } = admin;

    return {
      accessToken,
      admin: adminSafe,
    };
  }

  private async generateTokens(user: User) {
    return this.tokenService.issueUserTokens(user);
  }

  /**
   * Renouvelle la session : échange un jeton de rafraîchissement valide
   * contre un nouveau couple { accessToken, refreshToken } (rotation).
   *
   * Contrôles : signature (secret de refresh) + expiration + claim
   * `typ = 'refresh'` ; l'utilisateur existe, est actif et vérifié ; le jeton
   * n'a pas été émis avant `tokensValidAfter` (changement de mot de passe,
   * blocage, « Ce n'est pas moi »...). Tout échec → 401 au même message.
   *
   * ⚠️ Pas de détection de réutilisation : un ancien refresh token reste
   * utilisable jusqu'à son expiration ou jusqu'à la prochaine révocation
   * globale (changement/réinitialisation de mot de passe, blocage).
   */
  async refresh(dto: RefreshTokenDto) {
    const payload = this.tokenService.verifyRefreshToken(dto.refreshToken);

    const user = await this.userRepo.findOne({ where: { id: payload.sub } });
    if (
      !user ||
      !user.isActive ||
      !user.isVerified ||
      TokenService.isRevoked(payload.iat, user.tokensValidAfter)
    ) {
      throw new UnauthorizedException('Session expirée, reconnectez-vous');
    }

    return this.tokenService.issueUserTokens(user);
  }

  async sendOtp(user: User, type: OtpType): Promise<void> {
    // ⚠️ randomInt (CSPRNG), PAS Math.random() : Math.random n'est pas
    // cryptographique — sa sortie est prédictible à partir de quelques
    // valeurs observées, ce qui permettrait de deviner l'OTP d'un tiers
    // sans même le brute-forcer.
    const rawCode = randomInt(100000, 1000000).toString();
    const hashedCode = await bcrypt.hash(rawCode, 10);

    await this.otpRepo.update(
      { userId: user.id, type, isUsed: false },
      { isUsed: true },
    );

    const otp = this.otpRepo.create({
      userId: user.id,
      code: hashedCode,
      type,
      isUsed: false,
      expiresAt: new Date(Date.now() + 3 * 60 * 1000),
    });
    await this.otpRepo.save(otp);

    if (type === OtpType.EMAIL_VERIFICATION) {
      await this.mailService.sendOtp(user.email, user.prenom, rawCode);
    } else {
      await this.mailService.sendPasswordReset(user.email, user.prenom, rawCode);
    }
  }

  async getAllAdmins(page: number = 1, limit: number = 20) {
    const skip = (page - 1) * limit;
    const [admins, total] = await this.adminRepo.findAndCount({
      skip,
      take: limit,
      order: { createdAt: 'DESC' },
    });

    return {
      data: admins.map(admin => {
        const { passwordHash, invitationToken, ...safe } = admin;
        return safe;
      }),
      pagination: {
        total,
        page,
        limit,
        pages: Math.ceil(total / limit),
      },
    };
  }

  async getAdminById(id: string) {
    const admin = await this.adminRepo.findOne({ where: { id } });
    if (!admin) {
      throw new NotFoundException('Admin not found');
    }
    const { passwordHash, invitationToken, ...safe } = admin;
    return safe;
  }

  async deactivateAdmin(id: string, deactivatedById: string, ip: string) {
    const admin = await this.getAdminById(id);

    if (admin.role === AdminRole.SUPERADMIN) {
      throw new BadRequestException('Cannot deactivate a SUPERADMIN');
    }

    admin.isActive = false;
    await this.adminRepo.update(id, { isActive: false });

    await this.logService.log({
      actorId: deactivatedById,
      actorType: ActorType.SUPERADMIN,
      action: LogAction.ADMIN_DEACTIVATED,
      entityType: 'admin',
      entityId: id,
      ipAddress: ip,
    });

    return { message: 'Admin deactivated successfully' };
  }
}
