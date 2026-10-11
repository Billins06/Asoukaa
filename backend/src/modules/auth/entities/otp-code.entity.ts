import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  JoinColumn,
  CreateDateColumn,
  Index,
} from 'typeorm';
import { User } from '../../users/entities/user.entity';

export enum OtpType {
  EMAIL_VERIFICATION = 'email_verification',
  PASSWORD_RESET     = 'réinitialisation du mot de passe',
}

// Index composite : verifyOtp() et sendOtp() cherchent systématiquement
// par (userId, type, isUsed) — sans lui, chaque vérification d'OTP scanne
// toute la table.
@Index(['userId', 'type', 'isUsed'])
@Entity('otp_codes')
export class OtpCode {

  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Index()
  @Column()
  userId: string;

  @ManyToOne(() => User, {
    onDelete: 'CASCADE',  // si le user est supprimé, ses OTPs le sont aussi
  })
  @JoinColumn({ name: 'userId' })
  user: User;

  // ⚠️ PRODUCTION : ce code doit être hashé en base de données
  // comme un mot de passe, pas stocké en clair
  // On hashe avec bcrypt avant d'insérer
  @Column({ length: 255 })
  code: string;

  @Column({
    type: 'enum',
    enum: OtpType,
  })
  type: OtpType;

  // Devient true après utilisation → ne peut plus être réutilisé
  @Column({ default: false })
  isUsed: boolean;

  // ⚠️ Nombre de tentatives de vérification échouées sur ce code.
  // Au-delà de MAX_OTP_ATTEMPTS (voir AuthService), le code est brûlé
  // (isUsed = true) : sans ce compteur, un code à 6 chiffres valable
  // 3 minutes se force en quelques secondes par script.
  @Column({ type: 'int', default: 0 })
  attempts: number;

  // ⚠️ PRODUCTION : toujours vérifier que cette date
  // n'est pas dépassée avant d'accepter le code
  @Index()
  @Column({ type: 'timestamp' })
  expiresAt: Date;

  @CreateDateColumn()
  createdAt: Date;
}