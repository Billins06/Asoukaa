import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sizer/sizer.dart';

import '../../theme/app_theme.dart';
import '../../routes/app_routes.dart';

class OrderConfirmationScreen extends StatelessWidget {
  const OrderConfirmationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

    final String orderNumber =
        args?['orderNumber'] as String? ??
        'ASK-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    final String firstName = args?['firstName'] as String? ?? 'Aminata';
    final String lastName = args?['lastName'] as String? ?? 'Konaté';
    final String address =
        args?['address'] as String? ?? 'Rue 42, Badalabougou';
    final String city = args?['city'] as String? ?? 'Bamako';
    final String country = args?['country'] as String? ?? 'Mali';
    final String phone = args?['phone'] as String? ?? '+223 76 00 00 00';
    final String paymentMethod =
        args?['paymentMethod'] as String? ?? 'Paiement à la livraison';
    final int total = args?['total'] as int? ?? 0;

    final deliveryDate = DateTime.now().add(const Duration(days: 3));
    final deliveryDateStr =
        '${deliveryDate.day} ${_monthName(deliveryDate.month)} ${deliveryDate.year}';

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: 2.h),
              // Success icon
              Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  color: AppTheme.successContainer,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: AppTheme.success,
                  size: 44,
                ),
              ),
              SizedBox(height: 2.h),
              Text(
                'Commande Confirmée !',
                style: GoogleFonts.outfit(
                  fontSize: 20.sp > 22 ? 22 : 20.sp,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 0.8.h),
              Text(
                'Merci pour votre commande. Nous la préparons avec soin.',
                style: GoogleFonts.outfit(
                  fontSize: 13.sp > 15 ? 15 : 13.sp,
                  color: AppTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 2.5.h),

              // Order number card
              _InfoCard(
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      child: const Icon(
                        Icons.receipt_long_rounded,
                        color: AppTheme.primary,
                        size: 22,
                      ),
                    ),
                    SizedBox(width: 3.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Numéro de commande',
                            style: GoogleFonts.outfit(
                              fontSize: 11.sp > 13 ? 13 : 11.sp,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '#$orderNumber',
                            style: GoogleFonts.outfit(
                              fontSize: 14.sp > 16 ? 16 : 14.sp,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.successContainer,
                        borderRadius: BorderRadius.circular(20.0),
                      ),
                      child: Text(
                        'Confirmée',
                        style: GoogleFonts.outfit(
                          fontSize: 11.sp > 12 ? 12 : 11.sp,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.success,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 1.5.h),

              // Delivery estimate card
              _InfoCard(
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      child: const Icon(
                        Icons.local_shipping_rounded,
                        color: AppTheme.warning,
                        size: 22,
                      ),
                    ),
                    SizedBox(width: 3.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Livraison estimée',
                            style: GoogleFonts.outfit(
                              fontSize: 11.sp > 13 ? 13 : 11.sp,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            deliveryDateStr,
                            style: GoogleFonts.outfit(
                              fontSize: 14.sp > 16 ? 16 : 14.sp,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.warningContainer,
                        borderRadius: BorderRadius.circular(20.0),
                      ),
                      child: Text(
                        '2–4 jours',
                        style: GoogleFonts.outfit(
                          fontSize: 11.sp > 12 ? 12 : 11.sp,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 1.5.h),

              // Shipping address card
              _InfoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryContainer,
                            borderRadius: BorderRadius.circular(10.0),
                          ),
                          child: const Icon(
                            Icons.location_on_rounded,
                            color: AppTheme.primary,
                            size: 22,
                          ),
                        ),
                        SizedBox(width: 3.w),
                        Text(
                          'Adresse de livraison',
                          style: GoogleFonts.outfit(
                            fontSize: 13.sp > 15 ? 15 : 13.sp,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 1.2.h),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$firstName $lastName',
                            style: GoogleFonts.outfit(
                              fontSize: 13.sp > 15 ? 15 : 13.sp,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            address,
                            style: GoogleFonts.outfit(
                              fontSize: 12.sp > 14 ? 14 : 12.sp,
                              color: AppTheme.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$city, $country',
                            style: GoogleFonts.outfit(
                              fontSize: 12.sp > 14 ? 14 : 12.sp,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            phone,
                            style: GoogleFonts.outfit(
                              fontSize: 12.sp > 14 ? 14 : 12.sp,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 1.5.h),

              // Payment & total card
              _InfoCard(
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      child: const Icon(
                        Icons.payments_rounded,
                        color: AppTheme.primary,
                        size: 22,
                      ),
                    ),
                    SizedBox(width: 3.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Mode de paiement',
                            style: GoogleFonts.outfit(
                              fontSize: 11.sp > 13 ? 13 : 11.sp,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            paymentMethod,
                            style: GoogleFonts.outfit(
                              fontSize: 13.sp > 15 ? 15 : 13.sp,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (total > 0)
                      Text(
                        _formatPrice(total),
                        style: GoogleFonts.outfit(
                          fontSize: 14.sp > 16 ? 16 : 14.sp,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primary,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(height: 3.h),

              // Action buttons
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(
                      context,
                    ).pushNamedAndRemoveUntil(AppRoutes.home, (r) => false);
                  },
                  icon: const Icon(Icons.home_rounded, size: 20),
                  label: Text(
                    'Retour à l\'accueil',
                    style: GoogleFonts.outfit(
                      fontSize: 14.sp > 16 ? 16 : 14.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14.0),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 1.2.h),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushNamed(
                      AppRoutes.orderTracking,
                      arguments: {
                        'orderNumber': orderNumber,
                        'firstName': firstName,
                        'lastName': lastName,
                        'address': address,
                        'city': city,
                        'country': country,
                        'phone': phone,
                        'paymentMethod': paymentMethod,
                        'total': total,
                      },
                    );
                  },
                  icon: const Icon(Icons.track_changes_rounded, size: 20),
                  label: Text(
                    'Suivre ma commande',
                    style: GoogleFonts.outfit(
                      fontSize: 14.sp > 16 ? 16 : 14.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.primary, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14.0),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 2.h),
            ],
          ),
        ),
      ),
    );
  }

  String _formatPrice(int price) {
    final str = price.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(str[i]);
    }
    return '${buffer.toString()} FCFA';
  }

  String _monthName(int month) {
    const months = [
      'jan.',
      'fév.',
      'mars',
      'avr.',
      'mai',
      'juin',
      'juil.',
      'août',
      'sept.',
      'oct.',
      'nov.',
      'déc.',
    ];
    return months[month - 1];
  }
}

class _InfoCard extends StatelessWidget {
  final Widget child;
  const _InfoCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}
