import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, IsNull, LessThan } from 'typeorm';

import { Payment, PaymentStatus } from './entities/payment.entity';
import { PaymentsService, SettleOutcome } from './payments.service';

// ─────────────────────────────────────────────────────────────────────────
// « L'EMPLOYÉ QUI REPASSE » : RATTRAPAGE DES PAIEMENTS FEEXPAY EN ATTENTE
//
// Pourquoi : l'appli n'interroge FeexPay que pendant ~2 minutes. Si le client
// valide son code PIN plus tard (ou si l'appli est fermée), personne ne
// vérifierait plus jamais le paiement. Le webhook FeexPay est le chemin
// principal (s'il existe) ; ce passage est le filet de sécurité, il marche
// même si FeexPay n'envoie jamais de webhook.
//
// Toutes les 5 minutes, on reprend les paiements « en attente » qui ont une
// référence FeexPay et qui sont créés depuis plus de 5 minutes :
//   - âge < 1 h        → vérifiés à chaque passage ;
//   - âge de 1 h à 24 h → vérifiés une seule fois par heure (passage où la
//                         minute est < 5) — pas de colonne en base nécessaire ;
//   - âge > 24 h       → vérifiés une fois par heure aussi ; si FeexPay ne
//                         dit pas « réussi », ET qu'il répond clairement « en cours »
//                         ou « échoué », le paiement est marqué échoué (un statut
//                         inconnu ou FeexPay injoignable ne change rien).
// Cas à part : un paiement « en attente » SANS référence FeexPay créé depuis
// plus de 15 minutes n'est jamais parti chez FeexPay (rien n'a pu être débité) :
// il est marqué échoué.
// Jamais « échoué » sans que FeexPay le dise (ou après 24 h sans succès).
// Les paiements d'un même panier groupé (groupRef) ne sont vérifiés qu'une
// fois. FeexPay injoignable : on ne change rien.
//
// Sûr : lot limité, un paiement à la fois, un seul passage à la fois (verrou
// en mémoire), toute erreur est journalisée sans arrêter les autres paiements.
// La confirmation est la même que celle de l'appli (idempotente : confirmer
// deux fois ne décrémente pas le stock deux fois).
// ─────────────────────────────────────────────────────────────────────────

const SYSTEM_IP = 'system';

const MIN_AGE_MS     = 5 * 60 * 1000;        // créés depuis plus de 5 minutes
const HOURLY_AGE_MS  = 60 * 60 * 1000;       // en dessous : à chaque passage
const EXPIRY_AGE_MS  = 24 * 60 * 60 * 1000;  // au-dessus : échoué si pas de succès
const UNSENT_AGE_MS  = 15 * 60 * 1000;       // sans référence FeexPay : échoué après 15 min

const BATCH_SIZE            = 50;   // paiements (ou paniers) traités par passage
const CANDIDATES_FETCH_SIZE = 200;  // lignes lues avant regroupement par panier
const MAX_CONSECUTIVE_UNREACHABLE = 3; // FeexPay en panne : on arrête le passage

@Injectable()
export class PaymentReconciliationService {
  private readonly logger = new Logger(PaymentReconciliationService.name);
  private running = false;

  constructor(
    @InjectRepository(Payment)
    private readonly paymentRepo: Repository<Payment>,
    private readonly paymentsService: PaymentsService,
  ) {}

  @Cron('*/5 * * * *', { name: 'reconcile-pending-payments' })
  async handleCron(): Promise<void> {
    if (this.running) return; // le passage précédent n'est pas fini
    this.running = true;
    try {
      await this.runOnce();
    } catch (err) {
      this.logger.error(
        `Rattrapage des paiements en échec : ${(err as Error)?.message}`,
      );
    } finally {
      this.running = false;
    }
  }

