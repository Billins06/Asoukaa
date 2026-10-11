import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  JoinColumn,
  CreateDateColumn,
  UpdateDateColumn,
  Index,
} from 'typeorm';
import { VendorProfile } from '../../users/entities/vendor-profile.entity';
import { AdminAccount } from '../../auth/entities/admin-account.entity';

// Demande de retrait de gains faite par un VENDEUR.
//
// Pendant de DeliveryEarning (delivery/entities/delivery-earning.entity.ts)
// cote vendeur, avec une difference importante : un gain livreur est CALCULE
// par le systeme a chaque livraison, alors qu'ici c'est le vendeur qui
// DEMANDE une somme. Le solde retirable n'est donc pas stocke : il est
// recalcule a la demande (voir VendorWithdrawalsService.getBalance).
//
// Aucun argent ne part automatiquement : l'admin fait le virement Mobile
// Money par ses propres moyens, puis marque la demande comme payee.
export enum VendorWithdrawalStatus {
  PENDING  = 'en attente', // demande soumise, virement pas encore fait
  PAID     = 'payé',       // l'admin a fait le virement et l'a confirme
  REJECTED = 'rejeté',     // l'admin a refuse la demande (motif obligatoire)
}

@Index(['vendorId'])
@Index(['status'])
@Index(['createdAt'])
@Entity('vendor_withdrawals')
export class VendorWithdrawal {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  vendorId: string;

  @ManyToOne(() => VendorProfile, {
    onDelete: 'RESTRICT',
    // RESTRICT comme pour Commission / Order : une demande de retrait est
    // une trace financiere, elle ne doit jamais disparaitre avec le profil.
  })
  @JoinColumn({ name: 'vendorId' })
  vendor: VendorProfile;

  // Montant demande par le vendeur (FCFA). Controle a la creation contre le
  // solde disponible ET contre VendorProfile.minWithdrawalAmount.
  @Column({ type: 'decimal', precision: 12, scale: 2 })
  montant: number;

  @Column({
    type: 'enum',
    enum: VendorWithdrawalStatus,
    default: VendorWithdrawalStatus.PENDING,
  })
  status: VendorWithdrawalStatus;

  // Operateur / moyen de paiement saisi par le vendeur au moment de la
  // demande (ex: "MTN", "Moov", "Wave"). Volontairement une chaine libre et
  // non une enumeration : la liste des operateurs Mobile Money du Benin
  // bouge, et l'admin paie a la main de toute facon.
  @Column({ length: 50 })
  paymentMethod: string;

  // Numero Mobile Money sur lequel l'admin doit envoyer l'argent.
  // Copie figee au moment de la demande : si le vendeur change ses
  // coordonnees de paiement ensuite, l'historique reste exact.
  @Column({ length: 20 })
  mobileNumber: string;

  // Commentaire de l'admin. Sert pour les DEUX decisions :
  //  - "payé"   : note libre (reference du virement, remarque...) -> optionnel
  //  - "rejeté" : MOTIF du refus -> obligatoire (voir RejectWithdrawalDto)
  // ATTENTION : `type: 'text'` explicite obligatoire avec le type TS
  // `string | null` (voir le commentaire dans vendor-profile.entity.ts).
  @Column({ type: 'text', nullable: true })
  noteAdmin: string | null;

  // Rempli uniquement au passage en "payé"
  @Column({ type: 'timestamp', nullable: true })
  paidAt: Date | null;

  // Admin qui a traite la demande (paiement OU rejet)
  @Column({ type: 'varchar', nullable: true })
  processedById: string | null;

  @ManyToOne(() => AdminAccount, { nullable: true })
  @JoinColumn({ name: 'processedById' })
  processedBy: AdminAccount;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
