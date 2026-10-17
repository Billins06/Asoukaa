import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/loading_skeleton_widget.dart';
import '../../services/api_service.dart';
import '../../services/unread_messages_notifier.dart';
import '../../utils/last_seen_format.dart';
import '../../utils/lecture_json.dart';

// ─── Data Models ────────────────────────────────────────────────────────────

enum MessageType { text, productAttachment, system, imageAttachment }

enum ContactBlockReason { phone, whatsapp, telegram, email }

enum MessageStatus { sending, sent, delivered, read }

class _ChatMessage {
  final String id;
  final String text;
  final bool isMe;
  final DateTime timestamp;
  final MessageType type;
  final _ProductAttachment? product;
  final ContactBlockReason? blockedReason;
  final MessageStatus status;
  final String? imageUrl;
  final bool isReported;

  const _ChatMessage({
    required this.id,
    required this.text,
    required this.isMe,
    required this.timestamp,
    this.type = MessageType.text,
    this.product,
    this.blockedReason,
    this.status = MessageStatus.sent,
    this.imageUrl,
    this.isReported = false,
  });

  factory _ChatMessage.fromSupabase(
    Map<String, dynamic> data,
    String currentUserId,
  ) {
    // ⚠️ Le backend NestJS renvoie du camelCase (senderId, createdAt,
    // isRead, imageUrl...) et n'a pas de messageType/productData —
    // ce mapping venait d'une ancienne intégration Supabase en
    // snake_case et ne correspondait plus du tout à l'API réelle
    // (tous les messages semblaient venir de l'autre participant).
    _ProductAttachment? productAttachment;
    if (data['messageType'] == 'product_attachment' &&
        data['productData'] != null) {
      final pd = data['productData'] as Map<String, dynamic>;
      productAttachment = _ProductAttachment(
        imageUrl: pd['image_url'] as String? ?? '',
        name: pd['name'] as String? ?? 'Produit',
        price: lireDouble(pd['price']),
        currency: 'FCFA',
        isPurchased: pd['is_purchased'] as bool? ?? false,
      );
    }
    final isRead = data['isRead'] == true;
    final isReported = data['isReported'] == true;
    final msgType = data['messageType'] as String? ?? 'text';
    return _ChatMessage(
      id: data['id'] as String,
      text: data['content'] as String? ?? '',
      isMe: data['senderId'] == currentUserId,
      timestamp:
          DateTime.tryParse(data['createdAt'] as String? ?? '') ??
          DateTime.now(),
      // Le backend n'envoie pas de champ messageType : un message est une
      // image dès qu'il porte une imageUrl.
      type: msgType == 'product_attachment'
          ? MessageType.productAttachment
          : (msgType == 'image' ||
                (data['imageUrl'] is String &&
                    (data['imageUrl'] as String).isNotEmpty))
          ? MessageType.imageAttachment
          : MessageType.text,
      product: productAttachment,
      imageUrl: data['imageUrl'] as String?,
      status: isRead ? MessageStatus.read : MessageStatus.sent,
      isReported: isReported,
    );
  }
}

class _ProductAttachment {
  final String imageUrl;
  final String name;
  final double price;
  final String currency;
  final bool isPurchased;

  const _ProductAttachment({
    required this.imageUrl,
    required this.name,
    required this.price,
    required this.currency,
    this.isPurchased = false,
  });
}

// ─── Regex patterns for external contact detection ──────────────────────────

final _phoneRegex = RegExp(r'(\+?\d[\d\s\-().]{7,}\d)');
final _emailRegex = RegExp(r'[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}');
final _whatsappRegex = RegExp(
  r'(whatsapp|wa\.me|wa\s*:?\s*\+?\d)',
  caseSensitive: false,
);
final _telegramRegex = RegExp(r'(telegram|t\.me\/|@\w+)', caseSensitive: false);

ContactBlockReason? _detectBlockedContent(String text) {
  if (_whatsappRegex.hasMatch(text)) return ContactBlockReason.whatsapp;
  if (_telegramRegex.hasMatch(text)) return ContactBlockReason.telegram;
  if (_emailRegex.hasMatch(text)) return ContactBlockReason.email;
  if (_phoneRegex.hasMatch(text)) return ContactBlockReason.phone;
  return null;
}