  private async failUnsentPayments(
    now:    Date,
    counts: Record<SettleOutcome, number>,
  ): Promise<void> {
    try {
      const unsent = await this.paymentRepo.find({
        where: [
          {
            status: PaymentStatus.PENDING,
            providerRef: IsNull(),
            createdAt: LessThan(new Date(now.getTime() - UNSENT_AGE_MS)),
          },
          {
            status: PaymentStatus.PENDING,
            providerRef: '',
            createdAt: LessThan(new Date(now.getTime() - UNSENT_AGE_MS)),
          },
        ],
        order: { createdAt: 'ASC' },
        take:  BATCH_SIZE,
      });
      for (const payment of unsent) {
        const done = await this.paymentsService.failUnsentPayment(payment.id, SYSTEM_IP);
        if (done) {
          counts.failed++;
          this.logger.warn(
            `Rattrapage : paiement ${payment.id} « en attente » sans référence FeexPay `
            + `depuis plus de 15 minutes (la demande n'est jamais partie chez FeexPay) → marqué échoué.`,
          );
        }
      }
    } catch (err) {
      this.logger.error(
        `Rattrapage : paiements sans référence FeexPay : ${(err as Error)?.message}`,
      );
    }
  }

  async runOnce(now: Date = new Date()): Promise<Record<SettleOutcome, number>> {
    const counts: Record<SettleOutcome, number> = {
      confirmed: 0, failed: 0, pending: 0, unreachable: 0,
      amount_mismatch: 0, error: 0, ignored: 0,
    };

    // Passage « de l'heure » : une seule fois par heure (minute 0 à 4 ; le
    // cron tourne toutes les 5 minutes, donc exactement un passage par heure).
    const hourlyPass = now.getMinutes() < 5;

    const qb = this.paymentRepo
      .createQueryBuilder('p')
      .leftJoinAndSelect('p.order', 'o')
      .where('p.status = :status', { status: PaymentStatus.PENDING })
      .andWhere('p.providerRef IS NOT NULL')
      .andWhere("p.providerRef <> ''")
      .andWhere('p.createdAt < :minDate', {
        minDate: new Date(now.getTime() - MIN_AGE_MS),
      });
    if (!hourlyPass) {
      qb.andWhere('p.createdAt > :maxDate', {
        maxDate: new Date(now.getTime() - HOURLY_AGE_MS),
      });
    }
    const candidates = await qb
      .orderBy('p.createdAt', 'ASC')
      .take(CANDIDATES_FETCH_SIZE)
      .getMany();

    // Un seul représentant par panier groupé (le plus ancien).
    const units: Payment[] = [];
    const seen = new Set<string>();
    for (const payment of candidates) {
      const key = payment.groupRef ?? payment.id;
      if (seen.has(key)) continue;
      seen.add(key);
      units.push(payment);
      if (units.length >= BATCH_SIZE) break;
    }

    // Paiements « en attente » SANS référence FeexPay depuis plus de 15 minutes :
    // la demande n'est jamais partie chez FeexPay (erreur serveur au mauvais
    // moment...). Aucun débit possible : on les marque échoués pour que le
    // client puisse réessayer.
    await this.failUnsentPayments(now, counts);

    if (units.length === 0) return counts;

    let consecutiveUnreachable = 0;
    for (const payment of units) {
      const age = now.getTime() - new Date(payment.createdAt).getTime();
      let outcome: SettleOutcome;
      try {
        outcome = await this.paymentsService.settlePendingPayment(
          payment,
          SYSTEM_IP,
          { source: 'rattrapage', failIfNotSuccess: age > EXPIRY_AGE_MS },
        );
      } catch (err) {
        // settlePendingPayment ne lève normalement jamais ; filet de sécurité.
        this.logger.error(
          `Rattrapage : paiement ${payment.id} en erreur : ${(err as Error)?.message}`,
        );
        outcome = 'error';
      }
      counts[outcome]++;

      if (outcome === 'unreachable') {
        consecutiveUnreachable++;
        if (consecutiveUnreachable >= MAX_CONSECUTIVE_UNREACHABLE) {
          this.logger.warn(
            'Rattrapage des paiements : FeexPay injoignable, passage interrompu '
            + '(nouvelle tentative au prochain passage).',
          );
          break;
        }
      } else {
        consecutiveUnreachable = 0;
      }
    }

    if (counts.confirmed || counts.failed || counts.amount_mismatch || counts.error) {
      this.logger.log(
        `Rattrapage des paiements : ${counts.confirmed} confirmé(s), `
        + `${counts.failed} échoué(s), ${counts.amount_mismatch} montant(s) à examiner, `
        + `${counts.error} erreur(s), ${counts.pending} toujours en attente, `
        + `${counts.unreachable} non vérifié(s) (FeexPay injoignable).`,
      );
    }
    return counts;
  }
}
