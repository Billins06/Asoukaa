/**
 * Utilitaires pour valider les uploads de fichiers
 */

export const ALLOWED_MIME_TYPES = {
  images: ['image/jpeg', 'image/png', 'image/webp', 'image/gif'],
  documents: ['application/pdf', 'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'],
};

export const FILE_SIZE_LIMITS = {
  image: 5 * 1024 * 1024, // 5MB
  document: 10 * 1024 * 1024, // 10MB
  default: 5 * 1024 * 1024, // 5MB
};

/**
 * Valide si un fichier est une image
 */
export function isValidImage(mimeType: string, fileSize: number): boolean {
  return (
    ALLOWED_MIME_TYPES.images.includes(mimeType) &&
    fileSize <= FILE_SIZE_LIMITS.image
  );
}

/**
 * Valide si un fichier est un document
 */
export function isValidDocument(mimeType: string, fileSize: number): boolean {
  return (
    ALLOWED_MIME_TYPES.documents.includes(mimeType) &&
    fileSize <= FILE_SIZE_LIMITS.document
  );
}

/**
 * Valide un fichier uploadé
 */
export function validateUpload(
  mimeType: string,
  fileSize: number,
  type: 'image' | 'document' | 'any' = 'any',
): { valid: boolean; error?: string } {
  if (!mimeType) {
    return { valid: false, error: 'Type MIME manquant' };
  }

  if (!fileSize || fileSize <= 0) {
    return { valid: false, error: 'Taille de fichier invalide' };
  }

  if (fileSize > FILE_SIZE_LIMITS.default) {
    return { valid: false, error: 'Fichier trop volumineux' };
  }

  if (type === 'image' && !isValidImage(mimeType, fileSize)) {
    return { valid: false, error: 'Format d\'image non autorisé' };
  }

  if (type === 'document' && !isValidDocument(mimeType, fileSize)) {
    return { valid: false, error: 'Format de document non autorisé' };
  }

  return { valid: true };
}
