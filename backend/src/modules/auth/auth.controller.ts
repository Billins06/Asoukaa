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
  UnauthorizedException,
} from '@nestjs/common';
import { ApiTags, ApiBearerAuth, ApiOperation } from '@nestjs/swagger';
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
import { AdminRole }             from './entities/admin-account.entity';
import { Role }                  from '../../common/enums/role.enum';

// Helper pour récupérer l'IP de la requête
const getIp = (req: Request): string =>
  (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim()
  ?? req.socket?.remoteAddress
  ?? 'unknown';

@ApiTags('Auth')
@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  // ─── Routes utilisateurs ─────────────────────────────────

  @ApiOperation({ summary: 'Inscription utilisateur' })
  @Post('register')
  @HttpCode(HttpStatus.CREATED)
  register(@Body() dto: RegisterDto, @Req() req: Request) {
    return this.authService.register(dto, getIp(req));
  }

  @ApiOperation({ summary: 'Vérification OTP' })
  @Post('verify-otp')
  @HttpCode(HttpStatus.OK)
  verifyOtp(@Body() dto: VerifyOtpDto) {
    return this.authService.verifyOtp(dto);
  }

  @ApiOperation({ summary: 'Renvoyer OTP' })
  @Post('resend-otp')
  @HttpCode(HttpStatus.OK)
  resendOtp(@Body() dto: ResendOtpDto) {
    return this.authService.resendOtp(dto);
  }

  @ApiOperation({ summary: 'Connexion utilisateur' })
  @Post('login')
  @HttpCode(HttpStatus.OK)
  login(@Body() dto: LoginDto, @Req() req: Request) {
    return this.authService.login(dto, getIp(req));
  }

  @ApiOperation({ summary: 'Mot de passe oublié' })
  @Post('forgot-password')
  @HttpCode(HttpStatus.OK)
  forgotPassword(@Body() dto: ForgotPasswordDto) {
    return this.authService.forgotPassword(dto);
  }

  @ApiOperation({ summary: 'Réinitialiser le mot de passe' })
  @Post('reset-password')
  @HttpCode(HttpStatus.OK)
  resetPassword(@Body() dto: ResetPasswordDto) {
    return this.authService.resetPassword(dto);
  }

  // ─── Routes admin ─────────────────────────────────────────

  @ApiOperation({ summary: 'Connexion admin/superadmin' })
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
    const createdById = (req as any).user?.id;
    if (!createdById) {
      throw new UnauthorizedException('SuperAdmin non identifié');
    }
    return this.authService.createAdmin(dto, createdById, getIp(req));
  }

  @ApiOperation({ summary: 'Définir le mot de passe admin (après invitation)' })
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
    const admin = (req as any).user;
    if (!admin || !admin.email) {
      throw new UnauthorizedException('Admin non authentifié');
    }
    // Retirer les champs sensibles
    const { passwordHash, invitationToken, ...adminSafe } = admin;
    return adminSafe;
  }
}

