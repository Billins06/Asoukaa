import {
  Injectable,
  Logger,
  NotFoundException,
  ConflictException,
  BadRequestException,
  ForbiddenException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository }       from 'typeorm';
import { MailService }      from '../mail/mail.service';

import {
  DeliveryAgentProfile,
  AgentStatus,
} from '../users/entities/delivery-agent-profile.entity';
import { UserRole, UserRoleEnum } from '../users/entities/user-role.entity';
import { User }                   from '../users/entities/user.entity';
import { DeliveryEarning, DeliveryEarningStatus } from '../delivery/entities/delivery-earning.entity';

import { SubmitAgentProfileDto }      from './dto/submit-agent-profile.dto';
import { CompleteAgentDocumentsDto }  from './dto/complete-agent-documents.dto';
import { UpdateAgentAvailabilityDto } from './dto/update-availability.dto';
import {
  ReviewAgentDto,
  AgentReviewAction,
} from './dto/review-agent.dto';

import { ActivityLogService } from '../../common/services/activity-log.service';
import { stripSecrets } from '../../common/utils/strip-secrets.util';
import { UploadService, UploadType } from '../upload/upload.service';
import {
  ActorType,
  LogAction,
} from '../../common/entities/activity-log.entity';

@Injectable()
export class DeliveryAgentsService {
  private readonly logger = new Logger(DeliveryAgentsService.name);

  constructor(
    @InjectRepository(DeliveryAgentProfile)
    private readonly agentRepo: Repository<DeliveryAgentProfile>,

    @InjectRepository(UserRole)
    private readonly userRoleRepo: Repository<UserRole>,

    @InjectRepository(User)
    private readonly userRepo: Repository<User>,

    @InjectRepository(DeliveryEarning)
    private readonly earningRepo: Repository<DeliveryEarning>,

    private readonly mailService:   MailService,
    private readonly logService:    ActivityLogService,
    // Rafraîchit les URL signées (expirantes) des documents privés pour l'admin.
    private readonly uploadService: UploadService,
  ) {}

  // ─────────────────────────────────────────────────────
  // SOUMETTRE UNE DEMANDE LIVREUR
  // ─────────────────────────────────────────────────────
  async submitProfile(
    userId: string,
    dto:    SubmitAgentProfileDto,
    ip:     string,
  ) {
    // 1. Vérifier qu'un profil n'existe pas déjà
    const existing = await this.agentRepo.findOne({
      where: { userId },
    });

    if (existing) {
      if (existing.status === AgentStatus.APPROVED) {
        throw new ConflictException('Votre profil livreur est déjà actif');
      }

      if (existing.status === AgentStatus.PENDING) {
        throw new ConflictException(
          'Votre demande est déjà en cours de traitement'
        );
      }

      if (existing.status === AgentStatus.BLOCKED) {
        throw new ForbiddenException(
          'Votre compte livreur a été bloqué. Contactez le support.'
        );
      }

      // Si rejeté → re-soumission autorisée
      if (existing.status === AgentStatus.REJECTED) {
        return this.resubmitProfile(existing, dto, ip);
      }
    }

    // 1 bis. Pièce d'identité / selfie : doivent provenir de notre stockage privé
    this.assertOwnKycUrls(dto);

    // 2. Créer le profil livreur
    const agent = this.agentRepo.create({
      userId,
      vehicleType:             dto.vehicleType,
      availability:            dto.availability,
      ville:                   dto.ville,
      quartier:                dto.quartier,
      preciseAddress:          dto.preciseAddress,
      idDocumentUrl:           dto.idDocumentUrl,
      selfieUrl:               dto.selfieUrl,
      vehiclePhotoUrl:         dto.vehiclePhotoUrl,
      licensePlate:            dto.licensePlate,
      termsAccepted:           dto.termsAccepted,
      fraudPenaltiesAccepted:  dto.fraudPenaltiesAccepted,
      status:                  AgentStatus.PENDING,
      isAvailableNow:          false,
      noteMoyenne:             0,
      tauxDeReussite:          0,
      totalLivraisons:         0,
    });

    await this.agentRepo.save(agent);

    await this.logService.log({
      actorId:    userId,
      actorType:  ActorType.CLIENT,
      action:     LogAction.AGENT_SUBMITTED,
      entityType: 'delivery_agent_profile',
      entityId:   agent.id,
      ipAddress:  ip,
    });

    // Email "demande reçue, en cours de traitement" — best-effort, comme
    // pour VendorsService.submitProfile (même correctif, même raison :
    // rien n'était envoyé alors que le message ci-dessous le promet).
    try {
      const submitter = await this.userRepo.findOne({ where: { id: userId } });
      if (submitter) {
        await this.mailService.sendAgentSubmitted(submitter.email, submitter.prenom);
      }
    } catch (error) {
      this.logger.error(
        `Échec envoi mail de soumission livreur → userId=${userId}`,
        error?.message,
      );
    }

    return {
      message: 'Demande soumise avec succès. '
             + 'Vous serez notifié par email après validation.',
      agentId: agent.id,
    };
  }

