import { renderEmailLayout, escapeHtml } from './base-layout.template';

// Email envoyé à l'utilisateur quand l'équipe répond à son ticket.
// Tout contenu venant d'un utilisateur ou d'un admin est échappé.
export interface SupportTicketReplyData {
  prenom:          string;
  /** « TCK-000042 » */
  reference:       string;
  subject:         string;
  /** Extrait (déjà tronqué) de la réponse. */
  excerpt:         string;
  attachmentCount: number;
}

// Texte brut -> HTML sûr, sauts de ligne conservés.
const toHtml = (text: string): string =>
  escapeHtml(text).replace(/\r?\n/g, '<br/>');

export const supportTicketReplyTemplate = (data: SupportTicketReplyData): string => {
  const attachments = data.attachmentCount > 0
    ? `<p style="margin:10px 0 0;font-size:12px;color:#9A9AA1;">${Number(data.attachmentCount)} image(s) jointe(s) : à consulter dans l'application.</p>`
    : '';

  const body = `
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
      <tr>
        <td style="padding-bottom:12px;border-bottom:1px solid #F1F0ED;font-size:12px;color:#9A9AA1;font-weight:600;text-transform:uppercase;letter-spacing:0.04em;">Ticket</td>
        <td align="right" style="padding-bottom:12px;border-bottom:1px solid #F1F0ED;font-size:14px;font-weight:700;color:#17171A;">${escapeHtml(data.reference)}</td>
      </tr>
      <tr>
        <td colspan="2" style="padding:12px 0 16px;font-size:14px;color:#3A3A40;">${escapeHtml(data.subject)}</td>
      </tr>
    </table>
    <div style="padding:16px 18px;background:#FAF9F7;border-radius:14px;">
      <p style="margin:0 0 6px;font-size:12px;font-weight:700;color:#FF6210;">Équipe Asoukaa</p>
      <p style="margin:0;font-size:14px;color:#3A3A40;line-height:1.6;">${toHtml(data.excerpt)}</p>
      ${attachments}
    </div>
    <p style="margin:20px 0 8px;font-size:14px;color:#6B6B72;line-height:1.6;text-align:center;">Ouvrez l'application Asoukaa pour lire la réponse complète et y répondre.</p>
    <p style="margin:0 0 16px;font-size:12px;color:#ACACB2;line-height:1.6;text-align:center;">Merci de ne pas répondre directement à cet email.</p>`;

  return renderEmailLayout({
    category: 'support',
    title: 'Notre équipe vous a répondu',
    intro: `Bonjour <strong style="color:#3A3A40;">${escapeHtml(data.prenom)}</strong>, l'équipe Asoukaa a répondu à votre demande.`,
    body,
  });
};
