import {
  Injectable,
  NotFoundException,
  ForbiddenException,
  BadRequestException,
  ConflictException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, Like, In, SelectQueryBuilder } from 'typeorm';

import { Product, ProductStatus }    from './entities/product.entity';
import { ProductVariant }            from './entities/product-variant.entity';
import { ProductImage }              from './entities/product-image.entity';
import { ProductTag }                from './entities/product-tag.entity';
import { ProductTierPrice }          from './entities/product-tier-price.entity';
import { Category }                  from '../categories/entities/category.entity';
import { VendorProfile, VendorStatus } from '../users/entities/vendor-profile.entity';
import { toPublicVendor } from './public-vendor.util';

import { CreateProductDto }   from './dto/create-product.dto';
import { UpdateProductDto }   from './dto/update-product.dto';
import { CreateVariantDto }   from './dto/create-variant.dto';
import { UpdateVariantDto }   from './dto/update-variant.dto';
import { CreateTierPriceDto } from './dto/create-tier-price.dto';

import { ActivityLogService } from '../../common/services/activity-log.service';
import { UploadService, UploadType } from '../upload/upload.service';
import {
  ActorType,
  LogAction,
} from '../../common/entities/activity-log.entity';

// Stock « technique » de la variante unique d'un livre numérique : un livre
// ne s'épuise jamais. Les contrôles de stock existants (panier, commande,
// paiement) passent donc sans modification, et la décrémentation est ignorée
// pour les livres (voir PaymentsService.confirmPayment).
export const DIGITAL_BOOK_STOCK = 999999;

@Injectable()
export class ProductsService {

  constructor(
    @InjectRepository(Product)
    private readonly productRepo: Repository<Product>,

    @InjectRepository(ProductVariant)
    private readonly variantRepo: Repository<ProductVariant>,

    @InjectRepository(ProductImage)
    private readonly imageRepo: Repository<ProductImage>,

    @InjectRepository(ProductTag)
    private readonly tagRepo: Repository<ProductTag>,

    @InjectRepository(ProductTierPrice)
    private readonly tierRepo: Repository<ProductTierPrice>,

    @InjectRepository(Category)
    private readonly categoryRepo: Repository<Category>,

    @InjectRepository(VendorProfile)
    private readonly vendorRepo: Repository<VendorProfile>,

    private readonly logService: ActivityLogService,

    // Contrôle « l'URL de l'image vient bien de notre stockage ».
    private readonly uploadService: UploadService,
  ) {}

