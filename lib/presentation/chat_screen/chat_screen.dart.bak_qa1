import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/loading_skeleton_widget.dart';
import '../../services/api_service.dart';

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
  });

  factory _ChatMessage.fromSupabase(
    Map<String, dynamic> data,
    String currentUserId,
  ) {
    _ProductAttachment? productAttachment;
    if (data['message_type'] == 'product_attachment' &&
        data['product_data'] != null) {
      final pd = data['product_data'] as Map<String, dynamic>;
      productAttachment = _ProductAttachment(
        imageUrl: pd['image_url'] as String? ?? '',
        name: pd['name'] as String? ?? 'Produit',
        price: (pd['price'] as num? ?? 0).toDouble(),
        currency: 'FCFA',
        isPurchased: pd['is_purchased'] as bool? ?? false,
      );
    }
    final isRead = data['is_read'] == true;
    final isDelivered = data['is_delivered'] == true;
    final msgType = data['message_type'] as String? ?? 'text';
    return _ChatMessage(
      id: data['id'] as String,
      text: data['content'] as String? ?? '',
      isMe: data['sender_id'] == currentUserId,
      timestamp:
          DateTime.tryParse(data['created_at'] as String? ?? '') ??
          DateTime.now(),
      type: msgType == 'product_attachment'
          ? MessageType.productAttachment
          : msgType == 'image'
          ? MessageType.imageAttachment
          : MessageType.text,
      product: productAttachment,
      imageUrl: data['image_url'] as String?,
      status: isRead
          ? MessageStatus.read
          : isDelivered
          ? MessageStatus.delivered
          : MessageStatus.sent,
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
  final bool _isOnline = true;
  bool _isTyping = false;
  bool _isLoading = true;
  bool _isSending = false;
  bool _isUploadingImage = false;
  Timer? _typingTimer;
  Timer? _pollingTimer;

  // Conversation data
  String? _conversationId;
  String? _otherUserId;
  String _otherUserName = 'Vendeur';
  String _otherUserAvatar = '';
  late DateTime _lastSeen;

  // Product attachment from product page
  Map<String, dynamic>? _productAttachment;

  // Current user
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _lastSeen = DateTime.now().subtract(const Duration(minutes: 2));
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
    setState(() => _isLoading = true);

    // Fetch current user ID
    try {
      final meRes = await ApiService.instance.client.get('/api/v1/users/me');
      _currentUserId = meRes.data['id'] as String?;
    } catch (_) {}

    final args = widget.chatArgs;
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
    }

    if (_conversationId == null && _otherUserId != null) {
      try {
        final res = await ApiService.instance.client.post(
          '/api/v1/chat/conversations',
          data: {
            'sellerId': _otherUserId,
            if (args?['product_id'] != null) 'productId': args!['product_id'],
          },
        );
        _conversationId = res.data['id'] as String?;
      } catch (_) {}
    }

    if (_conversationId != null) {
      await _loadMessages();
      _startPolling();
    } else {
      try {
        final res = await ApiService.instance.client.get('/api/v1/chat/conversations');
        final raw = res.data;
        final list = raw is List ? raw : (raw is Map ? (raw['data'] ?? raw['items'] ?? []) : []);
        if ((list as List).isNotEmpty) {
          final conv = list.first as Map<String, dynamic>;
          _conversationId = conv['id'] as String?;
          final isBuyer = conv['buyer_id'] == _currentUserId;
          final other = isBuyer ? conv['seller'] : conv['buyer'];
          if (other is Map) {
            _otherUserName = other['full_name'] as String? ?? 'Vendeur';
            _otherUserAvatar = other['avatar_url'] as String? ?? '';
          }
          await _loadMessages();
          _startPolling();
        }
      } catch (_) {}
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadMessages() async {
    if (_conversationId == null) return;
    try {
      final res = await ApiService.instance.client
          .get('/api/v1/chat/conversations/$_conversationId/messages');
      final raw = res.data;
      final list = raw is List ? raw : (raw is Map ? (raw['data'] ?? raw['items'] ?? []) : []);
      if (mounted) {
        setState(() {
          _messages = (list as List)
              .map((m) => _ChatMessage.fromSupabase(
                    Map<String, dynamic>.from(m as Map),
                    _currentUserId ?? '',
                  ))
              .toList();
        });
        _scrollToBottom(animated: false);
        if (_messages.isEmpty && _productAttachment != null) {
          _sendProductAttachment();
        }
      }
      // Mark as read
      try {
        await ApiService.instance.client
            .patch('/api/v1/chat/conversations/$_conversationId/read');
      } catch (_) {}
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
        price: (product['price'] as num? ?? 0).toDouble(),
        currency: 'FCFA',
      ),
      status: MessageStatus.sending,
    );
    if (mounted) {
      setState(() => _messages.add(tempMsg));
      _scrollToBottom();
    }

    try {
      await ApiService.instance.client.post(
        '/api/v1/chat/conversations/$_conversationId/messages',
        data: {
          'content': product['name'] as String? ?? 'Produit',
          'messageType': 'product_attachment',
          'productData': {
            'name': product['name'],
            'price': product['price'],
            'image_url': product['image_url'],
            'is_purchased': false,
          },
        },
      );
    } catch (_) {}
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
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isSending) return;

    _inputController.clear();
    setState(() {
      _isTyping = false;
      _isSending = true;
    });
    _typingTimer?.cancel();

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
      final fileName = 'chat_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: fileName),
      });
      final res = await ApiService.instance.client.post('/api/v1/uploads/image', data: formData);
      final uploadedUrl = res.data['url'] as String?;

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
          data: {'content': '📷 Image', 'messageType': 'image', 'imageUrl': uploadedUrl},
        );
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

  String _formatLastSeen(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'à l\'instant';
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'il y a ${diff.inHours}h';
    return 'hier';
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
                    itemCount: _messages.length + (_isTyping ? 1 : 0),
                    itemBuilder: (_, index) {
                      if (index == _messages.length) {
                        return _TypingIndicator(name: _otherUserName);
                      }
                      final msg = _messages[index];
                      final showDate =
                          index == 0 ||
                          _messages[index - 1].timestamp.day !=
                              msg.timestamp.day;
                      return Column(
                        children: [
                          if (showDate) _DateDivider(date: msg.timestamp),
                          _MessageBubble(
                            message: msg,
                            timeLabel: _formatTime(msg.timestamp),
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
              if (_isOnline)
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
                Text(
                  _isOnline ? 'En ligne' : 'Vu ${_formatLastSeen(_lastSeen)}',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: _isOnline
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

  Widget _buildInputBar() {
    return Container(
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
    final now = DateTime.now();
    final diff = now.difference(date).inDays;
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

  const _MessageBubble({required this.message, required this.timeLabel});

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