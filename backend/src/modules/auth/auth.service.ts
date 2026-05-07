// import {
//   BadRequestException,
//   ConflictException,
//   ForbiddenException,
//   Injectable,
//   NotFoundException,
//   UnauthorizedException,
// } from '@nestjs/common';
// import { ConfigService } from '@nestjs/config';
// import { JwtService } from '@nestjs/jwt';
// // import { MailerService } from '@nestjs-modules/mailer';
// import { MailService } from './modules/mail/mail.service';
// import { InjectRepository } from '@nestjs/typeorm';
// import type { StringValue } from 'ms';
// import * as bcrypt from 'bcrypt';
// import { Repository } from 'typeorm';
// import { v4 as uuidv4 } from 'uuid';
// import { ActivityLogService } from '../../common/services/activity-log.service';
// import {
//   ActorType,
//   LogAction,
//   LogResult,
// } from '../../common/entities/activity-log.entity';
// import { User } from '../users/entities/user.entity';
// import { UserRole, UserRoleEnum } from '../users/entities/user-role.entity';
// import { CreateAdminDto } from './dto/create-admin.dto';
// import { ForgotPasswordDto } from './dto/forgot-password.dto';
// import { LoginDto } from './dto/login.dto';
// import { RegisterDto } from './dto/register.dto';
// import { ResendOtpDto } from './dto/resend-otp.dto';
// import { ResetPasswordDto } from './dto/reset-password.dto';
// import { SetAdminPasswordDto } from './dto/set-admin-password.dto';
// import { VerifyOtpDto } from './dto/verify-otp.dto';
// import { AdminAccount, AdminRole } from './entities/admin-account.entity';
// import { OtpCode, OtpType } from './entities/otp-code.entity';

// @Injectable()
// export class AuthService {
//   constructor(
//     @InjectRepository(User)
//     private readonly userRepo: Repository<User>,
//     @InjectRepository(UserRole)
//     private readonly userRoleRepo: Repository<UserRole>,
//     @InjectRepository(OtpCode)
//     private readonly otpRepo: Repository<OtpCode>,
//     @InjectRepository(AdminAccount)
//     private readonly adminRepo: Repository<AdminAccount>,
//     private readonly jwtService: JwtService,
//     private readonly configService: ConfigService,
//     // private readonly mailerService: MailerService,
//     private readonly mailService: MailService,
//     private readonly logService: ActivityLogService,
//   ) {}

//   async register(dto: RegisterDto, ip: string) {
//     const emailExists = await this.userRepo.findOne({
//       where: { email: dto.email },
//     });
//     if (emailExists) {
//       throw new ConflictException('Cet email est deja utilise');
//     }

//     const phoneExists = await this.userRepo.findOne({
//       where: { phone: dto.phone },
//     });
//     if (phoneExists) {
//       throw new ConflictException('Ce numero de telephone est deja utilise');
//     }

//     const passwordHash = await bcrypt.hash(dto.password, 12);

//     const user = this.userRepo.create({
//       prenom: dto.prenom,
//       name: dto.name,
//       email: dto.email,
//       phone: dto.phone,
//       passwordHash,
//       isVerified: false,
//       isActive: true,
//     });
//     await this.userRepo.save(user);

//     const role = this.userRoleRepo.create({
//       userId: user.id,
//       role: UserRoleEnum.CLIENT,
//     });
//     await this.userRoleRepo.save(role);

//     await this.sendOtp(user, OtpType.EMAIL_VERIFICATION);

//     await this.logService.log({
//       actorId: user.id,
//       actorType: ActorType.CLIENT,
//       action: LogAction.USER_REGISTER,
//       entityType: 'user',
//       entityId: user.id,
//       ipAddress: ip,
//     });

//     return {
//       message: 'Inscription reussie. Verifiez votre email pour le code OTP.',
//       userId: user.id,
//     };
//   }

//   async verifyOtp(dto: VerifyOtpDto) {
//     const user = await this.userRepo.findOne({
//       where: { email: dto.email },
//     });
//     if (!user) {
//       throw new NotFoundException('Utilisateur introuvable');
//     }

//     const otpRecords = await this.otpRepo.find({
//       where: {
//         userId: user.id,
//         type: dto.type,
//         isUsed: false,
//       },
//       order: { createdAt: 'DESC' },
//     });

