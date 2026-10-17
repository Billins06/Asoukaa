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
import { UserRole, UserRoleEnum } from './entities/user-role.entity';
import { Address }        from './entities/address.entity';
import { VendorProfile }  from './entities/vendor-profile.entity';
import { DeliveryAgentProfile } from './entities/delivery-agent-profile.entity';

import { UpdateProfileDto }  from './dto/update-profile.dto';
import { AdminCreateUserDto } from './dto/admin-create-user.dto';
import { AdminUpdateUserDto } from './dto/admin-update-user.dto';
import { CreateAddressDto }  from './dto/create-address.dto';
import { UpdateAddressDto }  from './dto/update-address.dto';

import { ActivityLogService } from '../../common/services/activity-log.service';
import { TokenService } from '../../common/services/token.service';
import { UploadService, UploadType } from '../upload/upload.service';
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

    private readonly uploadService: UploadService,

    private readonly tokenService: TokenService,
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

    // ⚠️ Ne jamais retourner passwordHash, ni les champs de sécurité internes
    // (révocation des sessions, alerte d'e-mail annulé : affaire de l'admin).
    const {
      passwordHash,
      tokensValidAfter,
      securityAlertAt,
      securityAlertReason,
      securityAlertAckedAt,
      ...userSafe
    } = user;

    // ⚠️ paymentDetails est chiffré et n'a rien à faire côté appli (même
    // règle que VendorsService : on n'expose que « est-ce configuré »).
    // Les documents (idDocumentUrl, selfieUrl...) restent visibles : le
    // propriétaire les consulte dans son espace vendeur.
    let vendorSafe: Record<string, any> | null = null;
    if (vendorProfile) {
      const { paymentDetails, ...rest } = vendorProfile;
      vendorSafe = { ...rest, hasPaymentConfigured: !!paymentDetails };
    }

    return {
      ...userSafe,
      vendorProfile: vendorSafe,
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

    // Avatar : une URL non vide doit provenir de NOTRE stockage d'avatars.
    // Sans ce contrôle, n'importe quelle URL externe (pixel espion, contenu
    // malveillant) serait affichée dans l'appli des autres utilisateurs
    // (chat, avis, commandes). Échec → 400, avant toute modification.
    if (dto.avatarUrl) {
      this.uploadService.assertIsOwnUploadUrl(dto.avatarUrl, UploadType.AVATAR);
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
    // avatarUrl : une URL = nouvelle photo ; null (ou chaîne vide, convertie
    // en null par le DTO) = suppression de la photo ; absent = inchangé.
    if (dto.avatarUrl !== undefined) {
      user.avatarUrl = (dto.avatarUrl ? dto.avatarUrl : null) as unknown as string;
    }

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

    const {
      passwordHash,
      tokensValidAfter,
      securityAlertAt,
      securityAlertReason,
      securityAlertAckedAt,
      ...userSafe
    } = user;
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
    // Coupe toutes les AUTRES sessions (tous les jetons émis avant cet
    // instant, accès comme rafraîchissement, sont refusés par JwtStrategy et
    // par POST /auth/refresh). Le jeton utilisé pour cet appel est donc
    // révoqué lui aussi : on renvoie un NOUVEAU couple de jetons que
    // l'appli doit enregistrer à la place des anciens.
    user.tokensValidAfter = new Date();
    await this.userRepo.save(user);

    await this.logService.log({
      actorId:    userId,
      actorType:  ActorType.CLIENT,
      action:     LogAction.USER_PASSWORD_RESET,
      entityType: 'user',
      entityId:   userId,
      ipAddress:  ip,
    });

    const tokens = this.tokenService.issueUserTokens(user);
    return { message: 'Mot de passe modifié avec succès', ...tokens };
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

    try {
      await this.addressRepo.remove(address);
    } catch (err: any) {
      // Code Postgres 23503 = violation de contrainte de clé étrangère.
      // Order.address a onDelete: 'RESTRICT' : si une commande existe déjà
      // avec cette adresse, Postgres refuse la suppression. Sans ce catch,
      // l'exception brute remontait telle quelle et NestJS renvoyait un
      // 500 "Erreur interne du serveur" au lieu d'un message compréhensible.
      //
      // Vérification élargie (code ET message) : selon la façon dont
      // l'erreur remonte (QueryFailedError direct ou emballée dans
      // driverError), la propriété .code n'est pas toujours au même
      // endroit — on ne veut pas rater ce cas et relaisser passer un 500.
      const code = err?.code ?? err?.driverError?.code;
      const isForeignKeyViolation =
        code === '23503' ||
        (typeof err?.message === 'string' &&
          err.message.toLowerCase().includes('foreign key constraint'));
      if (isForeignKeyViolation) {
        throw new BadRequestException(
          "Cette adresse est utilisée par une ou plusieurs commandes et ne peut pas être supprimée.",
        );
      }
      throw err;
    }

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

    // Supprimer les passwordHash de tous les utilisateurs.
    // L'alerte « Ce n'est pas moi » est exposée À L'ADMIN seulement (cette
    // route est réservée aux admins) : valeurs explicites (date ISO ou null)
    // pour que le site admin affiche le badge et le bouton « Acquitter ».
    const safeUsers = users.map(({ passwordHash, ...u }) => ({
      ...u,
      securityAlertAt:      u.securityAlertAt      ?? null,
      securityAlertReason:  u.securityAlertReason  ?? null,
      securityAlertAckedAt: u.securityAlertAckedAt ?? null,
    }));

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
      // Alerte « Ce n'est pas moi » (admin seulement) : date ISO ou null.
      securityAlertAt:      user.securityAlertAt      ?? null,
      securityAlertReason:  user.securityAlertReason  ?? null,
      securityAlertAckedAt: user.securityAlertAckedAt ?? null,
      vendorProfile: vendorProfile ?? null,
      agentProfile:  agentProfile  ?? null,
    };
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — ACQUITTER L'ALERTE DE SÉCURITÉ D'UN UTILISATEUR
  // PATCH /users/:id/security-alert/ack
  // ─────────────────────────────────────────────────────
  // « Acquitter » = un admin a pris connaissance de l'alerte (« Ce n'est pas
  // moi »). On ne supprime RIEN : securityAlertAt / Reason restent comme
  // preuve, seule la date d'acquittement est posée. Si une NOUVELLE alerte
  // survient plus tard (securityAlertAt > securityAlertAckedAt), elle
  // redevient active d'elle-même.
  async ackSecurityAlert(userId: string, adminId: string, ip: string) {
    const user = await this.userRepo.findOne({
      where:  { id: userId },
      select: ['id', 'securityAlertAt', 'securityAlertAckedAt'],
    });
    if (!user) throw new NotFoundException('Utilisateur introuvable');

    if (!user.securityAlertAt) {
      throw new BadRequestException(
        "Cet utilisateur n'a aucune alerte de sécurité à acquitter",
      );
    }

    const ackedAt = new Date();
    await this.userRepo.update({ id: userId }, { securityAlertAckedAt: ackedAt });

    await this.logService.log({
      actorId:    adminId,
      actorType:  ActorType.ADMIN,
      action:     LogAction.SECURITY_ALERT_ACKED,
      entityType: 'user',
      entityId:   userId,
      oldValue:   { securityAlertAckedAt: user.securityAlertAckedAt ?? null },
      newValue:   { securityAlertAckedAt: ackedAt.toISOString() },
      ipAddress:  ip,
    });

    return { id: userId, securityAlertAckedAt: ackedAt.toISOString() };
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
    // Coupe aussi les sessions déjà ouvertes : tout jeton émis avant cet
    // instant est refusé (JwtStrategy). Au déblocage, les NOUVEAUX jetons
    // (émis après cette date) fonctionnent normalement : rien à remettre à zéro.
    user.tokensValidAfter = new Date();
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

  // ─────────────────────────────────────────────────────
  // ADMIN — CRÉER UN UTILISATEUR
  // ─────────────────────────────────────────────────────
  async adminCreateUser(
    dto:     AdminCreateUserDto,
    adminId: string,
    ip:      string,
  ) {
    const emailExists = await this.userRepo.findOne({ where: { email: dto.email } });
    if (emailExists) {
      throw new ConflictException('Cet email est déjà utilisé');
    }

    const phoneExists = await this.userRepo.findOne({ where: { phone: dto.phone } });
    if (phoneExists) {
      throw new ConflictException('Ce numéro de téléphone est déjà utilisé');
    }

    const passwordHash = await bcrypt.hash(dto.password, 12);

    const user = this.userRepo.create({
      prenom:       dto.prenom,
      name:         dto.name,
      email:        dto.email,
      phone:        dto.phone,
      passwordHash,
      // Créé par un admin : on considère le compte d'emblée vérifié,
      // pas besoin de repasser par l'OTP d'inscription.
      isVerified: true,
      isActive:   true,
    });
    await this.userRepo.save(user);

    const role = this.userRoleRepo.create({
      userId: user.id,
      role:   dto.role ?? UserRoleEnum.CLIENT,
    });
    await this.userRoleRepo.save(role);

    await this.logService.log({
      actorId:    adminId,
      actorType:  ActorType.ADMIN,
      action:     LogAction.USER_CREATED_BY_ADMIN,
      entityType: 'user',
      entityId:   user.id,
      newValue: {
        prenom: user.prenom,
        name:   user.name,
        email:  user.email,
        phone:  user.phone,
        role:   role.role,
      },
      ipAddress: ip,
    });

    const { passwordHash: _omit, ...userSafe } = user;
    return { ...userSafe, roles: [role] };
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — MODIFIER UN UTILISATEUR
  // ─────────────────────────────────────────────────────
  async adminUpdateUser(
    userId:  string,
    dto:     AdminUpdateUserDto,
    adminId: string,
    ip:      string,
  ) {
    const user = await this.userRepo.findOne({ where: { id: userId } });
    if (!user) throw new NotFoundException('Utilisateur introuvable');

    if (dto.email && dto.email !== user.email) {
      const emailExists = await this.userRepo.findOne({ where: { email: dto.email } });
      if (emailExists) {
        throw new ConflictException('Cet email est déjà utilisé');
      }
    }

    if (dto.phone && dto.phone !== user.phone) {
      const phoneExists = await this.userRepo.findOne({ where: { phone: dto.phone } });
      if (phoneExists) {
        throw new ConflictException('Ce numéro de téléphone est déjà utilisé');
      }
    }

    const oldValue = {
      prenom: user.prenom,
      name:   user.name,
      email:  user.email,
      phone:  user.phone,
    };

    if (dto.prenom !== undefined) user.prenom = dto.prenom;
    if (dto.name   !== undefined) user.name   = dto.name;
    if (dto.email  !== undefined) user.email  = dto.email;
    if (dto.phone  !== undefined) user.phone  = dto.phone;

    await this.userRepo.save(user);

    await this.logService.log({
      actorId:    adminId,
      actorType:  ActorType.ADMIN,
      action:     LogAction.USER_UPDATED_BY_ADMIN,
      entityType: 'user',
      entityId:   userId,
      oldValue,
      newValue: {
        prenom: user.prenom,
        name:   user.name,
        email:  user.email,
        phone:  user.phone,
      },
      ipAddress: ip,
    });

    const { passwordHash, ...userSafe } = user;
    return userSafe;
  }
}