  // Pièce d'identité / selfie : toute NOUVELLE valeur doit être une URL émise
  // par notre propre route d'upload privée (types documents / selfies), pas une
  // URL quelconque. Une valeur identique à celle déjà enregistrée n'est pas
  // re-contrôlée (dossiers existants non cassés).
  private assertOwnKycUrls(
    dto:     { idDocumentUrl?: string; selfieUrl?: string },
    current?: { idDocumentUrl?: string | null; selfieUrl?: string | null },
  ): void {
    if (dto.idDocumentUrl && dto.idDocumentUrl !== current?.idDocumentUrl) {
      this.uploadService.assertIsOwnUploadUrl(dto.idDocumentUrl, UploadType.DOCUMENT);
    }
    if (dto.selfieUrl && dto.selfieUrl !== current?.selfieUrl) {
      this.uploadService.assertIsOwnUploadUrl(dto.selfieUrl, UploadType.SELFIE);
    }
  }

  // ─────────────────────────────────────────────────────
  // RE-SOUMISSION APRÈS REFUS (méthode privée)
  // ─────────────────────────────────────────────────────
  private async resubmitProfile(
    existing: DeliveryAgentProfile,
    dto:      SubmitAgentProfileDto,
    ip:       string,
  ) {
    // Pièce d'identité / selfie : nouvelles valeurs issues de notre stockage privé
    this.assertOwnKycUrls(dto, existing);

    existing.vehicleType            = dto.vehicleType;
    existing.availability           = dto.availability;
    existing.ville                  = dto.ville;
    existing.quartier               = dto.quartier;
    existing.preciseAddress         = dto.preciseAddress;
    existing.idDocumentUrl          = dto.idDocumentUrl ?? existing.idDocumentUrl;
    existing.selfieUrl              = dto.selfieUrl ?? existing.selfieUrl;
    existing.vehiclePhotoUrl        = dto.vehiclePhotoUrl ?? existing.vehiclePhotoUrl;
    existing.licensePlate           = dto.licensePlate;
    existing.termsAccepted          = dto.termsAccepted;
    existing.fraudPenaltiesAccepted = dto.fraudPenaltiesAccepted;
    existing.status                 = AgentStatus.PENDING;
    existing.motifRefus             = null;

    await this.agentRepo.save(existing);

    await this.logService.log({
      actorId:    existing.userId,
      actorType:  ActorType.CLIENT,
      action:     LogAction.AGENT_SUBMITTED,
      entityType: 'delivery_agent_profile',
      entityId:   existing.id,
      newValue:   { resubmission: true },
      ipAddress:  ip,
    });

    // Même email "en cours de traitement" que pour une première soumission
    // — voir submitProfile() ci-dessus.
    try {
      const submitter = await this.userRepo.findOne({ where: { id: existing.userId } });
      if (submitter) {
        await this.mailService.sendAgentSubmitted(submitter.email, submitter.prenom);
      }
    } catch (error) {
      this.logger.error(
        `Échec envoi mail de re-soumission livreur → userId=${existing.userId}`,
        error?.message,
      );
    }

    return {
      message: 'Demande re-soumise avec succès. Vous serez notifié par email.',
      agentId: existing.id,
    };
  }

