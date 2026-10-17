import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../routes/app_routes.dart';
import '../../services/nest_auth_service.dart';
import '../../services/support_ticket_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import 'ticket_widgets.dart';

/// Support et aide : ouvrir un ticket (avec captures d'ecran), suivre ses
/// tickets et consulter la FAQ.
///
/// Arguments facultatifs (ModalRoute) : une Map avec
///  - 'category'    : categorie a preselectionner (ex. 'Commande')
///  - 'orderId'     : identifiant (uuid) de la commande concernee
///  - 'orderNumber' : numero de commande, pour l'affichage
///  - 'tab'         : 'tickets' pour ouvrir directement " Mes tickets "
/// ou simplement une String (la categorie).
class SupportHelpScreen extends StatefulWidget {
  const SupportHelpScreen({super.key});

  @override
  State<SupportHelpScreen> createState() => _SupportHelpScreenState();
}

const List<String> _kCategories = [
  'Commande',
  'Paiement',
  'Livraison',
  'Produit d\u00e9fectueux',
  'Remboursement',
  'Compte',
  'Vendeur',
  'Autre',
];

final RegExp _kUuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

class _SupportHelpScreenState extends State<SupportHelpScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final GlobalKey<_MyTicketsTabState> _ticketsKey =
      GlobalKey<_MyTicketsTabState>();

  bool _argsRead = false;
  String? _initialCategory;
  String? _initialOrderId;
  String? _initialOrderNumber;
  int _unreadTickets = 0;

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
    _tabController = TabController(length: 2, vsync: this);
    _loadUnread();
  }

  /// Pastille " non lu " de l'onglet, disponible des l'ouverture de l'ecran.
  Future<void> _loadUnread() async {
    try {
      final loggedIn = await NestAuthService.instance
          .isLoggedIn()
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      if (!loggedIn || !mounted) return;
      final n = await SupportTicketService.instance.unreadCount();
      if (mounted && n != _unreadTickets) setState(() => _unreadTickets = n);
    } catch (_) {
      // Simple confort visuel : aucune erreur a afficher.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsRead) return;
    _argsRead = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      _initialCategory = _matchCategory(args['category']?.toString());
      final orderId = args['orderId']?.toString().trim();
      if (orderId != null && _kUuid.hasMatch(orderId)) {
        _initialOrderId = orderId;
        final number = args['orderNumber']?.toString().trim();
        if (number != null && number.isNotEmpty) _initialOrderNumber = number;
      }
      if (args['tab']?.toString() == 'tickets') {
        _tabController.index = 1;
      }
    } else if (args is String) {
      _initialCategory = _matchCategory(args);
    }
  }

  static String? _matchCategory(String? value) {
    if (value == null) return null;
    final wanted = value.trim().toLowerCase();
    for (final c in _kCategories) {
      if (c.toLowerCase() == wanted) return c;
    }
    return null;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onTicketCreated() {
    _ticketsKey.currentState?.refresh();
    _tabController.animateTo(1);
  }

  @override
  Widget build(BuildContext context) {
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
              'Support et Aide',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            Text(
              'Asoukaa \u2014 B\u00e9nin Facile',
              style: GoogleFonts.outfit(fontSize: 11, color: AppTheme.muted),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.muted,
          indicatorColor: AppTheme.primary,
          labelStyle: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: GoogleFonts.outfit(fontSize: 13),
          tabs: [
            const Tab(text: 'Nouveau ticket'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Mes tickets'),
                  if (_unreadTickets > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$_unreadTickets',
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _NewTicketTab(
            initialCategory: _initialCategory,
            initialOrderId: _initialOrderId,
            initialOrderNumber: _initialOrderNumber,
            onCreated: _onTicketCreated,
          ),
          _MyTicketsTab(
            key: _ticketsKey,
            onUnreadChanged: (n) {
              if (mounted && n != _unreadTickets) {
                setState(() => _unreadTickets = n);
              }
            },
            onNewTicket: () => _tabController.animateTo(0),
          ),
        ],
      ),
    );
  }
}

// --- Onglet " Nouveau ticket " -----------------------------------------------

class _NewTicketTab extends StatefulWidget {
  final String? initialCategory;
  final String? initialOrderId;
  final String? initialOrderNumber;
  final VoidCallback onCreated;

  const _NewTicketTab({
    required this.initialCategory,
    required this.initialOrderId,
    required this.initialOrderNumber,
    required this.onCreated,
  });

  @override
  State<_NewTicketTab> createState() => _NewTicketTabState();
}

class _NewTicketTabState extends State<_NewTicketTab>
    with AutomaticKeepAliveClientMixin<_NewTicketTab> {
  final _formKey = GlobalKey<FormState>();
  final _subjectCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  final List<PickedTicketImage> _images = [];

  late String _category;
  String? _orderId;
  String? _orderNumber;
  bool _sending = false;
  bool _picking = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory ?? _kCategories.first;
    _orderId = widget.initialOrderId;
    _orderNumber = widget.initialOrderNumber;
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
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

  Future<void> _submit() async {
    if (_sending) return;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _sending = true);
    try {
      final loggedIn = await NestAuthService.instance
          .isLoggedIn()
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      if (!mounted) return;
      if (!loggedIn) {
        Navigator.pushNamed(context, AppRoutes.signUpLogin);
        return;
      }

      // 1. Envoi des images (une par une ; une image deja envoyee n'est
      //    jamais renvoyee si on reessaie apres une erreur).
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

      // 2. Creation du ticket.
      final ticket = await SupportTicketService.instance.create(
        subject: _subjectCtrl.text,
        message: _messageCtrl.text,
        category: _category,
        orderId: _orderId,
        attachments: urls,
      );
      if (!mounted) return;

      _formKey.currentState?.reset();
      setState(() {
        _images.clear();
        _orderId = null;
        _orderNumber = null;
      });
      AppToast.show(
        context,
        message:
            'Ticket ${ticket.reference} envoy\u00e9 ! Notre \u00e9quipe vous r\u00e9pondra sous 24h.',
        type: ToastType.success,
      );
      widget.onCreated();
    } on TicketException catch (e) {
      if (mounted) {
        AppToast.show(context, message: e.message, type: ToastType.error);
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          message: 'Erreur lors de l\'envoi. R\u00e9essayez.',
          type: ToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  InputDecoration _decoration({
    required String label,
    required String hint,
    bool alignLabelWithHint = false,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      alignLabelWithHint: alignLabelWithHint,
      filled: true,
      fillColor: AppTheme.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bandeau d'accueil
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF6210), Color(0xFFFF8C42)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.support_agent_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nous sommes l\u00e0 pour vous aider',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'R\u00e9ponse garantie sous 24h ouvrables',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: Colors.white.withAlpha(220),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Contacts rapides
          Row(
            children: [
              Expanded(
                child: _ContactCard(
                  icon: Icons.phone_rounded,
                  label: 'Appeler',
                  value: '+229 0164693637',
                  color: const Color(0xFF10B981),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ContactCard(
                  icon: Icons.email_rounded,
                  label: 'Email',
                  value: 'contact@asoukaa.com',
                  color: const Color(0xFF3B82F6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          Text(
            'Ouvrir un ticket de support',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'D\u00e9crivez votre probl\u00e8me et notre \u00e9quipe vous r\u00e9pondra ici m\u00eame.',
            style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.muted),
          ),
          const SizedBox(height: 16),

          Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Categorie
                Text(
                  'Cat\u00e9gorie',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _kCategories.map((cat) {
                    final isSelected = _category == cat;
                    return GestureDetector(
                      onTap: _sending
                          ? null
                          : () => setState(() => _category = cat),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTheme.primaryMuted
                              : AppTheme.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color:
                                isSelected ? AppTheme.primary : AppTheme.outline,
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Text(
                          cat,
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w400,
                            color: isSelected
                                ? AppTheme.primary
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                // Carte d'info " Remboursement "
                if (_category == 'Remboursement') ...[
                  const SizedBox(height: 12),
                  _buildRefundCard(),
                ],

                // Commande liee
                if (_orderId != null) ...[
                  const SizedBox(height: 12),
                  _buildOrderCard(),
                ],
                const SizedBox(height: 16),

                // Sujet
                TextFormField(
                  controller: _subjectCtrl,
                  enabled: !_sending,
                  maxLength: 150,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  decoration: _decoration(
                    label: 'Sujet *',
                    hint: 'Ex: Commande non re\u00e7ue, produit d\u00e9fectueux...',
                  ),
                  style: GoogleFonts.outfit(fontSize: 14),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return 'Le sujet est obligatoire';
                    if (t.length < 3) {
                      return 'Le sujet doit contenir au moins 3 caract\u00e8res';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),

                // Message
                TextFormField(
                  controller: _messageCtrl,
                  enabled: !_sending,
                  minLines: 5,
                  maxLines: 8,
                  maxLength: 4000,
                  textCapitalization: TextCapitalization.sentences,
                  keyboardType: TextInputType.multiline,
                  decoration: _decoration(
                    label: 'Description *',
                    hint: 'D\u00e9crivez votre probl\u00e8me en d\u00e9tail...',
                    alignLabelWithHint: true,
                  ),
                  style: GoogleFonts.outfit(fontSize: 14),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return 'Le message ne peut pas \u00eatre vide';
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Captures d'ecran
                Text(
                  'Captures d\'\u00e9cran (facultatif)',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Jusqu\'\u00e0 3 images (JPG, PNG ou WEBP, 5 Mo maximum chacune).',
                  style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.muted),
                ),
                if (_images.isNotEmpty)
                  PickedImagesStrip(
                    images: _images,
                    size: 72,
                    onRemove: (i) {
                      if (_sending) return;
                      setState(() => _images.removeAt(i));
                    },
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: (_sending ||
                          _picking ||
                          _images.length >= SupportTicketService.maxImages)
                      ? null
                      : _addImage,
                  icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
                  label: Text(
                    'Ajouter une image (${_images.length}/${SupportTicketService.maxImages})',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.primary),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _sending ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppTheme.primary.withAlpha(150),
                disabledForegroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: _sending
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Envoi en cours...',
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      'Envoyer le ticket',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 24),

          // FAQ
          Text(
            'Questions fr\u00e9quentes',
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ..._faqItems.map(
            (faq) => _FaqItem(question: faq['q']!, answer: faq['a']!),
          ),
        ],
      ),
    );
  }

  Widget _buildRefundCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primary.withAlpha(90)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: AppTheme.primary,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Le remboursement suit un circuit \u00e0 part : pour \u00eatre '
                  'rembours\u00e9, faites une demande d\u00e9di\u00e9e avec votre commande. '
                  'Vous pouvez quand m\u00eame cr\u00e9er ce ticket si vous avez une '
                  'question.',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: AppTheme.textPrimary,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () =>
                  Navigator.pushNamed(context, AppRoutes.refundRequest),
              icon: const Icon(Icons.payments_outlined, size: 18),
              label: Text(
                'Faire une demande de remboursement',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard() {
    final number = _orderNumber;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.outline),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.receipt_long_outlined,
            color: AppTheme.primary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              number != null
                  ? 'Commande concern\u00e9e : $number'
                  : 'Ce ticket sera li\u00e9 \u00e0 votre commande',
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Retirer la commande',
            icon: const Icon(Icons.close_rounded, size: 18),
            color: AppTheme.muted,
            onPressed: _sending
                ? null
                : () => setState(() {
                      _orderId = null;
                      _orderNumber = null;
                    }),
          ),
        ],
      ),
    );
  }

  static const List<Map<String, String>> _faqItems = [
    {
      'q': 'Comment suivre ma commande ?',
      'a':
          'Allez dans votre tableau de bord \u2192 Commandes \u2192 cliquez sur votre commande pour voir le suivi en temps r\u00e9el.',
    },
    {
      'q': 'Comment demander un remboursement ?',
      'a':
          'Choisissez la cat\u00e9gorie "Remboursement" ci-dessus, puis appuyez sur "Faire une demande de remboursement" et indiquez votre num\u00e9ro de commande. Notre \u00e9quipe traitera votre demande sous 24h.',
    },
    {
      'q': 'Comment contacter un vendeur ?',
      'a':
          'Sur la page produit, cliquez sur "Contacter le vendeur" pour d\u00e9marrer une conversation directe.',
    },
    {
      'q': 'Quels sont les d\u00e9lais de livraison ?',
      'a':
          'Livraison locale \u00e0 Cotonou : 24-48h. Autres villes du B\u00e9nin : 2-5 jours. Import Chine : 10-18 jours.',
    },
  ];
}

class _ContactCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _ContactCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.outline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(6),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withAlpha(25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.muted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _FaqItem extends StatefulWidget {
  final String question;
  final String answer;

  const _FaqItem({required this.question, required this.answer});

  @override
  State<_FaqItem> createState() => _FaqItemState();
}

class _FaqItemState extends State<_FaqItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.outline),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.question,
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: AppTheme.muted,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                widget.answer,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// --- Onglet " Mes tickets " --------------------------------------------------

class _MyTicketsTab extends StatefulWidget {
  final ValueChanged<int> onUnreadChanged;
  final VoidCallback onNewTicket;

  const _MyTicketsTab({
    super.key,
    required this.onUnreadChanged,
    required this.onNewTicket,
  });

  @override
  State<_MyTicketsTab> createState() => _MyTicketsTabState();
}

class _MyTicketsTabState extends State<_MyTicketsTab>
    with AutomaticKeepAliveClientMixin<_MyTicketsTab> {
  final ScrollController _scroll = ScrollController();
  final List<TicketSummary> _items = [];

  bool _loading = true;
  bool _loadingMore = false;
  bool _loadMoreFailed = false;
  bool _loggedIn = true;
  bool _hasMore = false;
  String? _error;
  int _page = 1;
  int _generation = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadFirst(showSpinner: false);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  /// Rechargement silencieux (appele quand un ticket vient d'etre cree).
  Future<void> refresh() => _loadFirst(showSpinner: false);

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _loadFirst({bool showSpinner = true}) async {
    final gen = ++_generation;
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final loggedIn = await NestAuthService.instance
        .isLoggedIn()
        .timeout(const Duration(seconds: 5), onTimeout: () => false);
    if (!mounted || gen != _generation) return;
    if (!loggedIn) {
      setState(() {
        _loggedIn = false;
        _loading = false;
        _loadingMore = false;
        _hasMore = false;
        _items.clear();
      });
      widget.onUnreadChanged(0);
      return;
    }
    try {
      final page = await SupportTicketService.instance.list(page: 1);
      if (!mounted || gen != _generation) return;
      setState(() {
        _loggedIn = true;
        _items
          ..clear()
          ..addAll(page.items);
        _page = page.page;
        _hasMore = page.hasMore;
        _loading = false;
        _loadingMore = false;
        _loadMoreFailed = false;
        _error = null;
      });
      _refreshUnread();
    } on TicketException catch (e) {
      if (!mounted || gen != _generation) return;
      final hadItems = _items.isNotEmpty;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (!hadItems) _error = e.message;
      });
      if (hadItems) {
        AppToast.show(context, message: e.message, type: ToastType.error);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _loadMoreFailed) return;
    final gen = _generation;
    setState(() => _loadingMore = true);
    try {
      final page = await SupportTicketService.instance.list(page: _page + 1);
      if (!mounted || gen != _generation) return;
      final known = _items.map((t) => t.id).toSet();
      setState(() {
        _items.addAll(page.items.where((t) => !known.contains(t.id)));
        _page = page.page;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } on TicketException {
      if (!mounted || gen != _generation) return;
      setState(() {
        _loadingMore = false;
        _loadMoreFailed = true;
      });
    }
  }

  void _retryLoadMore() {
    setState(() => _loadMoreFailed = false);
    _loadMore();
  }

  Future<void> _refreshUnread() async {
    try {
      final n = await SupportTicketService.instance.unreadCount();
      if (mounted) widget.onUnreadChanged(n);
    } catch (_) {
      // Le badge est un confort : une erreur ici ne doit rien afficher.
    }
  }

  Future<void> _open(TicketSummary t) async {
    final result = await Navigator.pushNamed<String>(
      context,
      AppRoutes.ticketDetail,
      arguments: {'ticketId': t.id, 'fromSupport': true},
    );
    if (!mounted) return;
    // Au retour : la pastille " non lu " doit avoir disparu.
    _loadFirst(showSpinner: false);
    if (result == 'new_ticket') widget.onNewTicket();
  }

  Widget _scrollableCenter(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _stateView({
    required IconData icon,
    required String title,
    required String message,
    String? buttonLabel,
    VoidCallback? onButton,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: AppTheme.primaryMuted,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(icon, size: 40, color: AppTheme.primary),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            fontSize: 13,
            color: AppTheme.muted,
            height: 1.4,
          ),
        ),
        if (buttonLabel != null && onButton != null) ...[
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: onButton,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              buttonLabel,
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    if (!_loggedIn) {
      return _scrollableCenter(
        _stateView(
          icon: Icons.lock_outline_rounded,
          title: 'Connectez-vous',
          message: 'Connectez-vous pour voir vos tickets et les r\u00e9ponses de notre \u00e9quipe.',
          buttonLabel: 'Se connecter',
          onButton: () {
            Navigator.pushNamed(context, AppRoutes.signUpLogin).then((_) {
              if (mounted) _loadFirst();
            });
          },
        ),
      );
    }

    final Widget content;
    if (_items.isEmpty) {
      content = _scrollableCenter(
        _error != null
            ? _stateView(
                icon: Icons.cloud_off_rounded,
                title: 'Chargement impossible',
                message: _error!,
                buttonLabel: 'R\u00e9essayer',
                onButton: () => _loadFirst(),
              )
            : _stateView(
                icon: Icons.confirmation_number_outlined,
                title: 'Aucun ticket pour le moment',
                message:
                    'Vos demandes d\'aide appara\u00eetront ici avec les r\u00e9ponses de notre \u00e9quipe.',
                buttonLabel: 'Ouvrir un ticket',
                onButton: widget.onNewTicket,
              ),
      );
    } else {
      final showFooter = _loadingMore || _loadMoreFailed;
      content = ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: _items.length + (showFooter ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          if (i >= _items.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: _loadMoreFailed
                    ? TextButton.icon(
                        onPressed: _retryLoadMore,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(
                          'Impossible de charger la suite. R\u00e9essayer',
                          style: GoogleFonts.outfit(fontSize: 13),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.primary,
                        ),
                      )
                    : const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.primary,
                        ),
                      ),
              ),
            );
          }
          final t = _items[i];
          return _TicketCard(ticket: t, onTap: () => _open(t));
        },
      );
    }

    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: () => _loadFirst(showSpinner: false),
      child: content,
    );
  }
}

class _TicketCard extends StatelessWidget {
  final TicketSummary ticket;
  final VoidCallback onTap;

  const _TicketCard({required this.ticket, required this.onTap});

  String _previewText() {
    final last = ticket.lastMessage;
    if (last == null) return '';
    final who = last.fromAdmin ? '\u00c9quipe Asoukaa : ' : 'Vous : ';
    if (last.preview.isEmpty) {
      if (last.attachmentCount > 0) {
        return '$who${last.attachmentCount} image(s) jointe(s)';
      }
      return '';
    }
    return '$who${last.preview}';
  }

  @override
  Widget build(BuildContext context) {
    final unread = ticket.hasUnread;
    final preview = _previewText();
    final attachments = ticket.lastMessage?.attachmentCount ?? 0;

    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: unread ? AppTheme.primary.withAlpha(110) : AppTheme.outline,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      ticket.reference,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TicketStatusChip(status: ticket.status),
                  const Spacer(),
                  Text(
                    ticketListDate(ticket.lastMessageAt),
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      color: unread ? AppTheme.primary : AppTheme.muted,
                      fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (unread) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Text(
                ticket.subject.isEmpty ? 'Sans sujet' : ticket.subject,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: unread ? FontWeight.w800 : FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              if (preview.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (attachments > 0 && ticket.lastMessage!.preview.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(
                          Icons.attach_file_rounded,
                          size: 14,
                          color: AppTheme.muted,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          color: unread
                              ? AppTheme.textPrimary
                              : AppTheme.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (ticket.category.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    ticket.category,
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
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
