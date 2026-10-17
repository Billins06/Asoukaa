import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import { Cron, CronExpression } from '@nestjs/schedule';
import { DataSource, In, Repository } from 'typeorm';

import { Order, OrderStatus } from './entities/order.entity';
import {
  Payment,
  PaymentMethod,
  PaymentStatus,
} from '../payments/entities/payment.entity';
import { VendorProfile } from '../users/entities/vendor-profile.entity';
import { AdminAccount } from '../auth/entities/admin-account.entity';
import { NotificationsService } from '../notifications/notifications.service';
import { NotificationType } from '../notifications/entities/notification.entity';
import { ActivityLogService } from '../../common/services/activity-log.service';
import { ActorType, LogAction } from '../../common/entities/activity-log.entity';

// ─────────────────────────────────────────────────────────────────────────
// DÉLAI DE CONFIRMATION VENDEUR
//
// Le vendeur garde son bouton « Confirmer » (la commande passe à « En
// cours ») : ce clic prouve qu'il a vu la commande. Aucune acceptation
// automatique. En revanche, si une commande payée reste trop longtemps sans
// confirmation :
//   - après ORDER_REMINDER_HOURS    (défaut 24 h) → rappel au vendeur ;
//   - après ORDER_ADMIN_ALERT_HOURS (défaut 48 h) → alerte aux admins.
//
// « En attente de confirmation du vendeur » =
//     orders.status = 'en attente'
//     ET le paiement existe ET (payments.status = 'success'
//                               OU (payments.method = 'cash_on_delivery'
//                                   ET payments.status = 'en attente'))
// Ce sont exactement les deux cas où OrdersService.updateStatus laisse le
// vendeur passer la commande à « En cours ».
//
// Date de référence = COALESCE(payments.paidAt, payments.createdAt,
// orders.createdAt) : date du paiement confirmé ; pour le paiement à la
// livraison (jamais « payé » avant la livraison), date de création du
// paiement ; à défaut, date de création de la commande.
//
// Ce service n'agit JAMAIS sur le statut d'une commande : il ne fait que
// notifier. Les commandes annulées/livrées/déjà confirmées ne sont jamais
// sélectionnées (filtre status = 'en attente' dans chaque requête).
// ─────────────────────────────────────────────────────────────────────────

export const DEFAULT_REMINDER_HOURS    = 24;
export const DEFAULT_ADMIN_ALERT_HOURS = 48;
// Plafond de sécurité : au-delà, `interval` Postgres déborde.
const MAX_HOURS  = 24 * 365;
const BATCH_SIZE = 200;
// Nombre maximum de lots traités par passage et par type (rappel / alerte).
const MAX_BATCHES_PER_RUN = 5;

export interface ConfirmationDelays {
  reminderHours:   number;
  adminAlertHours: number;
}

export interface LateConfirmationFilters {
  page?:     number;
  limit?:    number;
  vendorId?: string;
  // 'reminder' (défaut) : toutes les commandes dépassant le délai de rappel ;
  // 'alert' : seulement celles qui dépassent le délai d'alerte admin.
  level?:    string;
}

// Valeur littérale SQL pour une constante de NOTRE code (enums) — jamais
// pour une entrée utilisateur.
const lit = (v: string): string => `'${String(v).replace(/'/g, "''")}'`;

// Commande en attente de confirmation du vendeur (alias SQL : o = orders,
// p = payments).
const AWAITING_SQL = `
  o."status" = ${lit(OrderStatus.PENDING)}
  AND (
    p."status" = ${lit(PaymentStatus.SUCCESS)}
    OR (p."method" = ${lit(PaymentMethod.CASH_ON_DELIVERY)}
        AND p."status" = ${lit(PaymentStatus.PENDING)})
  )
`;
const REF_SQL = `COALESCE(p."paidAt", p."createdAt", o."createdAt")`;

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// TypeORM renvoie [rows, rowCount] pour un UPDATE ... RETURNING et
// directement les lignes pour un SELECT.
function rowsOf(res: any): any[] {
  if (!Array.isArray(res)) return [];
  if (res.length === 2 && Array.isArray(res[0]) && typeof res[1] === 'number') {
    return res[0];
  }
  return res;
}

