import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../routes/app_routes.dart';
import '../../services/support_ticket_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import 'ticket_widgets.dart';

/// Detail d'un ticket : conversation avec l'equipe Asoukaa, images
/// cliquables, zone de reponse.
///
/// Arguments de la route (ModalRoute) : l'id du ticket (String) ou une Map
/// { 'ticketId': String, 'fromSupport': bool }. Voir [idFromArguments].
class TicketDetailScreen extends StatefulWidget {
  final String ticketId;

  /// True si l'ecran a ete ouvert depuis la liste " Mes tickets " : pour
  /// ouvrir un nouveau ticket on revient alors simplement a cet ecran.
  final bool fromSupport;

  const TicketDetailScreen({
    super.key,
    required this.ticketId,
    this.fromSupport = false,
  });

  static String idFromArguments(Object? args) {
    if (args is String) return args.trim();
    if (args is Map) {
      final v = args['ticketId'] ?? args['id'];
      return v == null ? '' : v.toString().trim();
    }
    return '';
  }

  static bool fromSupportArguments(Object? args) =>
      args is Map && args['fromSupport'] == true;

  @override
  State<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends State<TicketDetailScreen> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _replyCtrl = TextEditingController();
  final FocusNode _replyFocus = FocusNode();
  final List<PickedTicketImage> _images = [];