// ─── Main Screen ─────────────────────────────────────────────────────────────

class ChatScreen extends StatefulWidget {
  final Map<String, dynamic>? chatArgs;

  const ChatScreen({super.key, this.chatArgs});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  List<_ChatMessage> _messages = [];
  bool _isTyping = false;
  bool _otherIsTyping = false;
  DateTime? _lastTypingPing;
  bool _isLoading = true;
  bool _isSending = false;
  bool _isUploadingImage = false;
  Timer? _typingTimer;
  Timer? _pollingTimer;

  // Message d'erreur si la conversation n'a pas pu être créée/ouverte.
  // Tant qu'il est non nul : aucune conversation n'est ouverte et aucun
  // message ne peut partir (jamais de repli sur une autre conversation).
  String? _erreurCreation;

  // Conversation data
  String? _conversationId;
  String? _otherUserId;
  String _otherUserName = 'Vendeur';
  String _otherUserAvatar = '';

  // Présence de l'interlocuteur, fournie par le serveur (otherUser).
  // Tant qu'elle n'est pas connue, rien n'est affiché (pas de faux « Hors ligne »).
  bool _otherPresenceKnown = false;
  bool _otherIsOnline = false;
  String? _otherLastSeenAt;

  // Product attachment from product page
  Map<String, dynamic>? _productAttachment;

