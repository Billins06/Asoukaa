import {
  Injectable,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository }       from 'typeorm';

import { Cart }            from './entities/cart.entity';
import { CartItem }        from './entities/cart-item.entity';
import { ProductVariant }  from '../products/entities/product-variant.entity';
import { AddToCartDto }    from './dto/add-to-cart.dto';
import { UpdateCartItemDto } from './dto/update-cart-item.dto';

@Injectable()
export class CartService {

  constructor(
    @InjectRepository(Cart)
    private readonly cartRepo: Repository<Cart>,

    @InjectRepository(CartItem)
    private readonly cartItemRepo: Repository<CartItem>,

    @InjectRepository(ProductVariant)
    private readonly variantRepo: Repository<ProductVariant>,
  ) {}

  // ─────────────────────────────────────────────────────
  // RÉCUPÉRER OU CRÉER LE PANIER
  // ─────────────────────────────────────────────────────
  private async getOrCreateCart(userId: string): Promise<Cart> {
    let cart = await this.cartRepo.findOne({
      where:     { userId },
      relations: [
        'items',
        'items.variant',
        'items.variant.product',
        'items.variant.product.images',
      ],
    });

    if (!cart) {
      cart        = this.cartRepo.create();
      cart.userId = userId;
      await this.cartRepo.save(cart);
      cart.items  = [];
    }

    return cart;
  }

  // ─────────────────────────────────────────────────────
  // VOIR SON PANIER (avec détection changement de prix)
  // ─────────────────────────────────────────────────────
  async getMyCart(userId: string) {
    const cart = await this.getOrCreateCart(userId);

    // Détecter les changements de prix pour chaque article
    let hasChanges = false;

    for (const item of cart.items) {
      const currentPrice = Number(item.variant.price);
      const savedPrice   = Number(item.unitPrice);

      if (currentPrice !== savedPrice) {
        // ⚠️ Prix changé depuis l'ajout au panier
        item.priceChanged = true;
        item.unitPrice    = currentPrice;
        await this.cartItemRepo.save(item);
        hasChanges = true;
      } else {
        item.priceChanged = false;
      }
    }

    // Calculer le total
    const total = cart.items.reduce((sum, item) => {
      return sum + Number(item.unitPrice) * item.quantity;
    }, 0);

    return {
      id:         cart.id,
      items:      cart.items,
      total:      Number(total.toFixed(2)),
      itemCount:  cart.items.length,
      hasPriceChanges: hasChanges,
    };
  }

  // ─────────────────────────────────────────────────────
  // AJOUTER UN ARTICLE AU PANIER
  // ─────────────────────────────────────────────────────
  async addItem(userId: string, dto: AddToCartDto) {
    // 1. Vérifier que la variante existe et est active
    const variant = await this.variantRepo.findOne({
      where:     { id: dto.variantId, isActive: true },
      relations: ['product'],
    });

    if (!variant) {
      throw new NotFoundException('Produit introuvable ou indisponible');
    }

    // 2. Vérifier que le produit est actif
    if (variant.product.status !== 'active') {
      throw new BadRequestException('Ce produit n\'est plus disponible');
    }

    // 3. Vérifier le stock disponible
    if (variant.stockQuantity < dto.quantity) {
      throw new BadRequestException(
        `Stock insuffisant. Il reste ${variant.stockQuantity} unité(s) disponible(s)`
      );
    }

    const cart = await this.getOrCreateCart(userId);

    // 4. Vérifier si la variante est déjà dans le panier
    const existingItem = await this.cartItemRepo.findOne({
      where: { cartId: cart.id, variantId: dto.variantId },
    });

    if (existingItem) {
      // Incrémenter la quantité
      const newQuantity = existingItem.quantity + dto.quantity;

      // Vérifier le stock pour la nouvelle quantité totale
      if (variant.stockQuantity < newQuantity) {
        throw new BadRequestException(
          `Stock insuffisant. Maximum ${variant.stockQuantity} unité(s) disponible(s)`
        );
      }

      existingItem.quantity     = newQuantity;
      existingItem.unitPrice    = Number(variant.price);
      existingItem.priceChanged = false;
      await this.cartItemRepo.save(existingItem);
    } else {
      // Créer un nouvel article
      const item          = this.cartItemRepo.create();
      item.cartId         = cart.id;
      item.variantId      = dto.variantId;
      item.quantity       = dto.quantity;
      item.unitPrice      = Number(variant.price);
      item.priceChanged   = false;
      await this.cartItemRepo.save(item);
    }

    return this.getMyCart(userId);
  }

  // ─────────────────────────────────────────────────────
  // MODIFIER LA QUANTITÉ D'UN ARTICLE
  // ─────────────────────────────────────────────────────
  async updateItem(
    userId: string,
    itemId: string,
    dto:    UpdateCartItemDto,
  ) {
    const cart = await this.cartRepo.findOne({
      where: { userId },
    });

    if (!cart) throw new NotFoundException('Panier introuvable');

    const item = await this.cartItemRepo.findOne({
      where:     { id: itemId, cartId: cart.id },
      relations: ['variant'],
    });

    if (!item) throw new NotFoundException('Article introuvable dans le panier');

    // Vérifier le stock pour la nouvelle quantité
    if (item.variant.stockQuantity < dto.quantity) {
      throw new BadRequestException(
        `Stock insuffisant. Maximum ${item.variant.stockQuantity} unité(s) disponible(s)`
      );
    }

    item.quantity = dto.quantity;
    await this.cartItemRepo.save(item);

    return this.getMyCart(userId);
  }

  // ─────────────────────────────────────────────────────
  // SUPPRIMER UN ARTICLE DU PANIER
  // ─────────────────────────────────────────────────────
  async removeItem(userId: string, itemId: string) {
    const cart = await this.cartRepo.findOne({
      where: { userId },
    });

    if (!cart) throw new NotFoundException('Panier introuvable');

    const item = await this.cartItemRepo.findOne({
      where: { id: itemId, cartId: cart.id },
    });

    if (!item) throw new NotFoundException('Article introuvable dans le panier');

    await this.cartItemRepo.remove(item);

    return this.getMyCart(userId);
  }

  // ─────────────────────────────────────────────────────
  // VIDER LE PANIER
  // ─────────────────────────────────────────────────────
  async clearCart(userId: string) {
    const cart = await this.cartRepo.findOne({
      where: { userId },
    });

    if (!cart) return { message: 'Panier déjà vide' };

    await this.cartItemRepo.delete({ cartId: cart.id });

    return { message: 'Panier vidé' };
  }

  // ─────────────────────────────────────────────────────
  // VIDER LE PANIER APRÈS COMMANDE
  // (appelé par le module orders)
  // ─────────────────────────────────────────────────────
  async clearAfterOrder(userId: string): Promise<void> {
    const cart = await this.cartRepo.findOne({
      where: { userId },
    });

    if (cart) {
      await this.cartItemRepo.delete({ cartId: cart.id });
    }
  }
}