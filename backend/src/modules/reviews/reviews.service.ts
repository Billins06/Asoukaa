import {
  Injectable,
  NotFoundException,
  BadRequestException,
  ConflictException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository }       from 'typeorm';

import { Review, ReviewStatus }  from './entities/review.entity';
import { Order, OrderStatus }    from '../orders/entities/order.entity';
import { OrderItem }             from '../orders/entities/order-item.entity';
import { Product }               from '../products/entities/product.entity';
import { ProductVariant }        from '../products/entities/product-variant.entity';

import { CreateReviewDto }    from './dto/create-review.dto';
import { ModerateReviewDto }  from './dto/moderate-review.dto';
import { ActivityLogService } from '../../common/services/activity-log.service';
import {
  ActorType,
  LogAction,
} from '../../common/entities/activity-log.entity';

@Injectable()
export class ReviewsService {

  constructor(
    @InjectRepository(Review)
    private readonly reviewRepo: Repository<Review>,

    @InjectRepository(Order)
    private readonly orderRepo: Repository<Order>,

    @InjectRepository(OrderItem)
    private readonly orderItemRepo: Repository<OrderItem>,

    @InjectRepository(Product)
    private readonly productRepo: Repository<Product>,

    @InjectRepository(ProductVariant)
    private readonly variantRepo: Repository<ProductVariant>,

    private readonly logService: ActivityLogService,
  ) {}

  // ─────────────────────────────────────────────────────
  // CRÉER UN AVIS
  // ─────────────────────────────────────────────────────
  async create(
    userId: string,
    dto:    CreateReviewDto,
    ip:     string,
  ) {
    // 1. Vérifier que le produit existe
    const product = await this.productRepo.findOne({
      where: { id: dto.productId },
    });

    if (!product) throw new NotFoundException('Produit introuvable');

    // 2. Vérifier que la commande existe et appartient au client
    const order = await this.orderRepo.findOne({
      where: { id: dto.orderId, userId },
    });

    if (!order) throw new NotFoundException('Commande introuvable');

    // 3. Vérifier que la commande est bien livrée
    // ⚠️ On ne peut noter que ce qu'on a reçu
    if (order.status !== OrderStatus.DELIVERED) {
      throw new BadRequestException(
        'Vous ne pouvez laisser un avis que pour une commande livrée'
      );
    }

    // 4. Vérifier que ce produit fait bien partie de la commande
    // On cherche via les variantes du produit
    const variants = await this.variantRepo.find({
      where: { productId: dto.productId },
      select: ['id'],
    });

    const variantIds = variants.map(v => v.id);

    const orderItem = await this.orderItemRepo
      .createQueryBuilder('item')
      .where('item.orderId = :orderId',          { orderId: dto.orderId })
      .andWhere('item.variantId IN (:...variantIds)', { variantIds })
      .getOne();

    if (!orderItem) {
      throw new BadRequestException(
        'Ce produit ne fait pas partie de cette commande'
      );
    }

    // 5. Vérifier qu'un avis n'existe pas déjà
    // (unique par userId + productId)
    const existing = await this.reviewRepo.findOne({
      where: { userId, productId: dto.productId },
    });

    if (existing) {
      throw new ConflictException(
        'Vous avez déjà laissé un avis pour ce produit'
      );
    }

    // 6. Créer l'avis
    const review          = this.reviewRepo.create();
    review.userId         = userId;
    review.productId      = dto.productId;
    review.orderId        = dto.orderId;
    review.notation       = dto.notation;
    review.comment        = dto.comment ?? null;
    review.status         = ReviewStatus.PENDING;

    await this.reviewRepo.save(review);

    return {
      message: 'Avis soumis avec succès. Il sera visible après modération.',
      reviewId: review.id,
    };
  }

  // ─────────────────────────────────────────────────────
  // LISTE DES AVIS D'UN PRODUIT (public)
  // ─────────────────────────────────────────────────────
  async getProductReviews(
    productId: string,
    page:      number = 1,
    limit:     number = 10,
  ) {
    const product = await this.productRepo.findOne({
      where: { id: productId },
    });

    if (!product) throw new NotFoundException('Produit introuvable');

    const [reviews, total] = await this.reviewRepo.findAndCount({
      where: {
        productId,
        status: ReviewStatus.APPROVED,
      },
      relations: ['user'],
      order:     { createdAt: 'DESC' },
      skip:      (page - 1) * limit,
      take:      limit,
    });

    // ⚠️ Masquer les données sensibles des utilisateurs
    const safeReviews = reviews.map(r => {
      if (r.user) {
        const { passwordHash, phone, ...userSafe } = r.user as any;
        (r as any).user = {
          id:     userSafe.id,
          prenom: userSafe.prenom,
          name:   userSafe.name,
        };
      }
      return r;
    });

    return {
      data:         safeReviews,
      total,
      page,
      limit,
      pages:        Math.ceil(total / limit),
      avgRating:    product.noteMoyenne,
      reviewCount:  product.nbreAvis,
    };
  }

