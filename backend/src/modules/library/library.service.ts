import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { DataSource, Repository } from 'typeorm';

import { LibraryItem } from './entities/library-item.entity';
import { Product } from '../products/entities/product.entity';
import { UploadService } from '../upload/upload.service';
import { ActivityLogService } from '../../common/services/activity-log.service';
import { ActorType, LogAction } from '../../common/entities/activity-log.entity';

// Durée de vie du lien de téléchargement : juste le temps de lancer le
// téléchargement. Un lien copié/partagé ne sert donc à rien quelques minutes plus tard.
const DOWNLOAD_LINK_TTL_SECONDS = 120;

@Injectable()
export class LibraryService {
  constructor(
    @InjectRepository(LibraryItem)
    private readonly itemRepo: Repository<LibraryItem>,

    @InjectRepository(Product)
    private readonly productRepo: Repository<Product>,

    private readonly dataSource: DataSource,
    private readonly uploadService: UploadService,
    private readonly logService: ActivityLogService,
  ) {}

  // Identifiants des livres que le client possède (accès actif) : sert à
  // afficher « Déjà acheté » sur les fiches et à retirer ces livres du panier.
  async myProductIds(userId: string): Promise<string[]> {
    const rows: Array<{ productId: string }> = await this.dataSource.query(
      `SELECT "productId" FROM "library_items"
        WHERE "userId" = $1 AND "revokedAt" IS NULL`,
      [userId],
    );
    return rows.map(r => r.productId);
  }

  // « Ma Bibliothèque » : un élément par livre acheté (plus récent d'abord).
  // Aucun chemin de fichier ni lien : seulement la fiche du livre.
  async myLibrary(userId: string) {
    const rows = await this.dataSource.query(
      `SELECT l."id", l."productId", l."orderId", l."createdAt" AS "purchasedAt",
              l."downloadCount", l."firstDownloadedAt", l."lastDownloadedAt",
              p."prod_name" AS "title", p."author", p."pageCount", p."language",
              p."fileSizeBytes", p."status" AS "productStatus",
              v."shopName",
              (SELECT pi."url" FROM "product_images" pi
                WHERE pi."productId" = p."id" AND pi."isVideo" = false
                ORDER BY pi."isPrimary" DESC, pi."sortOrder" ASC LIMIT 1) AS "coverUrl"
         FROM "library_items" l
         JOIN "products" p ON p."id" = l."productId"
         LEFT JOIN "vendor_profiles" v ON v."id" = p."vendorId"
        WHERE l."userId" = $1 AND l."revokedAt" IS NULL
        ORDER BY l."createdAt" DESC`,
      [userId],
    );
    return rows.map((r: any) => ({
      ...r,
      fileSizeBytes: r.fileSizeBytes === null || r.fileSizeBytes === undefined
        ? null
        : Number(r.fileSizeBytes),
    }));
  }

  // Délivre un lien de téléchargement COURT. Vérifie côté serveur : (1) le
  // client possède le livre (accès non retiré) ; (2) le paiement de la commande
  // est confirmé (ou livre gratuit) ; (3) le fichier existe. Tout refus renvoie
  // la MÊME réponse 404 (on ne révèle rien sur un livre qu'on ne possède pas).
  async createDownloadLink(userId: string, productId: string, ip: string) {
    const notOwned = new NotFoundException('Livre introuvable dans votre Bibliothèque');

    const item = await this.itemRepo.findOne({
      where: { userId, productId },
    });
    if (!item || item.revokedAt) throw notOwned;

    const paid: unknown[] = await this.dataSource.query(
      `SELECT 1 FROM "payments" pay
         JOIN "orders" o ON o."id" = pay."orderId"
        WHERE o."id" = $1 AND o."userId" = $2
          AND pay."status" = 'success' AND o."status" <> 'annulé'
        LIMIT 1`,
      [item.orderId, userId],
    );
    if (!Array.isArray(paid) || paid.length === 0) throw notOwned;

    // filePath est en select:false : on le demande explicitement, ici seulement.
    const product = await this.productRepo
      .createQueryBuilder('p')
      .addSelect('p.filePath')
      .where('p.id = :id', { id: productId })
      .getOne();
    if (!product?.filePath) {
      throw new NotFoundException('Le fichier de ce livre est momentanément indisponible');
    }

    const downloadName = this.fileNameFor(product.prod_name);
    const url = await this.uploadService.createEbookDownloadUrl(
      product.filePath,
      DOWNLOAD_LINK_TTL_SECONDS,
      downloadName,
    );

    await this.dataSource.query(
      `UPDATE "library_items"
          SET "downloadCount" = "downloadCount" + 1,
              "firstDownloadedAt" = COALESCE("firstDownloadedAt", now()),
              "lastDownloadedAt" = now()
        WHERE "id" = $1`,
      [item.id],
    );
    await this.logService.log({
      actorId:    userId,
      actorType:  ActorType.CLIENT,
      action:     LogAction.EBOOK_DOWNLOADED,
      entityType: 'product',
      entityId:   productId,
      newValue:   { orderId: item.orderId },
      ipAddress:  ip,
    });

    return { url, fileName: downloadName, expiresInSeconds: DOWNLOAD_LINK_TTL_SECONDS };
  }

  // « Titre du livre » → « Titre-du-livre.pdf » (sans accents ni caractères
  // spéciaux, 80 caractères maximum).
  private fileNameFor(title: string): string {
    const base = (title || 'livre')
      .normalize('NFD').replace(/[̀-ͯ]/g, '')
      .replace(/[^A-Za-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .slice(0, 80) || 'livre';
    return `${base}.pdf`;
  }
}