  // ─────────────────────────────────────────────────────
  // COMPLÉTER LES DOCUMENTS MANQUANTS (dossier EN ATTENTE)
  // ─────────────────────────────────────────────────────
  async completeDocuments(
    userId: string,
    dto:    CompleteAgentDocumentsDto,
    ip:     string,
  ) {
    const agent = await this.agentRepo.findOne({ where: { userId } });
    if (!agent) throw new NotFoundException('Profil livreur introuvable');

    if (agent.status !== AgentStatus.PENDING) {
      throw new BadRequestException(
        "Cette action n'est possible que pour un dossier en attente de validation"
      );
    }

    this.assertOwnKycUrls(dto, agent);

    if (dto.idDocumentUrl)   agent.idDocumentUrl = dto.idDocumentUrl;
    if (dto.selfieUrl)       agent.selfieUrl = dto.selfieUrl;
    if (dto.vehiclePhotoUrl) agent.vehiclePhotoUrl = dto.vehiclePhotoUrl;

    await this.agentRepo.save(agent);

    await this.logService.log({
      actorId:    userId,
      actorType:  ActorType.CLIENT,
      action:     LogAction.AGENT_SUBMITTED,
      entityType: 'delivery_agent_profile',
      entityId:   agent.id,
      ipAddress:  ip,
    });

    return { message: 'Documents mis à jour.' };
  }

  // ─────────────────────────────────────────────────────
  // VOIR SON PROPRE PROFIL LIVREUR
  // ─────────────────────────────────────────────────────
  async getMyProfile(userId: string) {
    const agent = await this.agentRepo.findOne({
      where: { userId },
    });

    if (!agent) {
      throw new NotFoundException(
        'Aucun profil livreur trouvé. Soumettez une demande d\'abord.'
      );
    }

    return agent;
  }

  // ─────────────────────────────────────────────────────
  // VOIR SES GAINS (solde, historique des livraisons payées)
  // ─────────────────────────────────────────────────────
  async getMyEarnings(userId: string) {
    const agent = await this.agentRepo.findOne({ where: { userId } });
    if (!agent) {
      throw new NotFoundException(
        'Aucun profil livreur trouvé. Soumettez une demande d\'abord.'
      );
    }

    const earnings = await this.earningRepo.find({
      where: { agentId: agent.id },
      relations: ['delivery', 'delivery.order'],
      order: { createdAt: 'DESC' },
    });

    const pendingAmount = earnings
      .filter(e => e.status === DeliveryEarningStatus.PENDING)
      .reduce((sum, e) => sum + Number(e.montantLivreur), 0);
    const paidAmount = earnings
      .filter(e => e.status === DeliveryEarningStatus.PAID)
      .reduce((sum, e) => sum + Number(e.montantLivreur), 0);

    return {
      soldeDisponible: pendingAmount,
      enAttente:       pendingAmount,
      totalRecu:       paidAmount,
      historique: earnings.slice(0, 30).map(e => ({
        id:          e.id,
        orderNumber: e.delivery?.order?.orderNumber ?? '—',
        montant:     Number(e.montantLivreur),
        statut:      e.status,
        date:        e.paidAt ?? e.createdAt,
      })),
    };
  }

  // ─────────────────────────────────────────────────────
  // METTRE À JOUR SA DISPONIBILITÉ EN TEMPS RÉEL
  // ─────────────────────────────────────────────────────
  async updateAvailability(
    userId: string,
    dto:    UpdateAgentAvailabilityDto,
  ) {
    const agent = await this.agentRepo.findOne({
      where: { userId },
    });

    if (!agent) throw new NotFoundException('Profil livreur introuvable');

    // ⚠️ Seul un livreur APPROUVÉ peut changer sa disponibilité
    if (agent.status !== AgentStatus.APPROVED) {
      throw new ForbiddenException(
        'Votre profil doit être validé pour modifier votre disponibilité'
      );
    }

    agent.isAvailableNow = dto.isAvailableNow;
    await this.agentRepo.save(agent);

    return {
      message:        dto.isAvailableNow
        ? 'Vous êtes maintenant disponible'
        : 'Vous êtes maintenant indisponible',
      isAvailableNow: agent.isAvailableNow,
    };
  }

