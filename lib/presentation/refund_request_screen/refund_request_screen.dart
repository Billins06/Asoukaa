import 'package:dio/dio.dart' show DioException;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/lecture_json.dart';
import '../../widgets/app_toast.dart';

/// Écran client : demander un remboursement pour une commande livrée ou
/// annulée, et suivre le statut des demandes déjà envoyées
/// (en attente / approuvé / rejetté / traité).
///
/// Basé sur les règles réelles du backend (POST /payments/refund) :
/// - la commande doit être livrée ou annulée,
/// - un paiement confirmé doit exister pour cette commande,
/// - une seule demande par commande,
/// - le montant ne peut pas dépasser le montant payé.
class RefundRequestScreen extends StatefulWidget {
  const RefundRequestScreen({super.key});

  @override
  State<RefundRequestScreen> createState() => _RefundRequestScreenState();
}

class _RefundRequestScreenState extends State<RefundRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _motifController = TextEditingController();

  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _hasError = false;

  List<Map<String, dynamic>> _eligibleOrders = [];
  List<Map<String, dynamic>> _refunds = [];
  String? _selectedOrderId;

  // Aperçu du remboursement demandé au serveur (GET /payments/refund-preview).
  // Si le serveur est ancien ou injoignable, ces valeurs restent à leur état
  // par défaut et l'écran garde l'ancien comportement (champ de saisie).
  int _previewJeton = 0; // ignore les réponses arrivées en retard
  bool _previewLoading = false;
  String? _previewErreur; // message du serveur (erreur 400)
  bool _montantFixe = false; // true : commande livrée, montant imposé
  bool _delaiDepasse = false; // true : 24 h après livraison dépassées
  double? _montantServeur; // montant fixe, ou plafond pour une annulée
  String? _messageApercu; // explication envoyée par le serveur (facultatif)
  int _formVersion = 0; // change pour réinitialiser la liste déroulante

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _motifController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final results = await Future.wait([
        ApiService.instance.client.get(
          '/api/v1/orders/me',
          queryParameters: {'limit': 100},
        ),
        ApiService.instance.client.get(
          '/api/v1/payments/refunds/me',
          queryParameters: {'limit': 50},
        ),
      ]);

      final ordersBody = results[0].data;
      final rawOrders = ordersBody is Map
          ? (ordersBody['data'] as List? ?? [])
          : (ordersBody is List ? ordersBody : []);

      final refundsBody = results[1].data;
      final rawRefunds = refundsBody is Map
          ? (refundsBody['data'] as List? ?? [])
          : (refundsBody is List ? refundsBody : []);

      // Commandes déjà couvertes par une demande de remboursement
      // (une seule demande autorisée par commande côté backend).
      final refundedOrderIds = rawRefunds
          .whereType<Map>()
          .map((r) => r['orderId']?.toString())
          .whereType<String>()
          .toSet();

      final eligible = rawOrders.whereType<Map>().where((o) {
        final status = (o['status'] as String? ?? '').toLowerCase();
        final isEligibleStatus = status == 'livré' || status == 'annulé';
        final id = o['id']?.toString() ?? '';
        return isEligibleStatus && !refundedOrderIds.contains(id);
      }).map((o) {
        final total = double.tryParse(o['total']?.toString() ?? '') ?? 0;
        return {
          'id': o['id']?.toString() ?? '',
          'orderNumber': o['orderNumber'] as String? ?? '',
          'total': total,
        };
      }).toList();

      final refunds = rawRefunds.whereType<Map>().map((r) {
        final order = r['order'] as Map<String, dynamic>?;
        final montant = double.tryParse(r['montantRemb']?.toString() ?? '') ?? 0;
        return {
          'id': r['id']?.toString() ?? '',
          'orderNumber': order?['orderNumber'] as String? ?? '',
          'montant': montant,
          'motif': r['motif'] as String? ?? '',
          'status': r['status'] as String? ?? 'en attente',
          'dateDemande': r['dateDemande'] as String? ?? '',
        };
      }).toList();

      if (mounted) {
        setState(() {
          _eligibleOrders = eligible.cast<Map<String, dynamic>>();
          _refunds = refunds.cast<Map<String, dynamic>>();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  void _onOrderSelected(String? orderId) {
    setState(() {
      _selectedOrderId = orderId;
      final order = _eligibleOrders.firstWhere(
        (o) => o['id'] == orderId,
        orElse: () => {},
      );
      final total = order['total'] as double? ?? 0;
      _amountController.text = total > 0 ? total.toStringAsFixed(0) : '';
      _effacerApercu();
    });
    if (orderId != null) _loadPreview(orderId);
  }

  /// Remet l'aperçu à zéro (à appeler dans un setState).
  void _effacerApercu() {
    _previewJeton++;
    _previewLoading = false;
    _previewErreur = null;
    _montantFixe = false;
    _messageApercu = null;
    _delaiDepasse = false;
    _montantServeur = null;
  }

  /// Demande au serveur le montant remboursable de la commande choisie.
  /// - 400 (ou 404 « commande introuvable ») : message du serveur affiché ;
  /// - ancien serveur (404 « Cannot GET »), réseau, autre erreur : on garde
  ///   l'ancien comportement (champ de saisie), le serveur validera à l'envoi.
  Future<void> _loadPreview(String orderId) async {
    final jeton = ++_previewJeton;
    setState(() {
      _previewLoading = true;
      _previewErreur = null;
      _montantFixe = false;
      _messageApercu = null;
      _delaiDepasse = false;
      _montantServeur = null;
    });
    try {
      final res = await ApiService.instance.client.get(
        '/api/v1/payments/refund-preview/${Uri.encodeComponent(orderId)}',
      );
      if (!mounted || jeton != _previewJeton) return;
      final data = res.data;
      if (data is Map) {
        final montant = lireDoubleOuNull(data['montant']);
        final fixe = data['montantFixe'] == true && montant != null;
        setState(() {
          _previewLoading = false;
          _montantFixe = fixe;
          _montantServeur = montant;
          _messageApercu = (data['message'] is String &&
                  (data['message'] as String).trim().isNotEmpty)
              ? (data['message'] as String).trim()
              : null;
          _delaiDepasse = fixe && data['delaiDepasse'] == true;
        });
      } else {
        setState(() => _previewLoading = false);
      }
    } on DioException catch (e) {
      if (!mounted || jeton != _previewJeton) return;
      final code = e.response?.statusCode;
      final msg = _messageServeur(e);
      final refus = code == 400 ||
          (code == 404 &&
              msg != null &&
              !msg.toLowerCase().contains('cannot get'));
      setState(() {
        _previewLoading = false;
        _previewErreur = refus
            ? (msg ?? 'Cette commande ne peut pas être remboursée.')
            : null;
      });
    } catch (_) {
      if (!mounted || jeton != _previewJeton) return;
      setState(() => _previewLoading = false);
    }
  }

  Future<void> _submitRequest() async {
    // Protection contre le double clic et contre un envoi pendant le calcul.
    if (_isSubmitting || _previewLoading) return;
    if (_selectedOrderId == null) {
      AppToast.show(
        context,
        message: 'Sélectionnez une commande.',
        type: ToastType.error,
      );
      return;
    }
    if (_previewErreur != null) return;
    if (_montantFixe && _delaiDepasse) {
      AppToast.show(
        context,
        message: 'Le délai de 24 h après la livraison est dépassé : '
            'la demande n\'est plus possible.',
        type: ToastType.error,
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    // Commande livrée : montant fixé par le serveur (il applique le sien,
    // mais le champ reste obligatoire). Sinon : montant saisi.
    final double montant = _montantFixe
        ? (_montantServeur ?? 0.0)
        : (double.tryParse(_amountController.text.trim()) ?? 0.0);

    setState(() => _isSubmitting = true);
    try {
      await ApiService.instance.client.post(
        '/api/v1/payments/refund',
        data: {
          'orderId': _selectedOrderId,
          'motif': _motifController.text.trim(),
          'montantRemb': montant,
        },
      );
      if (!mounted) return;
      AppToast.show(
        context,
        message: 'Votre demande de remboursement a été envoyée.',
        type: ToastType.success,
      );
      _motifController.clear();
      setState(() {
        _selectedOrderId = null;
        _effacerApercu();
        _formVersion++;
      });
      _amountController.clear();
      await _loadData();
    } on Object catch (e) {
      final message = _extractErrorMessage(e);
      if (!mounted) return;
      AppToast.show(context, message: message, type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Message d'erreur envoyé par le serveur, ou null s'il n'y en a pas.
  String? _messageServeur(Object e) {
    try {
      final response = (e as dynamic).response;
      final data = response?.data;
      if (data is Map && data['message'] != null) {
        final msg = data['message'];
        if (msg is String && msg.trim().isNotEmpty) return msg;
        if (msg is List && msg.isNotEmpty) return msg.first.toString();
      }
    } catch (_) {}
    return null;
  }

  String _extractErrorMessage(Object e) =>
      _messageServeur(e) ?? 'La demande a échoué. Réessayez.';

  Color _statusColor(String status) {
    switch (status) {
      case 'approuvé':
        return AppTheme.success;
      case 'rejetté':
        return AppTheme.error;
      case 'traité':
        return AppTheme.primary;
      default:
        return AppTheme.warning;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'approuvé':
        return 'Approuvée';
      case 'rejetté':
        return 'Refusée';
      case 'traité':
        return 'Remboursée';
      default:
        return 'En attente';
    }
  }

  String _formatAmount(double amount) {
    final s = amount.toStringAsFixed(0);
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return '${buf.toString()} FCFA';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        title: Text(
          'Remboursements',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _hasError
              ? _buildErrorState()
              : RefreshIndicator(
                  onRefresh: _loadData,
                  color: AppTheme.primary,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildForm(),
                        const SizedBox(height: 24),
                        Text(
                          'Mes demandes',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_refunds.isEmpty) _buildEmptyRefunds(),
                        ..._refunds.map(_buildRefundCard),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 48, color: AppTheme.muted),
            const SizedBox(height: 12),
            Text(
              'Impossible de charger vos remboursements.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadData,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyRefunds() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.outline),
      ),
      child: Text(
        'Vous n\'avez encore fait aucune demande de remboursement.',
        style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.textSecondary),
      ),
    );
  }

  Widget _buildForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outline),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nouvelle demande',
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Seules les commandes livrées ou annulées, déjà payées, '
              'peuvent faire l\'objet d\'un remboursement.',
              style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 14),
            if (_eligibleOrders.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Aucune commande éligible pour l\'instant.',
                  style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.textSecondary),
                ),
              )
            else ...[
              DropdownButtonFormField<String>(
                key: ValueKey<int>(_formVersion),
                initialValue: _selectedOrderId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Commande concernée',
                  filled: true,
                  fillColor: AppTheme.surfaceVariant,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                items: _eligibleOrders
                    .map(
                      (o) => DropdownMenuItem(
                        value: o['id'] as String,
                        child: Text(
                          '${o['orderNumber']} — ${_formatAmount(o['total'] as double)}',
                          style: GoogleFonts.outfit(fontSize: 13),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _onOrderSelected,
                validator: (v) => v == null ? 'Requis' : null,
              ),
              const SizedBox(height: 12),
              ..._buildSectionMontant(),
              if (_previewErreur == null) ...[
                TextFormField(
                  controller: _motifController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Motif du remboursement',
                    hintText: 'Ex : produit non conforme, colis endommagé...',
                    filled: true,
                    fillColor: AppTheme.surfaceVariant,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Le motif est obligatoire' : null,
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: (_isSubmitting ||
                          _previewLoading ||
                          (_montantFixe && _delaiDepasse))
                      ? null
                      : _submitRequest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Envoyer la demande',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// Zone « montant » du formulaire : chargement, erreur du serveur,
  /// montant fixe (commande livrée) ou champ de saisie (commande annulée /
  /// ancien serveur). Chaque cas se termine par un espacement.
  List<Widget> _buildSectionMontant() {
    if (_previewLoading) {
      return [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Calcul du montant remboursable...',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ];
    }

    final erreur = _previewErreur;
    if (erreur != null) {
      return [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.errorContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                erreur,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.error,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      final id = _selectedOrderId;
                      if (id != null) _loadPreview(id);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Réessayer'),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _selectedOrderId = null;
                      _amountController.clear();
                      _effacerApercu();
                      _formVersion++;
                    }),
                    child: const Text('Choisir une autre commande'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ];
    }

    if (_montantFixe) {
      return [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Montant remboursé : ${_formatAmount(_montantServeur ?? 0.0)}',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _messageApercu ??
                    'Ce montant correspond à la part reversée au vendeur. '
                        'Les frais de service et de livraison ne sont pas '
                        'remboursables.',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (_delaiDepasse) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.errorContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  size: 18,
                  color: AppTheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Le délai de 24 h après la livraison est dépassé : '
                    'la demande n\'est plus possible.',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
      ];
    }

    // Commande annulée (ou ancien serveur) : saisie libre comme avant.
    final plafond = _montantServeur;
    return [
              TextFormField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Montant à rembourser (FCFA)',
                  helperText: (plafond != null && plafond > 0)
                      ? 'Maximum remboursable : ${_formatAmount(plafond)}'
                      : null,
                  filled: true,
                  fillColor: AppTheme.surfaceVariant,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (v) {
                  final val = double.tryParse(v?.trim() ?? '');
                  if (val == null || val <= 0) return 'Montant invalide';
                  return null;
                },
              ),
              const SizedBox(height: 12),
    ];
  }

  Widget _buildRefundCard(Map<String, dynamic> r) {
    final status = r['status'] as String;
    final color = _statusColor(status);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
              Expanded(
                child: Text(
                  r['orderNumber'] as String,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withAlpha(25),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _statusLabel(status),
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _formatAmount(r['montant'] as double),
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            r['motif'] as String,
            style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}