//     if (!otpRecords.length) {
//       throw new BadRequestException('Aucun code OTP valide trouve');
//     }

//     const otp = otpRecords[0];

//     if (new Date() > otp.expiresAt) {
//       throw new BadRequestException('Le code OTP a expire');
//     }

//     const isValid = await bcrypt.compare(dto.code, otp.code);
//     if (!isValid) {
//       throw new BadRequestException('Code OTP invalide');
//     }

//     otp.isUsed = true;
//     await this.otpRepo.save(otp);

//     if (dto.type === OtpType.EMAIL_VERIFICATION) {
//       user.isVerified = true;
//       await this.userRepo.save(user);
//     }

//     return { message: 'Code OTP verifie avec succes' };
//   }

//   async login(dto: LoginDto, ip: string) {
//     const user = await this.userRepo.findOne({
//       where: [{ email: dto.identifier }, { phone: dto.identifier }],
//       relations: ['roles'],
//     });

//     if (!user) {
//       await this.logService.log({
//         actorType: ActorType.CLIENT,
//         action: LogAction.USER_LOGIN_FAILED,
//         ipAddress: ip,
//         result: LogResult.FAILURE,
//         errorMessage: `Tentative avec identifiant: ${dto.identifier}`,
//       });
//       throw new UnauthorizedException('Identifiants incorrects');
//     }

//     if (!user.isActive) {
//       throw new ForbiddenException('Votre compte a ete bloque');
//     }

//     if (!user.isVerified) {
//       throw new ForbiddenException(
//         'Veuillez verifier votre email avant de vous connecter',
//       );
//     }

//     const isPasswordValid = await bcrypt.compare(
//       dto.password,
//       user.passwordHash,
//     );
//     if (!isPasswordValid) {
//       await this.logService.log({
//         actorId: user.id,
//         actorType: ActorType.CLIENT,
//         action: LogAction.USER_LOGIN_FAILED,
//         entityId: user.id,
//         ipAddress: ip,
//         result: LogResult.FAILURE,
//       });
//       throw new UnauthorizedException('Identifiants incorrects');
//     }

//     const tokens = await this.generateTokens(user);

//     await this.logService.log({
//       actorId: user.id,
//       actorType: ActorType.CLIENT,
//       action: LogAction.USER_LOGIN,
//       entityId: user.id,
//       ipAddress: ip,
//     });

//     const { passwordHash, ...userSafe } = user;

//     return {
//       ...tokens,
//       user: userSafe,
//     };
//   }

//   async forgotPassword(dto: ForgotPasswordDto) {
//     const user = await this.userRepo.findOne({
//       where: { email: dto.email },
//     });

//     if (!user) {
//       return {
//         message: 'Si cet email existe, vous recevrez un code OTP.',
//       };
//     }

//     await this.sendOtp(user, OtpType.PASSWORD_RESET);

//     return {
//       message: 'Si cet email existe, vous recevrez un code OTP.',
//     };
//   }

//   async resetPassword(dto: ResetPasswordDto) {
//     if (dto.newPassword !== dto.confirmPassword) {
//       throw new BadRequestException('Les mots de passe ne correspondent pas');
//     }

//     await this.verifyOtp({
//       email: dto.email,
//       code: dto.code,
//       type: OtpType.PASSWORD_RESET,
//     });

//     const user = await this.userRepo.findOne({
//       where: { email: dto.email },
//     });
//     if (!user) {
//       throw new NotFoundException('Utilisateur introuvable');
//     }

//     user.passwordHash = await bcrypt.hash(dto.newPassword, 12);
//     await this.userRepo.save(user);

//     await this.logService.log({
//       actorId: user.id,
//       actorType: ActorType.CLIENT,
//       action: LogAction.USER_PASSWORD_RESET,
//       entityId: user.id,
//     });

//     return { message: 'Mot de passe reinitialise avec succes' };
//   }

//   async resendOtp(dto: ResendOtpDto) {
//     const user = await this.userRepo.findOne({
//       where: { email: dto.email },
//     });

//     if (!user) {
//       return { message: 'Si cet email existe, un nouveau code sera envoye.' };
//     }

//     await this.otpRepo.update(
//       { userId: user.id, type: dto.type, isUsed: false },
//       { isUsed: true },
//     );

