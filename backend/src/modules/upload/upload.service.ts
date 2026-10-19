import {
  Injectable,
  BadRequestException,
  InternalServerErrorException,
  PayloadTooLargeException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { DataSource } from 'typeorm';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { v4 as uuidv4 }  from 'uuid';
import { extname, join } from 'path';
import { promises as fs } from 'fs';
import { createHmac, timingSafeEqual } from 'crypto';

export enum UploadType {
  DOCUMENT      = 'documents',
  SELFIE        = 'selfies',
  VEHICLE       = 'vehicles',
  PRODUCT       = 'products',
  AVATAR        = 'avatars',
  SHOP          = 'shop',
  CHAT          = 'chat',
  // Photos/preuves du parcours de livraison (ramassage, remise au
  // transporteur, réception client) — voir DeliveryProof.
  PROOF         = 'proofs',
  // Vidéo de présentation d'un produit (ProductImage.isVideo = true).
  // Fichier plus volumineux qu'une image → mimetypes et taille max
  // dédiés, voir VIDEO_MIME_TYPES / VIDEO_EXTENSIONS / maxVideoFileSize.
  PRODUCT_VIDEO = 'product-videos',
  // Images de la vitrine (rayons, bandeau d'accueil) — réservé aux
  // admins, voir ADMIN_ONLY_UPLOAD_TYPES.
  VITRINE       = 'vitrine',
  // Images des catégories du catalogue — réservé aux admins.
  CATEGORY      = 'categories',
  // Captures d'écran / photos jointes aux tickets de support (3 par
  // message max) — images uniquement, ouvert à tout compte connecté.
  TICKET        = 'tickets',
  // Livres numériques (PDF) — stockage PRIVÉ, jamais d'URL publique : le client
  // télécharge via un lien signé court délivré par le module library.
  // Réservé aux vendeurs approuvés, PDF uniquement.
  EBOOK         = 'ebooks',
}

const ALLOWED_MIME_TYPES = ['image/jpeg','image/jpg','image/png','image/webp','application/pdf'];
const ALLOWED_EXTENSIONS = ['.jpg', '.jpeg', '.png', '.webp', '.pdf'];
// Vidéo produit : formats les plus courants côté vendeur mobile
// (export iPhone = .mov/quicktime, Android = .mp4, web = .webm).
const VIDEO_MIME_TYPES = ['video/mp4', 'video/quicktime', 'video/webm'];
const VIDEO_EXTENSIONS = ['.mp4', '.mov', '.webm'];
const VIDEO_UPLOAD_TYPES = new Set<UploadType>([UploadType.PRODUCT_VIDEO]);
// Plafond par défaut pour une vidéo produit (50 MB) : nettement plus
// gros qu'une image mais reste raisonnable pour un plan Supabase
// Storage standard/gratuit et pour de la donnée mobile. Surchargeable
// via MAX_VIDEO_FILE_SIZE (en octets), sur le même modèle que
// MAX_FILE_SIZE pour les images/documents.
export const DEFAULT_MAX_VIDEO_FILE_SIZE = 50 * 1024 * 1024;
// Livre numérique : PDF uniquement, 50 Mo par défaut (MAX_EBOOK_FILE_SIZE, en octets).
export const DEFAULT_MAX_EBOOK_FILE_SIZE = 50 * 1024 * 1024;
const EBOOK_UPLOAD_TYPES = new Set<UploadType>([UploadType.EBOOK]);
const PRIVATE_TYPES = new Set<UploadType>([UploadType.DOCUMENT, UploadType.SELFIE, UploadType.EBOOK]);
// Types publics alimentés uniquement depuis le back-office : seul un
// compte ADMIN/SUPERADMIN peut y envoyer un fichier (contrôle dans
// UploadController). Sans ça, n'importe quel client connecté pourrait
// déposer des fichiers dans le dossier servi pour la vitrine/les catégories.
const ADMIN_ONLY_UPLOAD_TYPES = new Set<UploadType>([UploadType.VITRINE, UploadType.CATEGORY]);
// Types "image uniquement" : pas de PDF, le fichier est toujours affiché
// comme une image (vitrine, catégories, avatar, logo/bannière de boutique,
// photos produit, photo de véhicule, selfie). Les vidéos produit ont leur
// propre type (PRODUCT_VIDEO) ; DOCUMENT et PROOF gardent le PDF ; CHAT
// n'est pas restreint (aucun usage connu du client pour ce type).
const IMAGE_ONLY_UPLOAD_TYPES = new Set<UploadType>([
  UploadType.VITRINE,
  UploadType.CATEGORY,
  UploadType.AVATAR,
  UploadType.SHOP,
  UploadType.PRODUCT,
  UploadType.VEHICLE,
  UploadType.SELFIE,
  UploadType.TICKET,
]);
const IMAGE_MIME_TYPES = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp'];
const IMAGE_EXTENSIONS = ['.jpg', '.jpeg', '.png', '.webp'];

// Octets magiques : on ne se fie pas au mimetype/à l'extension annoncés par
// le client, on vérifie les premiers octets du fichier reçu.
function isJpeg(b: Buffer): boolean {
  return b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff;
}
function isPng(b: Buffer): boolean {
  return b.length >= 8 && b.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
}
function isWebp(b: Buffer): boolean {
  return b.length >= 12
    && b.subarray(0, 4).toString('latin1') === 'RIFF'
    && b.subarray(8, 12).toString('latin1') === 'WEBP';
}
function isPdf(b: Buffer): boolean {
  return b.length >= 5 && b.subarray(0, 5).toString('latin1') === '%PDF-';
}
function matchesImageSignature(b: Buffer): boolean {
  return isJpeg(b) || isPng(b) || isWebp(b);
}
// MP4 / MOV (QuickTime) : conteneur ISO-BMFF, la boîte « ftyp » commence à
// l'octet 4 (les 4 premiers octets sont la taille de la boîte).
function isIsoBmff(b: Buffer): boolean {
  return b.length >= 12 && b.subarray(4, 8).toString('latin1') === 'ftyp';
}
// WEBM : en-tête EBML (1A 45 DF A3) dont le « DocType » est « webm »
// (ce qui écarte les fichiers Matroska .mkv).
function isWebm(b: Buffer): boolean {
  return b.length >= 16
    && b[0] === 0x1a && b[1] === 0x45 && b[2] === 0xdf && b[3] === 0xa3
    && b.subarray(0, Math.min(b.length, 64)).toString('latin1').includes('webm');
}
const SIGNED_URL_TTL_SECONDS = 60 * 60 * 24 * 7;

// 📁 Repli "stockage local" (dev) : activé via STORAGE_DRIVER=local dans
// .env. Utile quand la machine ne peut pas joindre Supabase Storage
// (proxy d'entreprise qui bloque les appels sortants de Node, projet
// Supabase gratuit en pause, etc.) — le contrat de retour
// ({url, path, filename, size}) reste identique quel que soit le driver,
// donc ni le frontend ni le reste du backend n'ont besoin de savoir
// lequel est actif. On reprend le dossier `uploads/{type}/` qui existait
// déjà (voir .gitignore) — c'était visiblement le stockage d'origine
// avant le passage à Supabase.
const LOCAL_UPLOAD_ROOT = join(process.cwd(), 'uploads');

@Injectable()
export class UploadService {
  private readonly driver: 'supabase' | 'local';
  private readonly supabase: SupabaseClient | null = null;
  private readonly publicBucket: string;
  private readonly privateBucket: string;
  private readonly appUrl: string;
  private readonly supabaseUrl: string | null = null;

  constructor(
    private readonly configService: ConfigService,
    private readonly dataSource: DataSource,
  ) {
    this.driver = (this.configService.get<string>('STORAGE_DRIVER') ?? 'supabase') === 'local'
      ? 'local'
      : 'supabase';
    this.publicBucket = this.configService.get<string>('SUPABASE_PUBLIC_BUCKET') ?? 'asoukaa-public';
    this.privateBucket = this.configService.get<string>('SUPABASE_PRIVATE_BUCKET') ?? 'asoukaa-private';
    const port = this.configService.get<number>('APP_PORT') ?? this.configService.get<number>('PORT') ?? 3000;
    this.appUrl = (this.configService.get<string>('APP_URL') ?? `http://localhost:${port}`).replace(/\/$/, '');

    if (this.driver === 'supabase') {
      const supabaseUrl = this.configService.getOrThrow<string>('SUPABASE_URL');
      const serviceRoleKey = this.configService.getOrThrow<string>('SUPABASE_SERVICE_ROLE_KEY');
      this.supabase = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });
      this.supabaseUrl = supabaseUrl;
    }
  }

  private bucketFor(type: UploadType): { bucket: string; isPrivate: boolean } {
    const isPrivate = PRIVATE_TYPES.has(type);
    return { bucket: isPrivate ? this.privateBucket : this.publicBucket, isPrivate };
  }

  // Utilisé par le contrôleur pour savoir si un type doit passer par la
  // route authentifiée (documents/selfies) ou par le fichier statique
  // public, quand le driver local est actif.
  isPrivateType(type: string): boolean {
    return PRIVATE_TYPES.has(type as UploadType);
  }

  // Utilisé par le contrôleur : ces types ne peuvent être envoyés que
  // par un compte ADMIN/SUPERADMIN (images de vitrine et de catégories).
  isAdminOnlyType(type: string): boolean {
    return ADMIN_ONLY_UPLOAD_TYPES.has(type as UploadType);
  }

  // Types d'envoi connus (valeurs de UploadType) — utilisé par
  // UploadParseInterceptor pour refuser un type inconnu AVANT de lire le fichier.
  isKnownType(type: string): boolean {
    return (Object.values(UploadType) as string[]).includes(type);
  }

  knownTypes(): string[] {
    return Object.values(UploadType) as string[];
  }

  // Taille maximale (en octets) d'un fichier pour un type d'envoi :
  // vidéos produit → MAX_VIDEO_FILE_SIZE (50 Mo par défaut) ; tous les autres
  // types (images, PDF) → MAX_FILE_SIZE (5 Mo par défaut). Une valeur de .env
  // absente ou invalide retombe sur le défaut.
  maxBytesFor(type: string): number {
    const positive = (raw: unknown, fallback: number): number => {
      const n = Number(raw);
      return Number.isFinite(n) && n > 0 ? Math.trunc(n) : fallback;
    };
    if (EBOOK_UPLOAD_TYPES.has(type as UploadType)) {
      return positive(this.configService.get('MAX_EBOOK_FILE_SIZE'), DEFAULT_MAX_EBOOK_FILE_SIZE);
    }
    return VIDEO_UPLOAD_TYPES.has(type as UploadType)
      ? positive(this.configService.get('MAX_VIDEO_FILE_SIZE'), DEFAULT_MAX_VIDEO_FILE_SIZE)
      : positive(this.configService.get('MAX_FILE_SIZE'), 5242880);
  }

  // Vérifie qu'une URL de fichier soumise par un client (ex: dans une
  // preuve de livraison) pointe bien vers un fichier hébergé par NOTRE
  // propre stockage — jamais une URL externe arbitraire. Sans ce
  // contrôle, n'importe qui pourrait soumettre l'URL d'une image
  // hébergée ailleurs comme "preuve", y compris une URL malveillante
  // affichée ensuite dans l'appli d'un autre utilisateur.
  // ⚠️ Ne vérifie pas que le fichier existe réellement sur le disque —
  // seulement qu'il a la forme d'une URL émise par notre propre route
  // d'upload. L'upload lui-même (types/tailles autorisés) est déjà
  // validé par uploadFile() au moment de l'envoi du fichier.
  assertIsOwnUploadUrl(url: string, type: UploadType): void {
    if (!url || typeof url !== 'string') {
      throw new BadRequestException('URL de fichier manquante ou invalide');
    }

    let parsed: URL;
    try {
      parsed = new URL(url);
    } catch {
      throw new BadRequestException('URL de fichier invalide');
    }

    if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') {
      throw new BadRequestException('URL de fichier invalide');
    }

    const pathContainsType = parsed.pathname.includes(`/${type}/`);

    if (this.driver === 'local') {
      const isOwnHost = `${parsed.protocol}//${parsed.host}` === this.appUrl;
      // En développement l'appli réécrit l'adresse locale (localhost) vers
      // celle du tunnel / de l'IP du réseau (voir ApiService côté Flutter) :
      // le fichier est le même, seul l'hôte change. On accepte alors ces
      // hôtes de test SEULEMENT si le chemin a exactement la forme d'un
      // fichier émis par notre route d'upload (type + nom UUID + extension).
      const filePath = new RegExp(
        `^/(?:uploads|api/v1/upload/file)/${type}/[0-9a-f-]{36}\\.[a-z0-9]{2,5}$`,
        'i',
      );
      const host = parsed.hostname.toLowerCase();
      const isDevAccessHost =
        host === 'localhost'
        || /^127\./.test(host)
        || /^10\./.test(host)
        || /^192\.168\./.test(host)
        || /^172\.(1[6-9]|2\d|3[01])\./.test(host)
        || host.endsWith('.trycloudflare.com')
        || host.endsWith('.ngrok-free.app')
        || host.endsWith('.ngrok.io')
        || host.endsWith('.ngrok.app');
      const isReachableOwnFile = isDevAccessHost && filePath.test(parsed.pathname);
      // Documents/selfies (privés) : seule la forme EXACTE émise par notre
      // route d'upload est acceptée, quel que soit l'hôte — sinon on pourrait
      // enregistrer une URL « /quelconque/documents/<nom d'autrui> » sur notre
      // propre hôte pour se faire passer pour propriétaire du fichier.
      const isStrictPrivateOk = !this.isPrivateType(type) || filePath.test(parsed.pathname);
      if ((!isOwnHost && !isReachableOwnFile) || !pathContainsType || !isStrictPrivateOk) {
        throw new BadRequestException(
          'Ce fichier ne provient pas du stockage de l\'application'
        );
      }
      return;
    }

    // Driver supabase : l'URL doit pointer vers notre propre projet
    // Supabase et notre propre bucket.
    const isOwnSupabaseHost = this.supabaseUrl
      ? parsed.host === new URL(this.supabaseUrl).host
      : false;

    if (this.isPrivateType(type)) {
      // Documents/selfies : stockés dans le bucket PRIVÉ, l'URL émise par
      // l'upload est une URL signée « …/storage/v1/object/sign/<bucket privé>/
      // <type>/<uuid>.<ext>?token=… ». On exige exactement cette forme (le
      // bucket public n'est PAS valable pour ces types).
      const escapedBucket = this.privateBucket.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      const privatePath = new RegExp(
        `^/storage/v1/object/(?:sign|authenticated)/${escapedBucket}/${type}/[0-9a-f-]{36}\\.[a-z0-9]{2,5}$`,
        'i',
      );
      if (!isOwnSupabaseHost || !privatePath.test(parsed.pathname)) {
        throw new BadRequestException(
          'Ce fichier ne provient pas du stockage de l\'application'
        );
      }
      return;
    }

    const isOwnBucket = parsed.pathname.includes(`/${this.publicBucket}/`);

    if (!isOwnSupabaseHost || !isOwnBucket || !pathContainsType) {
      throw new BadRequestException(
        'Ce fichier ne provient pas du stockage de l\'application'
      );
    }
  }

  async uploadFile(file: Express.Multer.File, type: UploadType): Promise<{ url: string; path: string; filename: string; size: number }> {
    if (!file) throw new BadRequestException('Aucun fichier reçu');

    const isVideoType = VIDEO_UPLOAD_TYPES.has(type);
    const isEbookType = EBOOK_UPLOAD_TYPES.has(type);
    const isImageOnlyType = IMAGE_ONLY_UPLOAD_TYPES.has(type);
    const allowedMimeTypes = isVideoType
      ? VIDEO_MIME_TYPES
      : isEbookType ? ['application/pdf']
      : isImageOnlyType ? IMAGE_MIME_TYPES : ALLOWED_MIME_TYPES;
    const allowedExtensions = isVideoType
      ? VIDEO_EXTENSIONS
      : isEbookType ? ['.pdf']
      : isImageOnlyType ? IMAGE_EXTENSIONS : ALLOWED_EXTENSIONS;
    // Même valeur que la limite Multer appliquée à la réception (deuxième
    // barrière, au cas où le service serait appelé ailleurs que par la route).
    const maxSize = this.maxBytesFor(type);

    if (file.size > maxSize) throw new PayloadTooLargeException(`Fichier trop volumineux. Maximum ${maxSize / 1024 / 1024} Mo`);
    if (!allowedMimeTypes.includes(file.mimetype)) {
      throw new BadRequestException(
        isVideoType
          ? `Type de fichier non autorisé. Formats acceptés : MP4, MOV, WEBM`
          : isEbookType
            ? `Type de fichier non autorisé. Seul le format PDF est accepté pour un livre`
          : isImageOnlyType
            ? `Type de fichier non autorisé. Formats acceptés : JPG, PNG, WEBP`
            : `Type de fichier non autorisé. Formats acceptés : JPG, PNG, WEBP, PDF`
      );
    }
    const ext = extname(file.originalname).toLowerCase();
    if (!allowedExtensions.includes(ext)) throw new BadRequestException(`Extension non autorisée. Extensions acceptées : ${allowedExtensions.join(', ')}`);

    // Contenu réel (octets « magiques »), cohérent avec ce que le fichier
    // prétend être (mimetype + extension) :
    //  - vidéo : MP4/MOV (« ftyp ») ou WEBM (EBML + DocType webm) ;
    //  - PDF annoncé : doit commencer par « %PDF- » ;
    //  - image annoncée : JPEG, PNG ou WEBP.
    // Un fichier dont les octets ne correspondent pas est refusé même si son
    // mimetype/extension sont acceptables.
    const buf = file.buffer;
    if (isVideoType) {
      const wantsWebm = ext === '.webm' || file.mimetype === 'video/webm';
      const videoOk = !!buf && (wantsWebm ? isWebm(buf) : isIsoBmff(buf));
      if (!videoOk) {
        throw new BadRequestException(
          'Le contenu du fichier n\'est pas une vidéo valide (MP4, MOV, WEBM)'
        );
      }
    } else {
      const wantsPdf = isEbookType || ext === '.pdf' || file.mimetype === 'application/pdf';
      const contentOk = !!buf && (wantsPdf ? isPdf(buf) : matchesImageSignature(buf));
      if (!contentOk) {
        throw new BadRequestException(
          isEbookType
            ? 'Le contenu du fichier n\'est pas un PDF valide'
          : isImageOnlyType
            ? 'Le contenu du fichier n\'est pas une image valide (JPG, PNG, WEBP)'
            : 'Le contenu du fichier n\'est pas une image ou un PDF valide'
        );
      }
    }
    const uniqueFilename = `${uuidv4()}${ext}`;

    return this.driver === 'local'
      ? this.uploadFileLocal(file, type, uniqueFilename)
      : this.uploadFileSupabase(file, type, uniqueFilename);
  }

  private async uploadFileSupabase(file: Express.Multer.File, type: UploadType, uniqueFilename: string) {
    const { bucket, isPrivate } = this.bucketFor(type);
    const storagePath = `${type}/${uniqueFilename}`;
    const { error: uploadError } = await this.supabase!.storage.from(bucket).upload(storagePath, file.buffer, { contentType: file.mimetype, upsert: false });
    if (uploadError) throw new InternalServerErrorException(`Échec de l'upload vers le stockage : ${uploadError.message}`);
    // Livre numérique : AUCUNE URL renvoyée (le fichier ne se télécharge que via
    // la Bibliothèque, après achat) ; seul `path` est utile au formulaire.
    const url = EBOOK_UPLOAD_TYPES.has(type)
      ? ''
      : isPrivate
        ? await this.createSignedUrl(bucket, storagePath)
        : this.supabase!.storage.from(bucket).getPublicUrl(storagePath).data.publicUrl;
    return { url, path: `${bucket}/${storagePath}`, filename: uniqueFilename, size: file.size };
  }

  private async uploadFileLocal(file: Express.Multer.File, type: UploadType, uniqueFilename: string) {
    const { isPrivate } = this.bucketFor(type);
    const dir = join(LOCAL_UPLOAD_ROOT, type);
    try {
      await fs.mkdir(dir, { recursive: true });
      await fs.writeFile(join(dir, uniqueFilename), file.buffer);
    } catch (err) {
      throw new InternalServerErrorException(`Échec de l'upload vers le stockage local : ${(err as Error).message}`);
    }
    const url = EBOOK_UPLOAD_TYPES.has(type)
      ? ''
      : isPrivate
        ? `${this.appUrl}/api/v1/upload/file/${type}/${uniqueFilename}`
        : `${this.appUrl}/uploads/${type}/${uniqueFilename}`;
    return { url, path: `local/${type}/${uniqueFilename}`, filename: uniqueFilename, size: file.size };
  }

  async uploadMultiple(files: Express.Multer.File[], type: UploadType) {
    if (!files || files.length === 0) throw new BadRequestException('Aucun fichier reçu');
    if (files.length > 10) throw new BadRequestException('Maximum 10 fichiers par requête');
    return Promise.all(files.map(file => this.uploadFile(file, type)));
  }

  // Régénère une URL fraîche pour un document PRIVÉ (pièce d'identité,
  // selfie) tel qu'il est stocké en base. En mode Supabase, l'URL enregistrée
  // est une URL signée qui EXPIRE (7 jours) : sans ce rafraîchissement, l'admin
  // verrait des images cassées pour toute demande un peu ancienne.
  //  - mode local : l'URL de la route authentifiée n'expire pas → inchangée ;
  //  - URL/chemin d'un autre bucket (fichier public) → inchangé ;
  //  - toute erreur → on renvoie la valeur d'origine (jamais d'échec de la
  //    fiche admin à cause d'une image).
  async refreshPrivateUrl(stored: string | null | undefined): Promise<string | null> {
    if (!stored) return null;
    if (this.driver !== 'supabase' || !this.supabase) return stored;
    try {
      let path: string | null = stored;
      if (/^https?:\/\//i.test(stored)) {
        const m = new URL(stored).pathname.match(
          /\/storage\/v1\/object\/(?:sign|authenticated|public)\/(.+)$/,
        );
        path = m ? decodeURIComponent(m[1]) : null;
      }
      if (!path || path.split('/')[0] !== this.privateBucket) return stored;
      return await this.refreshSignedUrl(path);
    } catch {
      return stored;
    }
  }

  // Le compte `userId` est-il PROPRIÉTAIRE de ce fichier privé ? = son profil
  // vendeur ou livreur référence ce nom de fichier (documents → pièce d'identité,
  // selfies → selfie). Sert à la route GET /upload/file/:type/:filename.
  // Comparaison de fin de chaîne (RIGHT) et non LIKE : le nom contient « _ »
  // ou « % » possibles, qui sont des jokers LIKE.
  async isPrivateFileOwner(userId: string, type: string, filename: string): Promise<boolean> {
    if (!userId || !this.isPrivateType(type) || EBOOK_UPLOAD_TYPES.has(type as UploadType)) return false;
    if (!/^[A-Za-z0-9._-]{1,200}$/.test(filename) || filename.includes('..')) return false;

    const column = type === UploadType.DOCUMENT ? 'idDocumentUrl' : 'selfieUrl';
    const needle = `/${type}/${filename}`;
    // L'URL enregistrée doit SE TERMINER par « /<type>/<nom> » (et non le
    // contenir quelque part) : on retire d'abord un éventuel « ?token=… »
    // (URL signée Supabase) ou « #… », puis on compare la fin de la chaîne.
    // Sans cela, une URL arbitraire contenant le nom d'un fichier d'autrui
    // aurait fait passer le contrôle.
    const rows = await this.dataSource.query(
      `SELECT 1 FROM "vendor_profiles"
        WHERE "userId" = $1
          AND RIGHT(split_part(split_part(COALESCE("${column}", ''), '#', 1), '?', 1), char_length($2::text)) = $2::text
       UNION ALL
       SELECT 1 FROM "delivery_agent_profiles"
        WHERE "userId" = $1
          AND RIGHT(split_part(split_part(COALESCE("${column}", ''), '#', 1), '?', 1), char_length($2::text)) = $2::text
       LIMIT 1`,
      [userId, needle],
    );
    return Array.isArray(rows) && rows.length > 0;
  }

  // ─── Livres numériques ───────────────────────────────────────────────

  isEbookType(type: string): boolean {
    return EBOOK_UPLOAD_TYPES.has(type as UploadType);
  }

  // Le compte est-il un vendeur APPROUVÉ ? (envoi d'un PDF de livre)
  async isApprovedVendor(userId: string): Promise<boolean> {
    if (!userId) return false;
    const rows = await this.dataSource.query(
      `SELECT 1 FROM "vendor_profiles" WHERE "userId" = $1 AND "status" = 'approuvé' LIMIT 1`,
      [userId],
    );
    return Array.isArray(rows) && rows.length > 0;
  }

  // Un chemin de livre valide a EXACTEMENT la forme émise par notre upload :
  // « <bucket privé>/ebooks/<uuid>.pdf » (ou « local/ebooks/<uuid>.pdf »).
  // Empêche d'enregistrer un chemin arbitraire (autre bucket, autre dossier, « .. »).
  isEbookPath(path: string): boolean {
    if (typeof path !== 'string' || path.length > 500) return false;
    const head = this.driver === 'local' ? 'local' : this.privateBucket.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    return new RegExp(`^${head}/ebooks/[0-9a-f-]{36}\\.pdf$`, 'i').test(path);
  }

  // Taille réelle (octets) d'un PDF déjà envoyé ; lève une erreur claire s'il
  // n'existe pas. La taille vient du stockage, jamais du client.
  async getEbookSize(path: string): Promise<number> {
    if (!this.isEbookPath(path)) {
      throw new BadRequestException('Fichier du livre invalide : renvoyez le PDF.');
    }
    const [, type, filename] = path.split('/');
    const missing = new BadRequestException('Fichier PDF introuvable : renvoyez le PDF du livre.');
    if (this.driver === 'local') {
      try {
        const st = await fs.stat(join(LOCAL_UPLOAD_ROOT, type, filename));
        return st.size;
      } catch {
        throw missing;
      }
    }
    const { data, error } = await this.supabase!.storage.from(this.privateBucket).list(type, { search: filename, limit: 5 });
    if (error) throw new InternalServerErrorException(`Échec de lecture du stockage : ${error.message}`);
    const item = (data ?? []).find((f) => f.name === filename);
    const size = Number((item as any)?.metadata?.size);
    if (!item || !Number.isFinite(size) || size <= 0) throw missing;
    return size;
  }

  // Lien de téléchargement COURT (quelques minutes) vers un livre acheté.
  //  - Supabase : URL signée par le stockage, avec nom de fichier de téléchargement ;
  //  - local (dev) : jeton HMAC signé avec JWT_SECRET, lu par GET /library/file/:token.
  async createEbookDownloadUrl(path: string, ttlSeconds: number, downloadName: string): Promise<string> {
    if (!this.isEbookPath(path)) {
      throw new BadRequestException('Fichier du livre invalide');
    }
    if (this.driver === 'local') {
      const payload = Buffer.from(JSON.stringify({ p: path, e: Date.now() + ttlSeconds * 1000, n: downloadName })).toString('base64url');
      return `${this.appUrl}/api/v1/library/file/${payload}.${this.signLocalToken(payload)}`;
    }
    const objectPath = path.split('/').slice(1).join('/');
    const { data, error } = await this.supabase!.storage
      .from(this.privateBucket)
      .createSignedUrl(objectPath, ttlSeconds, { download: downloadName });
    if (error || !data) throw new InternalServerErrorException(`Échec de génération du lien de téléchargement : ${error?.message ?? 'inconnue'}`);
    return data.signedUrl;
  }

  private signLocalToken(payload: string): string {
    const secret = this.configService.getOrThrow<string>('JWT_SECRET');
    return createHmac('sha256', `ebook:${secret}`).update(payload).digest('base64url');
  }

  // Vérifie un jeton local (dev) : signature + expiration. Renvoie le chemin disque
  // et le nom de téléchargement, ou null si invalide/expiré.
  verifyLocalEbookToken(token: string): { filePath: string; downloadName: string } | null {
    if (this.driver !== 'local' || typeof token !== 'string') return null;
    const [payload, sig] = token.split('.');
    if (!payload || !sig) return null;
    const expected = this.signLocalToken(payload);
    const a = Buffer.from(sig);
    const b = Buffer.from(expected);
    if (a.length !== b.length || !timingSafeEqual(a, b)) return null;
    try {
      const { p, e, n } = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
      if (typeof p !== 'string' || typeof e !== 'number' || e < Date.now() || !this.isEbookPath(p)) return null;
      const [, type, filename] = p.split('/');
      return { filePath: join(LOCAL_UPLOAD_ROOT, type, filename), downloadName: typeof n === 'string' ? n : filename };
    } catch {
      return null;
    }
  }

  async refreshSignedUrl(storedPath: string): Promise<string> {
    if (storedPath.startsWith('local/')) {
      // Les fichiers locaux n'ont pas d'URL signée qui expire : on
      // reconstruit simplement l'URL correspondante.
      const [, type, filename] = storedPath.split('/');
      return this.isPrivateType(type)
        ? `${this.appUrl}/api/v1/upload/file/${type}/${filename}`
        : `${this.appUrl}/uploads/${type}/${filename}`;
    }
    const [bucket, ...rest] = storedPath.split('/');
    return this.createSignedUrl(bucket, rest.join('/'));
  }

  private async createSignedUrl(bucket: string, objectPath: string): Promise<string> {
    const { data, error } = await this.supabase!.storage.from(bucket).createSignedUrl(objectPath, SIGNED_URL_TTL_SECONDS);
    if (error || !data) throw new InternalServerErrorException(`Échec de génération de l'URL signée : ${error?.message ?? 'inconnue'}`);
    return data.signedUrl;
  }

  // Résout le chemin disque d'un fichier privé stocké en local, pour la
  // route authentifiée du contrôleur (JwtAuthGuard). Rejette toute
  // tentative de traversée de répertoire.
  resolveLocalFilePath(type: string, filename: string): string {
    if (type.includes('..') || type.includes('/') || filename.includes('..') || filename.includes('/')) {
      throw new BadRequestException('Chemin de fichier invalide');
    }
    return join(LOCAL_UPLOAD_ROOT, type, filename);
  }

  async deleteFile(storedPath: string): Promise<void> {
    try {
      if (storedPath.startsWith('local/')) {
        const [, type, filename] = storedPath.split('/');
        if (!type || !filename || storedPath.includes('..')) throw new BadRequestException('Chemin de fichier invalide');
        await fs.unlink(join(LOCAL_UPLOAD_ROOT, type, filename)).catch(() => {});
        return;
      }
      const [bucket, ...rest] = storedPath.split('/');
      const objectPath = rest.join('/');
      if (!bucket || !objectPath || storedPath.includes('..')) throw new BadRequestException('Chemin de fichier invalide');
      const { error } = await this.supabase!.storage.from(bucket).remove([objectPath]);
      if (error) console.error('Erreur suppression fichier Supabase:', error.message);
    } catch (error) {
      console.error('Erreur suppression fichier:', (error as Error).message);
    }
  }
}
