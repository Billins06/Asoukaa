import { PaymentStatus } from './entities/payment.entity';
import {
  LogAction,
  LogResult,
} from '../../common/entities/activity-log.entity';

// ─────────────────────────────────────────────────────
// « Paiements à examiner » : le client a payé (FeexPay a répondu SUCCESS) mais
// nous n'avons PAS pu valider la commande (stock insuffisant, commande
// annulée entre-temps...). L'argent est reçu, la commande n'est pas validée :
// un humain doit trancher (rejouer, rembourser manuellement...).
//
// CRITÈRE (fiable) : paiement resté « en attente » ET possédant une référence
// opérateur (providerRef) ET pour lequel confirmPayment() a écrit une ligne
// « Échec du paiement » avec result = failure dans le journal d'activité.
// Pourquoi le journal et pas seulement « commande annulée » : confirmPayment()
// n'est appelé QU'APRÈS une réponse SUCCESS de FeexPay, donc cette ligne est la
// seule preuve que le client a vraiment été débité. Une commande annulée dont
// le client n'a jamais validé le paiement n'est pas comptée (faux positif).
// Les autres lignes PAYMENT_FAILED (initiation, annulation par le client,
// échec FeexPay) ont result = success et ne sont pas concernées.
// Le paiement sort de la liste dès qu'il passe « success » (rejeu réussi) ou
// « échoué », ou dès qu'un admin le marque « traité » (colonne reviewedAt). Ce même critère sert au compteur du menu admin
// (`paymentsToReview`) et au filtre GET /payments?toReview=true.
//
// `alias` : alias SQL de la table payments dans la requête appelante.
// ─────────────────────────────────────────────────────
export const paymentsToReviewWhere = (alias: string): string => `(
  "${alias}"."status" = '${PaymentStatus.PENDING}'
  AND "${alias}"."providerRef" IS NOT NULL
  AND "${alias}"."providerRef" <> ''
  AND "${alias}"."reviewedAt" IS NULL
  AND EXISTS (
    SELECT 1 FROM "activity_logs" "l"
    WHERE "l"."entityType" = 'payment'
      AND "l"."entityId" = "${alias}"."id"::text
      AND "l"."action" = '${LogAction.PAYMENT_FAILED}'
      AND "l"."result" = '${LogResult.FAILURE}'
  )
)`;
