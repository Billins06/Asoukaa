import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  JoinColumn,
  CreateDateColumn,
  Index,
} from 'typeorm';
import { Order }    from '../../orders/entities/order.entity';
import { Delivery } from './delivery.entity';
import { User }      from '../../users/entities/user.entity';

// Qui a fourni la preuve.
export enum ProofRole {
  LIVREUR = 'livreur',
  VENDEUR = 'vendeur',
  CLIENT  = 'client',
}

// À quelle étape du parcours de la commande cette preuve correspond.
// Une seule table sert aux 3 chemins (Cas A = livreur interne,
// Cas B = retrait en boutique, Cas C = bus/taxi) pour ne pas dupliquer
// le même concept dans 3 tables différentes.
export enum ProofStage {
  // Cas A — le livreur récupère le colis chez le vendeur : photo du
  // colis + état déclaré. Déclenche automatiquement le passage de la
  // commande à "Expédiée".
  RAMASSAGE_LIVREUR   = 'ramassage_livreur',
  // Cas A — le livreur remet le colis au client : scan du QR code du
  // client + position GPS du livreur au moment du scan + signature du
  // client sur l'écran du livreur. Déclenche "Livrée".
  REMISE_CLIENT       = 'remise_client',
  // Cas B — le vendeur scanne le QR code du client venu retirer sa
  // commande en boutique. Déclenche directement "Livrée".
  RETRAIT_BOUTIQUE    = 'retrait_boutique',
  // Cas C — le vendeur remet le colis au transporteur (bus/taxi) :
  // photo du transporteur/colis + état déclaré. Déclenche "Expédiée".
  REMISE_TRANSPORTEUR = 'remise_transporteur',
  // Cas C — le client confirme lui-même avoir reçu le colis à
  // l'arrivée, avec une photo. Déclenche "Livrée".
  RECEPTION_CLIENT    = 'reception_client',
}

// Une preuve = un évènement immuable capturé à un instant précis du
// parcours de livraison. Selon l'étape (voir ProofStage), certains
// champs restent vides — c'est normal et prévu (ex : pas de signature
// pour une preuve de ramassage).
//
// ⚠️ Comme ActivityLog, une preuve n'est JAMAIS modifiée après sa
// création — pas de @UpdateDateColumn ici volontairement.
@Index(['orderId'])
@Index(['deliveryId'])
@Index(['stage'])
@Entity('delivery_proofs')
export class DeliveryProof {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  // Toujours renseigné — une preuve concerne toujours une commande.
  @Column()
  orderId: string;

  @ManyToOne(() => Order, {
    onDelete: 'RESTRICT',
    // ⚠️ RESTRICT — une preuve est une donnée probante, on ne veut
    // jamais la perdre automatiquement.
  })
  @JoinColumn({ name: 'orderId' })
  order: Order;

  // Renseigné uniquement pour le Cas A (un livreur interne intervient).
  // Reste null pour le retrait en boutique et le bus/taxi.
  @Column({ nullable: true })
  deliveryId: string | null;

  @ManyToOne(() => Delivery, {
    nullable: true,
    onDelete: 'RESTRICT',
  })
  @JoinColumn({ name: 'deliveryId' })
  delivery: Delivery | null;

  @Column({ type: 'enum', enum: ProofRole })
  role: ProofRole;

  @Column({ type: 'enum', enum: ProofStage })
  stage: ProofStage;

  // Lien vers la photo, quand l'étape en demande une (ramassage,
  // remise au transporteur, réception client). Doit pointer vers un
  // fichier réellement hébergé par notre propre stockage (voir
  // DeliveryProofsService.assertOwnUploadUrl) — jamais une URL
  // arbitraire fournie par le client.
  @Column({ type: 'varchar', nullable: true, length: 500 })
  photoUrl: string | null;

  // État du colis déclaré par le livreur ou le vendeur (ex: "bon état",
  // "carton légèrement abîmé"), pour les étapes de remise.
  @Column({ nullable: true, type: 'text' })
  etatColis: string | null;

  // Contenu brut du QR code scanné (remise au client, retrait en
  // boutique) — sert de preuve technique qu'un vrai scan a eu lieu.
  @Column({ type: 'varchar', nullable: true, length: 255 })
  qrScanValue: string | null;

  // Position GPS du livreur, capturée au moment précis où il scanne
  // le QR code du client (Cas A, remise finale uniquement).
  @Column({ type: 'double precision', nullable: true })
  latitude: number | null;

  @Column({ type: 'double precision', nullable: true })
  longitude: number | null;

  // Signature du client, dessinée sur l'écran du livreur au moment de
  // la remise (Cas A uniquement). Stockée en SVG/JSON de points, pas
  // en image — reste un champ texte volontairement.
  @Column({ nullable: true, type: 'text' })
  signatureData: string | null;

  // Qui a réellement soumis cette preuve (le compte connecté au
  // moment de l'appel) — jamais déduit d'un champ du corps de la
  // requête, toujours pris depuis le JWT côté service.
  @Column()
  createdByUserId: string;

  @ManyToOne(() => User, {
    onDelete: 'RESTRICT',
  })
  @JoinColumn({ name: 'createdByUserId' })
  createdByUser: User;

  @CreateDateColumn()
  createdAt: Date;
}