  TicketDetail? _ticket;
  List<TicketMessage> _messages = [];
  String _status = '';
  bool _canReply = true;
  bool _loading = true;
  String? _error;
  bool _sending = false;
  bool _picking = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
        ),
      );
    }
    _replyFocus.addListener(_onFocusChanged);
    if (widget.ticketId.isEmpty) {
      _loading = false;
      _error = 'Ticket introuvable.';
    } else {
      _load(showSpinner: false, toBottom: true);
    }
  }

  @override
  void dispose() {
    _replyFocus.removeListener(_onFocusChanged);
    _replyFocus.dispose();
    _replyCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_replyFocus.hasFocus) return;
    // Le clavier met un instant a s'ouvrir : on recale ensuite la conversation.
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) _scrollToBottom();
    });
  }

  Future<void> _load({bool showSpinner = true, bool toBottom = false}) async {
    if (widget.ticketId.isEmpty) return;
    final gen = ++_generation;
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final t = await SupportTicketService.instance.detail(widget.ticketId);
      if (!mounted || gen != _generation) return;
      setState(() {
        _ticket = t;
        _messages = List<TicketMessage>.of(t.messages);
        _status = t.status;
        _canReply = t.canReply;
        _loading = false;
        _error = null;
      });
      if (toBottom) _scrollToBottom(animate: false);
    } on TicketException catch (e) {
      if (!mounted || gen != _generation) return;
      final hadTicket = _ticket != null;
      setState(() {
        _loading = false;
        if (!hadTicket) _error = e.message;
      });
      if (hadTicket) {
        AppToast.show(context, message: e.message, type: ToastType.error);
      }
    }
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (animate) {
        _scroll.animateTo(
          max,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      } else {
        _scroll.jumpTo(max);
      }
    });
  }

  Future<void> _addImage() async {
    if (_sending || _picking) return;
    if (_images.length >= SupportTicketService.maxImages) {
      AppToast.show(
        context,
        message: 'Vous pouvez joindre 3 images au maximum.',
        type: ToastType.info,
      );
      return;
    }
    setState(() => _picking = true);
    final img = await pickTicketImage(context);
    if (!mounted) return;
    setState(() {
      _picking = false;
      if (img != null && _images.length < SupportTicketService.maxImages) {
        _images.add(img);
      }
    });
  }

  Future<void> _send() async {
    if (_sending) return;
    final text = _replyCtrl.text.trim();
    if (text.isEmpty) {
      AppToast.show(
        context,
        message: '\u00c9crivez votre message avant d\'envoyer.',
        type: ToastType.info,
      );
      return;
    }
    setState(() => _sending = true);
    try {
      final urls = <String>[];
      for (final img in List<PickedTicketImage>.of(_images)) {
        var url = img.uploadedUrl;
        if (url == null) {
          url = await SupportTicketService.instance.uploadImage(img.file);
          img.uploadedUrl = url;
        }
        urls.add(url);
      }
      if (!mounted) return;

      final res = await SupportTicketService.instance.reply(
        widget.ticketId,
        message: text,
        attachments: urls,
      );
      if (!mounted) return;

      setState(() {
        _messages = [..._messages, res.message];
        if (res.status.isNotEmpty) _status = res.status;
        _images.clear();
        _replyCtrl.clear();
      });
      _scrollToBottom();
    } on TicketException catch (e) {
      if (mounted) {
        AppToast.show(context, message: e.message, type: ToastType.error);
        // Ticket ferme entre-temps : on recharge pour afficher le bon etat.
        if (e.statusCode == 400) _load(showSpinner: false);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _openNewTicket() {
    if (widget.fromSupport) {
      Navigator.pop(context, 'new_ticket');
      return;
    }
    final t = _ticket;
    Navigator.pushReplacementNamed(
      context,
      AppRoutes.supportHelp,
      arguments: <String, dynamic>{
        'category': t?.category,
        'orderId': t?.orderId,
        'orderNumber': t?.orderNumber,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _ticket;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppTheme.textPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t != null && t.reference.isNotEmpty ? t.reference : 'Ticket',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            Text(
              'Support Asoukaa',
              style: GoogleFonts.outfit(fontSize: 11, color: AppTheme.muted),
            ),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }
    final t = _ticket;
    if (t == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                size: 48,
                color: AppTheme.muted,
              ),
              const SizedBox(height: 12),
              Text(
                _error ?? 'Ticket introuvable.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
              ),
              if (widget.ticketId.isNotEmpty) ...[
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => _load(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'R\u00e9essayer',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            color: AppTheme.primary,
            onRefresh: () => _load(showSpinner: false),
            child: SingleChildScrollView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(t),
                  const SizedBox(height: 16),
                  ..._buildMessages(),
                ],
              ),
            ),
          ),
        ),
        if (_canReply) _buildReplyBar() else _buildClosedNotice(),
      ],
    );
  }

  Widget _buildHeader(TicketDetail t) {
    final opened = t.createdAt;
    final closed = t.closedAt;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                t.reference,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              TicketStatusChip(status: _status),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            t.subject,
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (t.category.isNotEmpty) _infoPill(Icons.sell_outlined, t.category),
              if (t.orderNumber != null)
                _infoPill(Icons.receipt_long_outlined, 'Commande ${t.orderNumber}'),
            ],
          ),
          if (opened != null) ...[
            const SizedBox(height: 8),
            Text(
              'Ouvert le ${ticketFullDate(opened)}',
              style: GoogleFonts.outfit(fontSize: 11, color: AppTheme.muted),
            ),
          ],
          if (_status == TicketStatus.ferme && closed != null) ...[
            const SizedBox(height: 2),
            Text(
              'Ferm\u00e9 le ${ticketFullDate(closed)}',
              style: GoogleFonts.outfit(fontSize: 11, color: AppTheme.muted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoPill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppTheme.textSecondary),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 11,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMessages() {
    final out = <Widget>[];
    DateTime? lastDay;
    for (final m in _messages) {
      final d = m.createdAt;
      if (d != null && (lastDay == null || !ticketSameDay(lastDay, d))) {
        out.add(_daySeparator(ticketDayLabel(d)));
        lastDay = d;
      }
      out.add(_MessageBubble(message: m));
    }
    return out;
  }

  Widget _daySeparator(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(14),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReplyBar() {
    final reopens =
        _status == TicketStatus.ferme || _status == TicketStatus.resolu;
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.outline)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (reopens)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 0, 6),
                child: Text(
                  _status == TicketStatus.ferme
                      ? 'Ce ticket est ferm\u00e9 : votre r\u00e9ponse le rouvrira.'
                      : 'Ce ticket est marqu\u00e9 comme r\u00e9solu : votre r\u00e9ponse le rouvrira.',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            if (_images.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 4),
                child: PickedImagesStrip(
                  images: _images,
                  size: 56,
                  onRemove: (i) {
                    if (_sending) return;
                    setState(() => _images.removeAt(i));
                  },
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Ajouter une image',
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  color: AppTheme.primary,
                  disabledColor: AppTheme.muted,
                  onPressed: (_sending ||
                          _picking ||
                          _images.length >= SupportTicketService.maxImages)
                      ? null
                      : _addImage,
                ),
                Expanded(
                  child: TextField(
                    controller: _replyCtrl,
                    focusNode: _replyFocus,
                    enabled: !_sending,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 4000,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    style: GoogleFonts.outfit(fontSize: 14),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '\u00c9crivez votre r\u00e9ponse...',
                      hintStyle: GoogleFonts.outfit(
                        fontSize: 14,
                        color: AppTheme.muted,
                      ),
                      filled: true,
                      fillColor: AppTheme.surfaceVariant,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: const BorderSide(
                          color: AppTheme.primary,
                          width: 1.2,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: AppTheme.primary,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _sending ? null : _send,
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: _sending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClosedNotice() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.outline)),
      ),
      padding: const EdgeInsets.all(16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 20,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Ce ticket est ferm\u00e9 depuis plus de 7 jours. Ouvrez-en un nouveau.',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: AppTheme.textPrimary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _openNewTicket,
                icon: const Icon(Icons.add_comment_outlined, size: 18),
                label: Text(
                  'Ouvrir un nouveau ticket',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Bulle de message --------------------------------------------------------

class _MessageBubble extends StatelessWidget {
  final TicketMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final mine = message.isMine;
    final maxWidth = MediaQuery.of(context).size.width * 0.78;
    final thumb = ((maxWidth - 24 - 6) / 2).floorToDouble().clamp(80.0, 130.0).toDouble();
    final created = message.createdAt;

    final textColor = mine ? Colors.white : AppTheme.textPrimary;
    final timeColor = mine ? Colors.white.withAlpha(215) : AppTheme.muted;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
          decoration: BoxDecoration(
            color: mine ? AppTheme.primary : const Color(0xFFE8E8EB),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 4),
              bottomRight: Radius.circular(mine ? 4 : 16),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!mine)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.support_agent_rounded,
                        size: 14,
                        color: AppTheme.primary,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          message.authorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (message.body.isNotEmpty)
                SelectableText(
                  message.body,
                  style: GoogleFonts.outfit(
                    fontSize: 14.5,
                    fontWeight: mine ? FontWeight.w500 : FontWeight.w400,
                    color: textColor,
                    height: 1.35,
                  ),
                ),
              if (message.attachments.isNotEmpty) ...[
                if (message.body.isNotEmpty) const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < message.attachments.length; i++)
                      TicketAttachmentThumb(
                        urls: message.attachments,
                        index: i,
                        size: thumb,
                      ),
                  ],
                ),
              ],
              if (created != null) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    ticketTime(created),
                    style: GoogleFonts.outfit(fontSize: 10.5, color: timeColor),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
