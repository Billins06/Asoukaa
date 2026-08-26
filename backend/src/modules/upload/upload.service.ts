import {
  Injectable,
  BadRequestException,
  InternalServerErrorException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { v4 as uuidv4 }  from 'uuid';
import { extname }       from 'path';

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

// Documents et selfies = pièces KYC sensibles → bucket privé, jamais public.
// Le reste (produits, boutique, avatar, chat, véhicule) → bucket public.
const PRIVATE_TYPES = new Set<UploadType>([UploadType.DOCUMENT, UploadType.SELFIE]);

// Durée de validité des URLs signées pour les fichiers privés (7 jours —
// le temps qu'un admin ait l'occasion de review un dossier vendeur).
// Au-delà, il faudra régénérer une URL via un endpoint dédié.
const SIGNED_URL_TTL_SECONDS = 60 * 60 * 24 * 7;

@Injectable()
export class UploadService {
  private readonly supabase: SupabaseClient;
  private readonly publicBucket: string;
  private readonly privateBucket: string;

  constructor(private readonly configService: ConfigService) {
    const supabaseUrl = this.configService.getOrThrow<string>('SUPABASE_URL');
    const serviceRoleKey = this.configService.getOrThrow<string>('SUPABASE_SERVICE_ROLE_KEY');

    this.supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    this.publicBucket = this.configService.get<string>('SUPABASE_PUBLIC_BUCKET') ?? 'asoukaa-public';
    this.privateBucket = this.configService.get<string>('SUPABASE_PRIVATE_BUCKET') ?? 'asoukaa-private';
  }

  private bucketFor(type: UploadType): { bucket: string; isPrivate: boolean } {
    const isPrivate = PRIVATE_TYPES.has(type);
    return { bucket: isPrivate ? this.privateBucket : this.publicBucket, isPrivate };
  }

  // ─────────────────────────────────────────────────────
  // UPLOAD D'UN FICHIER
  // ─────────────────────────────────────────────────────
  async uploadFile(
    file:        Express.Multer.File,
    type:        UploadType,
  ): Promise<{ url: string; path: string; filename: string; size: number }> {

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

    // 6. Construire le chemin dans le bucket (documents/selfies → privé, reste → public)
    const { bucket, isPrivate } = this.bucketFor(type);
    const storagePath = `${type}/${uniqueFilename}`;

    // 7. Upload vers Supabase Storage
    const { error: uploadError } = await this.supabase.storage
      .from(bucket)
      .upload(storagePath, file.buffer, {
        contentType: file.mimetype,
        upsert: false,
      });

    if (uploadError) {
      throw new InternalServerErrorException(
        `Échec de l'upload vers le stockage : ${uploadError.message}`
      );
    }

    // 8. Construire l'URL de retour
    const url = isPrivate
      ? await this.createSignedUrl(bucket, storagePath)
      : this.supabase.storage.from(bucket).getPublicUrl(storagePath).data.publicUrl;

    return {
      url,
      path:     `${bucket}/${storagePath}`,
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
  ): Promise<Array<{ url: string; path: string; filename: string; size: number }>> {

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
  // RÉGÉNÉRER UNE URL SIGNÉE (fichiers privés — documents/selfies)
  // À appeler quand une URL signée précédente a expiré (> 7 jours).
  // ─────────────────────────────────────────────────────
  async refreshSignedUrl(storedPath: string): Promise<string> {
    const [bucket, ...rest] = storedPath.split('/');
    const objectPath = rest.join('/');
    return this.createSignedUrl(bucket, objectPath);
  }

  private async createSignedUrl(bucket: string, objectPath: string): Promise<string> {
    const { data, error } = await this.supabase.storage
      .from(bucket)
      .createSignedUrl(objectPath, SIGNED_URL_TTL_SECONDS);

    if (error || !data) {
      throw new InternalServerErrorException(
        `Échec de génération de l'URL signée : ${error?.message ?? 'inconnue'}`
      );
    }

    return data.signedUrl;
  }

  // ─────────────────────────────────────────────────────
  // SUPPRIMER UN FICHIER
  // ─────────────────────────────────────────────────────
  // `storedPath` = valeur retournée dans `path` par uploadFile, ex: "asoukaa-public/products/uuid.jpg"
  async deleteFile(storedPath: string): Promise<void> {
    try {
      const [bucket, ...rest] = storedPath.split('/');
      const objectPath = rest.join('/');

      if (!bucket || !objectPath || storedPath.includes('..')) {
        throw new BadRequestException('Chemin de fichier invalide');
      }

      const { error } = await this.supabase.storage.from(bucket).remove([objectPath]);
      if (error) {
        console.error('Erreur suppression fichier Supabase:', error.message);
      }
    } catch (error) {
      // On ne bloque pas l'app si le fichier n'existe pas
      // (peut être déjà supprimé)
      console.error('Erreur suppression fichier:', error.message);
    }
  }
}