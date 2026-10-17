import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  HttpException,
  HttpStatus,
  Injectable,
  Logger,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import * as bcrypt from 'bcrypt';
import { createHash, randomBytes, randomInt } from 'crypto';
import { DataSource, EntityManager, MoreThan, Repository } from 'typeorm';
import {
  ActorType,
  LogAction,
} from '../../../common/entities/activity-log.entity';
import { ActivityLogService } from '../../../common/services/activity-log.service';
import { OtpCode } from '../../auth/entities/otp-code.entity';
import { MailService } from '../../mail/mail.service';
import { User } from '../entities/user.entity';
import { ConfirmEmailChangeDto } from './dto/confirm-email-change.dto';
import { RequestEmailChangeDto } from './dto/request-email-change.dto';
import { EmailChange, EmailChangeStatus } from './email-change.entity';

// Mêmes règles que le flux OTP de AuthService (voir MAX_OTP_ATTEMPTS) : un
// code à 6 chiffres n'est sûr que s'il est de courte durée ET limité en essais.
const MAX_ATTEMPTS = 5;
const CODE_TTL_MS = 10 * 60 * 1000;
const RESEND_DELAY_MS = 60 * 1000;
// Plafond d'envois (1er inclus) par demande : le renvoi ne doit pas servir à
// spammer la nouvelle adresse, ni à multiplier les essais de devinette.
const MAX_SENDS_PER_REQUEST = 5;
// Une demande plus vieille que ça n'est plus relançable : on repart de zéro.
const REQUEST_MAX_AGE_MS = 60 * 60 * 1000;
const MAX_REQUESTS_PER_HOUR = 5;
const REVERT_TTL_MS = 7 * 24 * 60 * 60 * 1000;
// Échecs de mot de passe sur la route de demande (en mémoire, par processus) :
// sans cela, quiconque détient un jeton d'accès volé pourrait deviner le mot
// de passe via cette route. Les 400 ne déconnectent pas l'appli, un 429 non plus.
const MAX_PASSWORD_FAILURES = 5;
const PASSWORD_FAILURE_WINDOW_MS = 15 * 60 * 1000;

export const REVERT_TOKEN_REGEX = /^[a-f0-9]{64}$/;

const sha256 = (value: string): string =>
  createHash('sha256').update(value).digest('hex');

/** « jean.dupont@gmail.com » → « j***@gmail.com » : jamais l'adresse complète. */
export const maskEmail = (email: string): string => {
  const [local, ...rest] = String(email ?? '').split('@');
  const domain = rest.join('@');
  if (!domain) return '***';
  return `${local.charAt(0)}***@${domain}`;
};

const isUniqueViolation = (error: any): boolean =>
  error?.code === '23505' || error?.driverError?.code === '23505';

const formatDateFr = (date: Date): string => {
  try {
    return `${new Intl.DateTimeFormat('fr-FR', {
      dateStyle: 'long',
      timeStyle: 'short',
      timeZone: 'Africa/Porto-Novo',
    }).format(date)} (heure du Bénin)`;
  } catch {
    return date.toISOString();
  }
};

// Lancée DANS la transaction d'annulation quand le lien n'est (plus) applicable :
// l'exception provoque le ROLLBACK, donc aucune des écritures déjà faites
// (extinction des autres liens...) n'est conservée.
class RevertNotApplicableError extends Error {}

export type RevertOutcome =
  | { outcome: 'invalid' }
  | { outcome: 'restored' | 'not_restored' };

@Injectable()
export class EmailChangeService {
  private readonly logger = new Logger(EmailChangeService.name);
  private readonly appUrl: string;
  private readonly passwordFailures = new Map<
    string,
    { count: number; resetAt: number }
  >();

