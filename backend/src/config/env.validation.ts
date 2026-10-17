/**
 * Vérification de l'environnement (.env) AU DÉMARRAGE.
 *
 * Branchée sur ConfigModule.forRoot({ validate }) dans AppModule : elle
 * s'exécute avant que le moindre module ne démarre.
 *
 *  - NODE_ENV=production : toute erreur BLOQUE le démarrage (message clair,
 *    code de sortie 1). Mieux vaut un serveur qui refuse de démarrer qu'un
 *    serveur qui tourne avec une clé de chiffrement invalide ou la base de
 *    données en mode « synchronize ».
 *  - Autre environnement (développement) : les mêmes problèmes sont affichés
 *    en AVERTISSEMENT bien visible, mais le serveur démarre quand même.
 *    (Ce qui est déjà indispensable au démarrage — JWT_SECRET, DB_* — fait de
 *    toute façon échouer le serveur plus loin, comme avant.)
 *
 * ⚠️ Aucune VALEUR de variable n'est jamais affichée (secrets), seulement le
 * nom de la variable et ce qui ne va pas.
 */

export const GENERATE_KEY_COMMAND =
  "node -e \"console.log(require('crypto').randomBytes(32).toString('hex'))\"";

/** Clé de chiffrement valide : exactement 64 caractères hexadécimaux (= 32 octets). */
export function isValidEncryptionKey(value: unknown): boolean {
  return typeof value === 'string' && /^[0-9a-fA-F]{64}$/.test(value);
}

type Env = Record<string, unknown>;

const str = (env: Env, key: string): string => {
  const v = env[key];
  return typeof v === 'string' ? v.trim() : '';
};

export interface EnvReport {
  errors: string[];
  warnings: string[];
}

/** Analyse pure (sans effet de bord) : facile à tester. */
export function analyzeEnvironment(env: Env): EnvReport {
  const errors: string[] = [];
  const warnings: string[] = [];
  const isProd = str(env, 'NODE_ENV') === 'production';
  // Problème « bloquant en production, avertissement ailleurs ».
  const problem = (msg: string) => (isProd ? errors : warnings).push(msg);

  // ── ENCRYPTION_KEY ─────────────────────────────────────────────────
  const enc = str(env, 'ENCRYPTION_KEY');
  if (!enc) {
    problem(
      'ENCRYPTION_KEY est absente. Elle sert à chiffrer les coordonnées de paiement des vendeurs ' +
        '(sans elle, leur enregistrement échoue avec une erreur). ' +
        `Générez-en une avec : ${GENERATE_KEY_COMMAND}`,
    );
  } else if (!isValidEncryptionKey(enc)) {
    problem(
      `ENCRYPTION_KEY est invalide : elle doit faire EXACTEMENT 64 caractères hexadécimaux ` +
        `(0-9 et a-f), or elle en contient ${enc.length}` +
        `${/^[0-9a-fA-F]*$/.test(enc) ? '' : ' dont certains ne sont pas hexadécimaux'}. ` +
        'Tant qu\'elle est invalide, l\'enregistrement des coordonnées de paiement vendeur échoue. ' +
        `Générez-en une valide avec : ${GENERATE_KEY_COMMAND}  (npm run generate:key)`,
    );
  }

  // ── Secrets JWT ────────────────────────────────────────────────────
  const jwt = str(env, 'JWT_SECRET');
  const jwtRefresh = str(env, 'JWT_REFRESH_SECRET');
  if (!jwt) {
    problem('JWT_SECRET est absente (signature des jetons de connexion).');
  } else if (jwt.length < 32) {
    warnings.push('JWT_SECRET est courte (moins de 32 caractères) : utilisez une valeur longue et aléatoire.');
  }
  if (!jwtRefresh) {
    problem('JWT_REFRESH_SECRET est absente (signature des jetons de rafraîchissement).');
  } else if (jwtRefresh.length < 32) {
    warnings.push('JWT_REFRESH_SECRET est courte (moins de 32 caractères) : utilisez une valeur longue et aléatoire.');
  }
  if (jwt && jwtRefresh && jwt === jwtRefresh) {
    problem(
      'JWT_REFRESH_SECRET est identique à JWT_SECRET : elles doivent être DIFFÉRENTES ' +
        `(générez-en une autre avec : ${GENERATE_KEY_COMMAND}).`,
    );
  }
  if (!str(env, 'JWT_EXPIRES_IN')) problem('JWT_EXPIRES_IN est absente (ex. 15m).');
  if (!str(env, 'JWT_REFRESH_EXPIRES_IN')) problem('JWT_REFRESH_EXPIRES_IN est absente (ex. 30d).');

  // ── Base de données ────────────────────────────────────────────────
  for (const key of ['DB_HOST', 'DB_PORT', 'DB_USER', 'DB_PASSWORD', 'DB_NAME']) {
    if (!str(env, key)) problem(`${key} est absente (connexion à la base de données).`);
  }

  // ── DB_SYNCHRONIZE ─────────────────────────────────────────────────
  if (str(env, 'DB_SYNCHRONIZE') === 'true') {
    if (isProd) {
      errors.push(
        'DB_SYNCHRONIZE=true est INTERDIT en production : TypeORM pourrait supprimer des colonnes ou ' +
          'des index pour « aligner » la base sur le code (perte de données). ' +
          'Mettez DB_SYNCHRONIZE=false (ou retirez la ligne) et faites évoluer la base uniquement ' +
          'par migrations (npm run typeorm:run).',
      );
    } else {
      warnings.push(
        'DB_SYNCHRONIZE=true : à chaque démarrage, TypeORM modifie la base pour la faire ressembler aux ' +
          'entités et SUPPRIME les index ou colonnes créés seulement par migration. ' +
          'Prévoyez DB_SYNCHRONIZE=false et lancez les migrations (npm run typeorm:run) dès que possible.',
      );
    }
  }

  // ── Autres avertissements (jamais bloquants) ───────────────────────
  if (isProd) {
    if (!str(env, 'FRONTEND_WEB_URL')) {
      warnings.push('FRONTEND_WEB_URL est absente : en production, le site web (CORS) ne pourra pas appeler l\'API.');
    }
    if (str(env, 'STORAGE_DRIVER') === 'local') {
      warnings.push('STORAGE_DRIVER=local en production : les fichiers sont stockés sur le disque du serveur (réservé au développement).');
    }
  }
  if (!str(env, 'TZ')) {
    warnings.push('TZ n\'est pas défini : recommandé TZ=Africa/Lagos (heure du Bénin) pour des dates cohérentes entre le serveur et la base.');
  }

  return { errors, warnings };
}

const BAR = '='.repeat(78);

function box(title: string, lines: string[]): string {
  return [
    '',
    BAR,
    `  ${title}`,
    BAR,
    ...lines.map((l) => `  • ${l}`),
    BAR,
    '',
  ].join('\n');
}

/**
 * Point d'entrée pour ConfigModule.forRoot({ validate }).
 * Retourne la configuration inchangée, ou arrête le processus (production).
 */
export function validateEnvironment(config: Env): Env {
  const { errors, warnings } = analyzeEnvironment(config);

  if (warnings.length) {
    console.warn(box('⚠️  AVERTISSEMENT — configuration (.env) à corriger', warnings));
  }
  if (errors.length) {
    console.error(
      box('⛔ DÉMARRAGE REFUSÉ — configuration (.env) invalide pour la PRODUCTION', errors),
    );
    // Arrêt net : le message ci-dessus est la seule chose utile à lire.
    process.exit(1);
  }
  return config;
}
