import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import 'api_service.dart';

// Service des tickets de support (cote application).
// Routes : /api/v1/support-tickets (voir backend, module support-tickets)
// et /api/v1/upload/tickets pour les images jointes.

/// Erreur lisible par l'utilisateur (message deja en francais).
class TicketException implements Exception {
  final String message;
  final int? statusCode;

  const TicketException(this.message, {this.statusCode});

  /// Transforme n'importe quelle erreur (Dio, reseau, ...) en message clair.
  factory TicketException.from(Object error) {
    if (error is TicketException) return error;
    if (error is DioException) {
      final code = error.response?.statusCode;
      final msg = _serverMessage(error.response?.data);
      if (code == null) {
        return const TicketException(
          'Connexion impossible. V\u00e9rifiez votre r\u00e9seau.',
        );
      }
      if (code == 429) {
        // Limite metier (message serveur en francais) ou limite technique
        // (message anglais du serveur) : dans ce cas, texte generique.
        if (msg != null &&
            !RegExp(r'throttler|too many', caseSensitive: false)
                .hasMatch(msg)) {
          return TicketException(msg, statusCode: code);
        }
        return TicketException(
          'Trop de demandes, r\u00e9essayez dans un moment',
          statusCode: code,
        );
      }
      if (code == 401) {
        return TicketException(
          'Votre session a expir\u00e9. Reconnectez-vous.',
          statusCode: code,
        );
      }
      if (code == 413) {
        return TicketException(
          'Image trop lourde (5 Mo maximum).',
          statusCode: code,
        );
      }
      if (code >= 500) {
        return TicketException(
          'Le serveur rencontre un probl\u00e8me. R\u00e9essayez dans un moment.',
          statusCode: code,
        );
      }
      return TicketException(
        msg ?? 'Une erreur est survenue. R\u00e9essayez.',
        statusCode: code,
      );
    }
    return const TicketException('Une erreur est survenue. R\u00e9essayez.');
  }

  @override
  String toString() => message;

  static const Set<String> _englishGeneric = {
    'bad request',
    'unauthorized',
    'forbidden',
    'not found',
    'internal server error',
    'too many requests',
    'service unavailable',
    'bad gateway',
    'payload too large',
  };

  /// Extrait le message du corps d'erreur NestJS (texte ou liste de textes).
  static String? _serverMessage(dynamic data) {
    if (data is! Map) return null;
    final raw = data['message'];
    String? text;
    if (raw is String) {
      text = raw;
    } else if (raw is List) {
      final parts = raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (parts.isNotEmpty) text = parts.join('\n');
    }
    if (text == null) return null;
    text = text.trim();
    if (text.isEmpty) return null;
    if (_englishGeneric.contains(text.toLowerCase())) return null;
    return text;
  }
}

String _asString(dynamic v) => v == null ? '' : v.toString();

int _asInt(dynamic v, [int fallback = 0]) {
  if (v is num) return v.toInt();
  return int.tryParse(_asString(v)) ?? fallback;
}

DateTime? _asDate(dynamic v) {
  if (v is! String || v.isEmpty) return null;
  return DateTime.tryParse(v)?.toLocal();
}

Map<String, dynamic> _asMap(dynamic v) {
  if (v is Map) return Map<String, dynamic>.from(v);
  throw const TicketException('R\u00e9ponse inattendue du serveur.');
}

/// Statuts d'un ticket (valeurs exactes du serveur).
class TicketStatus {
  static const String ouvert = 'ouvert';
  static const String enCours = 'en_cours';
  static const String resolu = 'resolu';
  static const String ferme = 'ferme';
}

class TicketLastMessage {
  final String authorType;
  final String preview;
  final int attachmentCount;
  final DateTime? createdAt;

  const TicketLastMessage({
    required this.authorType,
    required this.preview,
    required this.attachmentCount,
    required this.createdAt,
  });

  bool get fromAdmin => authorType == 'admin';

  factory TicketLastMessage.fromJson(Map<String, dynamic> j) {
    return TicketLastMessage(
      authorType: _asString(j['authorType']),
      preview: _asString(j['preview']),
      attachmentCount: _asInt(j['attachmentCount']),
      createdAt: _asDate(j['createdAt']),
    );
  }
}

class TicketSummary {
  final String id;
  final String reference;
  final String category;
  final String subject;
  final String status;
  final DateTime? lastMessageAt;
  final bool hasUnread;
  final TicketLastMessage? lastMessage;

  const TicketSummary({
    required this.id,
    required this.reference,
    required this.category,
    required this.subject,
    required this.status,
    required this.lastMessageAt,
    required this.hasUnread,
    required this.lastMessage,
  });