  // Current user
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    final args = widget.chatArgs;
    if (args != null && args['product_name'] != null) {
      _productAttachment = {
        'name': args['product_name'],
        'price': args['product_price'] ?? 0,
        'image_url': args['product_image'] ?? '',
      };
    }
    _initChat();
  }

  Future<void> _initChat() async {
    setState(() {
      _isLoading = true;
      _erreurCreation = null;
    });

    // Fetch current user ID
    try {
      final meRes = await ApiService.instance.client.get('/api/v1/users/me');
      _currentUserId = meRes.data['id'] as String?;
    } catch (_) {}

    final args = widget.chatArgs;
    String? vendorId;
    if (args != null) {
      _otherUserId =
          args['seller_id'] as String? ?? args['other_user_id'] as String?;
      _otherUserName =
          args['seller_name'] as String? ??
          args['other_user_name'] as String? ??
          'Vendeur';
      _otherUserAvatar =
          args['seller_avatar'] as String? ??
          args['other_user_avatar'] as String? ??
          '';
      _conversationId = args['conversation_id'] as String?;
      // ID de la boutique (VendorProfile.id) attendu par POST /chat/conversations,
      // distinct de _otherUserId qui est l'ID utilisateur du vendeur.
      vendorId = args['vendor_id'] as String? ?? args['vendorId'] as String?;
    }

    // Une boutique précise est visée : si la conversation ne peut pas être
    // créée, on N'OUVRE RIEN (avant, l'appli ouvrait la dernière conversation
    // existante, avec un autre vendeur, et le message partait chez lui).
    final boutiqueVisee = vendorId != null && vendorId.isNotEmpty;

    if (_conversationId == null && boutiqueVisee) {
      try {
        final res = await ApiService.instance.client.post(
          '/api/v1/chat/conversations',
          data: {
            'vendorId': vendorId,
            if (args?['product_id'] != null) 'productId': args!['product_id'],
          },
        );
        final data = res.data;
        _conversationId = data is Map ? data['id'] as String? : null;
        if (data is Map) _applyOtherPresence(data['otherUser']);
      } catch (_) {
        _conversationId = null;
      }
      if (_conversationId == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _erreurCreation = 'Impossible d\'ouvrir la conversation avec ce '
                'vendeur pour le moment. Vérifiez votre connexion et '
                'réessayez.';
          });
        }
        return;
      }
    }

    // Si on a un conversationId (venu des arguments, ex. depuis une
    // notification "nouveau message") mais pas de nom d'interlocuteur
    // (seller_name absent des arguments), on va le chercher.
    final needsOtherPartyLookup = _otherUserId == null || _otherUserId!.isEmpty;

    if (_conversationId != null) {
      if (needsOtherPartyLookup) {
        await _resolveOtherParticipant(_conversationId!);
      }
      await _loadMessages();
      _startPolling();
    } else if (!boutiqueVisee) {
      try {
        final res = await ApiService.instance.client.get('/api/v1/chat/conversations');
        final raw = res.data;
        final rawList = raw is List ? raw : (raw is Map ? (raw['data'] ?? raw['items'] ?? []) : []);
        final list = (rawList as List).whereType<Map>().toList();
        if (list.isNotEmpty) {
          final conv = Map<String, dynamic>.from(list.first);
          _conversationId = conv['id'] as String?;
          _applyOtherParticipant(conv);
          await _loadMessages();
          _startPolling();
        }
      } catch (_) {}
    }

    if (mounted) setState(() => _isLoading = false);
  }

  // Structure NestJS réelle de GET /chat/conversations :
  // { clientId, client: {id, prenom, nom}, vendorId,
  //   vendor: {id, userId, shopName, ...}, ... }
  // (les clés snake_case buyer_id/seller/buyer n'existent pas côté backend)
  void _applyOtherParticipant(Map<String, dynamic> conv) {
    _applyOtherPresence(conv['otherUser']);
    final isClient = conv['clientId'] == _currentUserId;
    if (isClient) {
      final vendor = conv['vendor'] as Map?;
      _otherUserId = vendor != null ? vendor['userId'] as String? : null;
      _otherUserName = vendor != null
          ? (vendor['shopName'] as String? ?? 'Vendeur')
          : 'Vendeur';
      _otherUserAvatar = vendor != null
          ? (vendor['logoUrl'] as String? ?? '')
          : '';
    } else {
      final client = conv['client'] as Map?;
      _otherUserId = client != null ? client['id'] as String? : null;
      final prenom = client != null ? client['prenom'] as String? ?? '' : '';
      final name = client != null ? client['name'] as String? ?? '' : '';
      final fullName = ('$prenom $name').trim();
      _otherUserName = fullName.isNotEmpty ? fullName : 'Client';
      _otherUserAvatar = client != null ? (client['avatarUrl'] as String? ?? '') : '';
    }
  }

  // Présence de l'autre participant : { id, lastSeenAt, isOnline } ou null.
  // Ne fait pas de setState : l'appelant s'en charge si besoin.
  void _applyOtherPresence(dynamic other) {
    if (other is! Map) return;
    _otherPresenceKnown = true;
    _otherIsOnline = other['isOnline'] == true;
    final seen = other['lastSeenAt'];
    _otherLastSeenAt = seen is String ? seen : null;
  }

  Future<void> _resolveOtherParticipant(String conversationId) async {
    try {
      final res = await ApiService.instance.client.get('/api/v1/chat/conversations');
      final raw = res.data;
      final rawList = raw is List ? raw : (raw is Map ? (raw['data'] ?? raw['items'] ?? []) : []);
      final list = (rawList as List).whereType<Map>().toList();
      final match = list.cast<Map>().firstWhere(
        (c) => c['id'] == conversationId,
        orElse: () => {},
      );
      if (match.isNotEmpty) {
        _applyOtherParticipant(Map<String, dynamic>.from(match));
      }
    } catch (_) {}
  }

  Future<void> _loadMessages() async {
    if (_conversationId == null) return;
    try {
      final res = await ApiService.instance.client
          .get('/api/v1/chat/conversations/$_conversationId/messages');
      final raw = res.data;
      final list = raw is List ? raw : (raw is Map ? (raw['data'] ?? raw['items'] ?? []) : []);
      final otherIsTyping = raw is Map ? raw['otherIsTyping'] == true : false;
      if (mounted) {
        setState(() {
          if (raw is Map) _applyOtherPresence(raw['otherUser']);
          _messages = (list as List)
              .map((m) => _ChatMessage.fromSupabase(
                    Map<String, dynamic>.from(m as Map),
                    _currentUserId ?? '',
                  ))
              .toList();
          _otherIsTyping = otherIsTyping;
        });
        _scrollToBottom(animated: false);
      }
      // Le GET ci-dessus vient de marquer comme lus les messages reçus :
      // si certains ne l'étaient pas encore, on met la pastille de l'onglet
      // "Messages" à jour immédiatement.
      final hadUnread = (list as List).any(
        (m) =>
            m is Map &&
            m['isRead'] != true &&
            m['senderId'] != null &&
            m['senderId'] != _currentUserId,
      );
      if (hadUnread) UnreadMessagesNotifier.instance.refresh();
      // Pas d'appel "mark as read" séparé : le backend n'expose aucune
      // route /chat/conversations/:id/read (404 systématique observé en
      // QA) — GET .../messages marque déjà les messages non lus comme
      // lus en effet de bord côté serveur.
    } catch (_) {}
  }

  Future<void> _sendProductAttachment() async {
    if (_productAttachment == null || _conversationId == null) return;
    final product = _productAttachment!;
    _productAttachment = null;

    final tempMsg = _ChatMessage(
      id: 'temp_product_${DateTime.now().millisecondsSinceEpoch}',
      text: product['name'] as String? ?? 'Produit',
      isMe: true,
      timestamp: DateTime.now(),
      type: MessageType.productAttachment,
      product: _ProductAttachment(
        imageUrl: product['image_url'] as String? ?? '',
        name: product['name'] as String? ?? 'Produit',
        price: lireDouble(product['price']),
        currency: 'FCFA',
      ),
      status: MessageStatus.sending,
    );
    if (mounted) {
      setState(() => _messages.add(tempMsg));
      _scrollToBottom();
    }

    try {
      // Le backend (SendMessageDto) n'accepte que { content, imageUrl } —
      // il rejette (400) tout champ inconnu comme messageType/productData,
      // qu'il ne sait de toute façon pas persister. On envoie donc un
      // texte descriptif ; la bulle "carte produit" ci-dessus reste
      // affichée localement pour une UX correcte à l'instant T.
      final priceText = product['price'] != null
          ? ' — ${product['price']} FCFA'
          : '';
      await ApiService.instance.client.post(
        '/api/v1/chat/conversations/$_conversationId/messages',
        data: {
          'content':
              '🛍️ ${product['name'] as String? ?? 'Produit'}$priceText',
        },
      );
    } catch (_) {}
  }

  Future<void> _confirmAndReportMessage(_ChatMessage msg) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Signaler ce message', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        content: Text(
          'Ce message sera transmis à l\'équipe de modération. Continuer ?',
          style: GoogleFonts.outfit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Annuler', style: GoogleFonts.outfit()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Signaler',
              style: GoogleFonts.outfit(color: AppTheme.error, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ApiService.instance.client.patch(
        '/api/v1/chat/messages/${msg.id}/report',
      );
      if (!mounted) return;
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == msg.id);
        if (idx != -1) {
          _messages[idx] = _ChatMessage(
            id: msg.id,
            text: msg.text,
            isMe: msg.isMe,
            timestamp: msg.timestamp,
            type: msg.type,
            product: msg.product,
            imageUrl: msg.imageUrl,
            status: msg.status,
            isReported: true,
          );
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Message signalé. Merci, notre équipe va l\'examiner.', style: GoogleFonts.outfit()),
          backgroundColor: const Color(0xFF1A1A1A),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final msg2 = e is DioException
          ? (e.response?.data is Map ? (e.response!.data['message']?.toString()) : null)
          : null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg2 ?? 'Erreur lors du signalement du message', style: GoogleFonts.outfit()),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _loadMessages();
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _typingTimer?.cancel();
    _pollingTimer?.cancel();
    UnreadMessagesNotifier.instance.refresh();
    super.dispose();
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        if (animated) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        } else {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      }
    });
  }

  void _onInputChanged(String value) {
    _typingTimer?.cancel();
    if (!_isTyping) setState(() => _isTyping = true);
    _typingTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _isTyping = false);
    });

    // Prévenir l'autre participant que j'écris (limité à un appel toutes
    // les ~2s pour ne pas spammer le backend à chaque frappe).
    final now = DateTime.now();
    if (_conversationId != null &&
        (_lastTypingPing == null ||
            now.difference(_lastTypingPing!) > const Duration(seconds: 2))) {
      _lastTypingPing = now;
      ApiService.instance.client
          .patch('/api/v1/chat/conversations/$_conversationId/typing')
          .catchError((_) {});
    }
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isSending) return;

    // Pas de conversation ouverte : on ne poste rien (ni texte ni produit).
    if (_conversationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _erreurCreation ?? 'Conversation indisponible. Réessayez.',
            style: GoogleFonts.outfit(),
          ),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    _inputController.clear();
    setState(() {
      _isTyping = false;
      _isSending = true;
    });
    _typingTimer?.cancel();

    // Produit epingle (arrive via le bouton "Contacter" d'une fiche
    // produit) : part avec ce premier message, comme une reponse a un
    // statut WhatsApp — jamais envoye tout seul si le client n'ecrit rien.
    if (_productAttachment != null) {
      await _sendProductAttachment();
    }

    final blockReason = _detectBlockedContent(text);
    if (blockReason != null) {
      setState(() => _isSending = false);
      _showBlockedAlert(blockReason);
      return;
    }

    final tempMsg = _ChatMessage(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      text: text,
      isMe: true,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
    );
    setState(() => _messages.add(tempMsg));
    _scrollToBottom();

    if (_conversationId != null) {
      try {
        await ApiService.instance.client.post(
          '/api/v1/chat/conversations/$_conversationId/messages',
          data: {'content': text},
        );
        if (mounted) {
          setState(() {
            final idx = _messages.indexWhere((m) => m.id == tempMsg.id);
            if (idx != -1) {
              _messages[idx] = _ChatMessage(
                id: tempMsg.id,
                text: tempMsg.text,
                isMe: true,
                timestamp: tempMsg.timestamp,
                status: MessageStatus.sent,
              );
            }
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() => _messages.removeWhere((m) => m.id == tempMsg.id));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Message non envoyé. Réessayez.', style: GoogleFonts.outfit()),
              backgroundColor: AppTheme.error,
            ),
          );
          _inputController.text = text;
        }
      }
    }

    if (mounted) setState(() => _isSending = false);
  }

  Future<void> _pickAndSendImage() async {
    if (_conversationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _erreurCreation ?? 'Conversation indisponible. Réessayez.',
            style: GoogleFonts.outfit(),
          ),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }
    final picker = ImagePicker();
    final source = await _showImageSourceDialog();
    if (source == null) return;

    final XFile? picked = await picker.pickImage(
      source: source,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 80,
    );
    if (picked == null) return;

    setState(() => _isUploadingImage = true);

    try {
      final bytes = await picked.readAsBytes();
      // Extension et type annoncé d'après le vrai format du fichier (le
      // serveur refuse tout type autre que JPG / PNG / WEBP).
      final lower = picked.name.toLowerCase();
      final String ext = lower.endsWith('.png')
          ? 'png'
          : (lower.endsWith('.webp') ? 'webp' : 'jpg');
      final String mime = ext == 'png'
          ? 'image/png'
          : (ext == 'webp' ? 'image/webp' : 'image/jpeg');
      final fileName = 'chat_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: fileName,
          contentType: DioMediaType.parse(mime),
        ),
      });
      final res = await ApiService.instance.client.post('/api/v1/upload/chat', data: formData);
      final uploadedUrl = res.data is Map ? res.data['url'] as String? : null;

      if (uploadedUrl != null && _conversationId != null) {
        final tempMsg = _ChatMessage(
          id: 'temp_img_${DateTime.now().millisecondsSinceEpoch}',
          text: '📷 Image',
          isMe: true,
          timestamp: DateTime.now(),
          type: MessageType.imageAttachment,
          imageUrl: uploadedUrl,
          status: MessageStatus.sending,
        );
        if (mounted) {
          setState(() => _messages.add(tempMsg));
          _scrollToBottom();
        }

        await ApiService.instance.client.post(
          '/api/v1/chat/conversations/$_conversationId/messages',
          data: {'content': '📷 Image', 'imageUrl': uploadedUrl},
        );
        // Le message est bien parti : on le fait passer de "envoi" à "envoyé"
        // sans attendre le prochain rafraîchissement.
        if (mounted) {
          setState(() {
            final idx = _messages.indexWhere((m) => m.id == tempMsg.id);
            if (idx != -1) {
              _messages[idx] = _ChatMessage(
                id: tempMsg.id,
                text: tempMsg.text,
                isMe: true,
                timestamp: tempMsg.timestamp,
                type: MessageType.imageAttachment,
                imageUrl: uploadedUrl,
                status: MessageStatus.sent,
              );
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erreur lors de l\'envoi de l\'image',
              style: GoogleFonts.outfit(),
            ),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  Future<ImageSource?> _showImageSourceDialog() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text('Galerie', style: GoogleFonts.outfit()),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text('Appareil photo', style: GoogleFonts.outfit()),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Joindre un fichier',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.image_outlined,
                  color: Color(0xFF3B82F6),
                ),
              ),
              title: Text(
                'Image',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                'Envoyer une photo',
                style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.muted),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndSendImage();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showBlockedAlert(ContactBlockReason reason) {
    final labels = {
      ContactBlockReason.phone: 'numéro de téléphone',
      ContactBlockReason.whatsapp: 'contact WhatsApp',
      ContactBlockReason.telegram: 'contact Telegram',
      ContactBlockReason.email: 'adresse email',
    };

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.errorContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.shield_outlined,
                color: AppTheme.error,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Contact bloqué',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Le partage de ${labels[reason]} est interdit sur Asoukaa pour protéger les acheteurs et vendeurs.',
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.warningContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.lock_outline,
                    color: AppTheme.warning,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Les contacts externes sont débloqués automatiquement après un achat confirmé.',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: AppTheme.warning,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Compris',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w600,
                color: AppTheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _FilterNoticeBanner(),
          Expanded(
            child: _isLoading
                ? const ChatListSkeleton()
                : _erreurCreation != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            size: 44,
                            color: AppTheme.error,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _erreurCreation!,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _initChat,
                            child: const Text('Réessayer'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _messages.isEmpty
                ? EmptyStateWidget(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: 'Aucun message',
                    description:
                        'Commencez la conversation en envoyant votre premier message au vendeur.',
                  )
                : ListView.builder(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    itemCount: _messages.length + (_otherIsTyping ? 1 : 0),
                    itemBuilder: (_, index) {
                      if (index == _messages.length) {
                        return _TypingIndicator(name: _otherUserName);
                      }
                      final msg = _messages[index];
                      final prevTs = index > 0
                          ? _messages[index - 1].timestamp
                          : null;
                      // Comparaison sur jour+mois+année : comparer
                      // uniquement .day aurait confondu le 15 janvier
                      // et le 15 février par exemple.
                      final showDate =
                          index == 0 ||
                          prevTs == null ||
                          prevTs.day != msg.timestamp.day ||
                          prevTs.month != msg.timestamp.month ||
                          prevTs.year != msg.timestamp.year;
                      return Column(
                        children: [
                          if (showDate) _DateDivider(date: msg.timestamp),
                          _MessageBubble(
                            message: msg,
                            timeLabel: _formatTime(msg.timestamp),
                            // On ne signale jamais ses propres messages
                            // (le backend le refuse de toute façon).
                            onReport: (!msg.isMe && !msg.isReported)
                                ? () => _confirmAndReportMessage(msg)
                                : null,
                          ),
                        ],
                      );
                    },
                  ),
          ),
          if (_isUploadingImage)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppTheme.surface,
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Envoi de l\'image...',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: AppTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
          _buildInputBar(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios_rounded,
          size: 20,
          color: Color(0xFF1A1A1A),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFFFEDE3),
                backgroundImage: _otherUserAvatar.isNotEmpty
                    ? NetworkImage(_otherUserAvatar)
                    : null,
                child: _otherUserAvatar.isEmpty
                    ? Text(
                        _otherUserName.isNotEmpty
                            ? _otherUserName[0].toUpperCase()
                            : 'V',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary,
                        ),
                      )
                    : null,
              ),
              if (_otherIsOnline)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: const Color(0xFF16A34A),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _otherUserName,
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A1A1A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (_otherPresenceKnown)
                  Text(
                    formatLastSeen(_otherLastSeenAt, isOnline: _otherIsOnline),
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: _otherIsOnline
                          ? const Color(0xFF16A34A)
                          : const Color(0xFF9E9E9E),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF1A1A1A)),
          onPressed: () {},
        ),
      ],
    );
  }

  // Apercu du produit "epingle" au-dessus du champ de saisie, tant que le
  // client n'a pas encore envoye son premier message depuis la fiche
  // produit (voir _sendMessage). Le bouton "x" annule sans rien envoyer.
  Widget _buildPinnedProductPreview() {
    if (_productAttachment == null) return const SizedBox.shrink();
    final product = _productAttachment!;
    final imageUrl = product['image_url'] as String? ?? '';
    final name = product['name'] as String? ?? 'Produit';
    final price = product['price'];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFFF5F5F5),
        border: Border(top: BorderSide(color: AppTheme.outline, width: 1)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: imageUrl.isNotEmpty
                ? Image.network(
                    imageUrl,
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 36,
                      height: 36,
                      color: const Color(0xFFEAE6E1),
                      child: const Icon(Icons.image_outlined, size: 16, color: Color(0xFF9E9E9E)),
                    ),
                  )
                : Container(
                    width: 36,
                    height: 36,
                    color: const Color(0xFFEAE6E1),
                    child: const Icon(Icons.shopping_bag_outlined, size: 16, color: Color(0xFF9E9E9E)),
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'À propos de ce produit',
                  style: GoogleFonts.outfit(fontSize: 10, color: AppTheme.muted),
                ),
                Text(
                  price != null ? '$name — $price FCFA' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _productAttachment = null),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close_rounded, size: 18, color: AppTheme.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildPinnedProductPreview(),
        Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.outline, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Attachment button
            GestureDetector(
              onTap: _showAttachmentOptions,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.attach_file_rounded,
                  size: 20,
                  color: AppTheme.muted,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _inputController,
                  focusNode: _focusNode,
                  onChanged: _onInputChanged,
                  maxLines: 4,
                  minLines: 1,
                  textCapitalization: TextCapitalization.sentences,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    color: const Color(0xFF1A1A1A),
                  ),
                  decoration: InputDecoration(
                    hintText: 'Votre message...',
                    hintStyle: GoogleFonts.outfit(
                      fontSize: 14,
                      color: const Color(0xFF9E9E9E),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sendMessage,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _isSending
                      ? AppTheme.primary.withAlpha(120)
                      : AppTheme.primary,
                  shape: BoxShape.circle,
                ),
                child: _isSending
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
              ),
            ),
          ],
        ),
      ),
    ),
      ],
    );
  }
}

