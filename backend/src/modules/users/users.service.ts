import {
  Injectable,
  NotFoundException,
  ConflictException,
  BadRequestException,
  ForbiddenException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository }       from 'typeorm';
import * as bcrypt          from 'bcrypt';

import { User }           from './entities/user.entity';
import { UserRole }       from './entities/user-role.entity';
import { Address }        from './entities/address.entity';
import { VendorProfile }  from './entities/vendor-profile.entity';
import { DeliveryAgentProfile } from './entities/delivery-agent-profile.entity';

import { UpdateProfileDto }  from './dto/update-profile.dto';
import { CreateAddressDto }  from './dto/create-address.dto';
import { UpdateAddressDto }  from './dto/update-address.dto';

import { ActivityLogService } from '../../common/services/activity-log.service';
import {
  ActorType,
  LogAction,
} from '../../common/entities/activity-log.entity';

@Injectable()
export class UsersService {

  constructor(
    @InjectRepository(User)
    private readonly userRepo: Repository<User>,

    @InjectRepository(UserRole)
    private readonly userRoleRepo: Repository<UserRole>,

    @InjectRepository(Address)
    private readonly addressRepo: Repository<Address>,

    @InjectRepository(VendorProfile)
    private readonly vendorRepo: Repository<VendorProfile>,

    @InjectRepository(DeliveryAgentProfile)
    private readonly agentRepo: Repository<DeliveryAgentProfile>,

    private readonly logService: ActivityLogService,
  ) {}

  // ─────────────────────────────────────────────────────
  // MÉTHODE UTILISÉE PAR JWT STRATEGY
  // ─────────────────────────────────────────────────────
  async findById(id: string): Promise<User | null> {
    return this.userRepo.findOne({
      where:     { id },
      relations: ['roles'],
    });
  }

  // ─────────────────────────────────────────────────────
  // PROFIL DE L'UTILISATEUR CONNECTÉ
  // ─────────────────────────────────────────────────────
  async getMyProfile(userId: string) {
    const user = await this.userRepo.findOne({
      where:     { id: userId },
      relations: ['roles'],
    });

    if (!user) throw new NotFoundException('Utilisateur introuvable');

    // Récupérer le profil vendeur si existant
    const vendorProfile = await this.vendorRepo.findOne({
      where: { userId },
    });

    // Récupérer le profil livreur si existant
    const agentProfile = await this.agentRepo.findOne({
      where: { userId },
    });

    // ⚠️ Ne jamais retourner passwordHash
    const { passwordHash, ...userSafe } = user;

    return {
      ...userSafe,
      vendorProfile: vendorProfile ?? null,
      agentProfile:  agentProfile  ?? null,
    };
  }

  // ─────────────────────────────────────────────────────
  // MODIFIER SON PROFIL
  // ─────────────────────────────────────────────────────
  async updateProfile(
    userId: string,
    dto:    UpdateProfileDto,
    ip:     string,
  ) {
    const user = await this.userRepo.findOne({ where: { id: userId } });
    if (!user) throw new NotFoundException('Utilisateur introuvable');

    // Vérifier si le nouveau téléphone est déjà utilisé
    if (dto.phone && dto.phone !== user.phone) {
      const phoneExists = await this.userRepo.findOne({
        where: { phone: dto.phone },
      });
      if (phoneExists) {
        throw new ConflictException('Ce numéro de téléphone est déjà utilisé');
      }
    }

    // Sauvegarder les anciennes valeurs pour le log
    const oldValue = {
      prenom: user.prenom,
      name:   user.name,
      phone:  user.phone,
    };

    // Mettre à jour uniquement les champs fournis
    if (dto.prenom)    user.prenom    = dto.prenom;
    if (dto.name)      user.name      = dto.name;
    if (dto.phone)     user.phone     = dto.phone;
    if (dto.avatarUrl) user.avatarUrl = dto.avatarUrl;

    await this.userRepo.save(user);

    await this.logService.log({
      actorId:    userId,
      actorType:  ActorType.CLIENT,
      action:     LogAction.USER_REGISTER,
      entityType: 'user',
      entityId:   userId,
      oldValue,
      newValue: {
        prenom: user.prenom,
        name:   user.name,
        phone:  user.phone,
      },
      ipAddress: ip,
    });

    const { passwordHash, ...userSafe } = user;
    return userSafe;
  }