//     await this.sendOtp(user, dto.type);

//     return { message: 'Nouveau code OTP envoye' };
//   }

//   async createAdmin(dto: CreateAdminDto, createdById: string, ip: string) {
//     const exists = await this.adminRepo.findOne({
//       where: { email: dto.email },
//     });
//     if (exists) {
//       throw new ConflictException('Cet email admin est deja utilise');
//     }

//     const rawToken = uuidv4();
//     const tokenHash = await bcrypt.hash(rawToken, 10);
//     const expiresAt = new Date(Date.now() + 48 * 60 * 60 * 1000);

//     const admin = this.adminRepo.create({
//       prenom: dto.prenom,
//       name: dto.name,
//       email: dto.email,
//       role: dto.role,
//       isPasswordSet: false,
//       invitationToken: tokenHash,
//       invitationExpiresAt: expiresAt,
//       createdById,
//     });
//     await this.adminRepo.save(admin);

//     const dashboardUrl = this.configService.get<string>('FRONTEND_WEB_URL') ?? '';
//     await this.mailerService.sendMail({
//       to: dto.email,
//       subject: 'Invitation - Dashboard Asoukaa',
//       html: `
//         <p>Bonjour ${dto.prenom},</p>
//         <p>Vous avez ete invite(e) en tant que <strong>${dto.role}</strong> sur Asoukaa.</p>
//         <p>Cliquez sur le lien ci-dessous pour definir votre mot de passe :</p>
//         <a href="${dashboardUrl}/set-password?token=${rawToken}&email=${dto.email}">
//           Definir mon mot de passe
//         </a>
//         <p>Ce lien expire dans 48 heures.</p>
//       `,
//     });

//     await this.logService.log({
//       actorId: createdById,
//       actorType: ActorType.SUPERADMIN,
//       action: LogAction.ADMIN_CREATED,
//       entityType: 'admin',
//       entityId: admin.id,
//       ipAddress: ip,
//     });

//     return { message: `Invitation envoyee a ${dto.email}` };
//   }

//   async setAdminPassword(dto: SetAdminPasswordDto, email: string) {
//     if (dto.password !== dto.confirmPassword) {
//       throw new BadRequestException('Les mots de passe ne correspondent pas');
//     }

//     const admin = await this.adminRepo.findOne({ where: { email } });
//     if (!admin) {
//       throw new NotFoundException('Admin introuvable');
//     }

//     if (admin.isPasswordSet) {
//       throw new BadRequestException('Le mot de passe a deja ete defini');
//     }

//     if (!admin.invitationToken || !admin.invitationExpiresAt) {
//       throw new BadRequestException('Invitation invalide ou deja utilisee');
//     }

//     if (new Date() > admin.invitationExpiresAt) {
//       throw new BadRequestException("Le lien d'invitation a expire");
//     }

//     const isTokenValid = await bcrypt.compare(
//       dto.invitationToken,
//       admin.invitationToken,
//     );
//     if (!isTokenValid) {
//       throw new BadRequestException("Token d'invitation invalide");
//     }

//     admin.passwordHash = await bcrypt.hash(dto.password, 12);
//     admin.isPasswordSet = true;
//     admin.invitationToken = null;
//     admin.invitationExpiresAt = null;
//     await this.adminRepo.save(admin);

//     return {
//       message:
//         'Mot de passe defini avec succes. Vous pouvez maintenant vous connecter.',
//     };
//   }

//   async loginAdmin(dto: LoginDto, ip: string) {
//     const admin = await this.adminRepo.findOne({
//       where: { email: dto.identifier },
//     });

//     if (!admin) {
//       await this.logService.log({
//         actorType: ActorType.ADMIN,
//         action: LogAction.ADMIN_LOGIN_FAILED,
//         ipAddress: ip,
//         result: LogResult.FAILURE,
//         errorMessage: `Email: ${dto.identifier}`,
//       });
//       throw new UnauthorizedException('Identifiants incorrects');
//     }

//     if (!admin.isActive) {
//       throw new ForbiddenException('Ce compte admin est desactive');
//     }

//     if (!admin.isPasswordSet || !admin.passwordHash) {
//       throw new ForbiddenException(
//         "Veuillez definir votre mot de passe via le lien d'invitation",
//       );
//     }

