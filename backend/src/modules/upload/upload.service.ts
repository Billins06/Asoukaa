import {
  Injectable,
  BadRequestException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { v4 as uuidv4 }  from 'uuid';
import { extname, join } from 'path';
import * as fs           from 'fs/promises';

// Types de fichiers autorisés selon le contexte
export enum UploadType {
  DOCUMENT = 'documents',
  SELFIE   = 'selfies',
  VEHICLE  = 'vehicles',
  PRODUCT  = 'products',
  AVATAR   = 'avatars',
  SHOP     = 'shop',
  CHAT     = 'chat',
}

// Types MIME autorisés
const ALLOWED_MIME_TYPES = [
  'image/jpeg',
  'image/jpg',
  'image/png',
  'image/webp',
  'application/pdf',
];

// Extensions autorisées
const ALLOWED_EXTENSIONS = ['.jpg', '.jpeg', '.png', '.webp', '.pdf'];

@Injectable()
export class UploadService {

  constructor(private readonly configService: ConfigService) {}

  // ─────────────────────────────────────────────────────
  // UPLOAD D'UN FICHIER
  // ─────────────────────────────────────────────────────
  async uploadFile(
    file:        Express.Multer.File,
    type:        UploadType,
  ): Promise<{ url: string; filename: string; size: number }> {

    // 1. Vérifier qu'un fichier a bien été envoyé
    if (!file) {
      throw new BadRequestException('Aucun fichier reçu');
    }

    // 2. Vérifier la taille
    const maxSize = this.configService.get<number>('MAX_FILE_SIZE') ?? 5242880;
    if (file.size > maxSize) {
      throw new BadRequestException(
        `Fichier trop volumineux. Maximum ${maxSize / 1024 / 1024} MB`
      );
    }

    // 3. Vérifier le type MIME
    if (!ALLOWED_MIME_TYPES.includes(file.mimetype)) {
      throw new BadRequestException(
        `Type de fichier non autorisé. Formats acceptés : JPG, PNG, WEBP, PDF`
      );
    }

    // 4. Vérifier l'extension du fichier
    const ext = extname(file.originalname).toLowerCase();
    if (!ALLOWED_EXTENSIONS.includes(ext)) {
      throw new BadRequestException(
        `Extension non autorisée. Extensions acceptées : ${ALLOWED_EXTENSIONS.join(', ')}`
      );
    }

    // 5. Générer un nom de fichier unique
    // ⚠️ On NE garde JAMAIS le nom original du fichier
    // Risque de path traversal et conflits
    const uniqueFilename = `${uuidv4()}${ext}`;

    // 6. Construire le chemin
    const uploadDir = join(process.cwd(), 'uploads', type);
    const filePath  = join(uploadDir, uniqueFilename);

    // 7. S'assurer que le dossier existe
    await fs.mkdir(uploadDir, { recursive: true });

    // 8. Écrire le fichier
    await fs.writeFile(filePath, file.buffer);

    // 9. Construire l'URL publique
    const appUrl = this.configService.get<string>('APP_URL') ?? 'http://localhost:3000';
    const url    = `${appUrl}/uploads/${type}/${uniqueFilename}`;

    return {
      url,
      filename: uniqueFilename,
      size:     file.size,
    };
  }

  // ─────────────────────────────────────────────────────
  // UPLOAD DE PLUSIEURS FICHIERS
  // ─────────────────────────────────────────────────────
  async uploadMultiple(
    files: Express.Multer.File[],
    type:  UploadType,
  ): Promise<Array<{ url: string; filename: string; size: number }>> {

    if (!files || files.length === 0) {
      throw new BadRequestException('Aucun fichier reçu');
    }

    // Limite : 10 fichiers max par requête
    if (files.length > 10) {
      throw new BadRequestException('Maximum 10 fichiers par requête');
    }

    const uploads = await Promise.all(
      files.map(file => this.uploadFile(file, type))
    );

    return uploads;
  }

  // ─────────────────────────────────────────────────────
  // SUPPRIMER UN FICHIER
  // ─────────────────────────────────────────────────────
  async deleteFile(fileUrl: string): Promise<void> {
    try {
      const appUrl = this.configService.get<string>('APP_URL') ?? 'http://localhost:3000';

      // Extraire le chemin relatif depuis l'URL
      // Ex: http://localhost:3000/uploads/products/abc.jpg → uploads/products/abc.jpg
      const relativePath = fileUrl.replace(`${appUrl}/`, '');

      // ⚠️ Sécurité : empêcher path traversal
      // Le chemin ne doit jamais contenir ".." ou commencer par "/"
      if (
        relativePath.includes('..') ||
        relativePath.startsWith('/') ||
        relativePath.startsWith('\\')
      ) {
        throw new BadRequestException('Chemin de fichier invalide');
      }

      const filePath = join(process.cwd(), relativePath);
      await fs.unlink(filePath);

    } catch (error) {
      // On ne bloque pas l'app si le fichier n'existe pas
      // (peut être déjà supprimé)
      console.error('Erreur suppression fichier:', error.message);
    }
  }
}