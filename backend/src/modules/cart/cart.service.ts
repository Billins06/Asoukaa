import { VendorStatus } from '../users/entities/vendor-profile.entity';
import { toPublicVendor } from '../products/public-vendor.util';
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
import { resolveTierUnitPrice } from '../../common/utils/tier-pricing.util';

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
        'items.variant.product.vendor',
        'items.variant.product.vendor.user',
        // Paliers de prix dégressifs : nécessaires pour recalculer le prix
        // unitaire attendu selon la quantité (voir tier-pricing.util.ts)
        'items.variant.product.tierPrices',
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
      // Prix attendu = prix dégressif applicable à la quantité du panier
      // (ou prix normal de la variante s'il n'y a pas de palier atteint)
      const currentPrice = resolveTierUnitPrice(
        item.variant.price,
        item.variant.product?.tierPrices,
        item.quantity,
      );
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

      // ⚠️ Ne pas exposer les données sensibles du vendeur (documents,
      // paiement, e-mail...) : seule la fiche publique part vers l'appli.
      const prod = item.variant?.product as any;
      if (prod?.vendor) {
        prod.vendor = toPublicVendor(prod.vendor);
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
      relations: ['product', 'product.tierPrices', 'product.vendor', 'product.vendor.user'],
    });

    if (!variant) {
      throw new NotFoundException('Produit introuvable ou indisponible');
    }

    // Produit d'un vendeur bloqué / non approuvé / désactivé : indisponible
    const vendorOfProduct = variant.product?.vendor;
    if (
      !vendorOfProduct
      || vendorOfProduct.status !== VendorStatus.APPROVED
      || vendorOfProduct.user?.isActive === false
    ) {
      throw new NotFoundException('Produit introuvable ou indisponible');
    }

    // Boutique masquée par son vendeur (« Boutique visible » désactivé) :
    // plus de nouveaux articles au panier.
    if (vendorOfProduct.shopVisible === false) {
      throw new BadRequestException('Cette boutique est momentanément indisponible');
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
      // Prix dégressif recalculé sur la NOUVELLE quantité totale
      existingItem.unitPrice    = resolveTierUnitPrice(
        variant.price,
        variant.product?.tierPrices,
        newQuantity,
      );
      existingItem.priceChanged = false;
      await this.cartItemRepo.save(existingItem);
    } else {
      // Créer un nouvel article
      const item          = this.cartItemRepo.create();
      item.cartId         = cart.id;
      item.variantId      = dto.variantId;
      item.quantity       = dto.quantity;
      item.unitPrice      = resolveTierUnitPrice(
        variant.price,
        variant.product?.tierPrices,
        dto.quantity,
      );
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
      relations: ['variant', 'variant.product', 'variant.product.tierPrices'],
    });

    if (!item) throw new NotFoundException('Article introuvable dans le panier');

    // Vérifier le stock pour la nouvelle quantité
    if (item.variant.stockQuantity < dto.quantity) {
      throw new BadRequestException(
        `Stock insuffisant. Maximum ${item.variant.stockQuantity} unité(s) disponible(s)`
      );
    }

    item.quantity  = dto.quantity;
    // Changer la quantité peut faire franchir (ou quitter) un palier de prix
    // dégressif : on recalcule le prix unitaire côté serveur.
    item.unitPrice = resolveTierUnitPrice(
      item.variant.price,
      item.variant.product?.tierPrices,
      dto.quantity,
    );
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