//     const isValid = await bcrypt.compare(dto.password, admin.passwordHash);
//     if (!isValid) {
//       await this.logService.log({
//         actorId: admin.id,
//         actorType: ActorType.ADMIN,
//         action: LogAction.ADMIN_LOGIN_FAILED,
//         entityId: admin.id,
//         ipAddress: ip,
//         result: LogResult.FAILURE,
//       });
//       throw new UnauthorizedException('Identifiants incorrects');
//     }

//     admin.lastLoginAt = new Date();
//     await this.adminRepo.save(admin);

//     const payload = {
//       sub: admin.id,
//       email: admin.email,
//       role: admin.role,
//       type: 'admin' as const,
//     };

//     const accessToken = this.jwtService.sign(payload);

//     await this.logService.log({
//       actorId: admin.id,
//       actorType:
//         admin.role === AdminRole.SUPERADMIN
//           ? ActorType.SUPERADMIN
//           : ActorType.ADMIN,
//       action: LogAction.ADMIN_LOGIN,
//       entityId: admin.id,
//       ipAddress: ip,
//     });

//     const { passwordHash, invitationToken, ...adminSafe } = admin;

//     return {
//       accessToken,
//       admin: adminSafe,
//     };
//   }

//   private async generateTokens(user: User) {
//     const payload = {
//       sub: user.id,
//       email: user.email,
//       type: 'user' as const,
//     };

//     const accessToken = this.jwtService.sign(payload, {
//       secret: this.configService.getOrThrow<string>('JWT_SECRET'),
//       expiresIn:
//         this.configService.getOrThrow<number | StringValue>('JWT_EXPIRES_IN'),
//     });

//     const refreshToken = this.jwtService.sign(payload, {
//       secret: this.configService.getOrThrow<string>('JWT_REFRESH_SECRET'),
//       expiresIn: this.configService.getOrThrow<number | StringValue>(
//         'JWT_REFRESH_EXPIRES_IN',
//       ),
//     });

//     return { accessToken, refreshToken };
//   }

//   // async sendOtp(user: User, type: OtpType): Promise<void> {
//   //   const rawCode = Math.floor(100000 + Math.random() * 900000).toString();
//   //   const hashedCode = await bcrypt.hash(rawCode, 10);

//   //   await this.otpRepo.update(
//   //     { userId: user.id, type, isUsed: false },
//   //     { isUsed: true },
//   //   );

//   //   const otp = this.otpRepo.create({
//   //     userId: user.id,
//   //     code: hashedCode,
//   //     type,
//   //     isUsed: false,
//   //     expiresAt: new Date(Date.now() + 10 * 60 * 1000),
//   //   });
//   //   await this.otpRepo.save(otp);

//   //   const subject =
//   //     type === OtpType.EMAIL_VERIFICATION
//   //       ? 'Verification de votre compte Asoukaa'
//   //       : 'Reinitialisation de votre mot de passe Asoukaa';

//   //   const message =
//   //     type === OtpType.EMAIL_VERIFICATION
//   //       ? 'pour verifier votre compte'
//   //       : 'pour reinitialiser votre mot de passe';

//   //   await this.mailerService.sendMail({
//   //     to: user.email,
//   //     subject,
//   //     html: `
//   //       <p>Bonjour ${user.prenom},</p>
//   //       <p>Votre code OTP ${message} est :</p>
//   //       <h2 style="letter-spacing: 8px; color: #2E74B5;">${rawCode}</h2>
//   //       <p>Ce code expire dans <strong>10 minutes</strong>.</p>
//   //       <p>Si vous n'etes pas a l'origine de cette demande, ignorez cet email.</p>
//   //     `,
//   //   });
//   // }

//   async sendOtp(user: User, type: OtpType): Promise<void> {
//   const rawCode = Math.floor(100000 + Math.random() * 900000).toString();
//   const hashedCode = await bcrypt.hash(rawCode, 10);

//   await this.otpRepo.update(
//     { userId: user.id, type, isUsed: false },
//     { isUsed: true },
//   );

//   const otp = this.otpRepo.create({
//     userId: user.id,
//     code: hashedCode,
//     type,
//     isUsed: false,
//     expiresAt: new Date(Date.now() + 3 * 60 * 1000), // ✅ 3 minutes
//   });
//   await this.otpRepo.save(otp);