function fmtHours(h: number): string {
  return Number.isInteger(h) ? String(h) : h.toFixed(1).replace('.', ',');
}

@Injectable()
export class OrderConfirmationService {
  private readonly logger = new Logger(OrderConfirmationService.name);
  private running = false;

  constructor(
    private readonly config:        ConfigService,
    private readonly dataSource:    DataSource,
    private readonly notifications: NotificationsService,
    private readonly logService:    ActivityLogService,

    @InjectRepository(VendorProfile)
    private readonly vendorRepo: Repository<VendorProfile>,

    @InjectRepository(AdminAccount)
    private readonly adminRepo: Repository<AdminAccount>,
  ) {}

  // ─────────────────────────────────────────────────────
  // CONFIGURATION
  // ─────────────────────────────────────────────────────
  private parseHours(raw: unknown, fallback: number): number {
    if (raw === undefined || raw === null) return fallback;
    const n =
      typeof raw === 'number'
        ? raw
        : Number(String(raw).trim().replace(',', '.'));
    if (!Number.isFinite(n) || n <= 0) return fallback;
    return Math.min(n, MAX_HOURS);
  }

  // Relue à chaque appel (peu coûteux) : toujours cohérent avec la config.
  getDelays(): ConfirmationDelays {
    return {
      reminderHours: this.parseHours(
        this.config.get('ORDER_REMINDER_HOURS'),
        DEFAULT_REMINDER_HOURS,
      ),
      adminAlertHours: this.parseHours(
        this.config.get('ORDER_ADMIN_ALERT_HOURS'),
        DEFAULT_ADMIN_ALERT_HOURS,
      ),
    };
  }

  // Date limite théorique de confirmation (= date de référence + délai de
  // rappel) pour une commande en attente de confirmation ; null sinon.
  // Utilisée pour le champ `confirmBy` de la liste vendeur.
  computeConfirmBy(
    order:   Pick<Order, 'status' | 'createdAt'>,
    payment: Payment | null | undefined,
  ): Date | null {
    if (order.status !== OrderStatus.PENDING || !payment) return null;

    const eligible =
      payment.status === PaymentStatus.SUCCESS ||
      (payment.method === PaymentMethod.CASH_ON_DELIVERY &&
        payment.status === PaymentStatus.PENDING);
    if (!eligible) return null;

    const ref = payment.paidAt ?? payment.createdAt ?? order.createdAt;
    if (!ref) return null;

    const t = new Date(ref).getTime();
    if (Number.isNaN(t)) return null;

    return new Date(t + this.getDelays().reminderHours * 3_600_000);
  }

  // ─────────────────────────────────────────────────────
  // PLANIFICATEUR — toutes les 10 minutes
  // ─────────────────────────────────────────────────────
  // @nestjs/schedule est déjà utilisé par le projet (ScheduleModule.forRoot()).
  // Le try/catch garantit qu'une erreur ne remonte jamais jusqu'au serveur ;
  // `running` évite deux passages simultanés dans la même instance ; entre
  // instances, c'est l'UPDATE conditionnel (… WHERE colonne IS NULL, avec
  // FOR UPDATE SKIP LOCKED) qui garantit qu'un rappel ne part qu'une fois.
  @Cron(CronExpression.EVERY_10_MINUTES, { name: 'order-confirmation-reminders' })
  async handleCron(): Promise<void> {
    if (this.running) return;
    this.running = true;
    try {
      await this.runOnce();
    } catch (err) {
      this.logger.error(
        `Passage des rappels de confirmation en échec : ${(err as Error)?.message}`,
      );
    } finally {
      this.running = false;
    }
  }