  // ─────────────────────────────────────────────────────
  // LISTE DES LIVREURS DISPONIBLES
  // (utilisé par le module livraison indépendante)
  // ─────────────────────────────────────────────────────
  async getAvailableAgents() {
    return this.agentRepo
      .createQueryBuilder('agent')
      .leftJoin('agent.user', 'user')
      .select([
        'agent.id',
        'agent.vehicleType',
        'agent.ville',
        'agent.quartier',
        'agent.noteMoyenne',
        'agent.tauxDeReussite',
        'agent.totalLivraisons',
        'user.id',
        'user.prenom',
        'user.name',
        'user.phone',
      ])
      .where('agent.status = :status',        { status: AgentStatus.APPROVED })
      .andWhere('agent.isAvailableNow = :av', { av: true })
      .orderBy('agent.noteMoyenne', 'DESC')
      .getMany();
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — LISTE DES PROFILS LIVREURS
  // ─────────────────────────────────────────────────────
  async getAllAgents(
    status?: AgentStatus,
    page:    number = 1,
    limit:   number = 20,
  ) {
    const query = this.agentRepo
      .createQueryBuilder('agent')
      .leftJoin('agent.user', 'user')
      .select([
        'agent.id',
        'agent.vehicleType',
        'agent.availability',
        'agent.ville',
        'agent.status',
        'agent.noteMoyenne',
        'agent.tauxDeReussite',
        'agent.totalLivraisons',
        'agent.createdAt',
        'user.id',
        'user.prenom',
        'user.name',
        'user.email',
        'user.phone',
      ])
      .orderBy('agent.createdAt', 'DESC')
      .skip((page - 1) * limit)
      .take(limit);

    if (status) {
      query.where('agent.status = :status', { status });
    }

    const [agents, total] = await query.getManyAndCount();

    return {
      data:  agents,
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
    };
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — DÉTAILS D'UN LIVREUR
  // ─────────────────────────────────────────────────────
  async getAgentById(agentId: string) {
    const agent = await this.agentRepo.findOne({
      where:     { id: agentId },
      relations: ['user', 'reviewedBy'],
    });

    if (!agent) throw new NotFoundException('Profil livreur introuvable');

    // Route admin : retire le hash du mot de passe du compte livreur et
    // les secrets de l'admin relecteur (reviewedBy).
    const safe = stripSecrets(agent);
    // Documents privés : URL fraîches (les URL signées Supabase expirent).
    // La photo du véhicule est un fichier public.
    safe.idDocumentUrl = await this.uploadService.refreshPrivateUrl(agent.idDocumentUrl);
    safe.selfieUrl     = await this.uploadService.refreshPrivateUrl(agent.selfieUrl);
    return safe;
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — VALIDER OU REFUSER UN LIVREUR
  // ─────────────────────────────────────────────────────
  async reviewAgent(
    agentId: string,
    adminId: string,
    dto:     ReviewAgentDto,
    ip:      string,
  ) {
    const agent = await this.agentRepo.findOne({
      where:     { id: agentId },
      relations: ['user'],
    });

    if (!agent) throw new NotFoundException('Profil livreur introuvable');

    if (agent.status !== AgentStatus.PENDING) {
      throw new BadRequestException(
        'Seules les demandes en attente peuvent être traitées'
      );
    }

    const oldStatus = agent.status;

    if (dto.action === AgentReviewAction.APPROVE) {
      if (!agent.idDocumentUrl || !agent.selfieUrl || !agent.vehiclePhotoUrl) {
        throw new BadRequestException(
          "Impossible d'approuver : il manque des documents (pièce d'identité, selfie ou photo du véhicule)"
        );
      }

      agent.status     = AgentStatus.APPROVED;
      agent.motifRefus = null;

      // Attribuer le rôle DELIVERY_AGENT
      const roleExists = await this.userRoleRepo.findOne({
        where: {
          userId: agent.userId,
          role:   UserRoleEnum.DELIVERY_AGENT,
        },
      });

      if (!roleExists) {
        await this.userRoleRepo.save(
          this.userRoleRepo.create({
            userId:   agent.userId,
            role:     UserRoleEnum.DELIVERY_AGENT,
            isActive: true,
          })
        );
      } else {
        roleExists.isActive = true;
        await this.userRoleRepo.save(roleExists);
      }
    } else {
      agent.status     = AgentStatus.REJECTED;
      agent.motifRefus = dto.rejectionReason ?? null;
    }

    // ⚠️ On persiste le statut AVANT l'envoi de l'email : un échec SMTP ne
    // doit jamais laisser le livreur dans un état incohérent (rôle attribué
    // mais statut resté "en attente").
    agent.reviewedById = adminId;
    agent.reviewedAt   = new Date();
    await this.agentRepo.save(agent);

    // Email de notification — best-effort.
    //
    // ⚠️ Même correctif que VendorsService.reviewVendor : ces deux emails
    // étaient envoyés en HTML brut fait main au lieu de passer par
    // MailService (agentApprovedTemplate/agentRejectedTemplate existaient
    // déjà mais n'étaient jamais appelés depuis ici).
    try {
      if (dto.action === AgentReviewAction.APPROVE) {
        await this.mailService.sendAgentApproved(
          agent.user.email,
          agent.user.prenom,
        );
      } else {
        await this.mailService.sendAgentRejected(
          agent.user.email,
          agent.user.prenom,
          dto.rejectionReason ?? '',
        );
      }
    } catch (error) {
      this.logger.error(
        `Échec envoi mail de revue livreur → ${agent.user.email}`,
        error?.message,
      );
    }

    await this.logService.log({
      actorId:    adminId,
      actorType:  ActorType.ADMIN,
      action:     dto.action === AgentReviewAction.APPROVE
                    ? LogAction.AGENT_APPROVED
                    : LogAction.AGENT_REJECTED,
      entityType: 'delivery_agent_profile',
      entityId:   agentId,
      oldValue:   { status: oldStatus },
      newValue:   {
        status: agent.status,
        reason: dto.rejectionReason ?? null,
      },
      ipAddress: ip,
    });

    return {
      message: dto.action === AgentReviewAction.APPROVE
        ? 'Livreur validé avec succès'
        : 'Demande refusée. Le livreur a été notifié.',
    };
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — BLOQUER UN LIVREUR
  // ─────────────────────────────────────────────────────
  async blockAgent(
    agentId: string,
    adminId: string,
    ip:      string,
  ) {
    const agent = await this.agentRepo.findOne({
      where:     { id: agentId },
      relations: ['user'],
    });

    if (!agent) throw new NotFoundException('Profil livreur introuvable');

    if (agent.status === AgentStatus.BLOCKED) {
      throw new BadRequestException('Ce livreur est déjà bloqué');
    }

    const oldStatus = agent.status;

    agent.status         = AgentStatus.BLOCKED;
    agent.isAvailableNow = false; // forcer indisponible
    agent.reviewedById   = adminId;
    agent.reviewedAt     = new Date();

    // Désactiver le rôle DELIVERY_AGENT
    await this.userRoleRepo.update(
      { userId: agent.userId, role: UserRoleEnum.DELIVERY_AGENT },
      { isActive: false },
    );

    await this.agentRepo.save(agent);

    // Notifier par email (best-effort)
    try {
      await this.mailService.sendAgentBlocked(
        agent.user.email,
        agent.user.prenom,
      );
    } catch (error) {
      this.logger.error(
        `Échec envoi mail de blocage livreur → ${agent.user.email}`,
        error?.message,
      );
    }

    await this.logService.log({
      actorId:    adminId,
      actorType:  ActorType.ADMIN,
      action:     LogAction.AGENT_BLOCKED,
      entityType: 'delivery_agent_profile',
      entityId:   agentId,
      oldValue:   { status: oldStatus },
      newValue:   { status: AgentStatus.BLOCKED },
      ipAddress:  ip,
    });

    return { message: 'Livreur bloqué avec succès' };
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — DÉBLOQUER UN LIVREUR
  // ─────────────────────────────────────────────────────
  async unblockAgent(
    agentId: string,
    adminId: string,
    ip:      string,
  ) {
    const agent = await this.agentRepo.findOne({
      where:     { id: agentId },
      relations: ['user'],
    });

    if (!agent) throw new NotFoundException('Profil livreur introuvable');

    if (agent.status !== AgentStatus.BLOCKED) {
      throw new BadRequestException("Ce livreur n'est pas bloqué");
    }

    const oldStatus = agent.status;

    // Un livreur ne pouvait être bloqué que s'il avait déjà été approuvé —
    // le débloquer le restaure donc dans l'état APPROUVÉ. Il reste
    // indisponible (isAvailableNow=false) jusqu'à ce qu'il se remette
    // lui-même en ligne.
    agent.status       = AgentStatus.APPROVED;
    agent.reviewedById = adminId;
    agent.reviewedAt   = new Date();

    // Réactiver le rôle DELIVERY_AGENT
    await this.userRoleRepo.update(
      { userId: agent.userId, role: UserRoleEnum.DELIVERY_AGENT },
      { isActive: true },
    );

    await this.agentRepo.save(agent);

    try {
      await this.mailService.sendAgentUnblocked(
        agent.user.email,
        agent.user.prenom,
      );
    } catch (error) {
      this.logger.error(
        `Échec envoi mail de déblocage livreur → ${agent.user.email}`,
        error?.message,
      );
    }

    await this.logService.log({
      actorId:    adminId,
      actorType:  ActorType.ADMIN,
      action:     LogAction.AGENT_UNBLOCKED,
      entityType: 'delivery_agent_profile',
      entityId:   agentId,
      oldValue:   { status: oldStatus },
      newValue:   { status: AgentStatus.APPROVED },
      ipAddress:  ip,
    });

    return { message: 'Livreur débloqué avec succès' };
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — DEMANDES EN ATTENTE
  // ─────────────────────────────────────────────────────
  async getPendingAgents() {
    const pending = await this.agentRepo
      .createQueryBuilder('agent')
      .leftJoin('agent.user', 'user')
      .select([
        'agent.id',
        'agent.vehicleType',
        'agent.ville',
        'agent.quartier',
        'agent.createdAt',
        // Pièces à vérifier par l'admin (route réservée aux admins).
        'agent.idDocumentUrl',
        'agent.selfieUrl',
        'agent.vehiclePhotoUrl',
        'user.id',
        'user.prenom',
        'user.name',
        'user.email',
        'user.phone',
      ])
      .where('agent.status = :status', { status: AgentStatus.PENDING })
      .orderBy('agent.createdAt', 'ASC')
      .getMany();

    return Promise.all(
      pending.map(async (a) => ({
        ...a,
        // Documents privés : URL fraîches (les URL signées expirent).
        idDocumentUrl: await this.uploadService.refreshPrivateUrl(a.idDocumentUrl),
        selfieUrl:     await this.uploadService.refreshPrivateUrl(a.selfieUrl),
      })),
    );
  }

  // ─────────────────────────────────────────────────────
  // METTRE À JOUR LES STATS D'UN LIVREUR
  // (appelé automatiquement par le module delivery
  //  quand une livraison est terminée)
  // ─────────────────────────────────────────────────────
  async updateAgentStats(agentId: string): Promise<void> {
    const agent = await this.agentRepo.findOne({
      where: { id: agentId },
    });

    if (!agent) return;

    // On incrémente le total des livraisons
    agent.totalLivraisons += 1;
    await this.agentRepo.save(agent);

    // ⚠️ Le tauxDeReussite et noteMoyenne seront calculés
    // depuis la table deliveries et reviews respectivement
    // Ce calcul sera fait dans le module delivery
    // quand on aura toutes les données nécessaires
  }
}