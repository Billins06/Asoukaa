/**
 * Utilitaires pour l'audit trail complet
 * Définit les actions qui doivent être loggées dans le système
 */

export enum AuditAction {
  // Auth
  USER_REGISTERED = 'USER_REGISTERED',
  USER_LOGIN = 'USER_LOGIN',
  USER_LOGOUT = 'USER_LOGOUT',
  USER_OTP_VERIFIED = 'USER_OTP_VERIFIED',
  USER_PASSWORD_RESET = 'USER_PASSWORD_RESET',
  USER_PASSWORD_CHANGED = 'USER_PASSWORD_CHANGED',

  // Admin
  ADMIN_LOGIN = 'ADMIN_LOGIN',
  ADMIN_LOGOUT = 'ADMIN_LOGOUT',
  ADMIN_CREATED = 'ADMIN_CREATED',
  ADMIN_ROLE_CHANGED = 'ADMIN_ROLE_CHANGED',
  ADMIN_DISABLED = 'ADMIN_DISABLED',
  ADMIN_PASSWORD_SET = 'ADMIN_PASSWORD_SET',

  // Resources
  RESOURCE_CREATED = 'RESOURCE_CREATED',
  RESOURCE_UPDATED = 'RESOURCE_UPDATED',
  RESOURCE_DELETED = 'RESOURCE_DELETED',
  RESOURCE_EXPORTED = 'RESOURCE_EXPORTED',

  // Sensitive Operations
  DATA_EXPORTED = 'DATA_EXPORTED',
  BULK_OPERATION = 'BULK_OPERATION',
  PERMISSION_CHANGED = 'PERMISSION_CHANGED',
  CONFIGURATION_CHANGED = 'CONFIGURATION_CHANGED',

  // Payments
  PAYMENT_CREATED = 'PAYMENT_CREATED',
  PAYMENT_PROCESSED = 'PAYMENT_PROCESSED',
  PAYMENT_FAILED = 'PAYMENT_FAILED',
  PAYMENT_REFUNDED = 'PAYMENT_REFUNDED',

  // File Operations
  FILE_UPLOADED = 'FILE_UPLOADED',
  FILE_DELETED = 'FILE_DELETED',
  FILE_DOWNLOADED = 'FILE_DOWNLOADED',

  // Security
  FAILED_LOGIN_ATTEMPT = 'FAILED_LOGIN_ATTEMPT',
  RATE_LIMIT_EXCEEDED = 'RATE_LIMIT_EXCEEDED',
  SUSPICIOUS_ACTIVITY = 'SUSPICIOUS_ACTIVITY',
}

export interface AuditContext {
  userId?: string;
  adminId?: string;
  action: AuditAction;
  entityType: string;
  entityId?: string;
  changes?: {
    before: Record<string, any>;
    after: Record<string, any>;
  };
  ipAddress?: string;
  userAgent?: string;
  metadata?: Record<string, any>;
}

/**
 * Helpers pour créer des contextes d'audit
 */
export class AuditTrail {
  static userAction(
    userId: string,
    action: AuditAction,
    entityType: string,
    entityId?: string,
  ): AuditContext {
    return { userId, action, entityType, entityId };
  }

  static adminAction(
    adminId: string,
    action: AuditAction,
    entityType: string,
    entityId?: string,
  ): AuditContext {
    return { adminId, action, entityType, entityId };
  }

  static withChanges(
    context: AuditContext,
    before: Record<string, any>,
    after: Record<string, any>,
  ): AuditContext {
    return { ...context, changes: { before, after } };
  }

  static withIpAndAgent(
    context: AuditContext,
    ipAddress: string,
    userAgent?: string,
  ): AuditContext {
    return { ...context, ipAddress, userAgent };
  }
}

/**
 * Les actions qui doivent être loggées :
 *
 * ✅ AUTHENTIFICATION:
 *   - Register user
 *   - Login (succès et échecs)
 *   - Logout
 *   - OTP verification
 *   - Password reset / change
 *
 * ✅ ADMIN:
 *   - Admin login/logout
 *   - Create admin
 *   - Change admin role
 *   - Disable admin
 *   - Set admin password
 *
 * ✅ DONNÉES:
 *   - Create resource
 *   - Update resource (avec avant/après)
 *   - Delete resource (soft et hard delete)
 *   - Export data
 *   - Bulk operations
 *
 * ✅ PERMISSIONS:
 *   - Change permissions
 *   - Change roles
 *
 * ✅ PAIEMENTS:
 *   - Create payment
 *   - Process payment
 *   - Payment failed
 *   - Payment refunded
 *
 * ✅ FICHIERS:
 *   - Upload
 *   - Delete
 *   - Download
 *
 * ✅ SÉCURITÉ:
 *   - Failed login attempts
 *   - Rate limit exceeded
 *   - Suspicious activity
 */
