import { renderEmailLayout, escapeHtml } from './base-layout.template';

// Livraison indépendante (type B) : envoyé au DEMANDEUR quand un livreur
// accepte sa demande. Pas de CTA : asoukaa://delivery ouvre le tableau de
// bord livreur, pas le suivi côté demandeur.
export const independentDeliveryAcceptedTemplate = (prenom: string): string => {
  const body = `
    <p style="margin:12px 0 8px;font-size:14px;color:#6B6B72;line-height:1.6;text-align:center;">Il vous contactera prochainement pour les détails.</p>`;

  return renderEmailLayout({
    category: 'commande',
    badge: 'check',
    title: 'Un livreur a accepté votre demande',
    intro: `Bonjour <strong style="color:#3A3A40;">${escapeHtml(prenom)}</strong>, un livreur a accepté votre demande de livraison.`,
    body,
  });
};
