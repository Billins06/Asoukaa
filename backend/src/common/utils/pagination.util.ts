/**
 * Bornage de la pagination.
 *
 * ⚠️ Les contrôleurs faisaient `Number(limit) || 20` sans plafond : un appel
 * à `/products?limit=500000` chargeait tout le catalogue avec ses jointures
 * (images, variantes, catégories) en une seule requête — déni de service
 * trivial, sans authentification, sur les routes publiques.
 *
 * Toutes les listes paginées doivent passer par `normalizePagination()`.
 */

export const DEFAULT_PAGE_SIZE = 20;
export const MAX_PAGE_SIZE = 100;
/** Plafond du numéro de page : évite un `skip` hors limites (erreur Postgres). */
export const MAX_PAGE = 100000;

export interface Pagination {
  page: number;
  limit: number;
  skip: number;
}

/**
 * Borne le nombre d'éléments par page reçu du client : entier, > 0, et
 * plafonné à MAX_PAGE_SIZE. Toute valeur absurde (0, -5, "abc", 500000)
 * retombe sur `defaultLimit`.
 */
export function clampLimit(
  limit?: number | string,
  defaultLimit: number = DEFAULT_PAGE_SIZE,
): number {
  const parsed = Math.trunc(Number(limit));
  if (!Number.isFinite(parsed) || parsed <= 0) return defaultLimit;
  return Math.min(parsed, MAX_PAGE_SIZE);
}

/** Borne le numéro de page : entier entre 1 et MAX_PAGE. */
export function clampPage(page?: number | string): number {
  const parsed = Math.trunc(Number(page));
  if (!Number.isFinite(parsed) || parsed <= 0) return 1;
  return Math.min(parsed, MAX_PAGE);
}

export function normalizePagination(
  page?: number | string,
  limit?: number | string,
  defaultLimit: number = DEFAULT_PAGE_SIZE,
): Pagination {
  const parsedPage = Math.trunc(Number(page));
  const parsedLimit = Math.trunc(Number(limit));

  const safePage =
    Number.isFinite(parsedPage) && parsedPage > 0
      ? Math.min(parsedPage, MAX_PAGE)
      : 1;

  const safeLimit =
    Number.isFinite(parsedLimit) && parsedLimit > 0
      ? Math.min(parsedLimit, MAX_PAGE_SIZE)
      : defaultLimit;

  return {
    page: safePage,
    limit: safeLimit,
    skip: (safePage - 1) * safeLimit,
  };
}
