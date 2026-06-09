import {
  Injectable,
  NotFoundException,
  ConflictException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository }       from 'typeorm';

import { Partner }            from './entities/partner.entity';
import { CreatePartnerDto }   from './dto/create-partner.dto';
import { UpdatePartnerDto }   from './dto/update-partner.dto';
import { ActivityLogService } from '../../common/services/activity-log.service';
import {
  ActorType,
  LogAction,
} from '../../common/entities/activity-log.entity';

@Injectable()
export class PartnersService {

  constructor(
    @InjectRepository(Partner)
    private readonly partnerRepo: Repository<Partner>,

    private readonly logService: ActivityLogService,
  ) {}

  // ─────────────────────────────────────────────────────
  // ADMIN — CRÉER UN PARTENAIRE
  // ─────────────────────────────────────────────────────
  async create(
    dto:     CreatePartnerDto,
    adminId: string,
    ip:      string,
  ) {
    // Vérifier l'unicité du nom
    const exists = await this.partnerRepo.findOne({
      where: { part_name: dto.part_name },
    });

    if (exists) {
      throw new ConflictException(
        `Un partenaire avec le nom "${dto.part_name}" existe déjà`
      );
    }

    const partner               = this.partnerRepo.create();
    partner.part_name           = dto.part_name;
    partner.part_logoUrl        = dto.part_logoUrl    ?? null;
    partner.part_websiteUrl     = dto.part_websiteUrl ?? null;
    partner.description         = dto.description     ?? null;
    partner.isActive            = dto.isActive ?? true;

    await this.partnerRepo.save(partner);

    await this.logService.log({
      actorId:    adminId,
      actorType:  ActorType.ADMIN,
      action:     LogAction.PARTNER_CREATED,
      entityType: 'partner',
      entityId:   partner.id,
      newValue:   { name: partner.part_name },
      ipAddress:  ip,
    });

    return partner;
  }

  // ─────────────────────────────────────────────────────
  // LISTE PUBLIQUE — UNIQUEMENT LES PARTENAIRES ACTIFS
  // ─────────────────────────────────────────────────────
  async findAllPublic() {
    return this.partnerRepo.find({
      where: { isActive: true },
      order: { part_name: 'ASC' },
      select: [
        'id',
        'part_name',
        'part_logoUrl',
        'part_websiteUrl',
        'description',
      ],
    });
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — LISTE COMPLÈTE (actifs + inactifs)
  // ─────────────────────────────────────────────────────
  async findAll(page = 1, limit = 20) {
    const [partners, total] = await this.partnerRepo.findAndCount({
      order: { createdAt: 'DESC' },
      skip:  (page - 1) * limit,
      take:  limit,
    });

    return {
      data:  partners,
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
    };
  }

  // ─────────────────────────────────────────────────────
  // DÉTAILS D'UN PARTENAIRE
  // ─────────────────────────────────────────────────────
  async findOne(id: string) {
    const partner = await this.partnerRepo.findOne({
      where: { id },
    });

    if (!partner) throw new NotFoundException('Partenaire introuvable');

    return partner;
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — MODIFIER UN PARTENAIRE
  // ─────────────────────────────────────────────────────
  async update(
    id:      string,
    dto:     UpdatePartnerDto,
    adminId: string,
    ip:      string,
  ) {
    const partner = await this.partnerRepo.findOne({
      where: { id },
    });

    if (!partner) throw new NotFoundException('Partenaire introuvable');

    // Vérifier l'unicité du nouveau nom
    if (dto.part_name && dto.part_name !== partner.part_name) {
      const exists = await this.partnerRepo.findOne({
        where: { part_name: dto.part_name },
      });

      if (exists && exists.id !== id) {
        throw new ConflictException(
          `Un partenaire avec le nom "${dto.part_name}" existe déjà`
        );
      }
    }

    const oldValue = {
      name:     partner.part_name,
      isActive: partner.isActive,
    };

    if (dto.part_name        !== undefined) partner.part_name       = dto.part_name;
    if (dto.part_logoUrl     !== undefined) partner.part_logoUrl    = dto.part_logoUrl;
    if (dto.part_websiteUrl  !== undefined) partner.part_websiteUrl = dto.part_websiteUrl;
    if (dto.description      !== undefined) partner.description     = dto.description;
    if (dto.isActive         !== undefined) partner.isActive        = dto.isActive;

    await this.partnerRepo.save(partner);

    await this.logService.log({
      actorId:    adminId,
      actorType:  ActorType.ADMIN,
      action:     LogAction.PARTNER_UPDATED,
      entityType: 'partner',
      entityId:   id,
      oldValue,
      newValue:   {
        name:     partner.part_name,
        isActive: partner.isActive,
      },
      ipAddress: ip,
    });

    return partner;
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — ACTIVER / DÉSACTIVER
  // ─────────────────────────────────────────────────────
  async toggleActive(
    id:      string,
    adminId: string,
    ip:      string,
  ) {
    const partner = await this.partnerRepo.findOne({
      where: { id },
    });

    if (!partner) throw new NotFoundException('Partenaire introuvable');

    const oldValue   = { isActive: partner.isActive };
    partner.isActive = !partner.isActive;
    await this.partnerRepo.save(partner);

    await this.logService.log({
      actorId:    adminId,
      actorType:  ActorType.ADMIN,
      action:     LogAction.PARTNER_UPDATED,
      entityType: 'partner',
      entityId:   id,
      oldValue,
      newValue:   { isActive: partner.isActive },
      ipAddress:  ip,
    });

    return {
      message:  partner.isActive
        ? 'Partenaire activé'
        : 'Partenaire désactivé',
      isActive: partner.isActive,
    };
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — SUPPRIMER UN PARTENAIRE
  // ─────────────────────────────────────────────────────
  async remove(
    id:      string,
    adminId: string,
    ip:      string,
  ) {
    const partner = await this.partnerRepo.findOne({
      where: { id },
    });

    if (!partner) throw new NotFoundException('Partenaire introuvable');

    await this.partnerRepo.remove(partner);

    await this.logService.log({
      actorId:    adminId,
      actorType:  ActorType.ADMIN,
      action:     LogAction.PARTNER_DELETED,
      entityType: 'partner',
      entityId:   id,
      oldValue:   { name: partner.part_name },
      ipAddress:  ip,
    });

    return { message: 'Partenaire supprimé' };
  }
}