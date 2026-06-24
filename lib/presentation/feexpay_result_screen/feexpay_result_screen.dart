import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../routes/app_routes.dart';
import '../../services/nest_auth_service.dart';
import '../../services/api_service.dart';
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
    // Read args before any await to avoid BuildContext async gap
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic> && _orderId == null) {
      _orderId = args['order_id'] as String?;
    }

    try {
      final isLoggedIn = await NestAuthService.instance.isLoggedIn()
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      if (!isLoggedIn) {
        if (mounted) setState(() => _isProcessing = false);
        return;
      }

      if (_orderId != null && _orderId!.isNotEmpty) {
        if (widget.success) {
          try {
            await ApiService.instance.client.patch(
              '/api/v1/orders/$_orderId/status',
              data: {
                'paymentStatus': 'paid',
                'status': 'confirme',
              },
            );
          } catch (_) {}
          // Clear cart only after successful payment
          try {
            await ApiService.instance.client.delete('/api/v1/cart');
          } catch (_) {}
        } else {
          try {
            await ApiService.instance.client.patch(
              '/api/v1/orders/$_orderId/status',
              data: {'paymentStatus': 'failed', 'status': 'annule'},
            );
          } catch (_) {}
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
