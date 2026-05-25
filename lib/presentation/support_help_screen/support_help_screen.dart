import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import '../../routes/app_routes.dart';
import '../../widgets/app_toast.dart';
import '../../services/auth_service.dart';
import '../../services/supabase_service.dart';

class SupportHelpScreen extends StatefulWidget {
  const SupportHelpScreen({super.key});

  @override
  State<SupportHelpScreen> createState() => _SupportHelpScreenState();
}

class _SupportHelpScreenState extends State<SupportHelpScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;
  List<Map<String, dynamic>> _myTickets = [];
  bool _loadingTickets = true;

  SupabaseClient get _client => SupabaseService.instance.client;

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
    _loadMyTickets();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadMyTickets() async {
    setState(() => _loadingTickets = true);
    try {
      final user = AuthService.instance.currentUser;
      if (user == null) {
        setState(() => _loadingTickets = false);
        return;
      }
      final res = await _client
          .from('support_tickets')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _myTickets = List<Map<String, dynamic>>.from(res as List);
          _loadingTickets = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingTickets = false);
    }
  }

  Future<void> _submitTicket(
    String subject,
    String message,
    String category,
  ) async {
    setState(() => _isLoading = true);
    try {
      final user = AuthService.instance.currentUser;
      if (user == null) {
        Navigator.pushNamed(context, AppRoutes.signUpLogin);
        return;
      }
      await _client.from('support_tickets').insert({
        'user_id': user.id,
        'subject': subject,
        'message': message,
        'category': category,
        'status': 'open',
        'created_at': DateTime.now().toIso8601String(),
      });
      if (mounted) {
        AppToast.show(
          context,
          message: 'Ticket envoyé ! Notre équipe vous répondra sous 24h.',
          type: ToastType.success,
        );
        _loadMyTickets();
        _tabController.animateTo(1);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          message: 'Erreur lors de l\'envoi. Réessayez.',
          type: ToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
              'Asoukaa — Bénin Facile',
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
          tabs: const [
            Tab(text: '🎫 Nouveau Ticket'),
            Tab(text: '📋 Mes Tickets'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _NewTicketTab(onSubmit: _submitTicket, isLoading: _isLoading),
          _MyTicketsTab(
            tickets: _myTickets,
            isLoading: _loadingTickets,
            onRefresh: _loadMyTickets,
          ),
        ],
      ),
    );
  }
}

// ─── New Ticket Tab ───────────────────────────────────────────────────────────

class _NewTicketTab extends StatefulWidget {
  final Future<void> Function(String subject, String message, String category)
  onSubmit;
  final bool isLoading;

  const _NewTicketTab({required this.onSubmit, required this.isLoading});

  @override
  State<_NewTicketTab> createState() => _NewTicketTabState();
}

class _NewTicketTabState extends State<_NewTicketTab> {
  final _subjectCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  String _selectedCategory = 'Commande';

  final List<String> _categories = [
    'Commande',
    'Paiement',
    'Livraison',
    'Produit défectueux',
    'Remboursement',
    'Compte',
    'Vendeur',
    'Autre',
  ];

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Contact info banner
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
                        'Nous sommes là pour vous aider',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Réponse garantie sous 24h ouvrables',
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

