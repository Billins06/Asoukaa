import {
  Controller,
  Post,
  Get,
  Body,
  Req,
  HttpCode,
  HttpStatus,
  UseGuards,
  Query,
  Param,
  UnauthorizedException,
} from '@nestjs/common';
import { ApiTags, ApiBearerAuth, ApiOperation } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { JwtService } from '@nestjs/jwt';
import type { Request } from 'express';

import { AuthService }           from './auth.service';
import { RegisterDto }           from './dto/register.dto';
import { LoginDto }              from './dto/login.dto';
import { VerifyOtpDto }          from './dto/verify-otp.dto';
import { ForgotPasswordDto }     from './dto/forgot-password.dto';
import { ResetPasswordDto }      from './dto/reset-password.dto';
import { ResendOtpDto }          from './dto/resend-otp.dto';
import { CreateAdminDto }        from './dto/create-admin.dto';
import { SetAdminPasswordDto }   from './dto/set-admin-password.dto';
import { JwtAuthGuard }          from './guards/jwt-auth.guard';
import { RolesGuard }            from './guards/roles.guard';
import { Roles }                 from './decorators/roles.decorator';
import { AdminRole, AdminAccount } from './entities/admin-account.entity';
import { Role }                  from '../../common/enums/role.enum';
import { TokenBlacklistService } from '../../common/services/token-blacklist.service';
import { clampLimit, clampPage } from '../../common/utils/pagination.util';

// 🛡️ Limites anti-brute-force sur les routes sensibles.
// Le ThrottlerGuard global (APP_GUARD dans AppModule) autorise 100 req/min ;
// ces limites-ci sont beaucoup plus strictes.
// - AUTH_THROTTLE   : login / register (5 tentatives par minute et par IP)
// - OTP_THROTTLE    : vérification de code (5 par minute — combiné à la
//   limite de 5 tentatives par code côté AuthService, un code à 6 chiffres
//   devient impossible à forcer)
// - RESEND_THROTTLE : envoi d'email (3 par 5 min — évite aussi de servir
//   de relais de spam via forgot-password / resend-otp)
const AUTH_THROTTLE = { default: { limit: 5, ttl: 60_000 } };
const OTP_THROTTLE = { default: { limit: 5, ttl: 60_000 } };
const RESEND_THROTTLE = { default: { limit: 3, ttl: 300_000 } };

