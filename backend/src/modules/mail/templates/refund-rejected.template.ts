import { renderEmailLayout, escapeHtml } from './base-layout.template';

export const refundRejectedTemplate = (prenom: string, orderNumber: string): string => {
  const body = `
    <p style="margin:12px 0 8px;font-size:14px;color:#6B6B72;line-height:1.6;text-align:center;">Pour plus d'informations, contactez notre support.</p>`;

  return renderEmailLayout({
    category: 'commande',
    badge: 'cross',
    title: 'Remboursement non approuvé',
    intro: `Bonjour <strong style="color:#3A3A40;">${escapeHtml(prenom)}</strong>, votre demande de remboursement pour la commande <strong style="color:#3A3A40;">#${escapeHtml(orderNumber)}</strong> n'a pas pu être approuvée.`,
    body,
  });
};
