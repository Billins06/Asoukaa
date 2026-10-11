// ─────────────────────────────────────────────────────────────────────────
// Système commun à tous les emails Asoukaa : même carte, même en-tête,
// même pied de page pour tous. Seule la couleur d'accent change selon la
// catégorie (à qui s'adresse l'email) pour qu'on reconnaisse d'un coup
// d'œil un email "Commande" d'un email "Livreur", par exemple.
//
// Conçu pour rester lisible dans Outlook/Gmail/Apple Mail : mise en page
// par tableaux, police web avec repli sur des polices systèmes, pas de
// SVG ni d'emoji dans les éléments structurants (juste des badges texte
// façon "✓" / "✕").
// ─────────────────────────────────────────────────────────────────────────

export type EmailCategory = 'commande' | 'livreur' | 'vendeur' | 'compte' | 'support';

/**
 * Échappe une valeur fournie par un utilisateur (prénom, nom de boutique,
 * motif...) avant de l'insérer dans le HTML d'un email, pour qu'un "<" ou
 * un "&" saisi ne casse pas la mise en page ni n'injecte de balises.
 */
export const escapeHtml = (value: unknown): string =>
  String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');

interface CategoryStyle {
  label: string;
  accent: string;
  tint: string;
}

const CATEGORY_STYLES: Record<EmailCategory, CategoryStyle> = {
  commande: { label: 'Commande', accent: '#FF6B00', tint: '#FFF1E6' },
  livreur:  { label: 'Livreur',  accent: '#0F9D74', tint: '#E7F7F1' },
  vendeur:  { label: 'Vendeur',  accent: '#B45309', tint: '#FBF0E1' },
  compte:   { label: 'Compte',   accent: '#4338CA', tint: '#EEECFC' },
  support:  { label: 'Support',  accent: '#FF6210', tint: '#FFF1E8' },
};

// Couleur neutre pour un badge "refusé", quelle que soit la catégorie : le
// refus est un statut, pas une identité de rôle. Le badge "Livreur" /
// "Vendeur" en haut à droite garde lui toujours sa couleur de famille.
const REJECTED_STYLE: CategoryStyle = { label: '', accent: '#B42318', tint: '#FDECEC' };

export interface EmailLayoutOptions {
  category: EmailCategory;
  /** Badge circulaire au centre du hero. Omis = pas de badge. */
  badge?: 'check' | 'cross';
  title: string;
  /** Texte d'intro sous le titre — HTML simple (strong) autorisé. */
  intro: string;
  /** Contenu HTML spécifique à cet email (tableaux, encarts...). */
  body: string;
  cta?: { label: string; href: string };
}

const FONT_STACK =
  "'Manrope',-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif";

const renderBadge = (badge: 'check' | 'cross' | undefined, style: CategoryStyle): string => {
  if (!badge) return '';
  const isCheck = badge === 'check';
  const glyphStyle = isCheck ? style : REJECTED_STYLE;
  const glyph = isCheck ? '&#10003;' : '&#10005;';
  return `
    <table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 auto 20px;">
      <tr>
        <td width="64" height="64" align="center" valign="middle" style="width:64px;height:64px;border-radius:50%;background:${glyphStyle.tint};font-size:26px;font-weight:800;color:${glyphStyle.accent};line-height:64px;font-family:${FONT_STACK};">${glyph}</td>
      </tr>
    </table>`;
};

const renderCta = (cta: { label: string; href: string } | undefined, accent: string): string => {
  if (!cta) return '';
  return `
        <tr>
          <td style="padding:32px 40px 40px;text-align:center;">
            <table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 auto;">
              <tr>
                <td style="border-radius:12px;background:${accent};">
                  <a href="${cta.href}" style="display:inline-block;padding:15px 34px;font-size:14px;font-weight:700;color:#FFFFFF;font-family:${FONT_STACK};">${cta.label}</a>
                </td>
              </tr>
            </table>
          </td>
        </tr>`;
};

export const renderEmailLayout = (opts: EmailLayoutOptions): string => {
  const style = CATEGORY_STYLES[opts.category];
  const year = new Date().getFullYear();

  return `<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1.0"/>
<title>Asoukaa</title>
<link href="https://fonts.googleapis.com/css2?family=Manrope:wght@400;600;700;800&display=swap" rel="stylesheet" type="text/css"/>
<!--[if mso]>
<style>table {border-collapse: collapse;}</style>
<![endif]-->
<style>
  body,table,td,a{-webkit-text-size-adjust:100%;-ms-text-size-adjust:100%;}
  img{border:0;line-height:100%;outline:none;text-decoration:none;}
  a{text-decoration:none;}
</style>
</head>
<body style="margin:0;padding:0;background:#F3F1EE;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F3F1EE;">
  <tr>
    <td align="center" style="padding:40px 16px;">
      <table role="presentation" width="600" cellpadding="0" cellspacing="0" style="width:600px;max-width:600px;background:#FFFFFF;border-radius:20px;border:1px solid #ECEAE6;font-family:${FONT_STACK};">
        <tr>
          <td style="padding:26px 40px;border-bottom:1px solid #ECEAE6;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
              <tr>
                <td style="font-size:18px;font-weight:800;color:#17171A;font-family:${FONT_STACK};">Asoukaa</td>
                <td align="right">
                  <span style="display:inline-block;font-size:11px;font-weight:700;letter-spacing:0.06em;text-transform:uppercase;padding:6px 14px;border-radius:999px;background:${style.tint};color:${style.accent};font-family:${FONT_STACK};">${style.label}</span>
                </td>
              </tr>
            </table>
          </td>
        </tr>
        <tr>
          <td style="padding:40px 40px 8px;text-align:center;">
            ${renderBadge(opts.badge, style)}
            <h1 style="margin:0 0 10px;font-size:24px;font-weight:800;color:#17171A;font-family:${FONT_STACK};">${opts.title}</h1>
            <p style="margin:0;font-size:15px;line-height:1.6;color:#6B6B72;font-family:${FONT_STACK};">${opts.intro}</p>
          </td>
        </tr>
        <tr>
          <td style="padding:8px 40px 0;">
            ${opts.body}
          </td>
        </tr>${renderCta(opts.cta, style.accent)}
        <tr>
          <td style="background:#FAF9F7;border-top:1px solid #ECEAE6;padding:24px 40px;text-align:center;">
            <p style="margin:0 0 6px;font-size:12px;color:#ACACB2;font-family:${FONT_STACK};">© ${year} Asoukaa · Cotonou, Bénin</p>
            <p style="margin:0;font-size:12px;color:#ACACB2;font-family:${FONT_STACK};">Aide · Confidentialité</p>
          </td>
        </tr>
      </table>
    </td>
  </tr>
</table>
</body>
</html>`;
};
