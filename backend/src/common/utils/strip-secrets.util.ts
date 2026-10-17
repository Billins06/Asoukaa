// Retire récursivement les champs secrets d'un objet (ou d'un tableau
// d'objets) avant de le renvoyer à l'appli, notamment les routes ADMIN qui
// chargent des relations user / admin / reviewedBy complètes.
//
// - Ne modifie PAS l'objet d'origine : renvoie une copie « propre ».
// - Garde contre les cycles : une référence circulaire est supprimée
//   (undefined) au lieu de faire planter la sérialisation.
// - Les dates et les Buffers sont conservés tels quels.
export const SECRET_KEYS: ReadonlySet<string> = new Set([
  'passwordHash',
  'invitationToken',
  'tokensValidAfter',
  'securityAlertAt',
  'securityAlertReason',
  'securityAlertAckedAt',
]);

function walk(value: any, path: Set<object>): any {
  if (value === null || typeof value !== 'object') return value;
  if (value instanceof Date || Buffer.isBuffer(value)) return value;

  // Cycle : cet objet est déjà en cours de traitement plus haut.
  if (path.has(value)) return undefined;
  path.add(value);

  let result: any;
  if (Array.isArray(value)) {
    result = value.map((item) => walk(item, path));
  } else {
    result = {};
    for (const key of Object.keys(value)) {
      if (SECRET_KEYS.has(key)) continue;
      result[key] = walk(value[key], path);
    }
  }

  path.delete(value);
  return result;
}

export function stripSecrets<T>(value: T): T {
  return walk(value, new Set<object>()) as T;
}
