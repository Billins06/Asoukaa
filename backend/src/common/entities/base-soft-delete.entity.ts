import {
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  DeleteDateColumn,
} from 'typeorm';

/**
 * Base entity avec support du soft delete
 * Les entités qui héritent de cette classe peuvent être "supprimées" logiquement
 * sans être réellement effacées de la base de données
 */
export abstract class BaseSoftDeleteEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;

  /**
   * Date de suppression logique (soft delete)
   * Si cette colonne est NULL, l'enregistrement n'est pas supprimé
   * Si elle a une valeur, l'enregistrement est considéré comme supprimé
   */
  @DeleteDateColumn({ nullable: true })
  deletedAt: Date | null;

  /**
   * Indique si l'enregistrement est supprimé
   */
  get isDeleted(): boolean {
    return this.deletedAt !== null;
  }
}

/**
 * Conseils d'utilisation :
 *
 * 1. Dans votre entity, héritez de BaseSoftDeleteEntity :
 *    export class Product extends BaseSoftDeleteEntity { ... }
 *
 * 2. Quand vous interrogez la base, utilisez withDeleted() pour inclure les supprimés :
 *    this.repo.find()  // Exclut les supprimés par défaut
 *    this.repo.withDeleted().find()  // Inclut les supprimés
 *
 * 3. Pour supprimer un enregistrement (soft delete) :
 *    await this.repo.softRemove(entity)
 *
 * 4. Pour supprimer définitivement (hard delete) :
 *    await this.repo.remove(entity)
 */