// ── Supporting Widgets ────────────────────────────────────────────────────────

class _FilterNoticeBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFFFFF8F5),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, size: 14, color: Color(0xFFFF6210)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Les contacts externes sont bloqués pour votre sécurité.',
              style: GoogleFonts.outfit(
                fontSize: 11,
                color: const Color(0xFF9E9E9E),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _DateDivider extends StatelessWidget {
  final DateTime date;
  const _DateDivider({required this.date});

  String _label() {
    // Comparaison sur le jour calendaire (minuit à minuit), pas sur la
    // durée écoulée : un message d'hier 20h34 vu aujourd'hui à 08h48 ne
    // fait que ~12h d'écart, ce qui donnait 0 jour avec .inDays et
    // affichait donc "Aujourd'hui" au lieu de "Hier".
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(date.year, date.month, date.day);
    final diff = today.difference(messageDay).inDays;
    if (diff == 0) return 'Aujourd\'hui';
    if (diff == 1) return 'Hier';
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _label(),
              style: GoogleFonts.outfit(
                fontSize: 11,
                color: const Color(0xFF9E9E9E),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;
  final String timeLabel;
  final VoidCallback? onReport;

  const _MessageBubble({
    required this.message,
    required this.timeLabel,
    this.onReport,
  });

  Widget _buildStatusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.sending:
        return const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: Colors.white70,
          ),
        );
      case MessageStatus.sent:
        return const Icon(Icons.done_rounded, size: 13, color: Colors.white70);
      case MessageStatus.delivered:
        return const Icon(
          Icons.done_all_rounded,
          size: 13,
          color: Colors.white70,
        );
      case MessageStatus.read:
        return const Icon(
          Icons.done_all_rounded,
          size: 13,
          color: Color(0xFF93C5FD),
        );
    }
  }

  String _statusLabel(MessageStatus status) {
    switch (status) {
      case MessageStatus.sending:
        return 'envoi...';
      case MessageStatus.sent:
        return 'envoyé';
      case MessageStatus.delivered:
        return 'livré';
      case MessageStatus.read:
        return 'lu';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (message.type == MessageType.productAttachment &&
        message.product != null) {
      return _ProductAttachmentBubble(message: message, timeLabel: timeLabel);
    }
    if (message.type == MessageType.imageAttachment &&
        message.imageUrl != null) {
      return _ImageAttachmentBubble(message: message, timeLabel: timeLabel);
    }

    final isMe = message.isMe;
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onReport,
        child: Container(
          margin: EdgeInsets.only(
            top: 2,
            bottom: 2,
            left: isMe ? 60 : 0,
            right: isMe ? 0 : 60,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isMe ? AppTheme.primary : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMe ? 16 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 16),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(8),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                message.text,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  color: isMe ? Colors.white : const Color(0xFF1A1A1A),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    timeLabel,
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      color: isMe
                          ? Colors.white.withAlpha(180)
                          : const Color(0xFF9E9E9E),
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    _buildStatusIcon(message.status),
                    const SizedBox(width: 2),
                    Text(
                      _statusLabel(message.status),
                      style: GoogleFonts.outfit(
                        fontSize: 9,
                        color: message.status == MessageStatus.read
                            ? const Color(0xFF93C5FD)
                            : Colors.white.withAlpha(180),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageAttachmentBubble extends StatelessWidget {
  final _ChatMessage message;
  final String timeLabel;

  const _ImageAttachmentBubble({
    required this.message,
    required this.timeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: 4,
          bottom: 4,
          left: isMe ? 60 : 0,
          right: isMe ? 0 : 60,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              Image.network(
                message.imageUrl!,
                width: 220,
                height: 200,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 220,
                  height: 200,
                  color: const Color(0xFFF5F2EF),
                  child: const Icon(
                    Icons.broken_image_outlined,
                    color: Color(0xFF9E9E9E),
                  ),
                ),
              ),
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(120),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    timeLabel,
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductAttachmentBubble extends StatelessWidget {
  final _ChatMessage message;
  final String timeLabel;

  const _ProductAttachmentBubble({
    required this.message,
    required this.timeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;
    final product = message.product!;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: 4,
          bottom: 4,
          left: isMe ? 60 : 0,
          right: isMe ? 0 : 60,
        ),
        decoration: BoxDecoration(
          color: isMe ? AppTheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: product.imageUrl.isNotEmpty
                  ? Image.network(
                      product.imageUrl,
                      width: 220,
                      height: 140,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 220,
                        height: 140,
                        color: const Color(0xFFF5F2EF),
                        child: const Icon(
                          Icons.image_outlined,
                          color: Color(0xFF9E9E9E),
                        ),
                      ),
                    )
                  : Container(
                      width: 220,
                      height: 140,
                      color: const Color(0xFFF5F2EF),
                      child: const Icon(
                        Icons.shopping_bag_outlined,
                        color: Color(0xFF9E9E9E),
                        size: 40,
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isMe
                          ? Colors.white.withAlpha(30)
                          : AppTheme.primaryMuted,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '🛍 Produit partagé',
                      style: GoogleFonts.outfit(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isMe ? Colors.white70 : AppTheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    product.name,
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isMe ? Colors.white : const Color(0xFF1A1A1A),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${product.price.toInt()} ${product.currency}',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: isMe
                          ? Colors.white.withAlpha(220)
                          : AppTheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        timeLabel,
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          color: isMe
                              ? Colors.white.withAlpha(180)
                              : const Color(0xFF9E9E9E),
                        ),
                      ),
                      if (isMe)
                        Row(
                          children: [
                            Icon(
                              Icons.done_all_rounded,
                              size: 13,
                              color: message.status == MessageStatus.read
                                  ? const Color(0xFF93C5FD)
                                  : Colors.white70,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              message.status == MessageStatus.read
                                  ? 'lu'
                                  : 'livré',
                              style: GoogleFonts.outfit(
                                fontSize: 9,
                                color: message.status == MessageStatus.read
                                    ? const Color(0xFF93C5FD)
                                    : Colors.white.withAlpha(180),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  final String name;
  const _TypingIndicator({required this.name});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 4, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          '$name est en train d\'écrire...',
          style: GoogleFonts.outfit(
            fontSize: 12,
            color: const Color(0xFF9E9E9E),
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}