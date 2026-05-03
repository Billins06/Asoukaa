import {
  Injectable,
  NotFoundException,
  ForbiddenException,
  BadRequestException,
  ConflictException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, Like, In } from 'typeorm';

import { Product, ProductStatus }    from './entities/product.entity';
import { ProductVariant }            from './entities/product-variant.entity';
import { ProductImage }              from './entities/product-image.entity';
import { ProductTag }                from './entities/product-tag.entity';
import { ProductTierPrice }          from './entities/product-tier-price.entity';
import { Category }                  from '../categories/entities/category.entity';
import { VendorProfile, VendorStatus } from '../users/entities/vendor-profile.entity';

import { CreateProductDto }   from './dto/create-product.dto';
import { UpdateProductDto }   from './dto/update-product.dto';
import { CreateVariantDto }   from './dto/create-variant.dto';
import { UpdateVariantDto }   from './dto/update-variant.dto';
import { CreateTierPriceDto } from './dto/create-tier-price.dto';

import { ActivityLogService } from '../../common/services/activity-log.service';
import {
  ActorType,
  LogAction,
} from '../../common/entities/activity-log.entity';

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

    // 4. Générer le slug unique
    const slug = await this.generateUniqueSlug(dto.prod_name);

    // 5. Créer le produit
    const product     = this.productRepo.create();
    product.vendorId  = vendor.id;
    product.prod_name = dto.prod_name;
    product.slug      = slug;
    product.description = dto.description;
    product.basePrice = dto.basePrice;
    product.weight    = dto.weight    ?? null;
    product.dimensions = dto.dimensions ?? null;
    product.status    = dto.status    ?? ProductStatus.DRAFT;
    product.categories = categories;

    await this.productRepo.save(product);

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
      newValue:   { name: product.prod_name, status: product.status },
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
      minPrice,
      maxPrice,
      status     = ProductStatus.ACTIVE,
    } = params;

    // Optimisation : QueryBuilder pour filtres dynamiques
    const query = this.productRepo
      .createQueryBuilder('product')
      .leftJoinAndSelect('product.categories', 'category')
      .leftJoinAndSelect('product.images',     'image',
        'image.isPrimary = true')           // uniquement l'image principale
      .leftJoinAndSelect('product.variants',   'variant',
        'variant.isActive = true')
      .where('product.status = :status', { status })
      .orderBy('product.createdAt', 'DESC')
      .skip((page - 1) * limit)
      .take(limit);

    // Recherche textuelle sur nom et tags
    if (search) {
      query.andWhere(
        '(product.prod_name ILIKE :search OR EXISTS '
        + '(SELECT 1 FROM product_tags pt WHERE pt.product_id = product.id '
        + 'AND pt.tag ILIKE :search))',
        { search: `%${search}%` }
      );
    }

    if (categoryId) {
      query.andWhere(
        'EXISTS (SELECT 1 FROM product_categories pc '
        + 'WHERE pc.product_id = product.id '
        + 'AND pc.category_id = :categoryId)',
        { categoryId }
      );
    }

    if (vendorId) {
      query.andWhere('product.vendorId = :vendorId', { vendorId });
    }

    if (minPrice !== undefined) {
      query.andWhere('product.basePrice >= :minPrice', { minPrice });
    }

    if (maxPrice !== undefined) {
      query.andWhere('product.basePrice <= :maxPrice', { maxPrice });
    }

    const [products, total] = await query.getManyAndCount();

    return {
      data:  products,
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
    };
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

    if (dto.prod_name)   {
      product.prod_name = dto.prod_name;
      product.slug      = await this.generateUniqueSlug(
        dto.prod_name,
        productId,
      );
    }
    if (dto.description !== undefined) product.description = dto.description;
    if (dto.basePrice   !== undefined) product.basePrice   = dto.basePrice;
    if (dto.weight      !== undefined) product.weight      = dto.weight;
    if (dto.dimensions  !== undefined) product.dimensions  = dto.dimensions;
    if (dto.status      !== undefined) product.status      = dto.status;

    // Mettre à jour les catégories si fournies
    if (dto.categoryIds?.length) {
      const categories = await this.categoryRepo.find({
        where: { id: In(dto.categoryIds) },
      });
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

    const variant = await this.variantRepo.findOne({
      where: { id: variantId, productId },
    });

    if (!variant) throw new NotFoundException('Variante introuvable');

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

    // ⚠️ Vérifier la cohérence des paliers
    // Chaque minQuantity doit être > maxQuantity du palier précédent
    const sorted = [...tiers].sort(
      (a, b) => a.minQuantity - b.minQuantity
    );

    for (let i = 0; i < sorted.length - 1; i++) {
      const current = sorted[i];
      const next    = sorted[i + 1];

      if (current.maxQuantity === undefined || current.maxQuantity === null) {
        throw new BadRequestException(
          'Seul le dernier palier peut avoir une quantité maximale illimitée'
        );
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
      .leftJoinAndSelect('product.images',   'image', 'image.isPrimary = true')
      .leftJoinAndSelect('product.variants', 'variant')
      .where('product.vendorId = :vendorId', { vendorId: vendor.id })
      .orderBy('product.createdAt', 'DESC')
      .skip((page - 1) * limit)
      .take(limit);

    if (status) {
      query.andWhere('product.status = :status', { status });
    }

    const [products, total] = await query.getManyAndCount();

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