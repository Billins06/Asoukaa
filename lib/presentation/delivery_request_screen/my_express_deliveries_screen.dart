import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../routes/app_routes.dart';
import '../../services/express_delivery_service.dart';
import '../../services/payment_prefs_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';

/// « Mes courses express » (client) : suivi des demandes, réponse à la
/// contre-proposition d'un livreur et paiement Mobile Money de la course.
class MyExpressDeliveriesScreen extends StatefulWidget {
  const MyExpressDeliveriesScreen({super.key});

  @override
  State<MyExpressDeliveriesScreen> createState() =>
      _MyExpressDeliveriesScreenState();
}

class _MyExpressDeliveriesScreenState extends State<MyExpressDeliveriesScreen> {
  final _service = ExpressDeliveryService.instance;
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _error = false;
  String? _busyId;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    // Rafraîchissement doux : un livreur peut répondre à tout moment.
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 20), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final list = await _service.myRequests();
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
        _error = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = true;
      });
    }
  }

  void _toast(String msg, ToastType type) {
    if (!mounted) return;
    AppToast.show(context, message: msg, type: type);
  }

  Future<void> _respond(String id, bool accept) async {
    setState(() => _busyId = id);
    try {
      await _service.respondToCounter(id, accept);
      _toast(
        accept
            ? 'Prix accepté. Payez pour confirmer la course.'
            : 'Contre-proposition refusée.',
        ToastType.success,
      );
      await _load(silent: true);
    } catch (e) {
      _toast(ExpressDeliveryService.errorMessage(e, 'Action impossible.'),
          ToastType.error);
      await _load(silent: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _cancel(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Annuler la demande ?', style: GoogleFonts.outfit()),
        content: Text('Les livreurs ne la verront plus.',
            style: GoogleFonts.outfit()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Non', style: GoogleFonts.outfit())),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Oui, annuler', style: GoogleFonts.outfit())),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busyId = id);
    try {
      await _service.cancel(id);
      _toast('Demande annulée.', ToastType.success);
    } catch (e) {
      _toast(ExpressDeliveryService.errorMessage(e, 'Annulation impossible.'),
          ToastType.error);
    } finally {
      if (mounted) setState(() => _busyId = null);
      await _load(silent: true);
    }
  }

  // ── Paiement Mobile Money ──────────────────────────────────

  Future<void> _pay(Map<String, dynamic> item) async {
    final id = item['id'] as String;
    final amount = toNum(item['tarifConvenu']);
    SavedPaymentMethod? def;
    try {
      def = await PaymentPrefsService.instance.getDefault();
    } catch (_) {}
    if (!mounted) return;

    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _PaySheet(
        amount: amount,
        initialOperator: def?.operator ?? 'MTN',
        initialNumber: def?.number ?? '',
      ),
    );
    if (result == null || !mounted) return;

    setState(() => _busyId = id);
    try {
      await _service.pay(id,
          operator: result['operator']!, phoneNumber: result['number']!);
      _toast('Confirmez le paiement sur votre téléphone.', ToastType.success);
      await _waitForPayment(id);
    } catch (e) {
      _toast(
          ExpressDeliveryService.errorMessage(
              e, 'Impossible de lancer le paiement.'),
          ToastType.error);
    } finally {
      if (mounted) setState(() => _busyId = null);
      await _load(silent: true);
    }
  }

  /// Interroge le serveur toutes les 4 s (3 min max) jusqu'au résultat.
  Future<void> _waitForPayment(String id) async {
    for (var i = 0; i < 45; i++) {
      await Future.delayed(const Duration(seconds: 4));
      if (!mounted) return;
      try {
        final r = await _service.paymentStatus(id);
        final ps = r['paymentStatus'];
        if (ps == 'success') {
          _toast('Paiement confirmé. Votre livreur est prévenu !',
              ToastType.success);
          return;
        }
        if (ps == 'échoué') {
          _toast('Paiement échoué ou refusé. Vous pouvez réessayer.',
              ToastType.error);
          return;
        }
        final st = r['status'];
        if (st != 'paiement en attente' && ps != 'en attente') return;
      } catch (_) {}
    }
    _toast('Paiement toujours en attente. Il sera mis à jour automatiquement.',
        ToastType.info);
  }

  // ── UI ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        title: Text('Mes courses express',
            style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary)),
        actions: [
          IconButton(
            tooltip: 'Nouvelle course',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => Navigator.pushReplacementNamed(
                context, AppRoutes.deliveryRequest),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : _error
              ? Center(
                  child: TextButton(
                    onPressed: _load,
                    child: Text('Erreur de chargement — réessayer',
                        style: GoogleFonts.outfit()),
                  ),
                )
              : _items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'Aucune course pour le moment.\nAppuyez sur + pour demander un livreur.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(color: AppTheme.muted),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      color: AppTheme.primary,
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length,
                        itemBuilder: (_, i) => _card(_items[i]),
                      ),
                    ),
    );
  }

  Widget _card(Map<String, dynamic> d) {
    final id = d['id'] as String;
    final status = d['status'] as String? ?? '';
    final ps = d['paymentStatus'] as String?;
    final busy = _busyId == id;
    final agent = d['agent'] is Map ? Map<String, dynamic>.from(d['agent']) : null;

    String label;
    Color color;
    switch (status) {
      case 'en attente':
        label = 'En attente d\'un livreur';
        color = AppTheme.warning;
        break;
      case 'contre-proposition':
        label = 'Contre-proposition reçue';
        color = AppTheme.primary;
        break;
      case 'paiement en attente':
        label = ps == 'en attente'
            ? 'Paiement en cours…'
            : ps == 'à vérifier'
                ? 'Paiement à vérifier'
                : 'À payer';
        color = AppTheme.primary;
        break;
      case 'accepté':
        label = 'Payée — le livreur arrive';
        color = AppTheme.success;
        break;
      case 'en cours de livraison':
        label = 'En route';
        color = AppTheme.success;
        break;
      case 'livré':
        label = 'Livrée';
        color = AppTheme.success;
        break;
      default:
        final refund = d['refundStatus'];
        label = refund == 'à rembourser'
            ? 'Annulée — remboursement en cours'
            : refund == 'remboursé'
                ? 'Annulée — remboursée'
                : 'Annulée';
        color = AppTheme.error;
    }

    final price = status == 'paiement en attente' ||
            status == 'accepté' ||
            status == 'en cours de livraison' ||
            status == 'livré'
        ? toNum(d['tarifConvenu'])
        : toNum(d['proposedPrice']);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withAlpha(25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(label,
                    style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: color)),
              ),
              const Spacer(),
              Text(formatFcfa(price),
                  style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.success)),
            ],
          ),
          const SizedBox(height: 10),
          Text('Délai : ${kDelaiLabels[d['delai']] ?? d['delai']}',
              style: GoogleFonts.outfit(
                  fontSize: 12, color: AppTheme.textSecondary)),
          const SizedBox(height: 6),
          Text('De : ${d['pickupAddress'] ?? ''}',
              style: GoogleFonts.outfit(fontSize: 13)),
          Text('Vers : ${d['adresseLivraison'] ?? ''}',
              style: GoogleFonts.outfit(fontSize: 13)),
          if ((d['packageDescription'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Colis : ${d['packageDescription']}',
                  style: GoogleFonts.outfit(
                      fontSize: 12, color: AppTheme.muted)),
            ),
          if (agent != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Livreur : ${agent['prenom'] ?? ''}'
                '${agent['phone'] != null ? ' · ${agent['phone']}' : ''}',
                style: GoogleFonts.outfit(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          if (status == 'contre-proposition') ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.primaryMuted,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Le livreur propose ${formatFcfa(toNum(d['counterPrice']))} '
                '(vous aviez proposé ${formatFcfa(toNum(d['proposedPrice']))}). '
                'Vous avez 15 minutes pour répondre.',
                style: GoogleFonts.outfit(fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : () => _respond(id, false),
                  child: Text('Refuser', style: GoogleFonts.outfit()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: busy ? null : () => _respond(id, true),
                  child: Text('Accepter', style: GoogleFonts.outfit()),
                ),
              ),
            ]),
          ],
          if (status == 'paiement en attente') ...[
            const SizedBox(height: 10),
            Text(
              ps == 'en attente'
                  ? 'Confirmez le paiement sur votre téléphone.'
                  : ps == 'à vérifier'
                      ? 'Votre paiement est en cours de vérification. Si vous avez été débité, contactez le support : ne repayez pas.'
                      : 'Prix convenu. Payez en Mobile Money pour confirmer la course (15 min).',
              style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.muted),
            ),
            if (ps != 'en attente' && ps != 'à vérifier') ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: busy ? null : () => _pay(d),
                  icon: const Icon(Icons.payments_rounded, size: 18),
                  label: Text('Payer ${formatFcfa(toNum(d['tarifConvenu']))}',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ],
          if (status == 'en attente' ||
              status == 'contre-proposition' ||
              (status == 'paiement en attente' &&
                  ps != 'en attente' &&
                  ps != 'à vérifier'))
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: busy ? null : () => _cancel(id),
                child: Text('Annuler la demande',
                    style: GoogleFonts.outfit(
                        fontSize: 12, color: AppTheme.error)),
              ),
            ),
          if (busy)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(color: AppTheme.primary),
            ),
        ],
      ),
    );
  }
}

