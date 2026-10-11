import { renderEmailLayout, escapeHtml } from './base-layout.template';

export const vendorUnblockedTemplate = (prenom: string, shopName: string): string => {
  const body = `
    <p style="margin:12px 0 8px;font-size:14px;color:#6B6B72;line-height:1.6;text-align:center;">Vous pouvez de nouveau vendre sur Asoukaa.</p>`;

  return renderEmailLayout({
    category: 'vendeur',
    badge: 'check',
    title: 'Votre boutique a été réactivée',
    intro: `Bonjour <strong style="color:#3A3A40;">${escapeHtml(prenom)}</strong>, votre boutique <strong style="color:#3A3A40;">"${escapeHtml(shopName)}"</strong> a été réactivée par notre équipe.`,
    body,
    // Lien profond asoukaa://vendor-dashboard : ouvre l'app directement sur
    // le tableau de bord vendeur.
    cta: { label: 'Accéder à mon tableau de bord', href: 'asoukaa://vendor-dashboard' },
  });
};
