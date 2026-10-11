// Préférences de notification (acheteur, vendeur, livreur).
//
// Stockage : users.notificationPrefs (jsonb) ne contient QUE les clés que
// l'utilisateur a réglées lui-même. Une clé absente prend la valeur par
// défaut de son profil (table ci-dessous), reprise des écrans Flutter
// actuels (buyer_/seller_/deliverer_profile_screen).

export const NOTIFICATION_PREF_KEYS = [
  'orders',         // acheteur : « Commandes & livraisons »
  'messages',       // messages de chat
  'payments',       // paiements / retraits / gains
  'promotions',     // promotions & offres
  'newOrders',      // vendeur : nouvelles commandes reçues
  'newDeliveries',  // livreur : nouvelles livraisons proposées
] as const;

export type NotificationPrefKey = (typeof NOTIFICATION_PREF_KEYS)[number];
export type NotificationPreferences = Record<NotificationPrefKey, boolean>;

// 'client' = acheteur pur ; 'pro' = a le rôle vendeur et/ou livreur.
export type PrefProfile = 'client' | 'pro';

// ⚠️ SEUL ENDROIT où les valeurs par défaut sont définies.
// Acheteur  (buyer_profile_screen)    : commandes oui, promotions oui,
//                                       messages oui (rien n'était coupé
//                                       avant l'introduction des préférences).
// Vendeur / livreur                   : messages oui, paiements oui,
//                                       promotions NON.
// Les clés sans interrupteur dans l'écran d'un rôle (ex. orders pour un
// vendeur) valent true : on ne coupe jamais ce que l'utilisateur ne peut
// pas régler.
export const PREF_DEFAULTS: Record<PrefProfile, NotificationPreferences> = {
  client: {
    orders:        true,
    messages:      true,
    payments:      true,
    promotions:    true,
    newOrders:     true,
    newDeliveries: true,
  },
  pro: {
    orders:        true,
    messages:      true,
    payments:      true,
    promotions:    false,
    newOrders:     true,
    newDeliveries: true,
  },
};

// Un utilisateur qui a le rôle vendeur ou livreur suit les valeurs par
// défaut « pro », sinon celles de l'acheteur.
export function profileForRoles(roles: readonly string[]): PrefProfile {
  return roles.some((r) => r === 'vendor' || r === 'delivery_agent')
    ? 'pro'
    : 'client';
}

// Valeurs effectives = défauts du profil, surchargés par les clés booléennes
// valides déjà enregistrées (tout le reste est ignoré).
export function mergePrefs(
  stored:  unknown,
  profile: PrefProfile,
): NotificationPreferences {
  const result: NotificationPreferences = { ...PREF_DEFAULTS[profile] };
  if (stored && typeof stored === 'object' && !Array.isArray(stored)) {
    for (const key of NOTIFICATION_PREF_KEYS) {
      const value = (stored as Record<string, unknown>)[key];
      if (typeof value === 'boolean') result[key] = value;
    }
  }
  return result;
}
