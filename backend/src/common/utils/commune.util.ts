// Comparaison de noms de communes insensible aux accents, à la casse et aux
// séparateurs : « Ségbana » = « segbana », « Abomey-Calavi » = « abomey calavi »,
// « N’Dali » = « N'Dali ». Utilisé pour retrouver la zone de livraison d'une
// adresse (delivery_zones.commune) — voir OrdersService.
export function normalizeCommune(value: unknown): string {
  if (typeof value !== 'string') return '';
  return value
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[-_'’‘`´]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}
