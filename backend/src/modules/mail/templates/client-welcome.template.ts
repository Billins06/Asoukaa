import { renderEmailLayout, escapeHtml } from './base-layout.template';

const infoRow = (text: string): string => `
  <tr>
    <td width="34" valign="top" style="padding:8px 0;">
      <table role="presentation" cellpadding="0" cellspacing="0"><tr><td width="22" height="22" align="center" valign="middle" style="width:22px;height:22px;border-radius:50%;background:#EEECFC;color:#4338CA;font-size:12px;font-weight:800;line-height:22px;">&#10003;</td></tr></table>
    </td>
    <td valign="middle" style="padding:8px 0;font-size:14px;color:#3A3A40;font-weight:500;">${text}</td>
  </tr>`;

export const clientWelcomeTemplate = (prenom: string): string => {
  const body = `
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#FAF9F7;border-radius:16px;">
      <tr><td style="padding:14px 20px 0;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
          ${infoRow('Parcourez des milliers de produits près de chez vous')}
          ${infoRow('Suivez vos commandes en temps réel')}
          ${infoRow('Discutez directement avec les boutiques')}
        </table>
      </td></tr>
      <tr><td style="padding-bottom:14px;"></td></tr>
    </table>`;

  return renderEmailLayout({
    category: 'compte',
    badge: 'check',
    title: 'Bienvenue sur Asoukaa !',
    intro: `Bonjour <strong style="color:#3A3A40;">${escapeHtml(prenom)}</strong>, votre compte est confirmé. Merci de nous avoir rejoints !`,
    body,
  });
};
