import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Cron, CronExpression } from '@nestjs/schedule';
import { DataSource } from 'typeorm';

import { OrderStatus } from './entities/order.entity';
import { releaseCouponForOrder } from './coupon-release.util';
import { ActivityLogService } from '../../common/services/activity-log.service';
import { NotificationsService } from '../notifications/notifications.service';
import { ActorType, LogAction } from '../../common/entities/activity-log.entity';

// ─────────────────────────────────────────────────────────────────────────
// ANNULATION AUTOMATIQUE DES COMMANDES JAMAIS PAYÉES
//
// Une commande « en attente » ne reçoit de ligne `payments` que lorsque le
// client lance le paiement. Un client qui crée sa commande puis abandonne
// laissait donc une commande « en attente » à vie, avec son coupon « consommé »
// (coupons.usedCount + coupon_usages) : le code était perdu pour lui comme pour
// la limite d'utilisations.
//
// Chaque passage annule les commandes :
//   - au statut « en attente » ;
//   - créées il y a plus de UNPAID_ORDER_CANCEL_HOURS (24 h par défaut, 12 h
//     minimum) ;
//   - pour lesquelles AUCUNE ligne payments n'existe (ni success, ni pending,
//     ni échoué : une commande qui a une trace de paiement n'est JAMAIS
//     touchée — un paiement « pending » peut très bien avoir abouti côté
//     opérateur : le webhook FeexPay et le rattrapage automatique des paiements
//     (PaymentReconciliationService) le règlent ensuite).
// Puis libère l'usage du coupon. Le stock n'est PAS restitué : il n'est
// décrémenté qu'à la confirmation d'un paiement (PaymentsService.confirmPayment),
// donc une commande sans paiement n'en a jamais pris.
//
// Sûr avec plusieurs instances : sélection `FOR UPDATE SKIP LOCKED` dans une
// transaction, puis UPDATE conditionnel (statut encore « en attente » ET toujours
// aucun paiement) — deux instances ne traitent jamais la même commande.
// ─────────────────────────────────────────────────────────────────────────

const DEFAULT_HOURS = 24;
const MIN_HOURS     = 12;
const MAX_HOURS     = 24 * 90;
const BATCH_SIZE    = 100;
const MAX_BATCHES   = 5;

const MOTIF =
  'Annulée automatiquement : commande non payée dans le délai imparti.';

@Injectable()
export class UnpaidOrdersService {
  private readonly logger = new Logger(UnpaidOrdersService.name);
  private running = false;

  constructor(
    private readonly config:     ConfigService,
    private readonly dataSource: DataSource,
    private readonly logService: ActivityLogService,
    private readonly notificationsService: NotificationsService,
  ) {}

  private getHours(): number {
    const raw = this.config.get('UNPAID_ORDER_CANCEL_HOURS');
    if (raw === undefined || raw === null || raw === '') return DEFAULT_HOURS;
    const n = Number(String(raw).trim().replace(',', '.'));
    if (!Number.isFinite(n) || n < MIN_HOURS) {
      this.logger.warn(
        `UNPAID_ORDER_CANCEL_HOURS invalide ou trop court (minimum ${MIN_HOURS} h) : `
        + `${DEFAULT_HOURS} h utilisées.`,
      );
      return DEFAULT_HOURS;
    }
    return Math.min(n, MAX_HOURS);
  }

  @Cron(CronExpression.EVERY_30_MINUTES, { name: 'cancel-unpaid-orders' })
  async handleCron(): Promise<void> {
    if (this.running) return;
    this.running = true;
    try {
      await this.runOnce();
    } catch (err) {
      this.logger.error(
        `Annulation des commandes impayées en échec : ${(err as Error)?.message}`,
      );
    } finally {
      this.running = false;
    }
  }

  async runOnce(): Promise<{ cancelled: number }> {
    const hours = this.getHours();
    let cancelled = 0;

    for (let i = 0; i < MAX_BATCHES; i++) {
      const done = await this.cancelBatch(hours);
      cancelled += done.length;

      // Journal APRÈS le commit de chaque lot (ActivityLogService.log n'échoue
      // jamais).
      for (const o of done) {
        await this.logService.log({
          actorType:  ActorType.SYSTEM,
          action:     LogAction.ORDER_CANCELLED,
          entityType: 'order',
          entityId:   o.id,
          oldValue:   { status: OrderStatus.PENDING },
          newValue:   {
            status:         OrderStatus.CANCELLED,
            reason:         MOTIF,
            source:         'annulation_automatique_impayee',
            delaiHeures:    hours,
            couponLibere:   o.couponReleased,
            stockRestitue:  false, // jamais décrémenté : aucun paiement
          },
        });

        // Prévient le client (ne doit jamais faire échouer le passage).
        try {
          if (o.userId) {
            await this.notificationsService.notifyOrderAutoCancelled(
              o.userId, o.orderNumber, o.id, hours,
            );
          }
        } catch (err) {
          this.logger.warn(
            `Notification d'annulation automatique non envoyée (commande ${o.id}) : ${(err as Error)?.message}`,
          );
        }
      }

      if (done.length < BATCH_SIZE) break;
    }

    if (cancelled) {
      this.logger.log(`${cancelled} commande(s) impayée(s) annulée(s) automatiquement.`);
    }
    return { cancelled };
  }

  // Un lot, dans une seule transaction. Renvoie les commandes réellement
  // annulées par CET appel.
  private async cancelBatch(
    hours: number,
  ): Promise<Array<{ id: string; userId: string | null; orderNumber: string; couponReleased: boolean }>> {
    return this.dataSource.transaction(async (manager) => {
      const due: Array<{ id: string; userId: string | null; orderNumber: string }> = await manager.query(
        `
        SELECT o."id", o."userId", o."orderNumber"
        FROM "orders" o
        WHERE o."status" = $1
          AND o."createdAt" < now() - ($2::double precision * interval '1 hour')
          AND NOT EXISTS (SELECT 1 FROM "payments" p WHERE p."orderId" = o."id")
        ORDER BY o."createdAt" ASC
        LIMIT ${BATCH_SIZE}
        FOR UPDATE OF o SKIP LOCKED
        `,
        [OrderStatus.PENDING, hours],
      );

      const done: Array<{ id: string; userId: string | null; orderNumber: string; couponReleased: boolean }> = [];

      for (const { id, userId, orderNumber } of due) {
        const res: any = await manager.query(
          `
          UPDATE "orders"
          SET "status" = $2, "motifAnnulation" = $3, "updatedAt" = now()
          WHERE "id" = $1
            AND "status" = $4
            AND NOT EXISTS (SELECT 1 FROM "payments" p WHERE p."orderId" = "orders"."id")
          RETURNING "id"
          `,
          [id, OrderStatus.CANCELLED, MOTIF, OrderStatus.PENDING],
        );
        const rows = Array.isArray(res) && Array.isArray(res[0]) ? res[0] : res;
        if (!Array.isArray(rows) || !rows.length) continue;

        const couponReleased = await releaseCouponForOrder(manager, id);
        done.push({ id, userId, orderNumber, couponReleased });
      }

      return done;
    });
  }
}