  // ─────────────────────────────────────────────────────
  // CRÉER UN PRODUIT
  // ─────────────────────────────────────────────────────
  async create(
    userId: string,
    dto:    CreateProductDto,
    ip:     string,
  ) {
    // 1. Vérifier que le vendeur est approuvé
    const vendor = await this.vendorRepo.findOne({
      where: { userId },
    });

    if (!vendor) {
      throw new ForbiddenException(
        'Vous devez avoir une boutique active pour ajouter des produits'
      );
    }

    if (vendor.status !== VendorStatus.APPROVED) {
      throw new ForbiddenException(
        'Votre boutique doit être validée pour ajouter des produits'
      );
    }

    // 2. Vérifier les catégories
    const categories = await this.categoryRepo.find({
      where: { id: In(dto.categoryIds) },
    });

    if (categories.length !== dto.categoryIds.length) {
      throw new BadRequestException(
        'Une ou plusieurs catégories sont introuvables'
      );
    }

    // 3. Vérifier les catégories actives
    const inactive = categories.filter(c => !c.isActive);
    if (inactive.length > 0) {
      throw new BadRequestException(
        'Une ou plusieurs catégories sont inactives'
      );
    }

    // 3 bis. Nature du produit : livre numérique (PDF) ou produit physique.
    const isDigital = dto.isDigital === true;
    let fileSizeBytes: number | null = null;
    if (isDigital) {
      if (!dto.author?.trim())   throw new BadRequestException('L\'auteur du livre est obligatoire');
      if (dto.pageCount === undefined) throw new BadRequestException('Le nombre de pages est obligatoire');
      if (!dto.language?.trim()) throw new BadRequestException('La langue du livre est obligatoire');
      if (!dto.filePath)         throw new BadRequestException('Le fichier PDF du livre est obligatoire');
      if (categories.some(c => !c.isDigital)) {
        throw new BadRequestException(
          'Un livre numérique doit être rangé dans une catégorie « numérique »'
        );
      }
      // Taille relevée dans le stockage (jamais fournie par le client) ; refuse
      // un chemin invalide ou un fichier qui n'a pas été envoyé.
      fileSizeBytes = await this.uploadService.getEbookSize(dto.filePath);
    } else {
      if (!(dto.basePrice > 0)) {
        throw new BadRequestException('Le prix doit être positif');
      }
      if (dto.author || dto.pageCount !== undefined || dto.language || dto.filePath) {
        throw new BadRequestException(
          'Auteur, pages, langue et fichier PDF sont réservés aux livres numériques'
        );
      }
      if (categories.some(c => c.isDigital)) {
        throw new BadRequestException(
          'Une catégorie numérique est réservée aux livres numériques'
        );
      }
    }

    // 4. Générer le slug unique
    const slug = await this.generateUniqueSlug(dto.prod_name);

    // 5. Créer le produit
    const product     = this.productRepo.create();
    product.vendorId  = vendor.id;
    product.prod_name = dto.prod_name;
    product.slug      = slug;
    product.description = dto.description;
    product.basePrice = dto.basePrice;
    product.weight    = isDigital ? null : (dto.weight    ?? null);
    product.dimensions = isDigital ? null : (dto.dimensions ?? null);
    product.status    = dto.status    ?? ProductStatus.DRAFT;
    product.categories = categories;
    product.isDigital = isDigital;
    if (isDigital) {
      product.author        = dto.author!.trim();
      product.pageCount     = dto.pageCount!;
      product.language      = dto.language!.trim();
      product.filePath      = dto.filePath!;
      product.fileSizeBytes = fileSizeBytes;
    }

    await this.productRepo.save(product);

    // Livre : une variante unique « technique » créée côté serveur (le panier
    // et les commandes reposent sur une variante). Pas de couleur/taille,
    // stock fictif jamais décrémenté. Si elle échoue, on annule le produit.
    if (isDigital) {
      try {
        const variant         = this.variantRepo.create();
        variant.productId     = product.id;
        variant.sku           = `BOOK-${product.id}`;
        variant.color         = null;
        variant.size          = null;
        variant.model         = null;
        variant.price         = dto.basePrice;
        variant.stockQuantity = DIGITAL_BOOK_STOCK;
        variant.lowStockAlert = 0;
        variant.imageUrl      = null;
        variant.isActive      = true;
        await this.variantRepo.save(variant);
      } catch (e) {
        await this.productRepo.delete({ id: product.id });
        throw e;
      }
    }

    // 6. Créer les tags si fournis
    if (dto.tags?.length) {
      const tags = dto.tags.map(tag => {
        const t       = this.tagRepo.create();
        t.productId   = product.id;
        t.tag         = tag.toLowerCase().trim();
        return t;
      });
      await this.tagRepo.save(tags);
    }

    await this.logService.log({
      actorId:    userId,
      actorType:  ActorType.VENDOR,
      action:     LogAction.PRODUCT_CREATED,
      entityType: 'product',
      entityId:   product.id,
      newValue:   { name: product.prod_name, status: product.status, isDigital },
      ipAddress:  ip,
    });

    return this.findOne(product.id);
  }

  // ─────────────────────────────────────────────────────
  // LISTE PUBLIQUE DES PRODUITS (avec filtres)
  // ─────────────────────────────────────────────────────
  async findAll(params: {
    page?:       number;
    limit?:      number;
    search?:     string;
    categoryId?: string;
    vendorId?:   string;
    onlyDigital?: boolean;
    minPrice?:   number;
    maxPrice?:   number;
    status?:     ProductStatus;
  }) {
    const {
      page       = 1,
      limit      = 20,
      search,
      categoryId,
      vendorId,
      onlyDigital,
      minPrice,
      maxPrice,
      status     = ProductStatus.ACTIVE,
    } = params;

    // Optimisation : QueryBuilder pour filtres dynamiques.
    // Jointures + règle de visibilité partagées avec la vitrine (voir
    // createPublicListQuery) : un produit renvoyé par /vitrine doit avoir
    // EXACTEMENT la même forme JSON qu'un élément de GET /products.
    // Tri STABLE (createdAt puis id) : deux produits créés à la même
    // milliseconde ne peuvent ni se doubler ni sauter d'une page à l'autre
    // pendant le défilement infini de l'accueil.
    const query = this.createPublicListQuery(status)
      .orderBy('product.createdAt', 'DESC')
      .addOrderBy('product.id', 'DESC')
      .skip((page - 1) * limit)
      .take(limit);

    // Recherche textuelle sur nom et tags
    if (search) {
      query.andWhere(
        '(product.prod_name ILIKE :search OR EXISTS '
        + '(SELECT 1 FROM product_tags pt WHERE pt."productId" = product.id '
        + 'AND pt.tag ILIKE :search))',
        { search: `%${search}%` }
      );
    }

    if (categoryId) {
      // Un produit range uniquement dans une sous-categorie (ex: "Padel")
      // doit quand meme remonter quand on filtre sur sa categorie parente
      // (ex: "Sports") — sinon la categorie parente semble vide des qu'on
      // a des produits uniquement tagges sur ses sous-categories.
      const categoryIds = await this.resolveCategoryIdsWithDescendants(categoryId);
      query.andWhere(
        'EXISTS (SELECT 1 FROM product_categories pc '
        + 'WHERE pc."productId" = product.id '
        + 'AND pc."categoryId" IN (:...categoryIds))',
        { categoryIds }
      );
    }

    if (vendorId) {
      query.andWhere('product.vendorId = :vendorId', { vendorId });
    }

    // « Livres numériques » de la page Catégories : tous les produits numériques.
    if (onlyDigital) {
      query.andWhere('product.isDigital = true');
    }

    if (minPrice !== undefined) {
      query.andWhere('product.basePrice >= :minPrice', { minPrice });
    }

    if (maxPrice !== undefined) {
      query.andWhere('product.basePrice <= :maxPrice', { maxPrice });
    }

    const [products, total] = await query.getManyAndCount();

    // Ordre stable des prix dégressifs par quantité minimale croissante,
    // comme dans findOne() et findByVendor().
    for (const p of products) {
      p.tierPrices?.sort((a, b) => a.minQuantity - b.minQuantity);
      (p as any).vendor = this.toPublicVendor(p.vendor);
    }

    return {
      data:  products,
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
      // true = il reste au moins une page après celle-ci (défilement infini)
      hasMore: page * limit < total,
    };
  }

