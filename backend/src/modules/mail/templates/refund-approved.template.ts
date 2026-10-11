import { renderEmailLayout, escapeHtml } from './base-layout.template';

export interface RefundApprovedData {
  prenom:      string;
  orderNumber: string;
  montant:     number;
  /** Id réel de la commande (UUID), pour le bouton "Voir ma commande". */
  orderId?:    string;
}

export const refundApprovedTemplate = (data: RefundApprovedData): string => {
  const body = `
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
      <tr>
        <td style="padding-bottom:16px;border-bottom:1px solid #F1F0ED;font-size:12px;color:#9A9AA1;font-weight:600;text-transform:uppercase;letter-spacing:0.04em;">N° de commande</td>
        <td align="right" style="padding-bottom:16px;border-bottom:1px solid #F1F0ED;font-size:14px;font-weight:700;color:#17171A;">#${escapeHtml(data.orderNumber)}</td>
      </tr>
      <tr>
        <td style="padding:16px 0 0;font-size:15px;font-weight:700;color:#17171A;">Montant remboursé</td>
        <td align="right" style="padding:16px 0 0;font-size:19px;font-weight:800;color:#FF6B00;">${Number(data.montant).toLocaleString('fr-FR')} FCFA</td>
      </tr>
    </table>
    <p style="margin:22px 0 8px;font-size:14px;color:#6B6B72;line-height:1.6;text-align:center;">Le montant sera crédité sous 3 à 5 jours ouvrables.</p>`;

  return renderEmailLayout({
    category: 'commande',
    badge: 'check',
    title: 'Remboursement approuvé',
    intro: `Bonjour <strong style="color:#3A3A40;">${escapeHtml(data.prenom)}</strong>, votre demande de remboursement pour la commande <strong style="color:#3A3A40;">#${escapeHtml(data.orderNumber)}</strong> a été approuvée.`,
    body,
    cta: data.orderId
      ? { label: 'Voir ma commande', href: `asoukaa://order?id=${encodeURIComponent(data.orderId)}` }
      : undefined,
  });
};
