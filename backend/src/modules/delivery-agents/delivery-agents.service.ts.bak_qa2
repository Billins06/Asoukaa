import {
  Injectable,
  NotFoundException,
  ConflictException,
  BadRequestException,
  ForbiddenException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository }       from 'typeorm';
import { MailerService }    from '@nestjs-modules/mailer';

import {
  DeliveryAgentProfile,
  AgentStatus,
} from '../users/entities/delivery-agent-profile.entity';
import { UserRole, UserRoleEnum } from '../users/entities/user-role.entity';
import { User }                   from '../users/entities/user.entity';

import { SubmitAgentProfileDto }      from './dto/submit-agent-profile.dto';
import { UpdateAgentAvailabilityDto } from './dto/update-availability.dto';
import {
  ReviewAgentDto,
  AgentReviewAction,
} from './dto/review-agent.dto';

import { ActivityLogService } from '../../common/services/activity-log.service';
import {
  ActorType,
  LogAction,
} from '../../common/entities/activity-log.entity';

@Injectable()
export class DeliveryAgentsService {

  constructor(
    @InjectRepository(DeliveryAgentProfile)
    private readonly agentRepo: Repository<DeliveryAgentProfile>,

    @InjectRepository(UserRole)
    private readonly userRoleRepo: Repository<UserRole>,

    @InjectRepository(User)
    private readonly userRepo: Repository<User>,

    private readonly mailerService: MailerService,
    private readonly logService:    ActivityLogService,
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

    return {
      message: 'Demande soumise avec succès. '
             + 'Vous serez notifié par email après validation.',
      agentId: agent.id,
    };
  }

  // ─────────────────────────────────────────────────────
  // RE-SOUMISSION APRÈS REFUS (méthode privée)
  // ─────────────────────────────────────────────────────
  private async resubmitProfile(
    existing: DeliveryAgentProfile,
    dto:      SubmitAgentProfileDto,
    ip:       string,
  ) {
    existing.vehicleType            = dto.vehicleType;
    existing.availability           = dto.availability;
    existing.ville                  = dto.ville;
    existing.quartier               = dto.quartier;
    existing.preciseAddress         = dto.preciseAddress;
    existing.idDocumentUrl          = dto.idDocumentUrl;
    existing.selfieUrl              = dto.selfieUrl;
    existing.vehiclePhotoUrl        = dto.vehiclePhotoUrl;
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

    return {
      message: 'Demande re-soumise avec succès. Vous serez notifié par email.',
      agentId: existing.id,
    };
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

    return agent;
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

      // Email de validation
      await this.mailerService.sendMail({
        to:      agent.user.email,
        subject: '🎉 Votre compte livreur Asoukaa a été validé !',
        html: `
          <p>Bonjour ${agent.user.prenom},</p>
          <p>Félicitations ! Votre profil livreur a été validé.</p>
          <p>Vous pouvez maintenant :</p>
          <ul>
            <li>Activer votre disponibilité depuis l'application</li>
            <li>Commencer à recevoir des demandes de livraison</li>
          </ul>
          <p>Bienvenue dans l'équipe Asoukaa !</p>
        `,
      });

    } else {
      agent.status     = AgentStatus.REJECTED;
     agent.motifRefus = dto.rejectionReason ?? null;

      // Email de refus
      await this.mailerService.sendMail({
        to:      agent.user.email,
        subject: 'Votre demande livreur Asoukaa',
        html: `
          <p>Bonjour ${agent.user.prenom},</p>
          <p>Votre demande de compte livreur n'a pas pu être validée 
             pour la raison suivante :</p>
          <blockquote style="border-left:3px solid #ccc; padding-left:12px;">
            ${dto.rejectionReason}
          </blockquote>
          <p>Vous pouvez corriger ces éléments et re-soumettre 
             votre demande depuis l'application.</p>
        `,
      });
    }

    agent.reviewedById = adminId;
    agent.reviewedAt   = new Date();
    await this.agentRepo.save(agent);

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

    // Notifier par email
    await this.mailerService.sendMail({
      to:      agent.user.email,
      subject: 'Votre compte livreur Asoukaa a été suspendu',
      html: `
        <p>Bonjour ${agent.user.prenom},</p>
        <p>Votre compte livreur a été suspendu par notre équipe.</p>
        <p>Pour plus d'informations, contactez notre support.</p>
      `,
    });

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
  // ADMIN — DEMANDES EN ATTENTE
  // ─────────────────────────────────────────────────────
  async getPendingAgents() {
    return this.agentRepo
      .createQueryBuilder('agent')
      .leftJoin('agent.user', 'user')
      .select([
        'agent.id',
        'agent.vehicleType',
        'agent.ville',
        'agent.quartier',
        'agent.createdAt',
        'user.id',
        'user.prenom',
        'user.name',
        'user.email',
        'user.phone',
      ])
      .where('agent.status = :status', { status: AgentStatus.PENDING })
      .orderBy('agent.createdAt', 'ASC')
      .getMany();
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