  async runOnce(): Promise<{ reminders: number; alerts: number }> {
    const delays = this.getDelays();
    if (delays.adminAlertHours < delays.reminderHours) {
      this.logger.warn(
        `ORDER_ADMIN_ALERT_HOURS (${delays.adminAlertHours}) est inférieur à `
        + `ORDER_REMINDER_HOURS (${delays.reminderHours}) : l'alerte admin partira avant le rappel vendeur.`,
      );
    }

    let reminders = 0;
    let alerts    = 0;

    try {
      reminders = await this.processReminders(delays.reminderHours);
    } catch (err) {
      this.logger.error(`Rappels vendeur en échec : ${(err as Error)?.message}`);
    }
    try {
      alerts = await this.processAdminAlerts(delays.adminAlertHours);
    } catch (err) {
      this.logger.error(`Alertes admin en échec : ${(err as Error)?.message}`);
    }

    if (reminders || alerts) {
      this.logger.log(
        `Confirmation vendeur : ${reminders} rappel(s) envoyé(s), ${alerts} alerte(s) admin.`,
      );
    }
    return { reminders, alerts };
  }

  // Réserve (atomiquement) un lot de commandes dues : la colonne `column`
  // est posée à now() par un UPDATE conditionnel ; seules les lignes
  // réellement modifiées par CETTE exécution sont renvoyées. Deux instances
  // (ou deux passages) ne peuvent donc jamais réserver la même commande.
  private async claimBatch(
    column: 'vendorReminderSentAt' | 'adminAlertedAt',
    hours:  number,
  ): Promise<Array<{ id: string; orderNumber: string; vendorId: string }>> {
    const res = await this.dataSource.query(
      `
      WITH due AS (
        SELECT o."id"
        FROM "orders" o
        JOIN "payments" p ON p."orderId" = o."id"
        WHERE ${AWAITING_SQL}
          AND o."${column}" IS NULL
          AND ${REF_SQL} <= now() - ($1::double precision * interval '1 hour')
        ORDER BY ${REF_SQL} ASC
        LIMIT ${BATCH_SIZE}
        FOR UPDATE OF o SKIP LOCKED
      )
      UPDATE "orders" o
      SET "${column}" = now()
      FROM due
      WHERE o."id" = due."id"
        AND o."${column}" IS NULL
        AND o."status" = ${lit(OrderStatus.PENDING)}
      RETURNING o."id", o."orderNumber", o."vendorId"
      `,
      [hours],
    );
    return rowsOf(res);
  }

  // Annule la réservation d'une commande si la notification a échoué : le
  // prochain passage réessaiera.
  private async releaseClaim(
    column:  'vendorReminderSentAt' | 'adminAlertedAt',
    orderId: string,
  ): Promise<void> {
    try {
      await this.dataSource.query(
        `UPDATE "orders" SET "${column}" = NULL WHERE "id" = $1 AND "status" = ${lit(OrderStatus.PENDING)}`,
        [orderId],
      );
    } catch (err) {
      this.logger.error(
        `Impossible d'annuler la réservation ${column} de la commande ${orderId} : ${(err as Error)?.message}`,
      );
    }
  }

  // ── Rappel au vendeur ────────────────────────────────
  private async processReminders(hours: number): Promise<number> {
    let sent = 0;

    for (let i = 0; i < MAX_BATCHES_PER_RUN; i++) {
      const claimed = await this.claimBatch('vendorReminderSentAt', hours);
      if (!claimed.length) break;

      const vendors = await this.vendorRepo.find({
        where:  { id: In([...new Set(claimed.map(c => c.vendorId))]) },
        select: ['id', 'userId'],
      });
      const vendorById = new Map(vendors.map(v => [v.id, v]));

      for (const order of claimed) {
        const vendor = vendorById.get(order.vendorId);
        if (!vendor?.userId) {
          // Boutique introuvable : rien à notifier, inutile de réessayer.
          this.logger.warn(
            `Rappel ignoré : boutique introuvable pour la commande ${order.id}`,
          );
          continue;
        }
        try {
          await this.notifications.create({
            userId:        vendor.userId,
            title:         '⏰ Commande en attente de confirmation',
            body:
              `La commande #${order.orderNumber} attend votre confirmation `
              + `depuis ${fmtHours(hours)} h. `
              + `Confirmez-la pour que le client soit rassuré.`,
            type:          NotificationType.ORDER,
            referenceId:   order.id,
            referenceType: 'order',
            sendEmail:     true,
          });
          sent++;
        } catch (err) {
          this.logger.error(
            `Rappel vendeur impossible pour la commande ${order.id} : ${(err as Error)?.message}`,
          );
          await this.releaseClaim('vendorReminderSentAt', order.id);
        }
      }

      if (claimed.length < BATCH_SIZE) break;
    }
    return sent;
  }

