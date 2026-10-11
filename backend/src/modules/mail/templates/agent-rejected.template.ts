import { renderEmailLayout, escapeHtml } from './base-layout.template';

export const agentRejectedTemplate = (prenom: string, motif: string): string => {
  const body = `
    <div style="padding:16px 18px;background:#FDECEC;border-radius:14px;">
      <p style="margin:0 0 4px;font-size:13px;font-weight:700;color:#B42318;">Motif du refus</p>
      <p style="margin:0;font-size:13px;color:#8A2A20;line-height:1.55;">${escapeHtml(motif)}</p>
    </div>
    <p style="margin:20px 0 24px;font-size:14px;color:#6B6B72;line-height:1.6;">Vous pouvez corriger les points mentionnés et soumettre à nouveau votre demande depuis l'application.</p>`;

  return renderEmailLayout({
    category: 'livreur',
    badge: 'cross',
    title: 'Demande livreur non approuvée',
    intro: `Bonjour <strong style="color:#3A3A40;">${escapeHtml(prenom)}</strong>, votre demande pour devenir livreur Asoukaa n'a pas pu être approuvée.`,
    body,
  });
};
