import { renderEmailLayout, escapeHtml } from './base-layout.template';

export const refundRejectedTemplate = (
  prenom: string,
  orderNumber: string,
  motif?: string | null,
): string => {
  // Le motif est saisi par un admin mais reste du texte libre : échappé.
  const motifBlock = motif && motif.trim()
    ? `<div style="margin:12px 0 0;padding:16px 18px;background:#FAF9F7;border-radius:14px;">
      <p style="margin:0 0 6px;font-size:12px;color:#9A9AA1;font-weight:600;text-transform:uppercase;letter-spacing:0.04em;">Motif</p>
      <p style="margin:0;font-size:14px;color:#3A3A40;line-height:1.6;">${escapeHtml(motif.trim()).replace(/\r?\n/g, '<br/>')}</p>
    </div>`
    : '';
  const body = `${motifBlock}
    <p style="margin:12px 0 8px;font-size:14px;color:#6B6B72;line-height:1.6;text-align:center;">Pour plus d'informations, contactez notre support.</p>`;

  return renderEmailLayout({
    category: 'commande',
    badge: 'cross',
    title: 'Remboursement non approuvé',
    intro: `Bonjour <strong style="color:#3A3A40;">${escapeHtml(prenom)}</strong>, votre demande de remboursement pour la commande <strong style="color:#3A3A40;">#${escapeHtml(orderNumber)}</strong> n'a pas pu être approuvée.`,
    body,
  });
};
