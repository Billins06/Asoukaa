/// Texte de présence « à la WhatsApp », en français.
///
/// - [isOnline] vrai (calculé par le serveur : vu il y a moins de 2 minutes)
///   -> « En ligne »
/// - sinon, selon la date de dernière activité ([lastSeenIso], date ISO 8601
///   renvoyée par le serveur, convertie en heure locale de l'appareil) :
///   « Vu aujourd'hui à 14:32 », « Vu hier à 20:05 », « Vu le 12/10 à 09:10 »
///   (avec l'année si ce n'est pas l'année en cours)
/// - jamais vu (null ou illisible) -> « Hors ligne »
String formatLastSeen(String? lastSeenIso, {bool isOnline = false}) {
  if (isOnline) return 'En ligne';
  if (lastSeenIso == null || lastSeenIso.trim().isEmpty) return 'Hors ligne';
  final parsed = DateTime.tryParse(lastSeenIso.trim());
  if (parsed == null) return 'Hors ligne';

  final seen = parsed.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final seenDay = DateTime(seen.year, seen.month, seen.day);
  final daysAgo = today.difference(seenDay).inDays;

  final hour = seen.hour.toString().padLeft(2, '0');
  final minute = seen.minute.toString().padLeft(2, '0');
  final time = '$hour:$minute';

  // daysAgo <= 0 : aujourd'hui (ou léger décalage d'horloge vers le futur).
  if (daysAgo <= 0) return "Vu aujourd'hui à $time";
  if (daysAgo == 1) return 'Vu hier à $time';

  final day = seen.day.toString().padLeft(2, '0');
  final month = seen.month.toString().padLeft(2, '0');
  final year = seen.year == now.year ? '' : '/${seen.year}';
  return 'Vu le $day/$month$year à $time';
}
