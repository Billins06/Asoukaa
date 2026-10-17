import { renderEmailLayout, escapeHtml } from './base-layout.template';

// E-mail envoyé à l'ÉQUIPE (adresse SUPPORT_TEAM_EMAIL) quand un utilisateur
// répond « Ce n'est pas moi » à un changement d'adresse e-mail : compte
// potentiellement compromis. Toutes les données viennent d'un utilisateur ou
// d'un état de compte : tout passe par escapeHtml. Les adresses sont déjà
// masquées (j***@gmail.com), jamais en clair.
export interface SecurityAlertTeamData {
  userId:         string;
  prenom:         string;
  /** « restored » : adresse d'origine rétablie ; « not_restored » : compte bloqué. */
  outcome:        'restored' | 'not_restored';
  maskedOldEmail: string;
  maskedNewEmail: string;
  /** Date/heure déjà mise en forme en français. */
  dateLabel:      string;
}

const row = (label: string, value: string): string => `
      <tr>
        <td style="padding:8px 0;border-bottom:1px solid #F1F0ED;font-size:12px;color:#9A9AA1;font-weight:600;text-transform:uppercase;letter-spacing:0.04em;">${escapeHtml(label)}</td>
        <td align="right" style="padding:8px 0;border-bottom:1px solid #F1F0ED;font-size:14px;color:#17171A;">${value}</td>
      </tr>`;

export const securityAlertTeamTemplate = (data: SecurityAlertTeamData): string => {
  const restored = data.outcome === 'restored';
  const consigne = restored
    ? "L'adresse d'origine a été rétablie, les sessions ont été coupées et le mot de passe invalidé. Vérifiez que le propriétaire a bien récupéré son compte."
    : "L'adresse d'origine n'a PAS pu être rétablie (déjà utilisée par un autre compte) : le compte a été bloqué par précaution. Une vérification manuelle est requise.";

  const body = `
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
      ${row('Utilisateur', escapeHtml(data.prenom))}
      ${row('Identifiant', escapeHtml(data.userId))}
      ${row('Ancienne adresse', escapeHtml(data.maskedOldEmail))}
      ${row('Nouvelle adresse', escapeHtml(data.maskedNewEmail))}
      ${row('Date', escapeHtml(data.dateLabel))}
      ${row('Résultat', escapeHtml(restored ? 'Adresse rétablie' : 'Compte bloqué'))}
    </table>
    <div style="margin-top:18px;padding:16px 18px;background:#FFF1E6;border:1px solid #F5D3B8;border-radius:14px;">
      <p style="margin:0;font-size:14px;color:#3A3A40;line-height:1.6;">${escapeHtml(consigne)}</p>
    </div>
    <p style="margin:20px 0 16px;font-size:13px;color:#6B6B72;line-height:1.6;text-align:center;">Consultez l'alerte dans le back-office Asoukaa (fiche utilisateur) puis acquittez-la une fois traitée.</p>`;

  return renderEmailLayout({
    category: 'support',
    title: 'Alerte de sécurité : « Ce n\'est pas moi »',
    intro: `Un utilisateur affirme ne pas être à l'origine du changement d'adresse e-mail de son compte (<strong style="color:#3A3A40;">${escapeHtml(data.prenom)}</strong>).`,
    body,
  });
};