  // ─────────────────────────────────────────────────────
  // MES AVIS (client connecté)
  // ─────────────────────────────────────────────────────
  async getMyReviews(userId: string, page = 1, limit = 10) {
    const [reviews, total] = await this.reviewRepo.findAndCount({
      where:     { userId },
      relations: ['product', 'product.images'],
      order:     { createdAt: 'DESC' },
      skip:      (page - 1) * limit,
      take:      limit,
    });

    return {
      data:  reviews,
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
    };
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — AVIS EN ATTENTE DE MODÉRATION
  // ─────────────────────────────────────────────────────
  async getPendingReviews(page = 1, limit = 20) {
    const [reviews, total] = await this.reviewRepo.findAndCount({
      where:     { status: ReviewStatus.PENDING },
      relations: ['user', 'product'],
      order:     { createdAt: 'ASC' },
      skip:      (page - 1) * limit,
      take:      limit,
    });

    const safeReviews = reviews.map(r => {
      if (r.user) {
        const { passwordHash, ...userSafe } = r.user as any;
        (r as any).user = userSafe;
      }
      return r;
    });

    return {
      data:  safeReviews,
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
    };
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — MODÉRER UN AVIS
  // ─────────────────────────────────────────────────────
  async moderate(
    reviewId: string,
    adminId:  string,
    dto:      ModerateReviewDto,
    ip:       string,
  ) {
    const review = await this.reviewRepo.findOne({
      where: { id: reviewId },
    });

    if (!review) throw new NotFoundException('Avis introuvable');

    if (review.status !== ReviewStatus.PENDING) {
      throw new BadRequestException('Cet avis a déjà été modéré');
    }

    const oldStatus  = review.status;
    review.status    = dto.status;
    await this.reviewRepo.save(review);

    // Recalculer la note moyenne du produit
    // uniquement si l'avis est approuvé ou si on annule une approbation
    await this.recalculateProductRating(review.productId);

    await this.logService.log({
      actorId:    adminId,
      actorType:  ActorType.ADMIN,
      action:     dto.status === ReviewStatus.APPROVED
                    ? LogAction.REVIEW_APPROVED
                    : LogAction.REVIEW_REJECTED,
      entityType: 'review',
      entityId:   reviewId,
      oldValue:   { status: oldStatus },
      newValue:   { status: dto.status },
      ipAddress:  ip,
    });

    return {
      message: dto.status === ReviewStatus.APPROVED
        ? 'Avis approuvé et publié'
        : 'Avis rejeté',
      status: review.status,
    };
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — TOUS LES AVIS
  // ─────────────────────────────────────────────────────
  async getAllReviews(
    status?: ReviewStatus,
    page = 1,
    limit = 20,
  ) {
    const query = this.reviewRepo
      .createQueryBuilder('review')
      .leftJoinAndSelect('review.user',    'user')
      .leftJoinAndSelect('review.product', 'product')
      .orderBy('review.createdAt', 'DESC')
      .skip((page - 1) * limit)
      .take(limit);

    if (status) {
      query.where('review.status = :status', { status });
    }

    const [reviews, total] = await query.getManyAndCount();

    const safeReviews = reviews.map(r => {
      if (r.user) {
        const { passwordHash, ...userSafe } = r.user as any;
        (r as any).user = userSafe;
      }
      return r;
    });

    return {
      data:  safeReviews,
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
    };
  }

  // ─────────────────────────────────────────────────────
  // MÉTHODE PRIVÉE — RECALCULER NOTE MOYENNE
  // ─────────────────────────────────────────────────────
  private async recalculateProductRating(productId: string): Promise<void> {
    // Compter uniquement les avis approuvés
    const result = await this.reviewRepo
      .createQueryBuilder('review')
      .select('AVG(review.notation)', 'avg')
      .addSelect('COUNT(review.id)',  'count')
      .where('review.productId = :productId', { productId })
      .andWhere('review.status = :status', {
        status: ReviewStatus.APPROVED,
      })
      .getRawOne();

    const avg   = result?.avg   ? Number(Number(result.avg).toFixed(2))   : 0;
    const count = result?.count ? Number(result.count) : 0;

    // Mettre à jour le produit
    await this.productRepo.update(
      { id: productId },
      {
        noteMoyenne: avg,
        nbreAvis:    count,
      },
    );
  }
}