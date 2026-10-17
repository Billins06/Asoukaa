import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as crypto from 'crypto';

@Injectable()
export class EncryptionService {
  private readonly algorithm = 'aes-256-gcm';

  constructor(private configService: ConfigService) {}

  /**
   * Chiffre un objet sensible (données bancaires, etc.)
   */
  encrypt(data: any): string {
    // La clé est lue HORS du try/catch : une clé invalide doit remonter comme
    // erreur de configuration claire (503), pas comme « Encryption failed ».
    const key = this.getEncryptionKey();
    try {
      const iv = crypto.randomBytes(16);
      const cipher = crypto.createCipheriv(this.algorithm, key, iv);

      const plaintext = JSON.stringify(data);
      let encrypted = cipher.update(plaintext, 'utf8', 'hex');
      encrypted += cipher.final('hex');

      const authTag = cipher.getAuthTag();
      const result = `${iv.toString('hex')}:${authTag.toString('hex')}:${encrypted}`;

      return result;
    } catch (error) {
      throw new Error(`Encryption failed: ${error.message}`);
    }
  }

  /**
   * Déchiffre un objet sensible
   */
  decrypt(encryptedData: string): any {
    const key = this.getEncryptionKey();
    try {
      const parts = encryptedData.split(':');

      if (parts.length !== 3) {
        throw new Error('Invalid encrypted data format');
      }

      const iv = Buffer.from(parts[0], 'hex');
      const authTag = Buffer.from(parts[1], 'hex');
      const encrypted = parts[2];

      const decipher = crypto.createDecipheriv(this.algorithm, key, iv);
      decipher.setAuthTag(authTag);

      let decrypted = decipher.update(encrypted, 'hex', 'utf8');
      decrypted += decipher.final('utf8');

      return JSON.parse(decrypted);
    } catch (error) {
      throw new Error(`Decryption failed: ${error.message}`);
    }
  }

  /**
   * Récupère la clé de chiffrement depuis les variables d'env
   */
  private getEncryptionKey(): Buffer {
    const keyEnv = this.configService.get<string>('ENCRYPTION_KEY');
    // Exactement 64 caractères hexadécimaux (= 32 octets pour AES-256).
    // Une clé de 60 caractères ou contenant des caractères non hexadécimaux
    // est refusée ici : AUCUNE donnée n'a donc jamais pu être chiffrée avec
    // une telle clé (voir aussi la vérification au démarrage :
    // src/config/env.validation.ts).
    if (!keyEnv || !/^[0-9a-fA-F]{64}$/.test(keyEnv)) {
      throw new ServiceUnavailableException(
        'Le chiffrement n\'est pas configuré correctement sur le serveur ' +
        '(ENCRYPTION_KEY invalide). Contactez l\'administrateur.',
      );
    }
    return Buffer.from(keyEnv, 'hex');
  }
}
