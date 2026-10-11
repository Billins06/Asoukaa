import { renderEmailLayout, escapeHtml } from './base-layout.template';

export const agentBlockedTemplate = (prenom: string): string => {
  const body = `
    <div style="padding:16px 18px;background:#FDECEC;border-radius:14px;">
      <p style="margin:0 0 4px;font-size:13px;font-weight:700;color:#B42318;">Compte suspendu</p>
      <p style="margin:0;font-size:13px;color:#8A2A20;line-height:1.55;">Vous ne pouvez plus vous mettre disponible ni accepter de livraisons pour le moment.</p>
    </div>
    <p style="margin:20px 0 24px;font-size:14px;color:#6B6B72;line-height:1.6;">Pour plus d'informations, contactez notre support.</p>`;

  return renderEmailLayout({
    category: 'livreur',
    badge: 'cross',
    title: 'Votre compte livreur a été suspendu',
    intro: `Bonjour <strong style="color:#3A3A40;">${escapeHtml(prenom)}</strong>, votre compte livreur a été suspendu par notre équipe.`,
    body,
  });
};
