// Projections « publiques » d'une livraison et de son livreur.
//
// Liste blanche volontaire : un vendeur ou un client qui consulte le suivi
// d'une commande ne doit voir du livreur que ce dont il a besoin (nom,
// téléphone, photo de profil, type de véhicule). Tout champ ajouté plus
// tard à DeliveryAgentProfile ou User reste privé par défaut — avant ce
// filtre, partaient aussi : pièce d'identité, selfie, photo du véhicule,
// adresse précise, taux de gain, hash du mot de passe, e-mail, etc.
export function toPublicAgent(agent: any): any {
  if (!agent) return agent ?? null;
  const user = agent.user;
  return {
    id:          agent.id,
    vehicleType: agent.vehicleType,
    user: user
      ? {
          id:        user.id,
          prenom:    user.prenom,
          name:      user.name,
          phone:     user.phone,
          avatarUrl: user.avatarUrl,
        }
      : undefined,
  };
}

// Livraison telle qu'elle peut sortir vers le vendeur / le client : champs
// propres à la livraison + livreur filtré. (La relation `order` n'est pas
// recopiée ici : l'appelant l'a déjà.)
export function toPublicDelivery(delivery: any, opts: { withOrder?: boolean } = {}): any {
  if (!delivery) return delivery ?? null;
  const out: any = {
    id:               delivery.id,
    orderId:          delivery.orderId,
    agentId:          delivery.agentId,
    pickupAddress:    delivery.pickupAddress,
    adresseLivraison: delivery.adresseLivraison,
    latitude:         delivery.latitude,
    longitude:        delivery.longitude,
    status:           delivery.status,
    instructions:     delivery.instructions,
    pickedUpAt:       delivery.pickedUpAt,
    deliveredAt:      delivery.deliveredAt,
    createdAt:        delivery.createdAt,
    updatedAt:        delivery.updatedAt,
    agent:            delivery.agent ? toPublicAgent(delivery.agent) : null,
  };
  if (opts.withOrder && delivery.order) out.order = delivery.order;
  return out;
}

// Demandeur d'une course express, tel qu'il peut sortir vers le livreur.
export function toPublicRequester(requester: any): any {
  if (!requester) return requester ?? null;
  return {
    id:     requester.id,
    prenom: requester.prenom,
    phone:  requester.phone,
  };
}
