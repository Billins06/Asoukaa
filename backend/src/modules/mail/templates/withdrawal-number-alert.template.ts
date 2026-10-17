import { renderEmailLayout, escapeHtml } from './base-layout.template';

export interface WithdrawalNumberAlertData {
  prenom: string;
  /** Montant demandé (FCFA). */
  montant: number;
  /** Opérateur saisi (MTN, Moov...). */
  operateur: string;
  /** Numéro de destination DÉJÀ masqué (ex. ******2026) — jamais en clair. */
  maskedNumber: string;
  /** Date/heure de la demande, déjà mise en forme en français. */
  requestedAtLabel: string;
}

// E-mail d'information (pas de bouton, rien n'est bloqué) envoyé au vendeur
// quand il demande un retrait vers un numéro différent de d'habitude.
export const withdrawalNumberAlertTemplate = (data: WithdrawalNumberAlertData): string => {
  const body = `
    <div style="margin:20px 0 0;padding:18px 20px;background:#FFF1E6;border:1px solid #F5D3B8;border-radius:14px;">
      <p style="margin:0;font-size:14px;color:#3A3A40;line-height:1.6;">Une demande de retrait de <strong>${escapeHtml(data.montant)} FCFA</strong> a été faite le <strong>${escapeHtml(data.requestedAtLabel)}</strong> vers le numéro <strong>${escapeHtml(data.maskedNumber)}</strong> (${escapeHtml(data.operateur)}).</p>
    </div>
    <p style="margin:20px 0 0;font-size:14px;color:#3A3A40;line-height:1.6;">Ce numéro est différent de celui de votre dernier retrait ou de celui enregistré sur votre boutique.</p>
    <p style="margin:10px 0 0;font-size:14px;color:#3A3A40;line-height:1.6;"><strong>Si c'est bien vous</strong>, ignorez ce message.</p>
    <p style="margin:10px 0 24px;font-size:14px;color:#3A3A40;line-height:1.6;"><strong>Sinon</strong>, changez votre mot de passe sans attendre et contactez le support Asoukaa.</p>`;

  return renderEmailLayout({
    category: 'vendeur',
    title: 'Retrait vers un nouveau numéro',
    intro: `Bonjour <strong style="color:#3A3A40;">${escapeHtml(data.prenom)}</strong>, nous vous prévenons d'une demande de retrait de gains sur votre compte vendeur.`,
    body,
  });
};