  // ─────────────────────────────────────────────────────
  // REQUÊTE DE BASE DE LA LISTE PUBLIQUE
  // ─────────────────────────────────────────────────────
  // Mêmes relations chargées et même règle de visibilité que GET /products.
  // Partagée avec la vitrine (VitrineService) pour que l'appli puisse
  // normaliser les produits des rayons avec le même code que /products.
  createPublicListQuery(
    status: ProductStatus = ProductStatus.ACTIVE,
  ): SelectQueryBuilder<Product> {
    return this.productRepo
      .createQueryBuilder('product')
      .leftJoinAndSelect('product.categories', 'category')
      .leftJoinAndSelect('product.vendor',     'vendor')
      .leftJoinAndSelect('product.images',     'image',
        'image.isPrimary = true')           // uniquement l'image principale
      .leftJoinAndSelect('product.variants',   'variant',
        'variant.isActive = true')
      // Prix dégressifs : les cartes produit côté client affichent une
      // fourchette "meilleur palier – prix normal". Sans cette relation,
      // l'appli n'a aucun moyen de connaître le palier le plus bas.
      .leftJoinAndSelect('product.tierPrices', 'tierPrices')
      .where('product.status = :status', { status })
      // Les produits d'un vendeur bloqué / rejeté / en attente, ou dont le
      // compte est désactivé, ne sont jamais visibles du public.
      .andWhere(this.vendorVisibilitySql('product'), {
        publicVendorStatus: VendorStatus.APPROVED,
      });
  }

  // Condition SQL "le vendeur du produit est public" : boutique approuvée ET
  // compte utilisateur actif. Écrite en sous-requête EXISTS pour fonctionner
  // sur n'importe quelle requête qui expose un alias de produit (comptages,
  // aperçus, rayons...), sans dépendre d'une jointure déjà présente.
  // Paramètre à fournir : publicVendorStatus (VendorStatus.APPROVED).
  private vendorVisibilitySql(alias: string): string {
    return 'EXISTS (SELECT 1 FROM vendor_profiles pubvp '
      + 'INNER JOIN users pubu ON pubu.id = pubvp."userId" '
      + `WHERE pubvp.id = "${alias}"."vendorId" `
      + 'AND pubvp.status = :publicVendorStatus '
      // Boutique masquée par l'admin (shopVisible = false) : ses produits
      // disparaissent des listes publiques. Le propriétaire garde l'accès
      // à ses produits (findByVendor / findOneForOwner n'utilisent pas
      // cette règle). Colonne créée par la migration 1791500000000.
      + 'AND pubvp."shopVisible" = true '
      + 'AND pubu."isActive" = true)';
  }

  // Voir public-vendor.util.ts (liste blanche des champs vendeur publics).
  // Ces endpoints produits sont consultables sans connexion : on retire donc
  // la présence (« En ligne / Vu à … ») qui, elle, n'est donnée qu'aux
  // utilisateurs connectés (fiche boutique, chat).
  private toPublicVendor(vendor: any): any {
    const pub = toPublicVendor(vendor);
    if (pub && typeof pub === 'object') {
      delete pub.lastSeenAt;
      delete pub.isOnline;
    }
    return pub;
  }

  // Ajoute à une requête quelconque la règle "produit visible
  // publiquement" (identique à findAll) sur l'alias donné. Sert aux
  // comptages (productCount des rayons, aperçus de l'annuaire des
  // boutiques) sans dupliquer la règle ailleurs.
  applyPublicVisibility<T extends object>(
    qb:    SelectQueryBuilder<T>,
    alias: string,
  ): SelectQueryBuilder<T> {
    return qb
      .andWhere(`${alias}.status = :publicProductStatus`, {
        publicProductStatus: ProductStatus.ACTIVE,
      })
      .andWhere(this.vendorVisibilitySql(alias), {
        publicVendorStatus: VendorStatus.APPROVED,
      });
  }