  factory TicketSummary.fromJson(Map<String, dynamic> j) {
    final last = j['lastMessage'];
    return TicketSummary(
      id: _asString(j['id']),
      reference: _asString(j['reference']),
      category: _asString(j['category']),
      subject: _asString(j['subject']),
      status: _asString(j['status']),
      lastMessageAt: _asDate(j['lastMessageAt']),
      hasUnread: j['hasUnread'] == true,
      lastMessage: last is Map
          ? TicketLastMessage.fromJson(Map<String, dynamic>.from(last))
          : null,
    );
  }
}

class TicketPage {
  final List<TicketSummary> items;
  final int total;
  final int page;
  final int pages;

  const TicketPage({
    required this.items,
    required this.total,
    required this.page,
    required this.pages,
  });

  bool get hasMore => page < pages;
}

class TicketMessage {
  final String id;
  final String authorType;
  final String authorName;
  final bool isMine;
  final String body;
  final List<String> attachments;
  final DateTime? createdAt;

  const TicketMessage({
    required this.id,
    required this.authorType,
    required this.authorName,
    required this.isMine,
    required this.body,
    required this.attachments,
    required this.createdAt,
  });

  factory TicketMessage.fromJson(Map<String, dynamic> j) {
    final authorType = _asString(j['authorType']);
    final rawAttachments = j['attachments'];
    final isMine = j['isMine'] is bool
        ? j['isMine'] as bool
        : authorType != 'admin';
    final authorName = _asString(j['authorName']);
    return TicketMessage(
      id: _asString(j['id']),
      authorType: authorType,
      authorName: authorName.isNotEmpty
          ? authorName
          : (isMine ? 'Vous' : '\u00c9quipe Asoukaa'),
      isMine: isMine,
      body: _asString(j['body']),
      attachments: rawAttachments is List
          ? rawAttachments
              .map((e) => _asString(e))
              .where((e) => e.isNotEmpty)
              .toList()
          : <String>[],
      createdAt: _asDate(j['createdAt']),
    );
  }
}

class TicketDetail {
  final String id;
  final String reference;
  final String category;
  final String subject;
  final String status;
  final String? orderId;
  final String? orderNumber;
  final bool canReply;
  final DateTime? createdAt;
  final DateTime? closedAt;
  final List<TicketMessage> messages;

  const TicketDetail({
    required this.id,
    required this.reference,
    required this.category,
    required this.subject,
    required this.status,
    required this.orderId,
    required this.orderNumber,
    required this.canReply,
    required this.createdAt,
    required this.closedAt,
    required this.messages,
  });

  factory TicketDetail.fromJson(Map<String, dynamic> j) {
    final rawMessages = j['messages'];
    final orderId = _asString(j['orderId']);
    final orderNumber = _asString(j['orderNumber']);
    return TicketDetail(
      id: _asString(j['id']),
      reference: _asString(j['reference']),
      category: _asString(j['category']),
      subject: _asString(j['subject']),
      status: _asString(j['status']),
      orderId: orderId.isEmpty ? null : orderId,
      orderNumber: orderNumber.isEmpty ? null : orderNumber,
      canReply: j['canReply'] != false,
      createdAt: _asDate(j['createdAt']),
      closedAt: _asDate(j['closedAt']),
      messages: rawMessages is List
          ? rawMessages
              .whereType<Map>()
              .map((e) => TicketMessage.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : <TicketMessage>[],
    );
  }
}

/// Resultat de l'envoi d'une reponse.
class TicketReplyResult {
  final TicketMessage message;
  final String status;
  final DateTime? lastMessageAt;

  const TicketReplyResult({
    required this.message,
    required this.status,
    required this.lastMessageAt,
  });
}

class SupportTicketService {
  static SupportTicketService? _instance;
  static SupportTicketService get instance =>
      _instance ??= SupportTicketService._();
  SupportTicketService._();

  static const String _base = '/api/v1/support-tickets';
  static const int maxImages = 3;
  static const int maxImageBytes = 5 * 1024 * 1024;

  Dio get _client => ApiService.instance.client;

  /// Ouvre un ticket (+ premier message). N'envoie que les champs acceptes
  /// par le serveur (il refuse les champs en trop).
  Future<TicketDetail> create({
    required String subject,
    required String message,
    required String category,
    String? orderId,
    List<String> attachments = const [],
  }) async {
    final data = <String, dynamic>{
      'subject': subject.trim(),
      'message': message.trim(),
      'category': category,
    };
    if (orderId != null && orderId.isNotEmpty) data['orderId'] = orderId;
    if (attachments.isNotEmpty) data['attachments'] = attachments;
    try {
      final r = await _client.post(_base, data: data);
      return TicketDetail.fromJson(_asMap(r.data));
    } catch (e) {
      throw TicketException.from(e);
    }
  }

