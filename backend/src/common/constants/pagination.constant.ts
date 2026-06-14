/**
 * Constantes de pagination pour limiter les requêtes et protéger la BD
 */
export const PAGINATION = {
  DEFAULT_LIMIT: 20,
  MAX_LIMIT: 100,
  MIN_LIMIT: 1,
  DEFAULT_PAGE: 1,
  MIN_PAGE: 1,
};

/**
 * Valide et normalise les paramètres de pagination
 */
export function normalizePagination(
  page?: number,
  limit?: number,
): { page: number; limit: number } {
  const validPage = Math.max(
    PAGINATION.MIN_PAGE,
    Math.floor(page || PAGINATION.DEFAULT_PAGE)
  );

  const validLimit = Math.max(
    PAGINATION.MIN_LIMIT,
    Math.min(
      limit || PAGINATION.DEFAULT_LIMIT,
      PAGINATION.MAX_LIMIT
    )
  );

  return { page: validPage, limit: validLimit };
}
