import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
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
    });
  }

  Future<void> _submitRequest() async {
    if (_selectedOrderId == null) {
      AppToast.show(
        context,
        message: 'Sélectionnez une commande.',
        type: ToastType.error,
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      await ApiService.instance.client.post(
        '/api/v1/payments/refund',
        data: {
          'orderId': _selectedOrderId,
          'motif': _motifController.text.trim(),
          'montantRemb': double.tryParse(_amountController.text.trim()) ?? 0,
        },
      );
      if (!mounted) return;
      AppToast.show(
        context,
        message: 'Votre demande de remboursement a été envoyée.',
        type: ToastType.success,
      );
      _motifController.clear();
      setState(() => _selectedOrderId = null);
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

  String _extractErrorMessage(Object e) {
    try {
      final response = (e as dynamic).response;
      final data = response?.data;
      if (data is Map && data['message'] != null) {
        final msg = data['message'];
        if (msg is String) return msg;
        if (msg is List && msg.isNotEmpty) return msg.first.toString();
      }
    } catch (_) {}
    return 'La demande a échoué. Réessayez.';
  }

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
              TextFormField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Montant à rembourser (FCFA)',
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
                  onPressed: _isSubmitting ? null : _submitRequest,
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
        ),
      ),
    );
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
