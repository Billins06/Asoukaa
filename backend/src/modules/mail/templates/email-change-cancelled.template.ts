import { renderEmailLayout } from './base-layout.template';

// Envoyé à l'adresse « nouvelle » quand le propriétaire du compte a annulé
// le changement. Volontairement générique : on ne dit ni qui, ni quelle
// était l'ancienne adresse.
export const emailChangeCancelledTemplate = (): string => {
  const body = `
    <p style="margin:20px 0 24px;font-size:13px;color:#8B8B93;line-height:1.55;">Cette adresse n'est plus associée à ce compte et ne peut plus servir à s'y connecter. Si vous pensez qu'il s'agit d'une erreur, contactez le support Asoukaa.</p>`;

  return renderEmailLayout({
    category: 'compte',
    badge: 'cross',
    title: 'Changement d’adresse annulé',
    intro: 'Le propriétaire d’un compte Asoukaa a annulé le changement d’adresse email qui utilisait cette adresse.',
    body,
  });
};