class _PaySheet extends StatefulWidget {
  final num? amount;
  final String initialOperator;
  final String initialNumber;
  const _PaySheet({
    required this.amount,
    required this.initialOperator,
    required this.initialNumber,
  });

  @override
  State<_PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends State<_PaySheet> {
  late String _operator = widget.initialOperator;
  late final _numberCtrl = TextEditingController(text: widget.initialNumber);
  String? _error;

  @override
  void dispose() {
    _numberCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final number = _numberCtrl.text.replaceAll(RegExp(r'[\s\-]'), '');
    if (!RegExp(r'^\+?[0-9]{8,15}$').hasMatch(number)) {
      setState(() => _error = 'Numéro invalide');
      return;
    }
    Navigator.pop(context, {'operator': _operator, 'number': number});
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Payer ${formatFcfa(widget.amount)}',
              style:
                  GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Mobile Money (frais de l\'opérateur en plus)',
              style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.muted)),
          const SizedBox(height: 14),
          Row(children: [
            for (final op in const ['MTN', 'Moov']) ...[
              ChoiceChip(
                label: Text(op, style: GoogleFonts.outfit()),
                selected: _operator == op,
                onSelected: (_) => setState(() => _operator = op),
              ),
              const SizedBox(width: 8),
            ],
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _numberCtrl,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s\-]')),
            ],
            decoration: InputDecoration(
              labelText: 'Numéro Mobile Money',
              hintText: '01 97 00 00 00',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _submit,
              child: Text('Payer maintenant',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
      ),
    );
  }
}
