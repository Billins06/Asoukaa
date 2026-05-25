import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum OrderStatus {
  received,
  processing,
  inDelivery,
  confirmed,
  completed,
  cancelled,
  failed,
}

class StatusBadgeWidget extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color textColor;
  final double fontSize;

  const StatusBadgeWidget({
    super.key,
    required this.label,
    required this.backgroundColor,
    required this.textColor,
    this.fontSize = 11,
  });

  factory StatusBadgeWidget.fromOrderStatus(OrderStatus status) {
    switch (status) {
      case OrderStatus.received:
        return StatusBadgeWidget(
          label: 'Reçue',
          backgroundColor: const Color(0xFFE3F2FD),
          textColor: const Color(0xFF1565C0),
        );
      case OrderStatus.processing:
        return StatusBadgeWidget(
          label: 'En traitement',
          backgroundColor: const Color(0xFFFEF3C7),
          textColor: const Color(0xFFD97706),
        );
      case OrderStatus.inDelivery:
        return StatusBadgeWidget(
          label: 'En livraison',
          backgroundColor: const Color(0xFFFFEDE3),
          textColor: const Color(0xFFFF6210),
        );
      case OrderStatus.confirmed:
        return StatusBadgeWidget(
          label: 'Confirmée',
          backgroundColor: const Color(0xFFDCFCE7),
          textColor: const Color(0xFF16A34A),
        );
      case OrderStatus.completed:
        return StatusBadgeWidget(
          label: 'Terminée',
          backgroundColor: const Color(0xFFDCFCE7),
          textColor: const Color(0xFF16A34A),
        );
      case OrderStatus.cancelled:
        return StatusBadgeWidget(
          label: 'Annulée',
          backgroundColor: const Color(0xFFFEE2E2),
          textColor: const Color(0xFFDC2626),
        );
      case OrderStatus.failed:
        return StatusBadgeWidget(
          label: 'Échouée',
          backgroundColor: const Color(0xFFFEE2E2),
          textColor: const Color(0xFFDC2626),
        );
    }
  }

  factory StatusBadgeWidget.custom({
    required String label,
    required Color backgroundColor,
    required Color textColor,
  }) {
    return StatusBadgeWidget(
      label: label,
      backgroundColor: backgroundColor,
      textColor: textColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.outfit(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: textColor,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
