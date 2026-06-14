import { Injectable } from '@nestjs/common';
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
    try {
      const key = this.getEncryptionKey();
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
    try {
      const key = this.getEncryptionKey();
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
    if (!keyEnv || keyEnv.length !== 64) {
      throw new Error('ENCRYPTION_KEY must be 32 bytes (64 hex chars)');
    }
    return Buffer.from(keyEnv, 'hex');
  }
}
