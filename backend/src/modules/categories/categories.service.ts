import {
  Injectable,
  NotFoundException,
  BadRequestException,
  ConflictException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository }       from 'typeorm';

import { Category }           from './entities/category.entity';
import { CreateCategoryDto }  from './dto/create-category.dto';
import { UpdateCategoryDto }  from './dto/update-category.dto';
import { ActivityLogService } from '../../common/services/activity-log.service';
import { UploadService, UploadType } from '../upload/upload.service';
import {
  ActorType,
  LogAction,
} from '../../common/entities/activity-log.entity';

@Injectable()
export class CategoriesService {

  constructor(
    @InjectRepository(Category)
    private readonly categoryRepo: Repository<Category>,

    private readonly logService: ActivityLogService,

    private readonly uploadService: UploadService,
  ) {}

  // ─────────────────────────────────────────────────────
  // CRÉER UNE CATÉGORIE
  // ─────────────────────────────────────────────────────
  async create(
    dto:     CreateCategoryDto,
    adminId: string,
    ip:      string,
  ) {
    // 1. Vérifier l'unicité du slug
    const slugExists = await this.categoryRepo.findOne({
      where: { slug: this.generateSlug(dto.name) },
    });
    if (slugExists) {
      throw new ConflictException(
        'Une catégorie avec ce nom existe déjà'
      );
    }

    // 2. Vérifier le niveau si parentId fourni
    let level = 1;
    if (dto.parentId) {
      const parent = await this.categoryRepo.findOne({
        where: { id: dto.parentId },
      });

      if (!parent) {
        throw new NotFoundException('Catégorie parente introuvable');
      }

      // ⚠️ Maximum 3 niveaux
      if (parent.level >= 3) {
        throw new BadRequestException(
          'Impossible de créer une sous-catégorie : '
          + 'profondeur maximale de 3 niveaux atteinte'
        );
      }

      level = parent.level + 1;
    }

    // 2 bis. Image : OBLIGATOIRE pour une catégorie de premier niveau (les
    // cercles de l'accueil l'affichent), facultative pour les
    // sous-catégories. Dans tous les cas, si elle est fournie, elle doit
    // venir de notre propre stockage (upload de type « categories »).
    if (level === 1 && !dto.imageUrl) {
      throw new BadRequestException(
        'L\'image est obligatoire pour une catégorie principale'
      );
    }
    if (dto.imageUrl) {
      this.uploadService.assertIsOwnUploadUrl(dto.imageUrl, UploadType.CATEGORY);
    }

    // 3. Créer la catégorie
    const category = this.categoryRepo.create();
category.name      = dto.name;
category.slug      = this.generateSlug(dto.name);
category.parentId  = dto.parentId ?? null;
category.imageUrl  = dto.imageUrl ?? null;
category.level     = level;
category.sortOrder = dto.sortOrder ?? 0;
category.isActive  = dto.isActive ?? true;

    await this.categoryRepo.save(category);

    await this.logService.log({
      actorId:    adminId,
      actorType:  ActorType.ADMIN,
      action:     LogAction.CATEGORY_CREATED,
      entityType: 'category',
      entityId:   category.id,
      newValue:   { name: category.name, level },
      ipAddress:  ip,
    });

    return category;
  }

  // ─────────────────────────────────────────────────────
  // LISTE COMPLÈTE (arbre hiérarchique)
  // Utilisée par admin et par l'app mobile/web
  // ─────────────────────────────────────────────────────
  async findAll() {
    // Optimisation : on charge tout en une requête
    // puis on construit l'arbre en mémoire
    const all = await this.categoryRepo.find({
      order: { level: 'ASC', sortOrder: 'ASC', name: 'ASC' },
    });

    return this.buildTree(all);
  }