  // Parmi `ids`, ne garde que les produits visibles publiquement, en
  // conservant l'ordre d'origine (ordre d'un rayon de la vitrine).
  // Requête légère : seuls les ids sont lus.
  async filterPublicVisibleIds(ids: string[]): Promise<string[]> {
    if (!ids.length) return [];
    const qb = this.productRepo
      .createQueryBuilder('product')
      .select('product.id', 'id')
      .where('product.id IN (:...ids)', { ids });
    this.applyPublicVisibility(qb, 'product');
    const rows: { id: string }[] = await qb.getRawMany();
    const visible = new Set(rows.map((r) => r.id));
    return ids.filter((id) => visible.has(id));
  }

  // Produits visibles publiquement, chargés EXACTEMENT comme dans
  // findAll(), renvoyés dans l'ordre de `ids` (les invisibles sont omis).
  async findPublicByIds(ids: string[]): Promise<Product[]> {
    if (!ids.length) return [];
    const products = await this.createPublicListQuery()
      .andWhere('product.id IN (:...ids)', { ids })
      .getMany();

    // Même tri des prix dégressifs que findAll().
    for (const p of products) {
      p.tierPrices?.sort((a, b) => a.minQuantity - b.minQuantity);
      (p as any).vendor = this.toPublicVendor(p.vendor);
    }

    const byId = new Map(products.map((p) => [p.id, p]));
    return ids
      .map((id) => byId.get(id))
      .filter((p): p is Product => !!p);
  }

  // ─────────────────────────────────────────────────────
  // Résout un id de catégorie + tous ses descendants (sous-catégories,
  // sous-sous-catégories...). Le filtre categoryId doit couvrir toute la
  // branche de l'arbre, pas seulement la catégorie exacte choisie.
  // ─────────────────────────────────────────────────────
  // Public : réutilisé par l'annuaire des boutiques (VendorsService,
  // filtre categoryId de GET /vendors/directory).
  async resolveCategoryIdsWithDescendants(
    categoryId: string,
  ): Promise<string[]> {
    const ids: string[] = [categoryId];
    let frontier: string[] = [categoryId];

    // Profondeur max 3 niveaux (cf. Category.level), mais on boucle tant
    // qu'on trouve des enfants, par sécurité si la limite change un jour.
    while (frontier.length > 0) {
      const children = await this.categoryRepo.find({
        where: { parentId: In(frontier) },
        select: ['id'],
      });
      if (children.length === 0) break;
      const childIds = children.map((c) => c.id);
      ids.push(...childIds);
      frontier = childIds;
    }

    return ids;
  }

  // ─────────────────────────────────────────────────────
  // DÉTAILS D'UN PRODUIT — VUE PUBLIQUE (compte la visite)
  // ─────────────────────────────────────────────────────
  // Séparée de findOne() car celle-ci est aussi appelée en interne (après
  // création/modification d'un produit) : compter ces appels-là gonflerait
  // artificiellement les vues du vendeur.
  async findOnePublic(id: string) {
    const product = await this.findOne(id);

    // Brouillon ou produit désactivé, vendeur non approuvé ou compte
    // désactivé : pour le public, c'est comme si le produit n'existait pas.
    // (Le vendeur propriétaire passe par findOneForOwner pour modifier.)
    // Un produit en rupture de stock reste consultable.
    if (
      product.status === ProductStatus.DRAFT
      || product.status === ProductStatus.INACTIVE
      || product.vendor?.status !== VendorStatus.APPROVED
      || (product.vendor?.user as any)?.isActive === false
      || (product.vendor as any)?.shopVisible === false
    ) {
      throw new NotFoundException('Produit introuvable');
    }

    // Best-effort : un compteur de vues qui échoue ne doit jamais empêcher
    // l'affichage de la fiche produit (même principe que visitCount côté
    // boutique, voir VendorsService.getPublicShop).
    try {
      await this.productRepo.increment({ id }, 'nombreVues', 1);
      (product as any).nombreVues = (product.nombreVues ?? 0) + 1;
    } catch {
      // On renvoie quand même le produit, avec le compteur non incrémenté.
    }

    (product as any).vendor = this.toPublicVendor(product.vendor);
    return product;
  }

  // ─────────────────────────────────────────────────────
  // DÉTAILS D'UN PRODUIT — VUE DU VENDEUR PROPRIÉTAIRE
  // ─────────────────────────────────────────────────────
  // Sert à l'écran de modification : renvoie le produit quel que soit son
  // statut (brouillon compris), mais seulement à son propriétaire. Ne compte
  // pas de visite.
  async findOneForOwner(id: string, userId: string) {
    const product = await this.findOne(id);
    await this.checkOwnership(product, userId);
    (product as any).vendor = this.toPublicVendor(product.vendor);
    return product;
  }

