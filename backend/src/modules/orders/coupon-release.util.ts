import { EntityManager } from 'typeorm';

// TypeORM renvoie [lignes, nombre] pour un DELETE ... RETURNING et
// directement les lignes pour un SELECT.
function rowsOf(res: any): any[] {
  if (!Array.isArray(res)) return [];
  if (res.length === 2 && Array.isArray(res[0]) && typeof res[1] === 'number') {
    return res[0];
  }
  return res;
}

// Libère l'usage d'un coupon consommé par une commande qui ne sera pas payée
// (annulation automatique d'une commande jamais payée, annulation admin d'une
// commande non payée) : supprime la ligne coupon_usages de la commande (le
// client peut alors réutiliser le code) et décrémente coupons.usedCount.
// Doit être appelée DANS la transaction qui annule la commande.
// Retourne true si un usage a été libéré.
export async function releaseCouponForOrder(
  manager: EntityManager,
  orderId: string,
): Promise<boolean> {
  const released = rowsOf(
    await manager.query(
      `DELETE FROM "coupon_usages" WHERE "orderId" = $1 RETURNING "couponId"`,
      [orderId],
    ),
  );

  for (const row of released) {
    await manager.query(
      `UPDATE "coupons" SET "usedCount" = GREATEST("usedCount" - 1, 0) WHERE "id" = $1`,
      [row.couponId],
    );
  }

  return released.length > 0;
}
