import { renderEmailLayout, escapeHtml } from './base-layout.template';

// Email envoyé à l'équipe support : nouveau ticket, ou réponse d'un
// utilisateur sur un ticket déjà résolu / fermé (ticket rouvert).
// Tout contenu venant de l'utilisateur est échappé ; les images ne sont
// jamais incluses (seulement leur nombre).
export interface SupportTicketTeamData {
  kind:            'created' | 'reopened';
  /** « TCK-000042 » */
  reference:       string;
  category:        string;
  subject:         string;
  /** Statut avant la réponse (kind = 'reopened'). */
  previousStatus?: string;
  userName:        string;
  userEmail:       string;
  userPhone:       string;
  userRoles:       string[];
  /** Numéro de commande lié, si le ticket en référence une. */
  orderNumber?:    string | null;
  excerpt:         string;
  attachmentCount: number;
}

const toHtml = (text: string): string =>
  escapeHtml(text).replace(/\r?\n/g, '<br/>');

const row = (label: string, value: string): string => `
      <tr>
        <td style="padding:8px 0;border-bottom:1px solid #F1F0ED;font-size:12px;color:#9A9AA1;font-weight:600;text-transform:uppercase;letter-spacing:0.04em;">${escapeHtml(label)}</td>
        <td align="right" style="padding:8px 0;border-bottom:1px solid #F1F0ED;font-size:14px;color:#17171A;">${value}</td>
      </tr>`;

export const supportTicketTeamTemplate = (data: SupportTicketTeamData): string => {
  const isReopen = data.kind === 'reopened';
  const attachments = data.attachmentCount > 0
    ? `<p style="margin:10px 0 0;font-size:12px;color:#9A9AA1;">${Number(data.attachmentCount)} image(s) jointe(s) (à consulter dans le back-office).</p>`
    : '';

  const body = `
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
      ${row('Ticket', `<strong>${escapeHtml(data.reference)}</strong>`)}
      ${row('Catégorie', escapeHtml(data.category))}
      ${row('Sujet', escapeHtml(data.subject))}
      ${isReopen && data.previousStatus ? row('Statut précédent', escapeHtml(data.previousStatus)) : ''}
      ${data.orderNumber ? row('Commande', `#${escapeHtml(data.orderNumber)}`) : ''}
      ${row('Utilisateur', escapeHtml(data.userName))}
      ${row('E-mail', escapeHtml(data.userEmail))}
      ${row('Téléphone', escapeHtml(data.userPhone))}
      ${row('Rôle(s)', escapeHtml(data.userRoles.join(', ') || '-'))}
    </table>
    <div style="margin-top:18px;padding:16px 18px;background:#FAF9F7;border-radius:14px;">
      <p style="margin:0;font-size:14px;color:#3A3A40;line-height:1.6;">${toHtml(data.excerpt)}</p>
      ${attachments}
    </div>
    <p style="margin:20px 0 16px;font-size:13px;color:#6B6B72;line-height:1.6;text-align:center;">Répondez depuis le back-office Asoukaa (section Support).</p>`;

  return renderEmailLayout({
    category: 'support',
    title: isReopen ? 'Un utilisateur a répondu à un ticket clos' : 'Nouveau ticket de support',
    intro: isReopen
      ? `Le ticket <strong style="color:#3A3A40;">${escapeHtml(data.reference)}</strong> a été rouvert par l'utilisateur.`
      : `Un nouveau ticket <strong style="color:#3A3A40;">${escapeHtml(data.reference)}</strong> vient d'être ouvert.`,
    body,
  });
};
