import {
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Req,
  Res,
  UseGuards,
  NotFoundException,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import type { Request, Response } from 'express';
import { existsSync } from 'fs';

import { LibraryService } from './library.service';
import { UploadService } from '../upload/upload.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';

const getIp = (req: Request) =>
  (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim()
  ?? req.socket?.remoteAddress ?? 'unknown';

// Bibliothèque du client connecté (livres numériques achetés).
@ApiTags('Library')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('library')
export class LibraryController {
  constructor(private readonly libraryService: LibraryService) {}

  @ApiOperation({ summary: 'Ma Bibliothèque (livres numériques achetés)' })
  @Get()
  myLibrary(@Req() req: Request) {
    return this.libraryService.myLibrary((req as any).user.id);
  }

  // Liste légère des identifiants possédés (badge « Déjà acheté »).
  @ApiOperation({ summary: 'Identifiants des livres que je possède' })
  @Get('ids')
  async myIds(@Req() req: Request) {
    return { productIds: await this.libraryService.myProductIds((req as any).user.id) };
  }

  // Lien de téléchargement valable 2 minutes. Limité pour éviter qu'un compte
  // ne serve à distribuer un livre en boucle.
  @ApiOperation({ summary: 'Obtenir un lien de téléchargement court pour un livre acheté' })
  @Throttle({ default: { limit: 20, ttl: 60_000 } })
  @Get(':productId/download')
  download(
    @Req() req: Request,
    @Param('productId', ParseUUIDPipe) productId: string,
  ) {
    return this.libraryService.createDownloadLink(
      (req as any).user.id,
      productId,
      getIp(req),
    );
  }
}

// Téléchargement du fichier en stockage LOCAL (développement uniquement) : le
// lien contient un jeton signé à courte durée, sans connexion requise (le
// navigateur qui ouvre le lien n'a pas l'en-tête d'authentification).
// En production (Supabase), le lien signé du stockage est utilisé et cette
// route répond toujours 404.
@ApiTags('Library')
@Controller('library/file')
export class LibraryLocalFileController {
  constructor(private readonly uploadService: UploadService) {}

  @Throttle({ default: { limit: 20, ttl: 60_000 } })
  @Get(':token')
  download(@Param('token') token: string, @Res() res: Response) {
    const decoded = this.uploadService.verifyLocalEbookToken(token);
    if (!decoded || !existsSync(decoded.filePath)) {
      throw new NotFoundException('Lien invalide ou expiré');
    }
    return res.download(decoded.filePath, decoded.downloadName);
  }
}