  // ── Alerte aux admins ────────────────────────────────
  private async processAdminAlerts(hours: number): Promise<number> {
    let alerted = 0;
    let admins: AdminAccount[] | null = null;

    for (let i = 0; i < MAX_BATCHES_PER_RUN; i++) {
      const claimed = await this.claimBatch('adminAlertedAt', hours);
      if (!claimed.length) break;

      // Comptes admin ET superadmin actifs (AdminAccount.role).
      if (admins === null) {
        admins = await this.adminRepo.find({
          where:  { isActive: true },
          select: ['id'],
        });
        if (!admins.length) {
          this.logger.warn('Alerte commande en retard : aucun compte admin actif à notifier.');
        }
      }

      const vendors = await this.vendorRepo.find({
        where:  { id: In([...new Set(claimed.map(c => c.vendorId))]) },
        select: ['id', 'shopName'],
      });
      const vendorById = new Map(vendors.map(v => [v.id, v]));

      for (const order of claimed) {
        const shopName = vendorById.get(order.vendorId)?.shopName ?? 'boutique inconnue';
        let delivered = 0;

        for (const admin of admins) {
          try {
            await this.notifications.create({
              adminId:       admin.id,
              title:         '🚨 Commande non confirmée par le vendeur',
              body:
                `La commande #${order.orderNumber} n'est toujours pas confirmée `
                + `par la boutique « ${shopName} » depuis plus de ${fmtHours(hours)} h.`,
              type:          NotificationType.ORDER,
              referenceId:   order.id,
              referenceType: 'order',
              sendEmail:     false,
            });
            delivered++;
          } catch (err) {
            this.logger.error(
              `Alerte admin impossible (admin ${admin.id}, commande ${order.id}) : ${(err as Error)?.message}`,
            );
          }
        }

        if (admins.length > 0 && delivered === 0) {
          // Personne n'a pu être prévenu : on réessaiera au prochain passage.
          await this.releaseClaim('adminAlertedAt', order.id);
          continue;
        }

        alerted++;
        await this.logService.log({
          actorType:  ActorType.SYSTEM,
          action:     LogAction.ORDER_CONFIRMATION_OVERDUE,
          entityType: 'order',
          entityId:   order.id,
          newValue:   {
            orderNumber:    order.orderNumber,
            vendorId:       order.vendorId,
            shopName,
            thresholdHours: hours,
            adminsNotified: delivered,
          },
        });
      }

      if (claimed.length < BATCH_SIZE) break;
    }
    return alerted;
  }

  // ─────────────────────────────────────────────────────
  // Nombre de commandes en retard de confirmation = le `total` de la liste
  // GET /admin/orders/late-confirmation au niveau par défaut (« reminder » :
  // délai de rappel dépassé, tous vendeurs). Même WHERE (AWAITING_SQL +
  // REF_SQL) : le compteur du menu admin ne peut donc pas diverger de la liste.
  // ─────────────────────────────────────────────────────
  async countLateConfirmation(): Promise<number> {
    const { reminderHours } = this.getDelays();
    const [row] = rowsOf(
      await this.dataSource.query(
        `SELECT COUNT(*)::int AS "total"
         FROM "orders" o JOIN "payments" p ON p."orderId" = o."id"
         WHERE ${AWAITING_SQL}
           AND ${REF_SQL} <= now() - ($1::double precision * interval '1 hour')`,
        [reminderHours],
      ),
    );
    return Number(row?.total ?? 0);
  }

