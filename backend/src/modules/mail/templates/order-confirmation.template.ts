import { renderEmailLayout, escapeHtml } from './base-layout.template';

export interface OrderConfirmationData {
  prenom: string;
  orderNumber: string;
  items: { name: string; quantity: number; price: number }[];
  total: number;
  adresse: string;
  /** Id réel de la commande (UUID), pour le bouton "Suivre ma commande". */
  orderId?: string;
}

export const orderConfirmationTemplate = (data: OrderConfirmationData): string => {
  const itemsRows = data.items
    .map(
      (item) => `
      <tr>
        <td style="padding:14px 0;border-bottom:1px solid #F1F0ED;">
          <div style="font-size:14px;font-weight:600;color:#17171A;">${escapeHtml(item.name)}</div>
          <div style="font-size:13px;color:#9A9AA1;margin-top:3px;">Qté : ${item.quantity}</div>
        </td>
        <td align="right" style="padding:14px 0;border-bottom:1px solid #F1F0ED;font-size:14px;font-weight:700;color:#17171A;white-space:nowrap;">${item.price.toLocaleString('fr-FR')} FCFA</td>
      </tr>`,
    )
    .join('');

  const body = `
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
      <tr>
        <td style="padding-bottom:16px;border-bottom:1px solid #F1F0ED;font-size:12px;color:#9A9AA1;font-weight:600;text-transform:uppercase;letter-spacing:0.04em;">N° de commande</td>
        <td align="right" style="padding-bottom:16px;border-bottom:1px solid #F1F0ED;font-size:14px;font-weight:700;color:#17171A;">#${escapeHtml(data.orderNumber)}</td>
      </tr>
      ${itemsRows}
      <tr>
        <td style="padding:16px 0 0;font-size:15px;font-weight:700;color:#17171A;">Total</td>
        <td align="right" style="padding:16px 0 0;font-size:19px;font-weight:800;color:#FF6B00;">${data.total.toLocaleString('fr-FR')} FCFA</td>
      </tr>
    </table>
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin-top:22px;background:#FAF9F7;border-radius:14px;">
      <tr>
        <td style="padding:18px 20px;">
          <div style="font-size:12px;color:#9A9AA1;font-weight:600;text-transform:uppercase;letter-spacing:0.04em;margin-bottom:4px;">Livraison à</div>
          <div style="font-size:14px;color:#3A3A40;line-height:1.5;">${escapeHtml(data.adresse)}</div>
        </td>
      </tr>
    </table>`;

  return renderEmailLayout({
    category: 'commande',
    badge: 'check',
    title: 'Commande confirmée',
    intro: `Bonjour <strong style="color:#3A3A40;">${escapeHtml(data.prenom)}</strong>, merci pour votre confiance. Voici le récapitulatif de votre commande <strong style="color:#3A3A40;">#${escapeHtml(data.orderNumber)}</strong>.`,
    body,
    cta: data.orderId
      ? { label: 'Suivre ma commande', href: `asoukaa://order?id=${encodeURIComponent(data.orderId)}` }
      : undefined,
  });
};
