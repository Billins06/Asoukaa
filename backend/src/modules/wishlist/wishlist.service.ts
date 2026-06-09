import {
  Injectable,
  NotFoundException,
  ConflictException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository }       from 'typeorm';

import { Wishlist }        from './entities/wishlist.entity';
import { Product, ProductStatus } from '../products/entities/product.entity';
import { AddToWishlistDto } from './dto/add-to-wishlist.dto';

@Injectable()
export class WishlistService {

  constructor(
    @InjectRepository(Wishlist)
    private readonly wishlistRepo: Repository<Wishlist>,

    @InjectRepository(Product)
    private readonly productRepo: Repository<Product>,
  ) {}

  // ─────────────────────────────────────────────────────
  // AJOUTER À LA WISHLIST
  // ─────────────────────────────────────────────────────
  async add(userId: string, dto: AddToWishlistDto) {
    // 1. Vérifier que le produit existe et est actif
    const product = await this.productRepo.findOne({
      where: { id: dto.productId },
    });

    if (!product) {
      throw new NotFoundException('Produit introuvable');
    }

    if (product.status !== ProductStatus.ACTIVE) {
      throw new NotFoundException('Ce produit n\'est plus disponible');
    }

    // 2. Vérifier qu'il n'est pas déjà dans la wishlist
    const existing = await this.wishlistRepo.findOne({
      where: { userId, productId: dto.productId },
    });

    if (existing) {
      throw new ConflictException(
        'Ce produit est déjà dans votre wishlist'
      );
    }

    // 3. Ajouter à la wishlist
    const item       = this.wishlistRepo.create();
    item.userId      = userId;
    item.productId   = dto.productId;

    await this.wishlistRepo.save(item);

    return {
      message: 'Produit ajouté à votre wishlist',
      item,
    };
  }

  // ─────────────────────────────────────────────────────
  // MA WISHLIST
  // ─────────────────────────────────────────────────────
  async getMyWishlist(
    userId: string,
    page:   number = 1,
    limit:  number = 20,
  ) {
    const query = this.wishlistRepo
      .createQueryBuilder('wishlist')
      .leftJoinAndSelect('wishlist.product',  'product')
      .leftJoinAndSelect(
        'product.images',
        'image',
        'image.isPrimary = true',
      )
      .leftJoinAndSelect('product.vendor', 'vendor')
      .where('wishlist.userId = :userId', { userId })
      .andWhere('product.status = :status', {
        status: ProductStatus.ACTIVE,
      })
      .orderBy('wishlist.createdAt', 'DESC')
      .skip((page - 1) * limit)
      .take(limit);

    const [items, total] = await query.getManyAndCount();

    return {
      data:  items,
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
    };
  }

  // ─────────────────────────────────────────────────────
  // RETIRER UN PRODUIT DE LA WISHLIST
  // ─────────────────────────────────────────────────────
  async remove(userId: string, productId: string) {
    const item = await this.wishlistRepo.findOne({
      where: { userId, productId },
    });

    if (!item) {
      throw new NotFoundException(
        'Ce produit n\'est pas dans votre wishlist'
      );
    }

    await this.wishlistRepo.remove(item);

    return { message: 'Produit retiré de votre wishlist' };
  }

  // ─────────────────────────────────────────────────────
  // VIDER LA WISHLIST
  // ─────────────────────────────────────────────────────
  async clear(userId: string) {
    const result = await this.wishlistRepo.delete({ userId });

    return {
      message: 'Wishlist vidée',
      count:   result.affected ?? 0,
    };
  }

  // ─────────────────────────────────────────────────────
  // VÉRIFIER SI UN PRODUIT EST DANS MA WISHLIST
  // (utilisé par l'app mobile pour afficher le coeur plein/vide)
  // ─────────────────────────────────────────────────────
  async isInWishlist(userId: string, productId: string) {
    const item = await this.wishlistRepo.findOne({
      where: { userId, productId },
    });

    return { inWishlist: !!item };
  }

  // ─────────────────────────────────────────────────────
  // COMPTER LES ÉLÉMENTS DE MA WISHLIST
  // ─────────────────────────────────────────────────────
  async count(userId: string) {
    const count = await this.wishlistRepo.count({
      where: { userId },
    });

    return { count };
  }
}