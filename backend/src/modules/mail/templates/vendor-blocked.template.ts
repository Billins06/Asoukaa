import { renderEmailLayout, escapeHtml } from './base-layout.template';

export const vendorBlockedTemplate = (prenom: string, shopName: string): string => {
  const body = `
    <div style="padding:16px 18px;background:#FDECEC;border-radius:14px;">
      <p style="margin:0 0 4px;font-size:13px;font-weight:700;color:#B42318;">Boutique suspendue</p>
      <p style="margin:0;font-size:13px;color:#8A2A20;line-height:1.55;">Vos produits ne sont plus visibles et vous ne pouvez plus recevoir de commandes pour le moment.</p>
    </div>
    <p style="margin:20px 0 24px;font-size:14px;color:#6B6B72;line-height:1.6;">Pour plus d'informations, contactez notre support.</p>`;

  return renderEmailLayout({
    category: 'vendeur',
    badge: 'cross',
    title: 'Votre boutique a été suspendue',
    intro: `Bonjour <strong style="color:#3A3A40;">${escapeHtml(prenom)}</strong>, votre boutique <strong style="color:#3A3A40;">"${escapeHtml(shopName)}"</strong> a été suspendue par notre équipe.`,
    body,
  });
};
