import {
  Controller,
  Post,
  Get,
  Param,
  Req,
  Res,
  UseGuards,
  UseInterceptors,
  UploadedFile,
  UploadedFiles,
  HttpCode,
  HttpStatus,
  BadRequestException,
  NotFoundException,
  ForbiddenException,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import { existsSync } from 'fs';
import { Throttle } from '@nestjs/throttler';
import {
  ApiTags,
  ApiBearerAuth,
  ApiOperation,
  ApiConsumes,
  ApiBody,
} from '@nestjs/swagger';

import { UploadService, UploadType } from './upload.service';
import { JwtAuthGuard }              from '../auth/guards/jwt-auth.guard';
import { Role }                      from '../../common/enums/role.enum';
import { UploadParseInterceptor }    from './upload.interceptor';

// Seuls les comptes du back-office (AdminAccount) portent un champ scalaire
// `role` ('admin' | 'superadmin') — voir RolesGuard.extractRoles. Les
// utilisateurs (client/vendeur/livreur) ont une relation `roles` qui ne
// contient jamais ces valeurs.
const isAdminPrincipal = (req: Request): boolean => {
  const role = (req as any).user?.role;
  return role === Role.ADMIN || role === Role.SUPERADMIN;
};

// 🛡️ Limites d'envoi (en plus du quota PAR UTILISATEUR de UploadQuotaService,
// 60 fichiers/heure par défaut) :
//  - rafale par IP : 30 requêtes d'envoi / minute (le ThrottlerGuard global
//    s'exécute avant l'authentification, il ne connaît que l'IP) ;
//  - taille : limite PAR TYPE appliquée par Multer pendant la réception
//    (images/documents 5 Mo, vidéos 50 Mo — voir UploadService.maxBytesFor).
const UPLOAD_BURST_THROTTLE = { default: { limit: 30, ttl: 60_000 } };

@ApiTags('Upload')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('upload')
export class UploadController {
  constructor(private readonly uploadService: UploadService) {}

  // ─── Upload d'un seul fichier ─────────────────────────

  @ApiOperation({ summary: 'Uploader un fichier (image ou PDF)' })
  @ApiConsumes('multipart/form-data')
  @ApiBody({
    schema: {
      type: 'object',
      properties: {
        file: { type: 'string', format: 'binary' },
      },
    },
  })
  @Post(':type')
  @Throttle(UPLOAD_BURST_THROTTLE)
  @UseInterceptors(UploadParseInterceptor('single'))
  @HttpCode(HttpStatus.CREATED)
  async uploadFile(
    @Param('type') type: string,
    @UploadedFile() file: Express.Multer.File,
    @Req() req: Request,
  ) {
    // Vérifier que le type est valide
    if (!Object.values(UploadType).includes(type as UploadType)) {
      throw new BadRequestException(
        `Type d'upload invalide. Valeurs acceptées : ${Object.values(UploadType).join(', ')}`
      );
    }
    this.assertAllowedForUser(type, req);
    await this.assertEbookSenderAllowed(type, req);

    return this.uploadService.uploadFile(file, type as UploadType);
  }

  // ─── Upload de plusieurs fichiers ─────────────────────

  @ApiOperation({ summary: 'Uploader plusieurs fichiers (max 10)' })
  @ApiConsumes('multipart/form-data')
  @ApiBody({
    schema: {
      type: 'object',
      properties: {
        files: {
          type:  'array',
          items: { type: 'string', format: 'binary' },
        },
      },
    },
  })
  @Post(':type/multiple')
  @Throttle(UPLOAD_BURST_THROTTLE)
  @UseInterceptors(UploadParseInterceptor('multiple'))
  @HttpCode(HttpStatus.CREATED)
  uploadMultiple(
    @Param('type') type: string,
    @UploadedFiles() files: Express.Multer.File[],
    @Req() req: Request,
  ) {
    if (!Object.values(UploadType).includes(type as UploadType)) {
      throw new BadRequestException(
        `Type d'upload invalide. Valeurs acceptées : ${Object.values(UploadType).join(', ')}`
      );
    }
    this.assertAllowedForUser(type, req);
    if (this.uploadService.isEbookType(type)) {
      throw new BadRequestException('Un livre s\'envoie un fichier à la fois');
    }

    return this.uploadService.uploadMultiple(files, type as UploadType);
  }

  // Livres numériques (PDF) : réservés aux VENDEURS APPROUVÉS (un vendeur
  // bloqué/en attente ne peut plus déposer de fichier de 50 Mo).
  private async assertEbookSenderAllowed(type: string, req: Request): Promise<void> {
    if (!this.uploadService.isEbookType(type)) return;
    const ok = await this.uploadService.isApprovedVendor((req as any).user?.id);
    if (!ok) {
      throw new ForbiddenException('Seul un vendeur approuvé peut envoyer un livre numérique');
    }
  }

  // Types réservés au back-office (vitrine, catégories) : refusés à tout
  // compte qui n'est pas ADMIN/SUPERADMIN. Les autres types sont inchangés.
  private assertAllowedForUser(type: string, req: Request): void {
    if (this.uploadService.isAdminOnlyType(type) && !isAdminPrincipal(req)) {
      throw new ForbiddenException(
        'Ce type d\'upload est réservé aux administrateurs'
      );
    }
  }

  // ─── Lecture d'un fichier privé stocké en local (dev) ─────────────────
  // Uniquement utile quand STORAGE_DRIVER=local : les fichiers "publics"
  // sont servis directement en statique (voir main.ts), mais les
  // documents/selfies (KYC) doivent rester derrière l'authentification —
  // d'où cette route dédiée au lieu d'une URL publique.

  // ⚠️ Accès : un ADMIN/SUPERADMIN (vérification des demandes vendeur/livreur)
  // ou le PROPRIÉTAIRE du fichier (son profil vendeur/livreur le référence).
  // Tout autre compte reçoit EXACTEMENT la même réponse qu'un fichier
  // inexistant (404) : on ne révèle jamais qu'un fichier existe. Avant, tout
  // compte connecté pouvait lire n'importe quel document d'identité dont il
  // connaissait le nom.
  @ApiOperation({ summary: 'Récupérer un fichier privé (admin ou propriétaire ; stockage local)' })
  @Get('file/:type/:filename')
  async getPrivateFile(
    @Param('type') type: string,
    @Param('filename') filename: string,
    @Req() req: Request,
    @Res() res: Response,
  ) {
    if (!this.uploadService.isPrivateType(type)) {
      throw new BadRequestException('Ce type de fichier n\'est pas servi par cette route');
    }
    const allowed =
      isAdminPrincipal(req)
      || await this.uploadService.isPrivateFileOwner(
        (req as any).user?.id,
        type,
        filename,
      );
    if (!allowed) {
      throw new NotFoundException('Fichier introuvable');
    }
    const filePath = this.uploadService.resolveLocalFilePath(type, filename);
    if (!existsSync(filePath)) {
      throw new NotFoundException('Fichier introuvable');
    }
    return res.sendFile(filePath);
  }
}