  constructor(
    @InjectRepository(EmailChange)
    private readonly changeRepo: Repository<EmailChange>,
    @InjectRepository(User)
    private readonly userRepo: Repository<User>,
    private readonly dataSource: DataSource,
    private readonly mailService: MailService,
    private readonly logService: ActivityLogService,
    private readonly configService: ConfigService,
  ) {
    const port =
      configService.get<number>('APP_PORT') ??
      configService.get<number>('PORT') ??
      3000;
    const configuredUrl = configService.get<string>('APP_URL')?.trim();
    const isHttps = !!configuredUrl && /^https:\/\//i.test(configuredUrl);

    // Le lien « Ce n'est pas moi » part par e-mail avec ce préfixe : un
    // localhost ou un http:// en production enverrait un lien mort (ou
    // interceptable) au propriétaire du compte, au pire moment. On refuse
    // donc de démarrer plutôt que d'envoyer des liens inutilisables.
    if (configService.get<string>('NODE_ENV') === 'production') {
      if (!isHttps) {
        throw new Error(
          'APP_URL est absent ou ne commence pas par https:// : ' +
            'indispensable en production pour le lien d\'annulation du changement d\'e-mail.',
        );
      }
    } else if (!isHttps) {
      this.logger.warn(
        'APP_URL absent ou non https : les liens « Ce n\'est pas moi » des e-mails ' +
          'de changement d\'adresse pointeront vers cette valeur (acceptable en développement uniquement).',
      );
    }
    this.appUrl = (configuredUrl || `http://localhost:${port}`).replace(/\/+$/, '');
  }

