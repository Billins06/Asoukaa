import { renderEmailLayout, escapeHtml } from './base-layout.template';

const checklistRow = (text: string, accent: string, tint: string): string => `
  <tr>
    <td width="34" valign="top" style="padding:8px 0;">
      <table role="presentation" cellpadding="0" cellspacing="0"><tr><td width="22" height="22" align="center" valign="middle" style="width:22px;height:22px;border-radius:50%;background:${tint};color:${accent};font-size:12px;font-weight:800;line-height:22px;">&#10003;</td></tr></table>
    </td>
    <td valign="middle" style="padding:8px 0;font-size:14px;color:#3A3A40;font-weight:500;">${text}</td>
  </tr>`;

export const agentApprovedTemplate = (prenom: string): string => {
  const body = `
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#FAF9F7;border-radius:16px;">
      <tr><td style="padding:14px 20px 0;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
          ${checklistRow("Activez votre disponibilité dans l'appli", '#0F9D74', '#E7F7F1')}
          ${checklistRow('Acceptez vos premières livraisons', '#0F9D74', '#E7F7F1')}
          ${checklistRow('Construisez votre réputation, livraison après livraison', '#0F9D74', '#E7F7F1')}
        </table>
      </td></tr>
      <tr><td style="padding-bottom:14px;"></td></tr>
    </table>`;

  return renderEmailLayout({
    category: 'livreur',
    badge: 'check',
    title: "Vous êtes approuvé(e) comme livreur !",
    intro: `Félicitations <strong style="color:#3A3A40;">${escapeHtml(prenom)}</strong> ! Votre profil livreur a été validé par notre équipe.`,
    body,
    // Lien profond asoukaa://delivery : ouvre l'app sur le tableau de bord
    // livreur.
    cta: { label: 'Accéder à mon tableau de bord', href: 'asoukaa://delivery' },
  });
};