// Helper pour récupérer l'IP de la requête
const getIp = (req: Request): string =>
  (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim()
  ?? req.socket?.remoteAddress
  ?? 'unknown';

@ApiTags('Auth')
@Controller('auth')
export class AuthController {
  constructor(
    private readonly authService: AuthService,
    private readonly tokenBlacklist: TokenBlacklistService,
    private readonly jwtService: JwtService,
  ) {}

  // ─── Routes utilisateurs ─────────────────────────────────

  @ApiOperation({ summary: 'Inscription utilisateur' })
  @Throttle(AUTH_THROTTLE)
  @Post('register')
  @HttpCode(HttpStatus.CREATED)
  register(@Body() dto: RegisterDto, @Req() req: Request) {
    return this.authService.register(dto, getIp(req));
  }

  @ApiOperation({ summary: 'Vérification OTP' })
  @Throttle(OTP_THROTTLE)
  @Post('verify-otp')
  @HttpCode(HttpStatus.OK)
  verifyOtp(@Body() dto: VerifyOtpDto) {
    return this.authService.verifyOtp(dto);
  }

  @ApiOperation({ summary: 'Renvoyer OTP' })
  @Throttle(RESEND_THROTTLE)
  @Post('resend-otp')
  @HttpCode(HttpStatus.OK)
  resendOtp(@Body() dto: ResendOtpDto) {
    return this.authService.resendOtp(dto);
  }

  @ApiOperation({ summary: 'Connexion utilisateur' })
  @Throttle(AUTH_THROTTLE)
  @Post('login')
  @HttpCode(HttpStatus.OK)
  login(@Body() dto: LoginDto, @Req() req: Request) {
    return this.authService.login(dto, getIp(req));
  }

  @ApiOperation({ summary: 'Mot de passe oublié' })
  @Throttle(RESEND_THROTTLE)
  @Post('forgot-password')
  @HttpCode(HttpStatus.OK)
  forgotPassword(@Body() dto: ForgotPasswordDto) {
    return this.authService.forgotPassword(dto);
  }

  @ApiOperation({ summary: 'Réinitialiser le mot de passe' })
  @Throttle(OTP_THROTTLE)
  @Post('reset-password')
  @HttpCode(HttpStatus.OK)
  resetPassword(@Body() dto: ResetPasswordDto) {
    return this.authService.resetPassword(dto);
  }

  // ─── Routes admin ─────────────────────────────────────────

  @ApiOperation({ summary: 'Connexion admin/superadmin' })
  @Throttle(AUTH_THROTTLE)
  @Post('admin/login')
  @HttpCode(HttpStatus.OK)
  loginAdmin(@Body() dto: LoginDto, @Req() req: Request) {
    return this.authService.loginAdmin(dto, getIp(req));
  }

  @ApiOperation({ summary: 'Créer un admin (SuperAdmin uniquement)' })
  @ApiBearerAuth()
  @Post('admin/create')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(Role.SUPERADMIN) // ✅ SEULEMENT les superadmins
  @HttpCode(HttpStatus.CREATED)
  createAdmin(
    @Body() dto: CreateAdminDto,
    @Req() req: Request,
  ) {
    const createdById = ((req as any).user as AdminAccount)?.id;
    if (!createdById) {
      throw new UnauthorizedException('SuperAdmin non identifié');
    }
    return this.authService.createAdmin(dto, createdById, getIp(req));
  }

  @ApiOperation({ summary: 'Définir le mot de passe admin (après invitation)' })
  @Throttle(AUTH_THROTTLE)
  @Post('admin/set-password')
  @HttpCode(HttpStatus.OK)
  setAdminPassword(
    @Body() dto: SetAdminPasswordDto,
    @Query('email') email: string,
  ) {
    return this.authService.setAdminPassword(dto, email);
  }

  @ApiOperation({ summary: 'Récupérer le profil admin/superadmin connecté' })
  @ApiBearerAuth()
  @Get('admin/me')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.OK)
  async getCurrentAdmin(@Req() req: Request) {
    const admin = (req as any).user as AdminAccount;
    if (!admin || !admin.email) {
      throw new UnauthorizedException('Admin non authentifié');
    }
    // Retirer les champs sensibles
    const { passwordHash, invitationToken, ...adminSafe } = admin;
    return adminSafe;
  }

  @ApiOperation({ summary: 'Logout (révoque le token)' })
  @ApiBearerAuth()
  @Post('logout')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.OK)
  logout(@Req() req: Request) {
    const authHeader = req.headers.authorization;
    if (authHeader && authHeader.startsWith('Bearer ')) {
      const token = authHeader.substring(7);

      // On transmet l'expiration réelle du JWT pour que la blacklist puisse
      // purger l'entrée d'elle-même une fois le token périmé (sinon elle
      // grossit indéfiniment). decode() ne vérifie pas la signature, mais
      // JwtAuthGuard vient déjà de la valider juste avant.
      const decoded = this.jwtService.decode(token) as { exp?: number } | null;
      const expiresAt = decoded?.exp ? decoded.exp * 1000 : undefined;

      this.tokenBlacklist.revokeToken(token, expiresAt);
    }
    return { message: 'Déconnecté avec succès' };
  }

  @ApiOperation({ summary: 'Lister tous les admins (SUPERADMIN uniquement)' })
  @ApiBearerAuth()
  @Get('admin/list')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(Role.SUPERADMIN)
  @HttpCode(HttpStatus.OK)
  getAllAdmins(@Query('page') page?: number, @Query('limit') limit?: number) {
    return this.authService.getAllAdmins(clampPage(page), clampLimit(limit));
  }

  @ApiOperation({ summary: 'Récupérer un admin par ID (SUPERADMIN uniquement)' })
  @ApiBearerAuth()
  @Get('admin/:id')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(Role.SUPERADMIN)
  @HttpCode(HttpStatus.OK)
  getAdminById(@Param('id') id: string) {
    return this.authService.getAdminById(id);
  }

  @ApiOperation({ summary: 'Désactiver un admin (SUPERADMIN uniquement)' })
  @ApiBearerAuth()
  @Post('admin/:id/deactivate')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(Role.SUPERADMIN)
  @HttpCode(HttpStatus.OK)
  deactivateAdmin(@Param('id') id: string, @Req() req: Request) {
    const superAdminId = ((req as any).user as AdminAccount)?.id;
    const ip = getIp(req);
    return this.authService.deactivateAdmin(id, superAdminId, ip);
  }

  // ⚠️ GET /auth/debug-token SUPPRIMÉ : cette route publique renvoyait les
  // 50 premiers caractères du JWT présenté (header + début du payload en
  // base64) à qui la demandait, sans aucune authentification.
  // Pour déboguer un token en local, utiliser jwt.io ou les logs.
}

