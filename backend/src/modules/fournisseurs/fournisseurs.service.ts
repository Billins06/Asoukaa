import {
  Injectable,
  NotFoundException,
  ConflictException,
  BadRequestException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, ILike } from 'typeorm';

import { Fournisseur }            from './entities/fournisseur.entity';
import { CreateFournisseurDto }   from './dto/create-fournisseur.dto';
import { UpdateFournisseurDto }   from './dto/update-fournisseur.dto';
import { ActivityLogService }     from '../../common/services/activity-log.service';
import {
  ActorType,
  LogAction,
} from '../../common/entities/activity-log.entity';

@Injectable()
export class FournisseursService {

  constructor(
    @InjectRepository(Fournisseur)
    private readonly fournisseurRepo: Repository<Fournisseur>,

    private readonly logService: ActivityLogService,
  ) {}

  // ─────────────────────────────────────────────────────
  // CRÉER UN FOURNISSEUR
  // ─────────────────────────────────────────────────────
  async create(
    dto:     CreateFournisseurDto,
    adminId: string,
    ip:      string,
  ) {
    // Vérifier unicité du nom
    const nameExists = await this.fournisseurRepo.findOne({
      where: { four_name: dto.four_name },
    });
    if (nameExists) {
      throw new ConflictException(
        `Un fournisseur avec le nom "${dto.four_name}" existe déjà`
      );
    }

    // Vérifier unicité de l'email si fourni
    if (dto.four_email) {
      const emailExists = await this.fournisseurRepo.findOne({
        where: { four_email: dto.four_email },
      });
      if (emailExists) {
        throw new ConflictException('Cet email est déjà utilisé');
      }
    }

    // Vérifier unicité du téléphone
    const phoneExists = await this.fournisseurRepo.findOne({
      where: { four_phone: dto.four_phone },
    });
    if (phoneExists) {
      throw new ConflictException(
        'Ce numéro de téléphone est déjà utilisé'
      );
    }

    const fournisseur                = this.fournisseurRepo.create();
    fournisseur.four_name            = dto.four_name;
    fournisseur.contactPerson        = dto.contactPerson;
    fournisseur.four_email           = dto.four_email   ?? null;
    fournisseur.four_phone           = dto.four_phone;
    fournisseur.four_country         = dto.four_country;
    fournisseur.four_ville           = dto.four_ville;
    fournisseur.currency             = dto.currency;
    fournisseur.delaiLivraison       = dto.delaiLivraison ?? null;
    fournisseur.notes                = dto.notes        ?? null;
    fournisseur.isActive             = true;

    await this.fournisseurRepo.save(fournisseur);

    await this.logService.log({
      actorId:    adminId,
      actorType:  ActorType.ADMIN,
      action:     LogAction.FOURNISSEUR_CREATED,
      entityType: 'fournisseur',
      entityId:   fournisseur.id,
      newValue:   {
        name:    fournisseur.four_name,
        country: fournisseur.four_country,
      },
      ipAddress:  ip,
    });

    return fournisseur;
  }

  // ─────────────────────────────────────────────────────
  // LISTE DES FOURNISSEURS (avec filtres)
  // ─────────────────────────────────────────────────────
  async findAll(params: {
    search?:     string;
    country?:    string;
    ville?:      string;
    currency?:   string;
    isActive?:   boolean;
    page?:       number;
    limit?:      number;
  }) {
    const {
      search,
      country,
      ville,
      currency,
      isActive,
      page  = 1,
      limit = 20,
    } = params;

    const query = this.fournisseurRepo
      .createQueryBuilder('fournisseur')
      .orderBy('fournisseur.createdAt', 'DESC')
      .skip((page - 1) * limit)
      .take(limit);

    // Recherche textuelle (nom, contact, ville)
    if (search) {
      query.andWhere(
        '(fournisseur.four_name ILIKE :search '
        + 'OR fournisseur.contactPerson ILIKE :search '
        + 'OR fournisseur.four_ville ILIKE :search)',
        { search: `%${search}%` }
      );
    }

    if (country)  query.andWhere('fournisseur.four_country = :country',   { country });
    if (ville)    query.andWhere('fournisseur.four_ville = :ville',       { ville });
    if (currency) query.andWhere('fournisseur.currency = :currency',      { currency });
    if (isActive !== undefined) {
      query.andWhere('fournisseur.isActive = :isActive', { isActive });
    }

    const [fournisseurs, total] = await query.getManyAndCount();

    return {
      data:  fournisseurs,
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
    };
  }

  // ─────────────────────────────────────────────────────
  // DÉTAILS D'UN FOURNISSEUR
  // ─────────────────────────────────────────────────────
  async findOne(id: string) {
    const fournisseur = await this.fournisseurRepo.findOne({
      where: { id },
    });

    if (!fournisseur) throw new NotFoundException('Fournisseur introuvable');

    return fournisseur;
  }

