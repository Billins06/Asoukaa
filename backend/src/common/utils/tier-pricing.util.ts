/**
 * Prix dégressifs (paliers de quantité — table product_tier_prices).
 *
 * Règle UNIQUE utilisée partout où le backend fixe un prix unitaire
 * (panier, commande depuis le panier, commande initiée par le vendeur) :
 *   - on retient le palier dont la minQuantity est la PLUS HAUTE tout en
 *     restant <= à la quantité achetée ;
 *   - le prix unitaire appliqué est le prix de ce palier, plafonné au prix
 *     normal de la variante (un palier mal saisi, plus cher que le prix
 *     normal, ne doit jamais faire payer plus au client) ;
 *   - aucun palier applicable → prix normal de la variante.
 *
 * maxQuantity est volontairement ignoré ici : c'est la minQuantity du palier
 * suivant qui fait office de borne, et le dernier palier est illimité.
 *
 * ⚠️ Le Flutter (fiche produit) reproduit exactement cette règle pour
 * l'affichage, mais c'est ce calcul serveur qui fait foi.
 */
export interface TierPriceLike {
  minQuantity: number | string;
  price:       number | string;
}

export function resolveTierUnitPrice(
  basePrice: number | string,
  tiers:     TierPriceLike[] | null | undefined,
  quantity:  number,
): number {
  const base = Number(basePrice);
  const qty  = Number(quantity);

  if (!Array.isArray(tiers) || tiers.length === 0) return base;
  if (!Number.isFinite(qty) || qty <= 0) return base;

  let bestMin:   number | null = null;
  let bestPrice: number | null = null;

  for (const tier of tiers) {
    const min   = Number(tier.minQuantity);
    const price = Number(tier.price);
    if (!Number.isFinite(min) || !Number.isFinite(price) || price <= 0) continue;
    if (min <= qty && (bestMin === null || min > bestMin)) {
      bestMin   = min;
      bestPrice = price;
    }
  }

  if (bestPrice === null) return base;

  const unit = Number.isFinite(base) && base > 0
    ? Math.min(base, bestPrice)
    : bestPrice;

  return Number(unit.toFixed(2));
}
