import { createHash, randomInt, timingSafeEqual } from 'crypto';
import { DataSource, EntityManager } from 'typeorm';
import {
  BadRequestException,
  HttpException,
  HttpStatus,
  NotFoundException,
} from '@nestjs/common';

// ─────────────────────────────────────────────────────────────────────────
// CODE DE REMISE (« QR de preuve »)
//
// Avant : le « QR » du client était simplement le numéro de commande
// (ex. ASK-2026-00123), visible du vendeur ET du livreur et facile à deviner :
// un livreur pouvait valider la remise sans le client, un vendeur valider un
// retrait en boutique.
//
// Maintenant : chaque commande a un code ALÉATOIRE (orders.handoverCode),
// connu uniquement du client propriétaire (GET /orders/me/:id). Le livreur
// (remise à domicile) ou le vendeur (retrait en boutique) doit saisir / scanner
// ce code ; il est comparé en temps constant et les essais ratés sont comptés
// par commande (blocage temporaire après 3 essais).
//
// ⚠️ Ce code ne doit JAMAIS apparaître dans une réponse vendeur / livreur /
// admin, ni dans un journal : la colonne est `select: false` côté entité.
// ─────────────────────────────────────────────────────────────────────────

// 31 caractères non ambigus : ni 0/O, ni 1/I/L.
export const HANDOVER_CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
export const HANDOVER_CODE_LENGTH   = 8;

// Essais ratés tolérés avant blocage, et durée du blocage.
export const HANDOVER_MAX_ATTEMPTS = 3;
export const HANDOVER_LOCK_MINUTES = 15;

// Code aléatoire cryptographique (crypto.randomInt, jamais Math.random).
export function generateHandoverCode(): string {
  let code = '';
  for (let i = 0; i < HANDOVER_CODE_LENGTH; i++) {
    code += HANDOVER_CODE_ALPHABET[randomInt(HANDOVER_CODE_ALPHABET.length)];
  }
  return code;
}

// Tolère les espaces / tirets de saisie et la casse ; rien d'autre.
export function normalizeHandoverInput(raw: unknown): string {
  if (typeof raw !== 'string') return '';
  return raw.trim().toUpperCase().replace(/[\s\-_]+/g, '').slice(0, 64);
}

// Comparaison en temps constant : on compare les empreintes SHA-256 (même
// longueur quelle que soit la saisie), jamais les chaînes brutes.
export function handoverCodesMatch(expected: string, provided: unknown): boolean {
  const a = createHash('sha256').update(String(expected)).digest();
  const b = createHash('sha256').update(normalizeHandoverInput(provided)).digest();
  return timingSafeEqual(a, b);
}

// TypeORM renvoie [lignes, nombre] pour un UPDATE ... RETURNING et
// directement les lignes pour un SELECT.
function rowsOf(res: any): any[] {
  if (!Array.isArray(res)) return [];
  if (res.length === 2 && Array.isArray(res[0]) && typeof res[1] === 'number') {
    return res[0];
  }
  return res;
}

// Vérifie le code saisi/scanné pour une commande. Lève une exception si le
// code est faux, absent, ou si la commande est temporairement bloquée.
//
// Ordre volontaire : la tentative est COMPTÉE D'ABORD, par un UPDATE atomique
// (qui verrouille la ligne) ; la comparaison vient ensuite. Ainsi, N requêtes
// parallèles ne peuvent pas contourner le plafond de 3 essais (elles se
// sérialisent sur le verrou de ligne). Si le code est bon, le compteur est
// remis à zéro. Un code correct n'est jamais journalisé ni renvoyé.
// Blocage EXPIRÉ (handoverLockedUntil <= now()) : la prochaine erreur recompte
// à partir de 1 (et le verrou est remis à NULL) au lieu de reverrouiller
// aussitôt à cause des anciens essais ratés.
export async function assertHandoverCode(
  db:      DataSource | EntityManager,
  orderId: string,
  provided: unknown,
): Promise<void> {
  const claimed = rowsOf(
    await db.query(
      `
      UPDATE "orders"
      SET "handoverFailedAttempts" = CASE
            WHEN "handoverLockedUntil" IS NOT NULL AND "handoverLockedUntil" <= now()
              THEN 1
            ELSE "handoverFailedAttempts" + 1
          END,
          "handoverLockedUntil" = CASE
            WHEN (CASE
                    WHEN "handoverLockedUntil" IS NOT NULL AND "handoverLockedUntil" <= now()
                      THEN 1
                    ELSE "handoverFailedAttempts" + 1
                  END) >= $2
              THEN now() + ($3::int * interval '1 minute')
            WHEN "handoverLockedUntil" IS NOT NULL AND "handoverLockedUntil" <= now()
              THEN NULL
            ELSE "handoverLockedUntil"
          END
      WHERE "id" = $1
        AND ("handoverLockedUntil" IS NULL OR "handoverLockedUntil" <= now())
      RETURNING "handoverCode", "handoverFailedAttempts",
        ("handoverLockedUntil" IS NOT NULL AND "handoverLockedUntil" > now()) AS "locked"
      `,
      [orderId, HANDOVER_MAX_ATTEMPTS, HANDOVER_LOCK_MINUTES],
    ),
  );

  if (!claimed.length) {
    // Soit la commande n'existe pas, soit elle est bloquée.
    const rows = rowsOf(
      await db.query(
        `SELECT GREATEST(1, CEIL(EXTRACT(EPOCH FROM ("handoverLockedUntil" - now())) / 60))::int AS "minutes"
         FROM "orders" WHERE "id" = $1`,
        [orderId],
      ),
    );
    if (!rows.length) throw new NotFoundException('Commande introuvable');
    throw new HttpException(
      `Trop de tentatives incorrectes. Réessayez dans ${rows[0].minutes} minute(s).`,
      HttpStatus.TOO_MANY_REQUESTS,
    );
  }

  const row = claimed[0];

  if (!row.handoverCode) {
    // Commande sans code (ancienne commande non migrée) : on refuse, par
    // sécurité, plutôt que de valider sans preuve. Le code est créé dès que
    // le client ouvre sa commande dans l'application.
    throw new BadRequestException(
      'Le code de remise de cette commande n\'est pas encore disponible. '
      + 'Demandez au client d\'ouvrir le suivi de sa commande dans l\'application.',
    );
  }

  if (handoverCodesMatch(row.handoverCode, provided)) {
    await db.query(
      `UPDATE "orders"
       SET "handoverFailedAttempts" = 0, "handoverLockedUntil" = NULL
       WHERE "id" = $1`,
      [orderId],
    );
    return;
  }

  if (row.locked) {
    throw new HttpException(
      `Code de remise incorrect. Trop de tentatives : réessayez dans ${HANDOVER_LOCK_MINUTES} minutes.`,
      HttpStatus.TOO_MANY_REQUESTS,
    );
  }

  const left = Math.max(0, HANDOVER_MAX_ATTEMPTS - Number(row.handoverFailedAttempts));
  throw new BadRequestException(
    `Code de remise incorrect. Il reste ${left} essai(s) avant un blocage temporaire.`,
  );
}

// Valeur enregistrée dans delivery_proofs.qrScanValue à la place du code
// saisi : on ne conserve JAMAIS le code lui-même (les preuves sont lisibles
// par le vendeur et l'admin).
export const HANDOVER_PROOF_MARKER = 'code de remise vérifié';
