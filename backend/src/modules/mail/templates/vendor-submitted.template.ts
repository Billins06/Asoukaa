import { renderEmailLayout, escapeHtml } from './base-layout.template';

const infoRow = (text: string): string => `
  <tr>
    <td width="34" valign="top" style="padding:8px 0;">
      <table role="presentation" cellpadding="0" cellspacing="0"><tr><td width="22" height="22" align="center" valign="middle" style="width:22px;height:22px;border-radius:50%;background:#FBF0E1;color:#B45309;font-size:12px;font-weight:800;line-height:22px;">&#8226;</td></tr></table>
    </td>
    <td valign="middle" style="padding:8px 0;font-size:14px;color:#3A3A40;font-weight:500;">${text}</td>
  </tr>`;

export const vendorSubmittedTemplate = (prenom: string, shopName: string): string => {
  const body = `
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#FAF9F7;border-radius:16px;">
      <tr><td style="padding:14px 20px 0;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
          ${infoRow('Notre équipe vérifie votre dossier (pièce d\'identité, selfie, produits)')}
          ${infoRow('Vous recevrez un email dès que la décision sera prise')}
          ${infoRow('Ce délai est généralement de quelques heures à 2 jours ouvrés')}
        </table>
      </td></tr>
      <tr><td style="padding-bottom:14px;"></td></tr>
    </table>`;

  return renderEmailLayout({
    category: 'vendeur',
    title: 'Votre demande a bien été reçue',
    intro: `Bonjour <strong style="color:#3A3A40;">${escapeHtml(prenom)}</strong>, votre demande pour la boutique <strong style="color:#3A3A40;">"${escapeHtml(shopName)}"</strong> est en cours d'examen par notre équipe.`,
    body,
  });
};