  // ─────────────────────────────────────────────────────
  // MODIFIER UN FOURNISSEUR
  // ─────────────────────────────────────────────────────
  async update(
    id:      string,
    dto:     UpdateFournisseurDto,
    adminId: string,
    ip:      string,
  ) {
    const fournisseur = await this.fournisseurRepo.findOne({
      where: { id },
    });

    if (!fournisseur) throw new NotFoundException('Fournisseur introuvable');

    // Vérifier unicité du nouveau nom
    if (dto.four_name && dto.four_name !== fournisseur.four_name) {
      const exists = await this.fournisseurRepo.findOne({
        where: { four_name: dto.four_name },
      });
      if (exists && exists.id !== id) {
        throw new ConflictException(
          `Un fournisseur avec le nom "${dto.four_name}" existe déjà`
        );
      }
    }

    // Vérifier unicité du nouvel email
    if (dto.four_email && dto.four_email !== fournisseur.four_email) {
      const exists = await this.fournisseurRepo.findOne({
        where: { four_email: dto.four_email },
      });
      if (exists && exists.id !== id) {
        throw new ConflictException('Cet email est déjà utilisé');
      }
    }

    // Vérifier unicité du nouveau téléphone
    if (dto.four_phone && dto.four_phone !== fournisseur.four_phone) {
      const exists = await this.fournisseurRepo.findOne({
        where: { four_phone: dto.four_phone },
      });
      if (exists && exists.id !== id) {
        throw new ConflictException(
          'Ce numéro de téléphone est déjà utilisé'
        );
      }
    }

    const oldValue = {
      name:    fournisseur.four_name,
      country: fournisseur.four_country,
      isActive: fournisseur.isActive,
    };

    // Mise à jour conditionnelle
    if (dto.four_name      !== undefined) fournisseur.four_name      = dto.four_name;
    if (dto.contactPerson  !== undefined) fournisseur.contactPerson  = dto.contactPerson;
    if (dto.four_email     !== undefined) fournisseur.four_email     = dto.four_email;
    if (dto.four_phone     !== undefined) fournisseur.four_phone     = dto.four_phone;
    if (dto.four_country   !== undefined) fournisseur.four_country   = dto.four_country;
    if (dto.four_ville     !== undefined) fournisseur.four_ville     = dto.four_ville;
    if (dto.currency       !== undefined) fournisseur.currency       = dto.currency;
    if (dto.delaiLivraison !== undefined) fournisseur.delaiLivraison = dto.delaiLivraison;
    if (dto.notes          !== undefined) fournisseur.notes          = dto.notes;

    await this.fournisseurRepo.save(fournisseur);

    await this.logService.log({
      actorId:    adminId,
      actorType:  ActorType.ADMIN,
      action:     LogAction.FOURNISSEUR_UPDATED,
      entityType: 'fournisseur',
      entityId:   id,
      oldValue,
      newValue:   {
        name:    fournisseur.four_name,
        country: fournisseur.four_country,
        isActive: fournisseur.isActive,
      },
      ipAddress: ip,
    });

    return fournisseur;
  }

  // ─────────────────────────────────────────────────────
  // ACTIVER / DÉSACTIVER UN FOURNISSEUR
  // ─────────────────────────────────────────────────────
  async toggleActive(
    id:      string,
    adminId: string,
    ip:      string,
  ) {
    const fournisseur = await this.fournisseurRepo.findOne({
      where: { id },
    });

    if (!fournisseur) throw new NotFoundException('Fournisseur introuvable');

    const oldValue       = { isActive: fournisseur.isActive };
    fournisseur.isActive = !fournisseur.isActive;
    await this.fournisseurRepo.save(fournisseur);

    await this.logService.log({
      actorId:    adminId,
      actorType:  ActorType.ADMIN,
      action:     LogAction.FOURNISSEUR_UPDATED,
      entityType: 'fournisseur',
      entityId:   id,
      oldValue,
      newValue:   { isActive: fournisseur.isActive },
      ipAddress:  ip,
    });

    return {
      message:  fournisseur.isActive
        ? 'Fournisseur activé'
        : 'Fournisseur désactivé',
      isActive: fournisseur.isActive,
    };
  }

  // ─────────────────────────────────────────────────────
  // SUPPRIMER UN FOURNISSEUR
  // ─────────────────────────────────────────────────────
  async remove(
    id:      string,
    adminId: string,
    ip:      string,
  ) {
    const fournisseur = await this.fournisseurRepo.findOne({
      where: { id },
    });

    if (!fournisseur) throw new NotFoundException('Fournisseur introuvable');

    await this.fournisseurRepo.remove(fournisseur);

    await this.logService.log({
      actorId:    adminId,
      actorType:  ActorType.ADMIN,
      action:     LogAction.FOURNISSEUR_DELETED,
      entityType: 'fournisseur',
      entityId:   id,
      oldValue:   { name: fournisseur.four_name },
      ipAddress:  ip,
    });

    return { message: 'Fournisseur supprimé' };
  }

  // ─────────────────────────────────────────────────────
  // STATISTIQUES — POUR LE DASHBOARD ADMIN
  // ─────────────────────────────────────────────────────
  async getStats() {
    const total      = await this.fournisseurRepo.count();
    const active     = await this.fournisseurRepo.count({ where: { isActive: true } });
    const inactive   = await this.fournisseurRepo.count({ where: { isActive: false } });

    // Compter par pays
    const byCountry = await this.fournisseurRepo
      .createQueryBuilder('f')
      .select('f.four_country', 'country')
      .addSelect('COUNT(f.id)', 'count')
      .where('f.isActive = true')
      .groupBy('f.four_country')
      .orderBy('count', 'DESC')
      .getRawMany();

    return {
      total,
      active,
      inactive,
      byCountry,
    };
  }
}