  // ─────────────────────────────────────────────────────
  // DÉTAILS D'UN PRODUIT
  // ─────────────────────────────────────────────────────
  async findOne(id: string) {
    const product = await this.productRepo.findOne({
      where:     { id },
      relations: [
        'categories',
        'images',
        'variants',
        'tags',
        'tierPrices',
        'vendor',
        'vendor.user',
      ],
    });

    if (!product) throw new NotFoundException('Produit introuvable');

    // Ordre stable pour la fiche produit : galerie (image principale puis
    // sortOrder) et prix dégressifs par quantité minimale croissante.
    // TypeORM ne garantit aucun ordre sur les relations chargées ainsi.
    product.images?.sort(
      (a, b) =>
        Number(b.isPrimary) - Number(a.isPrimary) || a.sortOrder - b.sortOrder,
    );
    product.tierPrices?.sort((a, b) => a.minQuantity - b.minQuantity);

    // ⚠️ Ne pas exposer les données du vendeur sensibles
    if (product.vendor?.user) {
      const { passwordHash, ...userSafe } = product.vendor.user as any;
      (product.vendor as any).user = userSafe;
    }

    return product;
  }

  // ─────────────────────────────────────────────────────
  // MODIFIER UN PRODUIT
  // ─────────────────────────────────────────────────────
  async update(
    productId: string,
    userId:    string,
    dto:       UpdateProductDto,
    ip:        string,
  ) {
    const product = await this.productRepo.findOne({
      where:     { id: productId },
      relations: ['vendor', 'categories', 'tags'],
    });

    if (!product) throw new NotFoundException('Produit introuvable');

    // ⚠️ Vérifier que c'est bien son produit
    await this.checkOwnership(product, userId);

    const oldValue = {
      name:   product.prod_name,
      status: product.status,
      price:  product.basePrice,
    };

    // `null` explicite (accepté par @IsOptional) : refusé, ces champs ne se vident pas.
    const rawDto = dto as unknown as Record<string, unknown>;
    for (const k of ['author', 'pageCount', 'language', 'filePath', 'isDigital']) {
      if (rawDto[k] === null) {
        throw new BadRequestException(`Le champ « ${k} » ne peut pas être vide.`);
      }
    }
    // La nature (livre / produit physique) est définitive.
    if (dto.isDigital !== undefined && dto.isDigital !== product.isDigital) {
      throw new BadRequestException(
        'La nature d\'un produit (livre numérique ou physique) ne peut pas être modifiée'
      );
    }
    if (!product.isDigital) {
      if (dto.basePrice !== undefined && !(dto.basePrice > 0)) {
        throw new BadRequestException('Le prix doit être positif');
      }
      if (dto.author !== undefined || dto.pageCount !== undefined || dto.language !== undefined || dto.filePath !== undefined) {
        throw new BadRequestException(
          'Auteur, pages, langue et fichier PDF sont réservés aux livres numériques'
        );
      }
    } else {
      if (dto.author !== undefined && !dto.author.trim()) {
        throw new BadRequestException('L\'auteur du livre est obligatoire');
      }
      if (dto.language !== undefined && !dto.language.trim()) {
        throw new BadRequestException('La langue du livre est obligatoire');
      }
    }

    if (dto.prod_name)   {
      product.prod_name = dto.prod_name;
      product.slug      = await this.generateUniqueSlug(
        dto.prod_name,
        productId,
      );
    }
    if (dto.description !== undefined) product.description = dto.description;
    if (dto.basePrice   !== undefined) product.basePrice   = dto.basePrice;
    if (!product.isDigital) {
      if (dto.weight      !== undefined) product.weight      = dto.weight;
      if (dto.dimensions  !== undefined) product.dimensions  = dto.dimensions;
    }
    if (dto.status      !== undefined) {
      // Produit désactivé par l'administration : le vendeur ne peut pas le
      // remettre en vente (ni changer son statut).
      if (product.isBlockedByAdmin && dto.status !== product.status) {
        throw new ForbiddenException(
          'Ce produit a été désactivé par l\'administration'
          + (product.adminBlockReason ? ` (motif : ${product.adminBlockReason})` : '')
          + '. Contactez le support pour le réactiver.',
        );
      }
      product.status = dto.status;
    }

    // Fiche du livre numérique
    if (product.isDigital) {
      if (dto.author    !== undefined) product.author    = dto.author.trim();
      if (dto.pageCount !== undefined) product.pageCount = dto.pageCount;
      if (dto.language  !== undefined) product.language  = dto.language.trim();
      if (dto.filePath  !== undefined) {
        product.fileSizeBytes = await this.uploadService.getEbookSize(dto.filePath);
        product.filePath      = dto.filePath;
      }
    }

    // Mettre à jour les catégories si fournies
    if (dto.categoryIds?.length) {
      const categories = await this.categoryRepo.find({
        where: { id: In(dto.categoryIds) },
      });
      if (categories.length !== dto.categoryIds.length) {
        throw new BadRequestException('Une ou plusieurs catégories sont introuvables');
      }
      // Nature des catégories = nature du produit (livre ↔ catégorie numérique).
      if (categories.some(c => c.isDigital !== product.isDigital)) {
        throw new BadRequestException(
          product.isDigital
            ? 'Un livre numérique doit être rangé dans une catégorie « numérique »'
            : 'Une catégorie numérique est réservée aux livres numériques'
        );
      }
      product.categories = categories;
    }

    // Mettre à jour les tags si fournis
    if (dto.tags !== undefined) {
      // Supprimer les anciens tags
      await this.tagRepo.delete({ productId });

      // Créer les nouveaux
      if (dto.tags.length) {
        const tags = dto.tags.map(tag => {
          const t     = this.tagRepo.create();
          t.productId = productId;
          t.tag       = tag.toLowerCase().trim();
          return t;
        });
        await this.tagRepo.save(tags);
      }
    }

    await this.productRepo.save(product);

    // Livre : le prix de la variante technique suit le prix du livre.
    if (product.isDigital && dto.basePrice !== undefined) {
      await this.variantRepo.update({ productId }, { price: dto.basePrice });
    }

    await this.logService.log({
      actorId:    userId,
      actorType:  ActorType.VENDOR,
      action:     LogAction.PRODUCT_UPDATED,
      entityType: 'product',
      entityId:   productId,
      oldValue,
      newValue: {
        name:   product.prod_name,
        status: product.status,
        price:  product.basePrice,
      },
      ipAddress: ip,
    });

    return this.findOne(productId);
  }