//   if (type === OtpType.EMAIL_VERIFICATION) {
//     // → Utilise le template otp.template.ts
//     // Sujet : "🔐 Votre code de vérification Asoukaa"
//     // Message : "Voici votre code de vérification pour activer votre compte Asoukaa. Ce code est valable 3 minutes."
//     await this.mailService.sendOtp(user.email, user.prenom, rawCode);
//   } else {
//     // → Utilise le template password-reset.template.ts
//     // Sujet : "🔑 Réinitialisation de votre mot de passe"
//     // Message : "Vous avez demandé à réinitialiser votre mot de passe. Voici votre code valable 3 minutes."
//     await this.mailService.sendPasswordReset(user.email, user.prenom, rawCode);
//   }
// }
// }


import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { MailService } from '../mail/mail.service';
import { InjectRepository } from '@nestjs/typeorm';
import type { StringValue } from 'ms';
import * as bcrypt from 'bcrypt';
import { Repository } from 'typeorm';
import { v4 as uuidv4 } from 'uuid';
import { ActivityLogService } from '../../common/services/activity-log.service';
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
import { RegisterDto } from './dto/register.dto';
import { ResendOtpDto } from './dto/resend-otp.dto';
import { ResetPasswordDto } from './dto/reset-password.dto';
import { SetAdminPasswordDto } from './dto/set-admin-password.dto';
import { VerifyOtpDto } from './dto/verify-otp.dto';
import { AdminAccount, AdminRole } from './entities/admin-account.entity';
import { OtpCode, OtpType } from './entities/otp-code.entity';

@Injectable()
export class AuthService {
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
      throw new NotFoundException('Utilisateur introuvable');
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
      throw new BadRequestException('Code OTP invalide');
    }

    otp.isUsed = true;
    await this.otpRepo.save(otp);

    if (dto.type === OtpType.EMAIL_VERIFICATION) {
      user.isVerified = true;
      await this.userRepo.save(user);
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

    if (!user.isActive) {
      throw new ForbiddenException('Votre compte a ete bloque');
    }

    if (!user.isVerified) {
      throw new ForbiddenException(
        'Veuillez verifier votre email avant de vous connecter',
      );
    }

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

    const tokens = await this.generateTokens(user);

    await this.logService.log({
      actorId: user.id,
      actorType: ActorType.CLIENT,
      action: LogAction.USER_LOGIN,
      entityId: user.id,
      ipAddress: ip,
    });

    const { passwordHash, ...userSafe } = user;

    return {
      ...tokens,
      user: userSafe,
    };
  }

  async forgotPassword(dto: ForgotPasswordDto) {
    const user = await this.userRepo.findOne({
      where: { email: dto.email },
    });

    if (!user) {
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

    const rawToken = uuidv4();
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

    if (!admin.isActive) {
      throw new ForbiddenException('Ce compte admin est desactive');
    }

    if (!admin.isPasswordSet || !admin.passwordHash) {
      throw new ForbiddenException(
        "Veuillez definir votre mot de passe via le lien d'invitation",
      );
    }

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
    const payload = {
      sub: user.id,
      email: user.email,
      type: 'user' as const,
    };

    const accessToken = this.jwtService.sign(payload, {
      secret: this.configService.getOrThrow<string>('JWT_SECRET'),
      expiresIn:
        this.configService.getOrThrow<number | StringValue>('JWT_EXPIRES_IN'),
    });

    const refreshToken = this.jwtService.sign(payload, {
      secret: this.configService.getOrThrow<string>('JWT_REFRESH_SECRET'),
      expiresIn: this.configService.getOrThrow<number | StringValue>(
        'JWT_REFRESH_EXPIRES_IN',
      ),
    });

    return { accessToken, refreshToken };
  }

  async sendOtp(user: User, type: OtpType): Promise<void> {
    const rawCode = Math.floor(100000 + Math.random() * 900000).toString();
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
      expiresAt: new Date(Date.now() + 3 * 60 * 1000), // 3 minutes
    });
    await this.otpRepo.save(otp);

    if (type === OtpType.EMAIL_VERIFICATION) {
      await this.mailService.sendOtp(user.email, user.prenom, rawCode);
    } else {
      await this.mailService.sendPasswordReset(user.email, user.prenom, rawCode);
    }
  }
}