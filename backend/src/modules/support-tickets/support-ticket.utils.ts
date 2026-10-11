import { BadRequestException } from '@nestjs/common';
import { UploadService, UploadType } from '../upload/upload.service';
import { TICKET_CATEGORIES, TICKET_LIMITS } from './support-ticket.constants';

// Caractères de contrôle (hors \n et \t) et caractères invisibles de
// direction du texte (usurpation d'affichage).
const CONTROL_CHARS = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F​‎‏‪-‮⁦-⁩﻿]/g;

/**
 * Convertit une saisie utilisateur en TEXTE BRUT : retire commentaires et
 * balises HTML (le contenu des <script>/<style> est supprimé), les
 * caractères de contrôle, normalise les sauts de ligne.
 * `multiline = false` (sujet) : tout est ramené sur une seule ligne.
 */
export function toPlainText(input: unknown, multiline: boolean): string {
  let s = typeof input === 'string' ? input : '';
  s = s.normalize('NFC');
  s = s.replace(/<!--[\s\S]*?-->/g, '');
  s = s.replace(/<(script|style)\b[^>]*>[\s\S]*?<\/\1\s*>/gi, '');
  s = s.replace(/<\/?[a-zA-Z!?][^>]*>/g, '');
  s = s.replace(CONTROL_CHARS, '');
  s = s.replace(/\r\n?/g, '\n');
  if (multiline) {
    s = s.replace(/[ \t]+\n/g, '\n').replace(/\n{4,}/g, '\n\n\n');
  } else {
    s = s.replace(/\s+/g, ' ');
  }
  return s.trim();
}

export function cleanSubject(raw: unknown): string {
  const subject = toPlainText(raw, false);
  if (subject.length < TICKET_LIMITS.SUBJECT_MIN) {
    throw new BadRequestException(`Le sujet doit contenir au moins ${TICKET_LIMITS.SUBJECT_MIN} caractères`);
  }
  if (subject.length > TICKET_LIMITS.SUBJECT_MAX) {
    throw new BadRequestException(`Le sujet ne peut pas dépasser ${TICKET_LIMITS.SUBJECT_MAX} caractères`);
  }
  return subject;
}

export function cleanBody(raw: unknown): string {
  const body = toPlainText(raw, true);
  if (body.length < TICKET_LIMITS.BODY_MIN) {
    throw new BadRequestException('Le message ne peut pas être vide');
  }
  if (body.length > TICKET_LIMITS.BODY_MAX) {
    throw new BadRequestException(`Le message ne peut pas dépasser ${TICKET_LIMITS.BODY_MAX} caractères`);
  }
  return body;
}

// Aperçu d'un message (liste des tickets) : une ligne, N caractères max.
export function previewOf(body: string, max: number = TICKET_LIMITS.PREVIEW_LENGTH): string {
  const flat = String(body ?? '').replace(/\s+/g, ' ').trim();
  const chars = Array.from(flat);
  return chars.length > max ? `${chars.slice(0, max).join('').trimEnd()}…` : flat;
}

const stripAccents = (s: string): string =>
  s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();

/**
 * Ramène une catégorie reçue (casse / accents tolérés) à sa forme canonique,
 * ou `undefined` si elle n'existe pas.
 */
export function normalizeCategory(value: unknown): string | undefined {
  if (typeof value !== 'string') return undefined;
  const wanted = stripAccents(value);
  return TICKET_CATEGORIES.find((c) => stripAccents(c) === wanted);
}

// Échappe % _ \ pour un ILIKE construit à partir d'une saisie utilisateur.
export const escapeLike = (s: string): string => s.replace(/[\\%_]/g, (c) => `\\${c}`);

// « TCK-000042 », « tck42 » ou « 42 » -> 42 ; autre chose -> null.
export function parseTicketNumber(search: string): number | null {
  const m = /^(?:tck-?)?0*(\d{1,9})$/i.exec(search.trim());
  return m ? Number(m[1]) : null;
}

const TICKET_FILE_PATH = /(?:^|\/)tickets\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(?:jpe?g|png|webp)$/i;

/**
 * Valide les images jointes (≤ 3) : chacune doit être une URL émise par NOTRE
 * route d'upload de type TICKET (assertIsOwnUploadUrl), sans paramètres de
 * requête ni identifiants, et avoir exactement la forme d'un fichier émis par
 * cette route (…/tickets/<uuid>.<jpg|jpeg|png|webp>). Doublons ignorés.
 */
export function normalizeAttachments(
  uploadService: UploadService,
  raw: unknown,
): string[] {
  if (raw === undefined || raw === null) return [];
  if (!Array.isArray(raw)) {
    throw new BadRequestException('Les pièces jointes doivent être une liste d\'URL');
  }
  if (raw.length > TICKET_LIMITS.MAX_ATTACHMENTS) {
    throw new BadRequestException(`Maximum ${TICKET_LIMITS.MAX_ATTACHMENTS} images par message`);
  }
  const out: string[] = [];
  for (const url of raw) {
    if (typeof url !== 'string' || url.length === 0 || url.length > TICKET_LIMITS.MAX_URL_LENGTH) {
      throw new BadRequestException('URL d\'image invalide');
    }
    // Lève 400 si l'URL ne pointe pas vers notre stockage / le dossier « tickets ».
    uploadService.assertIsOwnUploadUrl(url, UploadType.TICKET);
    let parsed: URL;
    try {
      parsed = new URL(url);
    } catch {
      throw new BadRequestException('URL d\'image invalide');
    }
    if (parsed.search || parsed.hash || parsed.username || parsed.password
        || !TICKET_FILE_PATH.test(parsed.pathname)) {
      throw new BadRequestException('Ce fichier n\'est pas une image de ticket valide');
    }
    if (!out.includes(url)) out.push(url);
  }
  return out;
}