  // ─────────────────────────────────────────────────────
  // SUPPRIMER UN PRODUIT
  // ─────────────────────────────────────────────────────
  async remove(
    productId: string,
    userId:    string,
    ip:        string,
  ) {
    const product = await this.productRepo.findOne({
      where:     { id: productId },
      relations: ['vendor'],
    });

    if (!product) throw new NotFoundException('Produit introuvable');

    await this.checkOwnership(product, userId);

    // ⚠️ Ne pas supprimer un produit qui a des commandes en cours
    // Ce check sera renforcé dans le module orders
    // On passe le produit en INACTIVE plutôt que supprimer
    product.status = ProductStatus.INACTIVE;
    // Produit bloqué par l'admin puis supprimé par le vendeur : à la
    // réactivation par l'admin, il ne doit PAS repasser en vente.
    if (product.isBlockedByAdmin) {
      product.adminBlockedFromStatus = ProductStatus.INACTIVE;
    }
    await this.productRepo.save(product);

    await this.logService.log({
      actorId:    userId,
      actorType:  ActorType.VENDOR,
      action:     LogAction.PRODUCT_DELETED,
      entityType: 'product',
      entityId:   productId,
      oldValue:   { name: product.prod_name },
      ipAddress:  ip,
    });

    return { message: 'Produit désactivé avec succès' };
  }

  // ─────────────────────────────────────────────────────
  // VARIANTES — CRÉER
  // ─────────────────────────────────────────────────────
  async createVariant(
    productId: string,
    userId:    string,
    dto:       CreateVariantDto,
  ) {
    const product = await this.productRepo.findOne({
      where:     { id: productId },
      relations: ['vendor'],
    });

    if (!product) throw new NotFoundException('Produit introuvable');

    await this.checkOwnership(product, userId);
    this.assertNotDigital(product, 'ajouter une variante');

    // Image de variante : doit être un fichier de NOTRE stockage (type
    // « products »), pas une URL quelconque.
    if (dto.imageUrl) {
      this.uploadService.assertIsOwnUploadUrl(dto.imageUrl, UploadType.PRODUCT);
    }

    // Vérifier l'unicité du SKU
    const skuExists = await this.variantRepo.findOne({
      where: { sku: dto.sku },
    });
    if (skuExists) {
      throw new ConflictException('Ce SKU est déjà utilisé');
    }

    const variant           = this.variantRepo.create();
    variant.productId       = productId;
    variant.sku             = dto.sku;
    variant.color           = dto.color      ?? null;
    variant.size            = dto.size       ?? null;
    variant.model           = dto.model      ?? null;
    variant.price           = dto.price;
    variant.stockQuantity   = dto.stockQuantity;
    variant.lowStockAlert   = dto.lowStockAlert ?? 5;
    variant.imageUrl        = dto.imageUrl   ?? null;
    variant.isActive        = true;

    return this.variantRepo.save(variant);
  }

