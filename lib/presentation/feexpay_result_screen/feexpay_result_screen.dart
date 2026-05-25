import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

class FeexpayResultScreen extends StatefulWidget {
  final bool success;
  const FeexpayResultScreen({super.key, required this.success});

  @override
  State<FeexpayResultScreen> createState() => _FeexpayResultScreenState();
}

class _FeexpayResultScreenState extends State<FeexpayResultScreen> {
  bool _isProcessing = true;
  String? _orderId;

  @override
  void initState() {
    super.initState();
    _processPaymentResult();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      _orderId = args['order_id'] as String?;
    }
  }

  Future<void> _processPaymentResult() async {
    try {
      final user = AuthService.instance.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isProcessing = false);
        return;
      }

      // Get order ID from args if not already set
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic> && _orderId == null) {
        _orderId = args['order_id'] as String?;
      }

      if (_orderId != null && _orderId!.isNotEmpty) {
        if (widget.success) {
          // Update order status to paid + confirmed
          // await DatabaseService.instance.updateOrderStatus(
          //   _orderId!,
          //   'confirme',
          // );
          // Also update payment status
          try {
            await Supabase.instance.client
                .from('orders')
                .update({
                  'payment_status': 'paid',
                  'status': 'confirme',
                  'paid_at': DateTime.now().toIso8601String(),
                })
                .eq('id', _orderId!);
          } catch (_) {}
          // Clear cart ONLY after successful payment
          try {
            await Supabase.instance.client
                .from('cart_items')
                .delete()
                .eq('user_id', user.id);
          } catch (_) {}
        } else {
          // Payment failed - update order status to failed
          try {
            await Supabase.instance.client
                .from('orders')
                .update({'payment_status': 'failed', 'status': 'annule'})
                .eq('id', _orderId!);
          } catch (_) {}
          // Do NOT clear cart on failure
        }
      }
    } catch (_) {}

    if (mounted) setState(() => _isProcessing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: _isProcessing
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(color: AppTheme.primary),
                      const SizedBox(height: 20),
                      Text(
                        'Traitement du paiement...',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          color: widget.success
                              ? AppTheme.successContainer
                              : const Color(0xFFFFEDED),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          widget.success
                              ? Icons.check_circle_rounded
                              : Icons.cancel_rounded,
                          color: widget.success
                              ? AppTheme.success
                              : AppTheme.error,
                          size: 48,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        widget.success
                            ? 'Paiement réussi !'
                            : 'Paiement échoué',
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        widget.success
                            ? 'Votre paiement a été traité avec succès. Votre commande est confirmée et en cours de préparation.'
                            : 'Le paiement n\'a pas pu être traité. Votre panier a été conservé. Veuillez réessayer.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          color: AppTheme.textSecondary,
                          height: 1.5,
                        ),
                      ),
                      if (_orderId != null && widget.success) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.successContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Commande confirmée',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.success,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () {
                            if (widget.success) {
                              Navigator.of(context).pushNamedAndRemoveUntil(
                                AppRoutes.home,
                                (route) => false,
                              );
                            } else {
                              Navigator.of(context).pop();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: widget.success
                                ? AppTheme.primary
                                : AppTheme.error,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            widget.success
                                ? 'Retour à l\'accueil'
                                : 'Réessayer',
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      if (widget.success) ...[
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () => Navigator.pushNamedAndRemoveUntil(
                            context,
                            AppRoutes.buyerDashboard,
                            (route) => false,
                          ),
                          child: Text(
                            'Voir mes commandes',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
