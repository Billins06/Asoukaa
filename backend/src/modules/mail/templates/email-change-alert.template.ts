import { renderEmailLayout, escapeHtml } from './base-layout.template';

export interface EmailChangeAlertData {
  prenom: string;
  /** Nouvelle adresse déjà masquée (ex. j***@gmail.com) — jamais l'adresse complète. */
  maskedNewEmail: string;
  /** Date/heure du changement, déjà mise en forme en français. */
  changedAtLabel: string;
  /** Lien « Ce n'est pas moi » (contient le jeton brut, valable 7 jours). */
  revertUrl: string;
}

// Alerte envoyée à l'ANCIENNE adresse. Le lien ne fait qu'ouvrir une page de
// confirmation : rien n'est annulé tant que la personne n'appuie pas sur le
// bouton de cette page (les scanners de liens d'email ouvrent les URL seuls).
export const emailChangeAlertTemplate = (data: EmailChangeAlertData): string => {
  const url = escapeHtml(data.revertUrl);
  const body = `
    <div style="margin:20px 0 0;padding:18px 20px;background:#FFF1E6;border:1px solid #F5D3B8;border-radius:14px;">
      <p style="margin:0;font-size:14px;color:#3A3A40;line-height:1.6;">Votre adresse de connexion a été changée vers <strong>${escapeHtml(data.maskedNewEmail)}</strong> le <strong>${escapeHtml(data.changedAtLabel)}</strong>.</p>
    </div>
    <p style="margin:20px 0 0;font-size:14px;color:#3A3A40;line-height:1.6;"><strong>Si c'est bien vous</strong>, ignorez ce message.</p>
    <p style="margin:10px 0 0;font-size:14px;color:#3A3A40;line-height:1.6;"><strong>Sinon</strong>, appuyez sur « Ce n'est pas moi » (lien valable 7 jours) : vous pourrez alors récupérer votre compte.</p>
    <p style="margin:20px 0 24px;font-size:12px;color:#8B8B93;line-height:1.55;word-break:break-all;">Si le bouton ne fonctionne pas, copiez ce lien dans votre navigateur :<br/>${url}</p>`;

  return renderEmailLayout({
    category: 'compte',
    title: 'Votre adresse de connexion a changé',
    intro: `Bonjour <strong style="color:#3A3A40;">${escapeHtml(data.prenom)}</strong>, nous vous écrivons pour vous prévenir d'une modification importante sur votre compte Asoukaa.`,
    body,
    cta: { label: 'Ce n&#39;est pas moi', href: url },
  });
};