  // ─────────────────────────────────────────────────────
  // VARIANTES — MODIFIER
  // ─────────────────────────────────────────────────────
  async updateVariant(
    productId: string,
    variantId: string,
    userId:    string,
    dto:       UpdateVariantDto,
  ) {
    const product = await this.productRepo.findOne({
      where:     { id: productId },
      relations: ['vendor'],
    });

    if (!product) throw new NotFoundException('Produit introuvable');

    await this.checkOwnership(product, userId);
    this.assertNotDigital(product, 'modifier une variante');

    const variant = await this.variantRepo.findOne({
      where: { id: variantId, productId },
    });

    if (!variant) throw new NotFoundException('Variante introuvable');

    // Nouvelle image de variante : doit venir de notre stockage. Une valeur
    // identique à celle déjà enregistrée n'est pas re-contrôlée (fiches
    // existantes / données de départ non cassées).
    if (dto.imageUrl && dto.imageUrl !== variant.imageUrl) {
      this.uploadService.assertIsOwnUploadUrl(dto.imageUrl, UploadType.PRODUCT);
    }

    // Vérifier l'unicité du SKU si changé
    if (dto.sku && dto.sku !== variant.sku) {
      const skuExists = await this.variantRepo.findOne({
        where: { sku: dto.sku },
      });
      if (skuExists) throw new ConflictException('Ce SKU est déjà utilisé');
    }

    Object.assign(variant, dto);
    return this.variantRepo.save(variant);
  }

  // ─────────────────────────────────────────────────────
  // IMAGES — AJOUTER
  // ─────────────────────────────────────────────────────
  async addImage(
    productId: string,
    userId:    string,
    imageUrl:  string,
    isPrimary: boolean = false,
    isVideo:   boolean = false,
  ) {
    const product = await this.productRepo.findOne({
      where:     { id: productId },
      relations: ['vendor'],
    });

    if (!product) throw new NotFoundException('Produit introuvable');

    await this.checkOwnership(product, userId);

    // L'image / la vidéo doit venir de NOTRE stockage (photos : type
    // « products » ; vidéos : « product-videos »), jamais d'une URL libre.
    this.uploadService.assertIsOwnUploadUrl(
      imageUrl,
      isVideo ? UploadType.PRODUCT_VIDEO : UploadType.PRODUCT,
    );

    // Si isPrimary → retirer le primary des autres images
    if (isPrimary) {
      await this.imageRepo.update(
        { productId },
        { isPrimary: false },
      );
    }

    // Vérifier le nombre d'images existantes
    const count = await this.imageRepo.count({ where: { productId } });

    const image         = this.imageRepo.create();
    image.productId     = productId;
    image.url           = imageUrl;
    image.isPrimary     = isPrimary || count === 0; // première image = primary
    image.isVideo       = isVideo;
    image.sortOrder     = count;

    return this.imageRepo.save(image);
  }

  // ─────────────────────────────────────────────────────
  // IMAGES — SUPPRIMER
  // ─────────────────────────────────────────────────────
  async removeImage(
    productId: string,
    imageId:   string,
    userId:    string,
  ) {
    const product = await this.productRepo.findOne({
      where:     { id: productId },
      relations: ['vendor'],
    });

    if (!product) throw new NotFoundException('Produit introuvable');

    await this.checkOwnership(product, userId);

    const image = await this.imageRepo.findOne({
      where: { id: imageId, productId },
    });

    if (!image) throw new NotFoundException('Image introuvable');

    const wasPrimary = image.isPrimary;
    await this.imageRepo.remove(image);

    // Si c'était l'image principale → mettre la suivante en primary
    if (wasPrimary) {
      const next = await this.imageRepo.findOne({
        where: { productId },
        order: { sortOrder: 'ASC' },
      });
      if (next) {
        next.isPrimary = true;
        await this.imageRepo.save(next);
      }
    }

    return { message: 'Image supprimée' };
  }