  // ─────────────────────────────────────────────────────
  // CHANGER SON MOT DE PASSE
  // ─────────────────────────────────────────────────────
  async changePassword(
    userId:      string,
    currentPassword: string,
    newPassword:     string,
    confirmPassword: string,
    ip:          string,
  ) {
    // 1. Vérifier que les nouveaux mots de passe correspondent
    if (newPassword !== confirmPassword) {
      throw new BadRequestException(
        'Les nouveaux mots de passe ne correspondent pas'
      );
    }

    const user = await this.userRepo.findOne({ where: { id: userId } });
    if (!user) throw new NotFoundException('Utilisateur introuvable');

    // 2. Vérifier l'ancien mot de passe
    const isValid = await bcrypt.compare(currentPassword, user.passwordHash);
    if (!isValid) {
      throw new BadRequestException('Mot de passe actuel incorrect');
    }

    // 3. Vérifier que le nouveau mot de passe est différent
    const isSame = await bcrypt.compare(newPassword, user.passwordHash);
    if (isSame) {
      throw new BadRequestException(
        'Le nouveau mot de passe doit être différent de l\'ancien'
      );
    }

    // 4. Hasher et sauvegarder
    user.passwordHash = await bcrypt.hash(newPassword, 12);
    await this.userRepo.save(user);

    await this.logService.log({
      actorId:    userId,
      actorType:  ActorType.CLIENT,
      action:     LogAction.USER_PASSWORD_RESET,
      entityType: 'user',
      entityId:   userId,
      ipAddress:  ip,
    });

    return { message: 'Mot de passe modifié avec succès' };
  }

  // ─────────────────────────────────────────────────────
  // ADRESSES — CRÉER
  // ─────────────────────────────────────────────────────
  async createAddress(userId: string, dto: CreateAddressDto) {
    // Si isDefault = true → retirer le default des autres adresses
    if (dto.isDefault) {
      await this.addressRepo.update(
        { userId },
        { isDefault: false },
      );
    }

    // Si c'est la première adresse → la mettre en default automatiquement
    const count = await this.addressRepo.count({ where: { userId } });
    if (count === 0) {
      dto.isDefault = true;
    }

    const address = this.addressRepo.create({ ...dto, userId });
    return this.addressRepo.save(address);
  }

  // ─────────────────────────────────────────────────────
  // ADRESSES — LISTER
  // ─────────────────────────────────────────────────────
  async getMyAddresses(userId: string) {
    return this.addressRepo.find({
      where: { userId },
      order: { isDefault: 'DESC', createdAt: 'ASC' },
    });
  }

  // ─────────────────────────────────────────────────────
  // ADRESSES — MODIFIER
  // ─────────────────────────────────────────────────────
  async updateAddress(
    userId:    string,
    addressId: string,
    dto:       UpdateAddressDto,
  ) {
    const address = await this.addressRepo.findOne({
      where: { id: addressId, userId },
    });

    if (!address) {
      throw new NotFoundException('Adresse introuvable');
    }

    // Si on met cette adresse en default
    if (dto.isDefault) {
      await this.addressRepo.update(
        { userId },
        { isDefault: false },
      );
    }

    Object.assign(address, dto);
    return this.addressRepo.save(address);
  }

  // ─────────────────────────────────────────────────────
  // ADRESSES — SUPPRIMER
  // ─────────────────────────────────────────────────────
  async deleteAddress(userId: string, addressId: string) {
    const address = await this.addressRepo.findOne({
      where: { id: addressId, userId },
    });

    if (!address) {
      throw new NotFoundException('Adresse introuvable');
    }

    await this.addressRepo.remove(address);

    // Si c'était l'adresse par défaut → mettre la première disponible en default
    if (address.isDefault) {
      const first = await this.addressRepo.findOne({
        where: { userId },
        order: { createdAt: 'ASC' },
      });
      if (first) {
        first.isDefault = true;
        await this.addressRepo.save(first);
      }
    }

    return { message: 'Adresse supprimée' };
  }

