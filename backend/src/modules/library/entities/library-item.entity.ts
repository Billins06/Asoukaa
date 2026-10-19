import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  Index,
  Unique,
  CreateDateColumn,
} from 'typeorm';

// Bibliothèque d'un client : UN livre numérique acheté = UNE ligne.
//  - unique (userId, productId) : un seul achat par client et par livre ;
//  - créée par PaymentsService.completeDigitalOrder (dans la transaction du
//    paiement) ;
//  - `revokedAt` renseigné quand le livre est remboursé : l'accès est retiré ;
//  - `downloadCount` / `firstDownloadedAt` : nombre de liens de téléchargement
//    délivrés (sert à juger « jamais téléchargé » lors d'un remboursement).
// Table créée par la migration 1791850000000-AddDigitalBooks.
@Unique('UQ_library_items_user_product', ['userId', 'productId'])
@Index('IDX_library_items_orderId', ['orderId'])
@Entity('library_items')
export class LibraryItem {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ type: 'uuid' })
  userId: string;

  @Column({ type: 'uuid' })
  productId: string;

  @Column({ type: 'uuid' })
  orderId: string;

  @Column({ type: 'int', default: 0 })
  downloadCount: number;

  @Column({ type: 'timestamp', nullable: true })
  firstDownloadedAt: Date | null;

  @Column({ type: 'timestamp', nullable: true })
  lastDownloadedAt: Date | null;

  @Column({ type: 'timestamp', nullable: true })
  revokedAt: Date | null;

  @Column({ type: 'varchar', length: 300, nullable: true })
  revokedReason: string | null;

  @CreateDateColumn()
  createdAt: Date;
}
