import { renderEmailLayout, escapeHtml, EmailCategory } from './base-layout.template';

// Email générique qui double une notification in-app (NotificationsService
// avec sendEmail: true). Le titre et le texte viennent de la notification.
export interface NotificationEmailData {
  prenom:   string;
  title:    string;
  message:  string;
  category: EmailCategory;
  /** Uniquement un lien asoukaa:// dont l'hôte est géré par l'app. */
  cta?:     { label: string; href: string };
}

export const notificationTemplate = (data: NotificationEmailData): string => {
  // Les titres de notification commencent souvent par un emoji ("✅ ...") :
  // on le retire du titre affiché (pas d'emoji dans la structure de l'email),
  // le sujet du mail garde le titre complet.
  const displayTitle = data.title.replace(/^[^\p{L}\p{N}]+/u, '') || data.title;

  const body = `
    <div style="padding:16px 18px;background:#FAF9F7;border-radius:14px;">
      <p style="margin:0;font-size:14px;color:#3A3A40;line-height:1.6;">${escapeHtml(data.message)}</p>
    </div>
    <p style="margin:20px 0 8px;font-size:14px;color:#6B6B72;line-height:1.6;">Connectez-vous à votre compte pour plus de détails.</p>
    <p style="margin:0 0 16px;font-size:12px;color:#ACACB2;line-height:1.6;">Vous recevez cet email car vous êtes inscrit(e) sur Asoukaa.</p>`;

  return renderEmailLayout({
    category: data.category,
    title: escapeHtml(displayTitle),
    intro: `Bonjour <strong style="color:#3A3A40;">${escapeHtml(data.prenom)}</strong>,`,
    body,
    cta: data.cta,
  });
};