  // ─────────────────────────────────────────────────────
  // ADRESSES — DÉFINIR COMME PRINCIPALE
  // ─────────────────────────────────────────────────────
  async setDefaultAddress(userId: string, addressId: string) {
    const address = await this.addressRepo.findOne({
      where: { id: addressId, userId },
    });

    if (!address) throw new NotFoundException('Adresse introuvable');

    // Retirer le default de toutes les adresses
    await this.addressRepo.update(
      { userId },
      { isDefault: false },
    );

    // Mettre cette adresse en default
    address.isDefault = true;
    await this.addressRepo.save(address);

    return { message: 'Adresse principale mise à jour' };
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — LISTE DES UTILISATEURS
  // ─────────────────────────────────────────────────────
  async getAllUsers(page = 1, limit = 20) {
    const [users, total] = await this.userRepo.findAndCount({
      relations: ['roles'],
      order:     { createdAt: 'DESC' },
      skip:      (page - 1) * limit,
      take:      limit,
    });

    // Supprimer les passwordHash de tous les utilisateurs
    const safeUsers = users.map(({ passwordHash, ...u }) => u);

    return {
      data:  safeUsers,
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
    };
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — DÉTAILS D'UN UTILISATEUR
  // ─────────────────────────────────────────────────────
  async getUserById(id: string) {
    const user = await this.userRepo.findOne({
      where:     { id },
      relations: ['roles', 'addresses'],
    });

    if (!user) throw new NotFoundException('Utilisateur introuvable');

    const vendorProfile = await this.vendorRepo.findOne({ where: { userId: id } });
    const agentProfile  = await this.agentRepo.findOne({ where: { userId: id } });

    const { passwordHash, ...userSafe } = user;

    return {
      ...userSafe,
      vendorProfile: vendorProfile ?? null,
      agentProfile:  agentProfile  ?? null,
    };
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — BLOQUER UN UTILISATEUR
  // ─────────────────────────────────────────────────────
  async blockUser(
    userId:  string,
    adminId: string,
    ip:      string,
  ) {
    const user = await this.userRepo.findOne({ where: { id: userId } });
    if (!user) throw new NotFoundException('Utilisateur introuvable');

    if (!user.isActive) {
      throw new BadRequestException('Cet utilisateur est déjà bloqué');
    }

    user.isActive = false;
    await this.userRepo.save(user);

    await this.logService.log({
      actorId:    adminId,
      actorType:  ActorType.ADMIN,
      action:     LogAction.USER_BLOCKED,
      entityType: 'user',
      entityId:   userId,
      oldValue:   { isActive: true },
      newValue:   { isActive: false },
      ipAddress:  ip,
    });

    return { message: 'Utilisateur bloqué avec succès' };
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — DÉBLOQUER UN UTILISATEUR
  // ─────────────────────────────────────────────────────
  async unblockUser(
    userId:  string,
    adminId: string,
    ip:      string,
  ) {
    const user = await this.userRepo.findOne({ where: { id: userId } });
    if (!user) throw new NotFoundException('Utilisateur introuvable');

    if (user.isActive) {
      throw new BadRequestException('Cet utilisateur est déjà actif');
    }

    user.isActive = true;
    await this.userRepo.save(user);

    await this.logService.log({
      actorId:    adminId,
      actorType:  ActorType.ADMIN,
      action:     LogAction.USER_UNBLOCKED,
      entityType: 'user',
      entityId:   userId,
      oldValue:   { isActive: false },
      newValue:   { isActive: true },
      ipAddress:  ip,
    });

    return { message: 'Utilisateur débloqué avec succès' };
  }
}