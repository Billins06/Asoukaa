import { renderEmailLayout, escapeHtml } from './base-layout.template';

export const agentUnblockedTemplate = (prenom: string): string => {
  const body = `
    <p style="margin:12px 0 8px;font-size:14px;color:#6B6B72;line-height:1.6;text-align:center;">Vous pouvez de nouveau vous mettre disponible pour livrer.</p>`;

  return renderEmailLayout({
    category: 'livreur',
    badge: 'check',
    title: 'Votre compte livreur a été réactivé',
    intro: `Bonjour <strong style="color:#3A3A40;">${escapeHtml(prenom)}</strong>, votre compte livreur a été réactivé par notre équipe.`,
    body,
    // Lien profond asoukaa://delivery : ouvre l'app sur le tableau de bord
    // livreur.
    cta: { label: 'Accéder à mon tableau de bord', href: 'asoukaa://delivery' },
  });
};