  // ─────────────────────────────────────────────────────
  // PRIX DÉGRESSIFS — GÉRER
  // ─────────────────────────────────────────────────────
  async setTierPrices(
    productId: string,
    userId:    string,
    tiers:     CreateTierPriceDto[],
  ) {
    const product = await this.productRepo.findOne({
      where:     { id: productId },
      relations: ['vendor'],
    });

    if (!product) throw new NotFoundException('Produit introuvable');

    await this.checkOwnership(product, userId);
    this.assertNotDigital(product, 'définir des prix par quantité');

    // ⚠️ Le corps est un TABLEAU : le ValidationPipe global ne valide pas
    // les éléments d'un tableau (CreateTierPriceDto n'est donc pas appliqué)
    // → contrôle manuel des valeurs ici.
    if (!Array.isArray(tiers)) {
      throw new BadRequestException('Liste de paliers de prix invalide');
    }
    for (const tier of tiers) {
      const min   = Number(tier?.minQuantity);
      const price = Number(tier?.price);
      if (!Number.isInteger(min) || min < 1 || !Number.isFinite(price) || price <= 0) {
        throw new BadRequestException(
          'Chaque palier doit avoir une quantité minimale (entier >= 1) et un prix positif'
        );
      }
    }

    // ⚠️ Vérifier la cohérence des paliers
    // Chaque minQuantity doit être > maxQuantity du palier précédent
    const sorted = [...tiers]
      .map(t => ({
        minQuantity: Number(t.minQuantity),
        maxQuantity:
          t.maxQuantity === undefined || t.maxQuantity === null
            ? undefined
            : Number(t.maxQuantity),
        price:       Number(t.price),
      }))
      .sort((a, b) => a.minQuantity - b.minQuantity);

    for (let i = 0; i < sorted.length - 1; i++) {
      const current = sorted[i];
      const next    = sorted[i + 1];

      if (next.minQuantity === current.minQuantity) {
        throw new BadRequestException(
          'Deux paliers de prix ne peuvent pas avoir la même quantité minimale'
        );
      }

      // L'app (publier_produit_screen) n'envoie que minQuantity + price :
      // avant, tout envoi de 2 paliers ou plus était rejeté ici ("Seul le
      // dernier palier peut avoir une quantité maximale illimitée") et
      // l'erreur, avalée côté app, faisait qu'AUCUN palier n'était
      // enregistré. Un palier intermédiaire sans maximum s'arrête donc
      // simplement juste avant le palier suivant.
      if (current.maxQuantity === undefined) {
        current.maxQuantity = next.minQuantity - 1;
      }

      if (next.minQuantity <= current.maxQuantity) {
        throw new BadRequestException(
          'Les paliers de prix ne doivent pas se chevaucher'
        );
      }
    }

    // Supprimer les anciens paliers
    await this.tierRepo.delete({ productId });

    // Créer les nouveaux
    const newTiers = sorted.map(tier => {
      const t         = this.tierRepo.create();
      t.productId     = productId;
      t.minQuantity   = tier.minQuantity;
      t.maxQuantity   = tier.maxQuantity ?? null;
      t.price         = tier.price;
      return t;
    });

    return this.tierRepo.save(newTiers);
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — METTRE EN VEDETTE UN PRODUIT
  // ─────────────────────────────────────────────────────
  async toggleFeatured(productId: string, adminId: string) {
    const product = await this.productRepo.findOne({
      where: { id: productId },
    });

    if (!product) throw new NotFoundException('Produit introuvable');

    product.isVedette = !product.isVedette;
    await this.productRepo.save(product);

    return {
      message:    product.isVedette
        ? 'Produit mis en vedette'
        : 'Produit retiré de la vedette',
      isVedette: product.isVedette,
    };
  }

  // ─────────────────────────────────────────────────────
  // PRODUITS D'UN VENDEUR
  // ─────────────────────────────────────────────────────
  async findByVendor(
    userId: string,
    status?: ProductStatus,
    page:   number = 1,
    limit:  number = 20,
  ) {
    const vendor = await this.vendorRepo.findOne({
      where: { userId },
    });

    if (!vendor) throw new NotFoundException('Boutique introuvable');

    const query = this.productRepo
      .createQueryBuilder('product')
      .leftJoinAndSelect('product.images',     'image', 'image.isPrimary = true')
      .leftJoinAndSelect('product.variants',   'variant')
      .leftJoinAndSelect('product.tierPrices', 'tierPrices')
      .where('product.vendorId = :vendorId', { vendorId: vendor.id })
      .orderBy('product.createdAt', 'DESC')
      .skip((page - 1) * limit)
      .take(limit);

    if (status) {
      query.andWhere('product.status = :status', { status });
    }

    const [products, total] = await query.getManyAndCount();

    // Ordre stable des prix dégressifs par quantité minimale croissante,
    // comme dans findOne().
    for (const p of products) {
      p.tierPrices?.sort((a, b) => a.minQuantity - b.minQuantity);
    }

    return {
      data:  products,
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
    };
  }

  // ─────────────────────────────────────────────────────
  // MÉTHODES PRIVÉES
  // ─────────────────────────────────────────────────────

  // Vérifie que le produit appartient bien au vendeur connecté
  // Un livre numérique n'a ni variantes ni prix par quantité (une seule variante
  // technique, créée par le serveur).
  private assertNotDigital(product: Product, action: string): void {
    if (product.isDigital) {
      throw new BadRequestException(
        `Un livre numérique ne permet pas de ${action}`
      );
    }
  }

  private async checkOwnership(
    product: Product,
    userId:  string,
  ): Promise<void> {
    const vendor = await this.vendorRepo.findOne({
      where: { userId },
    });

    if (!vendor || product.vendorId !== vendor.id) {
      throw new ForbiddenException(
        'Vous n\'êtes pas autorisé à modifier ce produit'
      );
    }
  }

  // Génère un slug unique en ajoutant un suffixe si nécessaire
  private async generateUniqueSlug(
    name:      string,
    excludeId?: string,
  ): Promise<string> {
    const base = name
      .toLowerCase()
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .replace(/[^a-z0-9\s-]/g, '')
      .trim()
      .replace(/\s+/g, '-')
      .replace(/-+/g, '-');

    let slug    = base;
    let counter = 1;

    while (true) {
      const existing = await this.productRepo.findOne({
        where: { slug },
      });

      // Pas de doublon, ou c'est le même produit qu'on met à jour
      if (!existing || existing.id === excludeId) {
        return slug;
      }

      // Ajouter un suffixe numérique
      slug = `${base}-${counter}`;
      counter++;
    }
  }
}