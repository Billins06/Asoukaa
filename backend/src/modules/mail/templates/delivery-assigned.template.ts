import { renderEmailLayout, escapeHtml } from './base-layout.template';

export interface DeliveryAssignedData {
  prenom:          string;
  pickupAddress:   string;
  deliveryAddress: string;
}

const infoRow = (label: string, value: string): string => `
  <tr>
    <td style="padding:10px 0;border-bottom:1px solid #ECEAE6;">
      <p style="margin:0 0 3px;font-size:11px;font-weight:700;letter-spacing:0.04em;text-transform:uppercase;color:#0F9D74;">${label}</p>
      <p style="margin:0;font-size:14px;color:#3A3A40;line-height:1.5;">${value}</p>
    </td>
  </tr>`;

export const deliveryAssignedTemplate = (data: DeliveryAssignedData): string => {
  const body = `
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#FAF9F7;border-radius:16px;padding:4px 20px;margin-top:8px;">
      ${infoRow('Adresse de récupération', escapeHtml(data.pickupAddress))}
      ${infoRow('Adresse de livraison', escapeHtml(data.deliveryAddress))}
    </table>
    `;

  return renderEmailLayout({
    category: 'livreur',
    title: 'Nouvelle livraison affectée',
    intro: `Bonjour <strong style="color:#3A3A40;">${escapeHtml(data.prenom)}</strong>, une nouvelle livraison vous a été affectée.`,
    body,
    // Lien profond asoukaa://delivery : ouvre l'app sur le tableau de bord
    // livreur, où se trouvent les détails et le bouton pour démarrer la
    // course (pas d'id de livraison spécifique transmis pour l'instant).
    cta: { label: 'Voir mes livraisons', href: 'asoukaa://delivery' },
  });
};