  // ─────────────────────────────────────────────────────
  // LISTE PLATE (pour les selects/dropdowns)
  // ─────────────────────────────────────────────────────
  async findFlat(onlyActive = true) {
    const where = onlyActive ? { isActive: true } : {};

    return this.categoryRepo.find({
      where,
      select: ['id', 'name', 'slug', 'parentId', 'level', 'isActive', 'imageUrl'],
      order:  { level: 'ASC', sortOrder: 'ASC', name: 'ASC' },
    });
  }

  // ─────────────────────────────────────────────────────
  // DÉTAILS D'UNE CATÉGORIE
  // ─────────────────────────────────────────────────────
  async findOne(id: string) {
    const category = await this.categoryRepo.findOne({
      where: { id },
    });

    if (!category) {
      throw new NotFoundException('Catégorie introuvable');
    }

    // Charger les enfants directs
    const children = await this.categoryRepo.find({
      where: { parentId: id },
      order: { sortOrder: 'ASC', name: 'ASC' },
    });

    return { ...category, children };
  }

  // ─────────────────────────────────────────────────────
  // MODIFIER UNE CATÉGORIE
  // ─────────────────────────────────────────────────────
  async update(
    id:      string,
    dto:     UpdateCategoryDto,
    adminId: string,
    ip:      string,
  ) {
    const category = await this.categoryRepo.findOne({
      where: { id },
    });

    if (!category) throw new NotFoundException('Catégorie introuvable');

    const oldValue = {
      name:      category.name,
      isActive:  category.isActive,
      sortOrder: category.sortOrder,
    };

    // Vérifier le nouveau nom si changé
    if (dto.name && dto.name !== category.name) {
      const newSlug    = this.generateSlug(dto.name);
      const slugExists = await this.categoryRepo.findOne({
        where: { slug: newSlug },
      });

      if (slugExists && slugExists.id !== id) {
        throw new ConflictException(
          'Une catégorie avec ce nom existe déjà'
        );
      }

      category.name = dto.name;
      category.slug = newSlug;
    }

    // ⚠️ On ne permet pas de changer le parentId
    // car ça changerait le niveau et casserait l'arbre
    // Si besoin, il faut supprimer et recréer
    if (dto.parentId !== undefined) {
      throw new BadRequestException(
        'Le parent d\'une catégorie ne peut pas être modifié. '
        + 'Supprimez et recréez la catégorie si nécessaire.'
      );
    }

    // Image : exigée seulement si elle est fournie. Une valeur identique à
    // l'actuelle n'est pas revalidée (anciennes catégories, ancienne URL).
    // Une catégorie principale ne peut pas perdre son image ; envoyer
    // null/vide sur une catégorie qui n'en a pas ne change rien.
    if (dto.imageUrl !== undefined) {
      const newImage = (dto.imageUrl as string | null) || null;
      if (newImage === null) {
        if (category.imageUrl && category.parentId === null) {
          throw new BadRequestException(
            'L\'image d\'une catégorie principale ne peut pas être supprimée'
          );
        }
        category.imageUrl = null;
      } else if (newImage !== category.imageUrl) {
        this.uploadService.assertIsOwnUploadUrl(newImage, UploadType.CATEGORY);
        category.imageUrl = newImage;
      }
    }
    if (dto.sortOrder !== undefined) category.sortOrder = dto.sortOrder;
    if (dto.isActive  !== undefined) category.isActive  = dto.isActive;

    await this.categoryRepo.save(category);

    await this.logService.log({
      actorId:    adminId,
      actorType:  ActorType.ADMIN,
      action:     LogAction.CATEGORY_UPDATED,
      entityType: 'category',
      entityId:   id,
      oldValue,
      newValue: {
        name:      category.name,
        isActive:  category.isActive,
        sortOrder: category.sortOrder,
      },
      ipAddress: ip,
    });

    return category;
  }