  // ═════════════════════════════════════════════════════════════════════
  // 1. DEMANDE : mot de passe vérifié, code envoyé à la NOUVELLE adresse
  // ═════════════════════════════════════════════════════════════════════
  async requestChange(userId: string, dto: RequestEmailChangeDto, ip: string) {
    const user = await this.loadUser(userId);

    this.assertPasswordAttemptsAllowed(userId);
    const passwordOk = await bcrypt.compare(
      dto.currentPassword,
      user.passwordHash,
    );
    if (!passwordOk) {
      this.registerPasswordFailure(userId);
      // ⚠️ 400 et JAMAIS 401/403 : l'appli mobile déconnecte l'utilisateur
      // sur un 401, or ici la session est parfaitement valide.
      throw new BadRequestException('Mot de passe incorrect');
    }
    this.passwordFailures.delete(userId);

    const newEmail = dto.newEmail.trim().toLowerCase();
    if (newEmail.length > 255) {
      throw new BadRequestException('Adresse email trop longue');
    }
    if (newEmail === user.email.trim().toLowerCase()) {
      throw new BadRequestException(
        'La nouvelle adresse est identique à votre adresse actuelle',
      );
    }

    // Plafond « 5 demandes par heure et par utilisateur » compté en base :
    // le @Throttle du contrôleur est par IP (partagée par beaucoup de
    // mobiles derrière un même opérateur), il ne suffit donc pas.
    const recent = await this.changeRepo.count({
      where: {
        userId,
        createdAt: MoreThan(new Date(Date.now() - 60 * 60 * 1000)),
      },
    });
    if (recent >= MAX_REQUESTS_PER_HOUR) {
      throw new HttpException(
        'Trop de demandes de changement d\'adresse. Réessayez dans une heure.',
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }

    // Fenêtre de protection : tant que le lien « Ce n'est pas moi » du
    // dernier changement est actif, on refuse un nouveau changement. Sans
    // cela, un attaquant qui connaît le mot de passe enchaînerait A→B puis
    // B→C et rendrait caduc le lien envoyé à la victime en A (un seul lien
    // est valable à la fois, voir confirmChange).
    const liveChange = await this.changeRepo.findOne({
      where: {
        userId,
        status: EmailChangeStatus.CONFIRMED,
        revertExpiresAt: MoreThan(new Date()),
      },
    });
    if (liveChange && liveChange.revertTokenHash) {
      throw new BadRequestException(
        'Votre adresse a été modifiée récemment. Par sécurité, un nouveau changement ne sera possible qu\'une fois le délai de protection de 7 jours écoulé.',
      );
    }

    // Seul 409 explicite autorisé par le contrat : la route est authentifiée
    // ET le mot de passe vient d'être vérifié.
    if (await this.isEmailTaken(newEmail, userId)) {
      throw new ConflictException('Cette adresse est déjà utilisée');
    }

    const code = randomInt(100000, 1000000).toString();
    const codeHash = await bcrypt.hash(code, 10);
    const now = new Date();

    // Annulation des anciennes demandes + création de la nouvelle dans UNE
    // transaction. L'index unique partiel « une seule pending par user »
    // tranche si deux requêtes arrivent exactement en même temps.
    let saved: EmailChange;
    try {
      saved = await this.dataSource.transaction(async (m) => {
        await m.update(
          EmailChange,
          { userId, status: EmailChangeStatus.PENDING },
          { status: EmailChangeStatus.CANCELLED },
        );
        return m.save(
          m.create(EmailChange, {
            userId,
            oldEmail: user.email,
            newEmail,
            codeHash,
            attempts: 0,
            sendCount: 1,
            codeExpiresAt: new Date(now.getTime() + CODE_TTL_MS),
            lastSentAt: now,
            status: EmailChangeStatus.PENDING,
            revertTokenHash: null,
            revertExpiresAt: null,
            confirmedAt: null,
            revertedAt: null,
            // Fixé côté Node (pas par le DEFAULT now() de la base) pour que le
            // comptage « dernière heure » ci-dessus compare des dates écrites
            // avec la même horloge/fuseau.
            createdAt: now,
          }),
        );
      });
    } catch (error) {
      if (isUniqueViolation(error)) {
        throw new BadRequestException(
          'Une demande est déjà en cours de traitement, réessayez dans un instant.',
        );
      }
      throw error;
    }

    // Le seul envoi qui DOIT remonter une erreur : sans le code, l'utilisateur
    // attendrait un message qui ne viendra jamais.
    try {
      await this.mailService.sendEmailChangeCode(newEmail, user.prenom, code);
    } catch (error) {
      await this.changeRepo.update(saved.id, {
        status: EmailChangeStatus.CANCELLED,
      });
      this.logger.error(
        `Code de changement d'e-mail non envoyé (demande ${saved.id}) : ${error?.message}`,
      );
      throw new ServiceUnavailableException(
        'Impossible d\'envoyer le code à cette adresse pour le moment. Vérifiez l\'adresse puis réessayez.',
      );
    }

    await this.logService.log({
      actorId: userId,
      actorType: ActorType.CLIENT,
      action: LogAction.EMAIL_CHANGE_REQUESTED,
      entityType: 'user',
      entityId: userId,
      newValue: { newEmail: maskEmail(newEmail) },
      ipAddress: this.cleanIp(ip),
    });

    return {
      message: `Un code de confirmation a été envoyé à ${maskEmail(newEmail)}.`,
      expiresInSeconds: CODE_TTL_MS / 1000,
    };
  }

  // ═════════════════════════════════════════════════════════════════════
  // 2. RENVOI DU CODE
  // ═════════════════════════════════════════════════════════════════════
  async resendCode(userId: string) {
    const user = await this.loadUser(userId);

    const pending = await this.changeRepo.findOne({
      where: { userId, status: EmailChangeStatus.PENDING },
    });
    if (!pending) {
      throw new BadRequestException(
        'Aucune demande de changement d\'adresse en cours. Recommencez la demande.',
      );
    }

    const nowMs = Date.now();
    if (nowMs - pending.createdAt.getTime() > REQUEST_MAX_AGE_MS) {
      await this.changeRepo.update(
        { id: pending.id, status: EmailChangeStatus.PENDING },
        { status: EmailChangeStatus.EXPIRED },
      );
      throw new BadRequestException(
        'Cette demande a expiré. Recommencez la demande de changement d\'adresse.',
      );
    }
    if (pending.sendCount >= MAX_SENDS_PER_REQUEST) {
      throw new HttpException(
        'Nombre maximal d\'envois atteint pour cette demande. Recommencez la demande plus tard.',
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
    const waitMs = pending.lastSentAt.getTime() + RESEND_DELAY_MS - nowMs;
    if (waitMs > 0) {
      throw new HttpException(
        `Veuillez patienter ${Math.ceil(waitMs / 1000)} seconde(s) avant de redemander un code.`,
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }

    const code = randomInt(100000, 1000000).toString();
    const codeHash = await bcrypt.hash(code, 10);
    const now = new Date();

    // « Réservation » atomique du renvoi : si deux appuis simultanés passent
    // la vérification ci-dessus, un seul UPDATE trouve encore le délai écoulé.
    const claim = await this.changeRepo
      .createQueryBuilder()
      .update(EmailChange)
      .set({
        codeHash,
        attempts: 0, // nouveau code = nouveau quota d'essais
        lastSentAt: now,
        codeExpiresAt: new Date(now.getTime() + CODE_TTL_MS),
        sendCount: () => '"sendCount" + 1',
      })
      .where(
        'id = :id AND status = :status AND "lastSentAt" <= :limit AND "sendCount" < :max',
        {
          id: pending.id,
          status: EmailChangeStatus.PENDING,
          limit: new Date(nowMs - RESEND_DELAY_MS),
          max: MAX_SENDS_PER_REQUEST,
        },
      )
      .execute();
    if (!claim.affected) {
      throw new HttpException(
        'Un code vient d\'être envoyé. Patientez un instant avant d\'en redemander un.',
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }

    try {
      await this.mailService.sendEmailChangeCode(
        pending.newEmail,
        user.prenom,
        code,
      );
    } catch (error) {
      // On rend le droit de réessayer tout de suite (le code n'est pas parti).
      await this.changeRepo.update(pending.id, {
        lastSentAt: pending.lastSentAt,
      });
      this.logger.error(
        `Code de changement d'e-mail non renvoyé (demande ${pending.id}) : ${error?.message}`,
      );
      throw new ServiceUnavailableException(
        'Impossible d\'envoyer le code pour le moment. Réessayez dans un instant.',
      );
    }

    return {
      message: `Un nouveau code a été envoyé à ${maskEmail(pending.newEmail)}.`,
      expiresInSeconds: CODE_TTL_MS / 1000,
    };
  }

  // ═════════════════════════════════════════════════════════════════════
  // 3. CONFIRMATION : le code est bon → l'adresse est remplacée
  // ═════════════════════════════════════════════════════════════════════
  async confirmChange(userId: string, dto: ConfirmEmailChangeDto, ip: string) {
    const user = await this.loadUser(userId);

    const pending = await this.changeRepo.findOne({
      where: { userId, status: EmailChangeStatus.PENDING },
    });
    if (!pending) {
      throw new BadRequestException(
        'Aucune demande de changement d\'adresse en cours. Recommencez la demande.',
      );
    }
    if (pending.codeExpiresAt.getTime() <= Date.now()) {
      throw new BadRequestException(
        'Le code a expiré. Demandez un nouveau code.',
      );
    }

    // ⚠️ L'essai est CONSOMMÉ AVANT la comparaison, par un UPDATE atomique
    // conditionné à « attempts < MAX » : 50 requêtes lancées en parallèle
    // avec 50 codes différents ne peuvent pas dépasser 5 essais au total
    // (avec « lire, comparer, puis incrémenter », elles passeraient toutes).
    const attemptUpdate = await this.changeRepo
      .createQueryBuilder()
      .update(EmailChange)
      .set({ attempts: () => '"attempts" + 1' })
      .where('id = :id AND status = :status AND attempts < :max', {
        id: pending.id,
        status: EmailChangeStatus.PENDING,
        max: MAX_ATTEMPTS,
      })
      .returning(['attempts'])
      .execute();
    const attemptsNow: number | undefined = attemptUpdate.raw?.[0]?.attempts;
    if (!attemptUpdate.affected || attemptsNow === undefined) {
      throw new BadRequestException(
        'Trop de tentatives échouées. Demandez un nouveau code.',
      );
    }

    const codeOk = await bcrypt.compare(dto.code, pending.codeHash);
    if (!codeOk) {
      const left = MAX_ATTEMPTS - attemptsNow;
      throw new BadRequestException(
        left <= 0
          ? 'Trop de tentatives échouées. Demandez un nouveau code.'
          : `Code invalide. ${left} tentative(s) restante(s).`,
      );
    }

    // Jeton de révocation : 256 bits aléatoires. Seul son SHA-256 est stocké.
    const rawToken = randomBytes(32).toString('hex');
    const now = new Date();

    let oldEmail: string;
    let newEmail: string;
    try {
      ({ oldEmail, newEmail } = await this.dataSource.transaction(
        async (m) => {
          // Verrou sur la demande : deux « confirm » simultanés avec le bon
          // code se sérialisent, le second voit « confirmed » et échoue.
          const row = await m.findOne(EmailChange, {
            where: { id: pending.id },
            lock: { mode: 'pessimistic_write' },
          });
          if (!row || row.status !== EmailChangeStatus.PENDING) {
            throw new BadRequestException(
              'Cette demande n\'est plus valide. Recommencez la demande.',
            );
          }
          if (row.codeExpiresAt.getTime() <= now.getTime()) {
            throw new BadRequestException(
              'Le code a expiré. Demandez un nouveau code.',
            );
          }

          // Ordre des verrous identique à revertInTransaction (ligne de
          // demande, autres lignes du même utilisateur, PUIS la ligne users) :
          // sinon un « confirm » et un « revert » simultanés pourraient
          // s'attendre mutuellement (deadlock).
          // Un seul lien « Ce n'est pas moi » actif à la fois : les autres
          // lignes confirmées perdent leur jeton.
          await m
            .createQueryBuilder()
            .update(EmailChange)
            .set({ status: EmailChangeStatus.CANCELLED, revertTokenHash: null })
            .where(
              '"userId" = :uid AND id <> :id AND status = :confirmed AND "revertTokenHash" IS NOT NULL',
              {
                uid: userId,
                id: row.id,
                confirmed: EmailChangeStatus.CONFIRMED,
              },
            )
            .execute();

          const current = await m.findOne(User, {
            where: { id: userId },
            lock: { mode: 'pessimistic_write' },
          });
          if (
            !current ||
            current.email.trim().toLowerCase() !==
              row.oldEmail.trim().toLowerCase()
          ) {
            throw new BadRequestException(
              'Cette demande n\'est plus valide. Recommencez la demande.',
            );
          }

          // Revérification de l'unicité APRÈS le code : la course est possible
          // entre la demande et la confirmation (quelqu'un a pu s'inscrire
          // avec cette adresse entre-temps).
          // Seul un compte VÉRIFIÉ « possède » une adresse. Un compte jamais
          // vérifié (inscription abandonnée ou squat) est écarté, sinon il
          // bloquerait l'index unique de users.email.
          const taken = await m
            .createQueryBuilder(User, 'u')
            .select('u.id')
            .where('LOWER(u.email) = :e', { e: row.newEmail.toLowerCase() })
            .andWhere('u.id <> :id', { id: userId })
            .andWhere('u.isVerified = true')
            .getOne();
          if (taken) {
            throw new ConflictException('Cette adresse est déjà utilisée');
          }
          await this.releaseUnverifiedHolders(m, row.newEmail, userId);

          // L'index unique de users.email reste le juge ultime (23505 → 409).
          await m.update(User, { id: userId }, { email: row.newEmail });
          await m.update(
            EmailChange,
            { id: row.id },
            {
              status: EmailChangeStatus.CONFIRMED,
              confirmedAt: now,
              revertTokenHash: sha256(rawToken),
              revertExpiresAt: new Date(now.getTime() + REVERT_TTL_MS),
            },
          );
          return { oldEmail: row.oldEmail, newEmail: row.newEmail };
        },
      ));
    } catch (error) {
      if (isUniqueViolation(error)) {
        throw new ConflictException('Cette adresse est déjà utilisée');
      }
      throw error;
    }

    await this.logService.log({
      actorId: userId,
      actorType: ActorType.CLIENT,
      action: LogAction.EMAIL_CHANGE_CONFIRMED,
      entityType: 'user',
      entityId: userId,
      oldValue: { email: maskEmail(oldEmail) },
      newValue: { email: maskEmail(newEmail) },
      ipAddress: this.cleanIp(ip),
    });

    // Envois « best-effort » : le changement est fait, un mail raté ne doit
    // pas le faire échouer. Le jeton brut ne part que dans ce mail et n'est
    // jamais écrit dans les logs.
    try {
      await this.mailService.sendEmailChangeAlert(oldEmail, {
        prenom: user.prenom,
        maskedNewEmail: maskEmail(newEmail),
        changedAtLabel: formatDateFr(now),
        revertUrl: `${this.appUrl}/api/v1/auth/email-change/revert/${rawToken}`,
      });
    } catch (error) {
      this.logger.error(`Alerte de changement d'e-mail non envoyée : ${error?.message}`);
    }
    try {
      await this.mailService.sendEmailChangeConfirmed(newEmail, user.prenom);
    } catch (error) {
      this.logger.error(`Confirmation de changement d'e-mail non envoyée : ${error?.message}`);
    }

    return {
      message: 'Votre adresse e-mail a été modifiée.',
      email: newEmail,
    };
  }

  // ═════════════════════════════════════════════════════════════════════
  // 4. PAGE « CE N'EST PAS MOI » (GET : lecture seule, n'exécute RIEN)
  // ═════════════════════════════════════════════════════════════════════
  async inspectRevertToken(
    token: string,
  ): Promise<{ valid: false } | { valid: true; maskedNewEmail: string }> {
    if (!REVERT_TOKEN_REGEX.test(token)) return { valid: false };
    const row = await this.changeRepo.findOne({
      where: { revertTokenHash: sha256(token) },
    });
    if (!row || !this.isRevertable(row)) return { valid: false };
    return { valid: true, maskedNewEmail: maskEmail(row.newEmail) };
  }

  // ═════════════════════════════════════════════════════════════════════
  // 5. ANNULATION (POST) : restaure l'adresse, coupe les sessions, annule le
  //    mot de passe, alerte l'admin. Jeton à usage unique.
  // ═════════════════════════════════════════════════════════════════════
  async executeRevert(token: string, ip: string): Promise<RevertOutcome> {
    if (!REVERT_TOKEN_REGEX.test(token)) return { outcome: 'invalid' };
    const tokenHash = sha256(token);

    // Pré-contrôle bon marché AVANT le bcrypt coûteux ci-dessous : un
    // inconnu qui martèle l'URL avec des jetons au hasard ne coûte presque rien.
    const probe = await this.changeRepo.findOne({
      where: { revertTokenHash: tokenHash },
    });
    if (!probe || !this.isRevertable(probe)) return { outcome: 'invalid' };

    // Mot de passe « poubelle » : bcrypt d'un secret aléatoire que personne ne
    // connaît (il n'est même pas conservé). Seul « Mot de passe oublié »,
    // avec un code envoyé à l'adresse restaurée, permet de se reconnecter.
    const lockedHash = await bcrypt.hash(randomBytes(32).toString('hex'), 12);

    let result: RevertTxResult;
    try {
      result = await this.runRevert(tokenHash, lockedHash, true);
    } catch (error) {
      if (!isUniqueViolation(error)) throw error;
      // L'adresse d'origine vient d'être prise par quelqu'un pendant la
      // transaction : on rejoue SANS restauration (sécurisation seule).
      result = await this.runRevert(tokenHash, lockedHash, false);
    }

    if (result.outcome === 'invalid') return { outcome: 'invalid' };

    await this.logService.log({
      actorId: result.userId,
      actorType: ActorType.CLIENT,
      action: LogAction.EMAIL_CHANGE_REVERTED,
      entityType: 'user',
      entityId: result.userId,
      oldValue: { email: maskEmail(result.oldEmail) },
      newValue: {
        fraudulentEmail: maskEmail(result.newEmail),
        addressRestored: result.outcome === 'restored',
        accountBlocked: result.outcome === 'not_restored',
      },
      ipAddress: this.cleanIp(ip),
    });

    // Prévenir l'ÉQUIPE (best-effort, jamais bloquant) : les admins n'ont pas
    // de notification dédiée, l'e-mail à l'adresse de support (la même que
    // pour les tickets) est le seul signal actif. Adresses masquées.
    try {
      await this.mailService.sendSecurityAlertToTeam(this.supportTeamEmail(), {
        userId:         result.userId,
        prenom:         result.prenom,
        outcome:        result.outcome,
        maskedOldEmail: maskEmail(result.oldEmail),
        maskedNewEmail: maskEmail(result.newEmail),
        dateLabel:      formatDateFr(new Date()),
      });
    } catch (error) {
      this.logger.error(`Mail d'alerte à l'équipe non envoyé : ${error?.message}`);
    }

    // Mails uniquement si l'adresse d'origine est bien rétablie : sinon elle
    // appartient désormais à un autre compte et l'adresse « nouvelle » est
    // encore celle du compte — on ne dit rien à personne par e-mail.
    if (result.outcome === 'restored') {
      try {
        await this.mailService.sendEmailChangeSecured(result.oldEmail, result.prenom);
      } catch (error) {
        this.logger.error(`Mail « compte sécurisé » non envoyé : ${error?.message}`);
      }
      try {
        await this.mailService.sendEmailChangeCancelled(result.newEmail);
      } catch (error) {
        this.logger.error(`Mail d'annulation non envoyé : ${error?.message}`);
      }
    }

    return { outcome: result.outcome };
  }

  private async runRevert(
    tokenHash: string,
    lockedPasswordHash: string,
    allowRestore: boolean,
  ): Promise<RevertTxResult> {
    try {
      return await this.dataSource.transaction((m) =>
        this.revertInTransaction(m, tokenHash, lockedPasswordHash, allowRestore),
      );
    } catch (error) {
      if (error instanceof RevertNotApplicableError) return { outcome: 'invalid' };
      throw error;
    }
  }

  private async revertInTransaction(
    m: EntityManager,
    tokenHash: string,
    lockedPasswordHash: string,
    allowRestore: boolean,
  ): Promise<RevertTxResult> {
    // Verrou : deux POST simultanés sur le même lien se sérialisent ; le
    // second trouve le jeton déjà consommé (revertTokenHash = NULL).
    const row = await m.findOne(EmailChange, {
      where: { revertTokenHash: tokenHash },
      lock: { mode: 'pessimistic_write' },
    });
    if (!row || !this.isRevertable(row)) return { outcome: 'invalid' };

    // Les demandes en attente et les autres liens actifs du compte sont
    // éteints AVANT de verrouiller la ligne users : même ordre de verrous que
    // confirmChange (demande → autres lignes → user), donc pas de deadlock.
    // Sinon un attaquant pourrait rejouer un ancien lien ou finir une demande
    // déjà commencée.
    await m
      .createQueryBuilder()
      .update(EmailChange)
      .set({ status: EmailChangeStatus.CANCELLED, revertTokenHash: null })
      .where(
        '"userId" = :uid AND id <> :id AND (status = :pending OR (status = :confirmed AND "revertTokenHash" IS NOT NULL))',
        {
          uid: row.userId,
          id: row.id,
          pending: EmailChangeStatus.PENDING,
          confirmed: EmailChangeStatus.CONFIRMED,
        },
      )
      .execute();

    const user = await m.findOne(User, {
      where: { id: row.userId },
      lock: { mode: 'pessimistic_write' },
    });
    if (!user) throw new RevertNotApplicableError();

    // Le lien ne vaut que pour le changement qu'il annule : si l'adresse
    // courante n'est plus celle posée par ce changement (modification faite
    // depuis par un autre chemin, ex. l'administration), il est périmé. On
    // ne touche à rien.
    if (user.email.trim().toLowerCase() !== row.newEmail.trim().toLowerCase()) {
      throw new RevertNotApplicableError();
    }

    const now = new Date();
    let restored = false;
    if (allowRestore) {
      // Seul un compte VÉRIFIÉ garde l'adresse d'origine. Un compte jamais
      // vérifié qui l'occupe (squat via l'inscription, qui crée la ligne
      // AVANT la saisie du code) est écarté : sans cela l'attaquant
      // empêcherait la victime de récupérer son adresse.
      const taken = await m
        .createQueryBuilder(User, 'u')
        .select('u.id')
        .where('LOWER(u.email) = :e', { e: row.oldEmail.toLowerCase() })
        .andWhere('u.id <> :id', { id: user.id })
        .andWhere('u.isVerified = true')
        .getOne();
      if (!taken) {
        await this.releaseUnverifiedHolders(m, row.oldEmail, user.id);
        restored = true;
      }
    }

    const reason = (
      restored
        ? `E-mail annulé par le propriétaire (changement vers ${maskEmail(row.newEmail)}) : compte potentiellement compromis, sessions coupées, mot de passe annulé.`
        : `E-mail NON restauré (adresse d'origine ${maskEmail(row.oldEmail)} déjà utilisée par un autre compte) après un « Ce n'est pas moi » : compte bloqué par précaution, vérification manuelle requise.`
    ).slice(0, 255);

    await m.update(
      User,
      { id: user.id },
      {
        ...(restored ? { email: row.oldEmail } : { isActive: false }),
        // Déconnecte tous les appareils (voir JwtStrategy.validate)
        tokensValidAfter: now,
        passwordHash: lockedPasswordHash,
        securityAlertAt: now,
        securityAlertReason: reason,
      },
    );

    // Un code « mot de passe oublié » / vérification déjà envoyé à l'adresse
    // frauduleuse ne doit plus servir à rien.
    await m.update(
      OtpCode,
      { userId: user.id, isUsed: false },
      { isUsed: true },
    );

    // Jeton à usage unique : détruit ici, avec le statut « reverted ».
    await m.update(
      EmailChange,
      { id: row.id },
      {
        status: EmailChangeStatus.REVERTED,
        revertedAt: now,
        revertTokenHash: null,
      },
    );

    return {
      outcome: restored ? 'restored' : 'not_restored',
      userId: user.id,
      prenom: user.prenom,
      oldEmail: row.oldEmail,
      newEmail: row.newEmail,
    };
  }

  // ─── Utilitaires ───────────────────────────────────────────────────────

  // Même règle que SupportTicketsNotifier : SUPPORT_TEAM_EMAIL s'il est
  // valide, sinon contact@asoukaa.com.
  private supportTeamEmail(): string {
    const configured = (this.configService.get<string>('SUPPORT_TEAM_EMAIL') ?? '').trim();
    return /^[^\s@,;<>]+@[^\s@,;<>]+\.[^\s@,;<>]+$/.test(configured)
      ? configured
      : 'contact@asoukaa.com';
  }

  private isRevertable(row: EmailChange): boolean {
    return (
      row.status === EmailChangeStatus.CONFIRMED &&
      !row.revertedAt &&
      !!row.revertExpiresAt &&
      row.revertExpiresAt.getTime() > Date.now()
    );
  }

  private async loadUser(userId: string): Promise<User> {
    const user = await this.userRepo.findOne({ where: { id: userId } });
    if (!user) {
      // Jeton admin (autre table) : cette fonction ne concerne que les comptes
      // clients/vendeurs/livreurs.
      throw new ForbiddenException(
        'Cette action est réservée aux comptes utilisateurs',
      );
    }
    return user;
  }

  private async isEmailTaken(email: string, exceptUserId: string): Promise<boolean> {
    const found = await this.userRepo
      .createQueryBuilder('u')
      .select('u.id')
      .where('LOWER(u.email) = :e', { e: email.toLowerCase() })
      .andWhere('u.id <> :id', { id: exceptUserId })
      // Un compte jamais vérifié n'est pas propriétaire de l'adresse (voir
      // releaseUnverifiedHolders) : il ne doit pas déclencher de 409.
      .andWhere('u.isVerified = true')
      .getOne();
    return !!found;
  }

  /**
   * Libère une adresse occupée par des comptes JAMAIS VÉRIFIÉS.
   *
   * AuthService.register() insère la ligne users AVANT la saisie du code OTP :
   * n'importe qui peut donc « squatter » une adresse sans en contrôler la
   * boîte. On RENOMME ces comptes (adresse technique unique + isActive=false)
   * plutôt que de les supprimer : aucune suppression en cascade de données
   * liées, l'opération est réversible par l'administration, et un compte non
   * vérifié ne pouvait de toute façon pas se connecter. Le UPDATE re-teste
   * isVerified = false : un compte vérifié entre-temps n'est jamais touché.
   */
  private async releaseUnverifiedHolders(
    m: EntityManager,
    email: string,
    exceptUserId: string,
  ): Promise<void> {
    const result = await m
      .createQueryBuilder()
      .update(User)
      .set({
        email: () => `'libere-' || "id" || '@invalid.local'`,
        isActive: false,
      })
      .where('LOWER("email") = :e AND "id" <> :id AND "isVerified" = false', {
        e: email.toLowerCase(),
        id: exceptUserId,
      })
      .execute();
    if (result.affected) {
      this.logger.warn(
        `${result.affected} compte(s) non vérifié(s) renommé(s) pour libérer une adresse (changement d'e-mail).`,
      );
    }
  }

  private assertPasswordAttemptsAllowed(userId: string): void {
    const entry = this.passwordFailures.get(userId);
    if (!entry) return;
    if (entry.resetAt <= Date.now()) {
      this.passwordFailures.delete(userId);
      return;
    }
    if (entry.count >= MAX_PASSWORD_FAILURES) {
      throw new HttpException(
        'Trop de mots de passe incorrects. Réessayez dans quelques minutes.',
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
  }

  private registerPasswordFailure(userId: string): void {
    const now = Date.now();
    // Nettoyage opportuniste pour que la table ne grossisse pas indéfiniment
    if (this.passwordFailures.size > 5000) {
      for (const [key, value] of this.passwordFailures) {
        if (value.resetAt <= now) this.passwordFailures.delete(key);
      }
    }
    const entry = this.passwordFailures.get(userId);
    if (!entry || entry.resetAt <= now) {
      this.passwordFailures.set(userId, {
        count: 1,
        resetAt: now + PASSWORD_FAILURE_WINDOW_MS,
      });
    } else {
      entry.count += 1;
    }
  }

  // La colonne activity_logs.ipAddress fait 45 caractères
  private cleanIp(ip: string): string {
    return String(ip ?? 'unknown').slice(0, 45);
  }
}

type RevertTxResult =
  | { outcome: 'invalid' }
  | {
      outcome: 'restored' | 'not_restored';
      userId: string;
      prenom: string;
      oldEmail: string;
      newEmail: string;
    };
