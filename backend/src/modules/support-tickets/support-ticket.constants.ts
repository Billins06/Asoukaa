// Constantes partagées du module « Tickets de support ».
// Voir src/modules/support-tickets/.

// Catégories proposées par l'application (texte EXACT stocké en base).
export const TICKET_CATEGORIES = [
  'Commande',
  'Paiement',
  'Livraison',
  'Produit défectueux',
  'Remboursement', // simple catégorie : le remboursement reste un circuit séparé (payments/refund)
  'Compte',
  'Vendeur',
  'Autre',
] as const;

export type TicketCategory = (typeof TICKET_CATEGORIES)[number];

export enum TicketStatus {
  OUVERT   = 'ouvert',
  EN_COURS = 'en_cours',
  RESOLU   = 'resolu',
  FERME    = 'ferme',
}

export const TICKET_STATUSES: string[] = Object.values(TicketStatus);

export enum TicketAuthorType {
  USER  = 'user',
  ADMIN = 'admin',
}

export const TICKET_LIMITS = {
  SUBJECT_MIN:        3,
  SUBJECT_MAX:        150,
  BODY_MIN:           1,
  BODY_MAX:           4000,
  MAX_ATTACHMENTS:    3,
  MAX_URL_LENGTH:     500,
  PREVIEW_LENGTH:     120,
  NEW_TICKETS_PER_HOUR: 5,
  MAX_OPEN_TICKETS:   10,
  MESSAGES_PER_HOUR:  20,
  REOPEN_WINDOW_DAYS: 7,
  MAX_PAGE_SIZE:      50,
} as const;

// Nom affiché à l'utilisateur pour toute réponse d'un administrateur :
// l'identité réelle de l'admin n'est JAMAIS exposée côté application.
export const ADMIN_DISPLAY_NAME = 'Équipe Asoukaa';

// Numéro lisible : 42 -> « TCK-000042 ».
export const formatTicketNumber = (n: number | string): string =>
  `TCK-${String(n).padStart(6, '0')}`;
