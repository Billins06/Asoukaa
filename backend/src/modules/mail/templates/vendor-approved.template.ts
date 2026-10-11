import { renderEmailLayout, escapeHtml } from './base-layout.template';

const checklistRow = (text: string, accent: string, tint: string): string => `
  <tr>
    <td width="34" valign="top" style="padding:8px 0;">
      <table role="presentation" cellpadding="0" cellspacing="0"><tr><td width="22" height="22" align="center" valign="middle" style="width:22px;height:22px;border-radius:50%;background:${tint};color:${accent};font-size:12px;font-weight:800;line-height:22px;">&#10003;</td></tr></table>
    </td>
    <td valign="middle" style="padding:8px 0;font-size:14px;color:#3A3A40;font-weight:500;">${text}</td>
  </tr>`;

export const vendorApprovedTemplate = (prenom: string, shopName: string): string => {
  const body = `
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#FAF9F7;border-radius:16px;">
      <tr><td style="padding:14px 20px 0;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
          ${checklistRow('Complétez votre profil boutique (logo, bannière)', '#B45309', '#FBF0E1')}
          ${checklistRow('Ajoutez vos premiers produits', '#B45309', '#FBF0E1')}
          ${checklistRow('Configurez vos informations de paiement', '#B45309', '#FBF0E1')}
        </table>
      </td></tr>
      <tr><td style="padding-bottom:14px;"></td></tr>
    </table>`;

  return renderEmailLayout({
    category: 'vendeur',
    badge: 'check',
    title: 'Votre boutique est approuvée !',
    intro: `Félicitations <strong style="color:#3A3A40;">${escapeHtml(prenom)}</strong> ! Votre boutique <strong style="color:#3A3A40;">"${escapeHtml(shopName)}"</strong> a été validée par notre équipe.`,
    body,
    // Lien profond asoukaa://vendor-dashboard : ouvre l'app directement sur
    // le tableau de bord vendeur.
    cta: { label: 'Accéder à mon tableau de bord', href: 'asoukaa://vendor-dashboard' },
  });
};
