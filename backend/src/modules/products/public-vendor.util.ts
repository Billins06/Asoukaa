import { toPresence } from '../presence/presence.util';

// Fiche vendeur « publique » : la seule forme de vendeur qui doit sortir
// vers un acheteur ou un visiteur (liste/fiche produit, panier, liste de
// souhaits, commandes du client).
//
// Liste blanche volontaire : tout champ ajouté plus tard à VendorProfile
// (documents, coordonnées de paiement, statut interne, e-mail du compte...)
// reste privé par défaut. Avant ce filtre, toute la fiche partait vers
// l'appli : liens de la pièce d'identité et du selfie, coordonnées de
// paiement (chiffrées), e-mail et téléphone du compte.
export function toPublicVendor(vendor: any): any {
  if (!vendor) return vendor;
  // Présence du propriétaire (« En ligne / Vu à … ») : UNIQUEMENT
  // { lastSeenAt, isOnline }, dérivés de vendor.user.lastSeenAt quand le
  // compte du vendeur a été chargé avec la fiche (fiche produit, liste de
  // conversations). Sans lastSeenAt chargé, les deux champs sont omis.
  const owner = vendor.user;
  const presence =
    owner && typeof owner === 'object' && owner.lastSeenAt !== undefined
      ? toPresence(owner.lastSeenAt)
      : {};
  return {
    ...presence,
    id:           vendor.id,
    userId:       vendor.userId,
    shopName:     vendor.shopName,
    shopAddress:  vendor.shopAddress,
    activityType: vendor.activityType,
    description:  vendor.description,
    logoUrl:      vendor.logoUrl,
    bannerUrl:    vendor.bannerUrl,
    // Forme historique attendue par l'appli : vendor.user.id
    user:         vendor.userId ? { id: vendor.userId } : undefined,
  };
}