  // ─────────────────────────────────────────────────────
  // ADMIN — COMMANDES EN RETARD DE CONFIRMATION
  // GET /api/v1/admin/orders/late-confirmation
  // ─────────────────────────────────────────────────────
  async listLateConfirmation(filters: LateConfirmationFilters & { page: number; limit: number }) {
    const { page, limit } = filters;
    const { reminderHours, adminAlertHours } = this.getDelays();

    const level = filters.level ?? 'reminder';
    if (level !== 'reminder' && level !== 'alert') {
      throw new BadRequestException(
        "Niveau invalide : utilisez « reminder » (délai de rappel dépassé) ou « alert » (délai d'alerte admin dépassé).",
      );
    }
    if (filters.vendorId !== undefined && !UUID_RE.test(filters.vendorId)) {
      throw new BadRequestException('Identifiant de boutique invalide');
    }

    const thresholdHours = level === 'alert' ? adminAlertHours : reminderHours;
    const params: any[]  = [thresholdHours];
    let vendorSql = '';
    if (filters.vendorId) {
      params.push(filters.vendorId);
      vendorSql = `AND o."vendorId" = $${params.length}::uuid`;
    }

    const where = `
      WHERE ${AWAITING_SQL}
        AND ${REF_SQL} <= now() - ($1::double precision * interval '1 hour')
        ${vendorSql}
    `;

    const [countRow] = rowsOf(
      await this.dataSource.query(
        `SELECT COUNT(*)::int AS "total"
         FROM "orders" o JOIN "payments" p ON p."orderId" = o."id"
         ${where}`,
        params,
      ),
    );
    const total = Number(countRow?.total ?? 0);

    const pageParams = [...params, limit, (page - 1) * limit];
    const rows = rowsOf(
      await this.dataSource.query(
        `SELECT
           o."id", o."orderNumber", o."status", o."total", o."createdAt",
           o."vendorReminderSentAt", o."adminAlertedAt",
           p."method" AS "paymentMethod", p."status" AS "paymentStatus",
           ${REF_SQL} AS "waitingSince",
           ROUND((EXTRACT(EPOCH FROM (now() - ${REF_SQL})) / 3600.0)::numeric, 1)::float8 AS "hoursWaiting",
           v."id" AS "vendorId", v."shopName", v."userId" AS "vendorUserId",
           vu."phone" AS "vendorPhone",
           u."id" AS "customerId", u."prenom" AS "customerPrenom", u."name" AS "customerName"
         FROM "orders" o
         JOIN "payments" p       ON p."orderId" = o."id"
         JOIN "vendor_profiles" v ON v."id" = o."vendorId"
         LEFT JOIN "users" vu    ON vu."id" = v."userId"
         LEFT JOIN "users" u     ON u."id" = o."userId"
         ${where}
         ORDER BY ${REF_SQL} ASC, o."id" ASC
         LIMIT $${params.length + 1} OFFSET $${params.length + 2}`,
        pageParams,
      ),
    );

    const data = rows.map((r: any) => ({
      id:                   r.id,
      orderNumber:          r.orderNumber,
      status:               r.status,
      total:                r.total,   // décimal Postgres = chaîne
      createdAt:            r.createdAt,
      waitingSince:         r.waitingSince,
      hoursWaiting:         r.hoursWaiting,
      stage:                r.hoursWaiting >= adminAlertHours ? 'alert' : 'reminder',
      vendorReminderSentAt: r.vendorReminderSentAt,
      adminAlertedAt:       r.adminAlertedAt,
      paymentMethod:        r.paymentMethod,
      paymentStatus:        r.paymentStatus,
      vendor: {
        id:       r.vendorId,
        userId:   r.vendorUserId,
        shopName: r.shopName,
        phone:    r.vendorPhone ?? null,
      },
      customer: {
        id:     r.customerId,
        prenom: r.customerPrenom ?? null,
        name:   r.customerName ?? null,
      },
    }));

    return {
      data,
      total,
      page,
      limit,
      pages: Math.ceil(total / limit),
      thresholds: { reminderHours, adminAlertHours },
    };
  }
}