          // Quick contact options
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
            'Décrivez votre problème et notre équipe vous contactera.',
            style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.muted),
          ),
          const SizedBox(height: 16),

          // Category
          Text(
            'Catégorie',
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
            children: _categories.map((cat) {
              final isSelected = _selectedCategory == cat;
              return GestureDetector(
                onTap: () => setState(() => _selectedCategory = cat),
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
                      color: isSelected ? AppTheme.primary : AppTheme.outline,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    cat,
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: isSelected
                          ? AppTheme.primary
                          : AppTheme.textSecondary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Subject
          TextField(
            controller: _subjectCtrl,
            decoration: InputDecoration(
              labelText: 'Sujet *',
              hintText: 'Ex: Commande non reçue, produit défectueux...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppTheme.primary,
                  width: 1.5,
                ),
              ),
            ),
            style: GoogleFonts.outfit(fontSize: 14),
          ),
          const SizedBox(height: 14),

          // Message
          TextField(
            controller: _messageCtrl,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: 'Description *',
              hintText: 'Décrivez votre problème en détail...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppTheme.primary,
                  width: 1.5,
                ),
              ),
              alignLabelWithHint: true,
            ),
            style: GoogleFonts.outfit(fontSize: 14),
          ),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: widget.isLoading
                  ? null
                  : () {
                      if (_subjectCtrl.text.trim().isEmpty ||
                          _messageCtrl.text.trim().isEmpty) {
                        AppToast.show(
                          context,
                          message:
                              'Veuillez remplir tous les champs obligatoires.',
                          type: ToastType.error,
                        );
                        return;
                      }
                      widget.onSubmit(
                        _subjectCtrl.text.trim(),
                        _messageCtrl.text.trim(),
                        _selectedCategory,
                      );
                      _subjectCtrl.clear();
                      _messageCtrl.clear();
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: widget.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
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

          // FAQ section
          Text(
            'Questions fréquentes',
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

  static const List<Map<String, String>> _faqItems = [
    {
      'q': 'Comment suivre ma commande ?',
      'a':
          'Allez dans votre tableau de bord → Commandes → cliquez sur votre commande pour voir le suivi en temps réel.',
    },
    {
      'q': 'Comment demander un remboursement ?',
      'a':
          'Ouvrez un ticket de support avec la catégorie "Remboursement" et indiquez votre numéro de commande. Notre équipe traitera votre demande sous 24h.',
    },
    {
      'q': 'Comment contacter un vendeur ?',
      'a':
          'Sur la page produit, cliquez sur "Contacter le vendeur" pour démarrer une conversation directe.',
    },
    {
      'q': 'Quels sont les délais de livraison ?',
      'a':
          'Livraison locale à Cotonou : 24-48h. Autres villes du Bénin : 2-5 jours. Import Chine : 10-18 jours.',
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

// ─── My Tickets Tab ───────────────────────────────────────────────────────────

class _MyTicketsTab extends StatelessWidget {
  final List<Map<String, dynamic>> tickets;
  final bool isLoading;
  final VoidCallback onRefresh;

  const _MyTicketsTab({
    required this.tickets,
    required this.isLoading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    if (tickets.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.primaryMuted,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.confirmation_number_outlined,
                size: 40,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Aucun ticket ouvert',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Vos tickets de support apparaîtront ici.',
              style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.muted),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      color: AppTheme.primary,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: tickets.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final t = tickets[i];
          final status = t['status'] as String? ?? 'open';
          final statusColors = {
            'open': const Color(0xFFD97706),
            'in_progress': const Color(0xFF3B82F6),
            'resolved': const Color(0xFF10B981),
            'closed': const Color(0xFF9E9E9E),
          };
          final statusLabels = {
            'open': 'Ouvert',
            'in_progress': 'En cours',
            'resolved': 'Résolu',
            'closed': 'Fermé',
          };
          final statusColor = statusColors[status] ?? const Color(0xFFD97706);
          final createdAt = t['created_at'] as String? ?? '';
          String dateStr = '';
          if (createdAt.isNotEmpty) {
            try {
              final dt = DateTime.parse(createdAt).toLocal();
              dateStr =
                  '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
            } catch (_) {}
          }

          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
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
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withAlpha(25),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        statusLabels[status] ?? status,
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (t['category'] != null)
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
                          t['category'] as String,
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    const Spacer(),
                    Text(
                      dateStr,
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: AppTheme.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  t['subject'] as String? ?? 'Sans sujet',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  t['message'] as String? ?? '',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                // Admin response
                if (t['admin_response'] != null &&
                    (t['admin_response'] as String).isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryMuted,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.support_agent_rounded,
                          size: 16,
                          color: AppTheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Réponse de l\'équipe Asoukaa',
                                style: GoogleFonts.outfit(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.primary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                t['admin_response'] as String,
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
