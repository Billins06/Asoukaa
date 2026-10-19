import {
  BadRequestException,
  CallHandler,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  NestInterceptor,
  PayloadTooLargeException,
  Type,
  mixin,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import multer, { memoryStorage } from 'multer';
import { Observable } from 'rxjs';

import { Role } from '../../common/enums/role.enum';
import { UploadQuotaService } from './upload-quota.service';
import { UploadService } from './upload.service';

const MAX_FILES_PER_REQUEST = 10;
// Marge pour les en-têtes multipart (frontières, noms de champs) lors du
// contrôle de Content-Length.
const MULTIPART_OVERHEAD_BYTES = 256 * 1024;

const isAdminPrincipal = (req: Request): boolean => {
  const role = (req as any).user?.role;
  return role === Role.ADMIN || role === Role.SUPERADMIN;
};

/**
 * Lit le fichier envoyé (multipart) AVEC une limite de taille propre au type
 * d'envoi, appliquée par Multer pendant la réception : un fichier trop gros
 * est interrompu dès que la limite est franchie (413), il n'est jamais
 * entièrement chargé en mémoire. Remplace FileInterceptor/FilesInterceptor,
 * dont la limite était unique (50 Mo, celle des vidéos) pour tous les types.
 *
 * Ordre : (1) type valide et autorisé pour ce compte, (2) quota horaire par
 * utilisateur (429), (3) contrôle de Content-Length (413), (4) lecture
 * Multer avec limite par type. S'exécute après JwtAuthGuard (req.user connu).
 */
export function UploadParseInterceptor(
  mode: 'single' | 'multiple',
): Type<NestInterceptor> {
  @Injectable()
  class MixinInterceptor implements NestInterceptor {
    constructor(
      private readonly uploadService: UploadService,
      private readonly quota: UploadQuotaService,
    ) {}

    async intercept(
      context: ExecutionContext,
      next: CallHandler,
    ): Promise<Observable<any>> {
      const http = context.switchToHttp();
      const req = http.getRequest<Request>();
      const res = http.getResponse<Response>();
      const type = String(req.params?.type ?? '');

      if (!this.uploadService.isKnownType(type)) {
        throw new BadRequestException(
          `Type d'upload invalide. Valeurs acceptées : ${this.uploadService.knownTypes().join(', ')}`,
        );
      }
      const admin = isAdminPrincipal(req);
      if (this.uploadService.isAdminOnlyType(type) && !admin) {
        throw new ForbiddenException(
          "Ce type d'upload est réservé aux administrateurs",
        );
      }

      // Livre numérique (PDF, jusqu'à 50 Mo) : vendeur APPROUVÉ seulement, et
      // contrôlé AVANT de lire le fichier en mémoire.
      if (this.uploadService.isEbookType(type)) {
        if (mode === 'multiple') {
          throw new BadRequestException("Un livre s'envoie un fichier à la fois");
        }
        const okVendor = await this.uploadService.isApprovedVendor((req as any).user?.id);
        if (!okVendor) {
          throw new ForbiddenException(
            'Seul un vendeur approuvé peut envoyer un livre numérique',
          );
        }
      }

      const userId = (req as any).user?.id;
      const quotaKey = `${admin ? 'admin' : 'user'}:${userId ?? req.ip}`;
      // Une tentative = 1 envoi décompté dès maintenant (même si le fichier
      // est ensuite refusé) ; pour un envoi multiple, le reste est décompté
      // une fois le nombre de fichiers connu.
      this.quota.consume(quotaKey, admin, 1);

      const maxBytes = this.uploadService.maxBytesFor(type);
      const maxFiles = mode === 'single' ? 1 : MAX_FILES_PER_REQUEST;
      const declared = Number(req.headers['content-length']);
      if (
        Number.isFinite(declared) &&
        declared > maxBytes * maxFiles + MULTIPART_OVERHEAD_BYTES
      ) {
        throw new PayloadTooLargeException(
          `Fichier trop volumineux. Maximum ${this.mo(maxBytes)} Mo par fichier.`,
        );
      }

      const parser = multer({
        storage: memoryStorage(),
        limits: {
          fileSize: maxBytes,
          files: maxFiles,
          fields: 5,
          fieldSize: 10 * 1024,
          parts: maxFiles + 5,
        },
      });
      const handler =
        mode === 'single'
          ? parser.single('file')
          : parser.array('files', MAX_FILES_PER_REQUEST);

      try {
        await new Promise<void>((resolve, reject) => {
          handler(req as any, res as any, (err: unknown) =>
            err ? reject(err) : resolve(),
          );
        });
      } catch (err: any) {
        throw this.translate(err, maxBytes, mode);
      }

      if (mode === 'multiple') {
        const count = ((req as any).files as unknown[] | undefined)?.length ?? 0;
        if (count > 1) this.quota.consume(quotaKey, admin, count - 1);
      }

      return next.handle();
    }

    private mo(bytes: number): string {
      const v = bytes / 1024 / 1024;
      return Number.isInteger(v) ? String(v) : v.toFixed(1);
    }

    private translate(err: any, maxBytes: number, m: 'single' | 'multiple') {
      switch (err?.code) {
        case 'LIMIT_FILE_SIZE':
          return new PayloadTooLargeException(
            `Fichier trop volumineux. Maximum ${this.mo(maxBytes)} Mo par fichier.`,
          );
        case 'LIMIT_UNEXPECTED_FILE':
          return new BadRequestException(
            `Champ de fichier inattendu : utilisez le champ "${m === 'single' ? 'file' : 'files'}" (maximum ${m === 'single' ? 1 : MAX_FILES_PER_REQUEST} fichier(s)).`,
          );
        case 'LIMIT_FILE_COUNT':
          return new BadRequestException(
            `Maximum ${MAX_FILES_PER_REQUEST} fichiers par requête`,
          );
        default:
          return new BadRequestException(
            "Envoi de fichier invalide ou incomplet. Réessayez.",
          );
      }
    }
  }
  return mixin(MixinInterceptor);
}
