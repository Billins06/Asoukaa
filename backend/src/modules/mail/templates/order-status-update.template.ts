import { renderEmailLayout, escapeHtml } from './base-layout.template';

export interface OrderStatusUpdateData {
  prenom: string;
  orderNumber: string;
  status: string; // 'en attente' | 'en cours' | 'expedié' | 'livré' | 'annulé'
  motif?: string;
  /** Id réel de la commande (UUID), pour le bouton "Suivre ma commande". */
  orderId?: string;
}

const STATUS_LABELS: Record<string, string> = {
  'en attente': 'En attente',
  'en cours': 'En cours de préparation',
  'livreur affecté': 'Livreur affecté',
  'expedié': 'Expédiée',
  'en transit': 'En transit',
  'livré': 'Livrée',
  'annulé': 'Annulée',
};

export const orderStatusUpdateTemplate = (data: OrderStatusUpdateData): string => {
  const label = STATUS_LABELS[data.status] ?? data.status;
  const isCancelled = data.status === 'annulé';
  const statusColor = isCancelled ? '#B42318' : '#FF6B00';

  const motifBlock = data.motif
    ? `<div style="margin-top:16px;padding:16px 18px;background:#FDECEC;border-radius:14px;">
         <p style="margin:0 0 4px;font-size:13px;font-weight:700;color:#B42318;">Motif</p>
         <p style="margin:0;font-size:13px;color:#8A2A20;line-height:1.55;">${escapeHtml(data.motif)}</p>
       </div>`
    : '';

  const body = `
    <div style="text-align:center;padding:8px 0 4px;">
      <span style="display:inline-block;font-size:18px;font-weight:800;color:${statusColor};">${escapeHtml(label)}</span>
    </div>
    ${motifBlock}`;

  return renderEmailLayout({
    category: 'commande',
    badge: isCancelled ? 'cross' : 'check',
    title: 'Mise à jour de votre commande',
    intro: `Bonjour <strong style="color:#3A3A40;">${escapeHtml(data.prenom)}</strong>, votre commande <strong style="color:#3A3A40;">#${escapeHtml(data.orderNumber)}</strong> est maintenant :`,
    body,
    // Lien profond asoukaa://order?id=... : ouvre directement le suivi de
    // cette commande chez qui a déjà l'app installée. Pas de CTA si on n'a
    // pas l'id réel (compatibilité avec d'anciens appels non mis à jour).
    cta: data.orderId
      ? { label: 'Suivre ma commande', href: `asoukaa://order?id=${encodeURIComponent(data.orderId)}` }
      : undefined,
  });
};