  // ─────────────────────────────────────────────────────
  // ACTIVER / DÉSACTIVER UNE CATÉGORIE
  // ─────────────────────────────────────────────────────
  async toggleActive(
    id:      string,
    adminId: string,
    ip:      string,
  ) {
    const category = await this.categoryRepo.findOne({
      where: { id },
    });

    if (!category) throw new NotFoundException('Catégorie introuvable');

    const oldValue   = { isActive: category.isActive };
    category.isActive = !category.isActive;
    await this.categoryRepo.save(category);

    // ⚠️ Si on désactive une catégorie parente,
    // on désactive aussi toutes ses sous-catégories
    if (!category.isActive) {
      await this.deactivateChildren(id);
    }

    await this.logService.log({
      actorId:    adminId,
      actorType:  ActorType.ADMIN,
      action:     LogAction.CATEGORY_UPDATED,
      entityType: 'category',
      entityId:   id,
      oldValue,
      newValue:   { isActive: category.isActive },
      ipAddress:  ip,
    });

    return {
      message:  category.isActive
        ? 'Catégorie activée'
        : 'Catégorie désactivée (et ses sous-catégories)',
      isActive: category.isActive,
    };
  }

  // ─────────────────────────────────────────────────────
  // SUPPRIMER UNE CATÉGORIE
  // ─────────────────────────────────────────────────────
  async remove(
    id:      string,
    adminId: string,
    ip:      string,
  ) {
    const category = await this.categoryRepo.findOne({
      where: { id },
    });

    if (!category) throw new NotFoundException('Catégorie introuvable');

    // ⚠️ Vérifier qu'il n'y a pas de sous-catégories
    const childrenCount = await this.categoryRepo.count({
      where: { parentId: id },
    });

    if (childrenCount > 0) {
      throw new BadRequestException(
        'Impossible de supprimer cette catégorie : '
        + 'elle contient des sous-catégories. '
        + 'Supprimez d\'abord les sous-catégories.'
      );
    }

    // ⚠️ Vérifier qu'aucun produit n'est lié à cette catégorie
    // Ce check sera renforcé dans le module products
    // Pour l'instant on supprime prudemment
    await this.categoryRepo.remove(category);

    await this.logService.log({
      actorId:    adminId,
      actorType:  ActorType.ADMIN,
      action:     LogAction.CATEGORY_DELETED,
      entityType: 'category',
      entityId:   id,
      oldValue:   { name: category.name, level: category.level },
      ipAddress:  ip,
    });

    return { message: 'Catégorie supprimée' };
  }

  // ─────────────────────────────────────────────────────
  // MÉTHODES PRIVÉES
  // ─────────────────────────────────────────────────────

  // Génère un slug depuis un nom
  // Ex: "Vêtements Hommes" → "vetements-hommes"
  private generateSlug(name: string): string {
    return name
      .toLowerCase()
      .normalize('NFD')                    // décompose les accents
      .replace(/[\u0300-\u036f]/g, '')     // supprime les accents
      .replace(/[^a-z0-9\s-]/g, '')        // supprime les caractères spéciaux
      .trim()
      .replace(/\s+/g, '-')               // espaces → tirets
      .replace(/-+/g, '-');               // tirets multiples → un seul
  }

  // Construit l'arbre hiérarchique depuis une liste plate
  // Optimisation : une seule requête DB au lieu de requêtes récursives
  private buildTree(categories: Category[]): any[] {
    const map = new Map<string, any>();
    const roots: any[] = [];

    // Créer un map id → category
    categories.forEach(cat => {
      map.set(cat.id, { ...cat, children: [] });
    });

    // Construire l'arbre
    categories.forEach(cat => {
      if (cat.parentId) {
        const parent = map.get(cat.parentId);
        if (parent) {
          parent.children.push(map.get(cat.id));
        }
      } else {
        roots.push(map.get(cat.id));
      }
    });

    return roots;
  }

  // Désactive récursivement toutes les sous-catégories
  private async deactivateChildren(parentId: string): Promise<void> {
    const children = await this.categoryRepo.find({
      where: { parentId },
    });

    for (const child of children) {
      child.isActive = false;
      await this.categoryRepo.save(child);
      // Récursion pour les sous-sous-catégories
      await this.deactivateChildren(child.id);
    }
  }
}