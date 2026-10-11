// Présence « En ligne / Vu à … » (comme WhatsApp).
//
// RÈGLE CALCULÉE CÔTÉ SERVEUR : un utilisateur est « en ligne » si sa
// dernière activité (users.lastSeenAt) date de moins de 2 minutes. Le client
// ne décide jamais de cela lui-même.
//
// ⚠️ VIE PRIVÉE : on n'expose QUE ces deux champs de présence
// ({ lastSeenAt, isOnline }), jamais d'autre donnée du compte.

export const ONLINE_WINDOW_MS = 2 * 60 * 1000;

export interface Presence {
  /** Date ISO de la dernière activité, ou null si jamais vu. */
  lastSeenAt: string | null;
  /** true si lastSeenAt date de moins de 2 minutes. */
  isOnline: boolean;
}

export function toPresence(
  lastSeenAt: Date | string | null | undefined,
  now: number = Date.now(),
): Presence {
  if (!lastSeenAt) return { lastSeenAt: null, isOnline: false };
  const date = lastSeenAt instanceof Date ? lastSeenAt : new Date(lastSeenAt);
  const time = date.getTime();
  if (!Number.isFinite(time)) return { lastSeenAt: null, isOnline: false };
  return {
    lastSeenAt: date.toISOString(),
    isOnline: now - time < ONLINE_WINDOW_MS && time <= now + 5000,
  };
}