  /// Mes tickets, les plus recents en premier (pagination serveur).
  Future<TicketPage> list({int page = 1, int limit = 20}) async {
    try {
      final r = await _client.get(
        _base,
        queryParameters: {'page': page, 'limit': limit},
      );
      final body = _asMap(r.data);
      final raw = body['data'];
      final items = raw is List
          ? raw
              .whereType<Map>()
              .map((e) => TicketSummary.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : <TicketSummary>[];
      return TicketPage(
        items: items,
        total: _asInt(body['total'], items.length),
        page: _asInt(body['page'], page),
        pages: _asInt(body['pages'], 1),
      );
    } catch (e) {
      throw TicketException.from(e);
    }
  }

  /// Detail + messages (le serveur marque le ticket comme lu).
  Future<TicketDetail> detail(String id) async {
    try {
      final r = await _client.get('$_base/$id');
      return TicketDetail.fromJson(_asMap(r.data));
    } catch (e) {
      throw TicketException.from(e);
    }
  }

  /// Repond a un de mes tickets.
  Future<TicketReplyResult> reply(
    String id, {
    required String message,
    List<String> attachments = const [],
  }) async {
    final data = <String, dynamic>{'message': message.trim()};
    if (attachments.isNotEmpty) data['attachments'] = attachments;
    try {
      final r = await _client.post('$_base/$id/messages', data: data);
      final body = _asMap(r.data);
      final ticket = body['ticket'];
      final ticketMap =
          ticket is Map ? Map<String, dynamic>.from(ticket) : <String, dynamic>{};
      return TicketReplyResult(
        message: TicketMessage.fromJson(_asMap(body['message'])),
        status: _asString(ticketMap['status']),
        lastMessageAt: _asDate(ticketMap['lastMessageAt']),
      );
    } catch (e) {
      throw TicketException.from(e);
    }
  }

  /// Nombre de tickets avec une reponse non lue.
  Future<int> unreadCount() async {
    try {
      final r = await _client.get('$_base/unread-count');
      final body = _asMap(r.data);
      return _asInt(body['tickets']);
    } catch (e) {
      throw TicketException.from(e);
    }
  }

  /// Envoie une image (JPG, PNG ou WEBP, 5 Mo max) et renvoie son URL, a
  /// placer dans `attachments`. Meme principe que UploadService
  /// (readAsBytes + FormData, valable sur mobile et sur le web).
  Future<String> uploadImage(XFile file) async {
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        throw const TicketException('Image illisible. Choisissez-en une autre.');
      }
      if (bytes.length > maxImageBytes) {
        throw const TicketException('Image trop lourde (5 Mo maximum).');
      }
      final ext = _detectExtension(bytes);
      if (ext == null) {
        throw const TicketException(
          'Format non pris en charge. Utilisez une image JPG, PNG ou WEBP.',
        );
      }
      // Type MIME explicite : le serveur refuse tout fichier dont le type
      // annoncé n'est pas image/jpeg, image/png ou image/webp.
      final mime = ext == 'png'
          ? 'image/png'
          : (ext == 'webp' ? 'image/webp' : 'image/jpeg');
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: 'ticket_${DateTime.now().millisecondsSinceEpoch}.$ext',
          contentType: DioMediaType.parse(mime),
        ),
      });
      final r = await _client.post('/api/v1/upload/tickets', data: formData);
      final data = r.data;
      final url = data is Map ? data['url'] : null;
      if (url is! String || url.isEmpty) {
        throw const TicketException('Envoi de l\'image impossible. R\u00e9essayez.');
      }
      return url;
    } catch (e) {
      throw TicketException.from(e);
    }
  }

  /// Reconnait le vrai format d'apres les premiers octets.
  static String? _detectExtension(List<int> b) {
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return 'jpg';
    }
    if (b.length >= 4 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47) {
      return 'png';
    }
    if (b.length >= 12 &&
        b[0] == 0x52 && // R
        b[1] == 0x49 && // I
        b[2] == 0x46 && // F
        b[3] == 0x46 && // F
        b[8] == 0x57 && // W
        b[9] == 0x45 && // E
        b[10] == 0x42 && // B
        b[11] == 0x50) {
      // P
      return 'webp';
    }
    return null;
  }
}
