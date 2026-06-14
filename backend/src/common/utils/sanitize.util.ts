/**
 * Utilitaires de sanitisation pour prévenir les attaques XSS
 */

/**
 * Sanitise une chaîne en supprimant les caractères dangereux
 */
export function sanitizeString(input: string): string {
  if (!input || typeof input !== 'string') {
    return '';
  }

  return input
    .replace(/[<>]/g, '') // Supprimer < et >
    .replace(/javascript:/gi, '') // Supprimer javascript:
    .replace(/on\w+\s*=/gi, '') // Supprimer onload=, onclick=, etc.
    .trim();
}

/**
 * Sanitise un objet récursivement
 */
export function sanitizeObject(obj: any): any {
  if (obj === null || obj === undefined) {
    return obj;
  }

  if (typeof obj === 'string') {
    return sanitizeString(obj);
  }

  if (Array.isArray(obj)) {
    return obj.map(item => sanitizeObject(item));
  }

  if (typeof obj === 'object') {
    const sanitized: any = {};
    for (const key in obj) {
      if (obj.hasOwnProperty(key)) {
        sanitized[key] = sanitizeObject(obj[key]);
      }
    }
    return sanitized;
  }

  return obj;
}

/**
 * Valide que une chaîne ne contient pas de caractères dangéreux
 */
export function isStringSafe(input: string): boolean {
  if (!input || typeof input !== 'string') {
    return true;
  }

  const dangerousPatterns = [
    /<script/i,
    /javascript:/i,
    /on\w+\s*=/i,
    /<iframe/i,
    /<embed/i,
    /<object/i,
  ];

  return !dangerousPatterns.some(pattern => pattern.test(input));
}
