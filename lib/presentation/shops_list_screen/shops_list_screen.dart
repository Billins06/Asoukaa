import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../services/nest_auth_service.dart';
import '../../theme/app_theme.dart';
import './widgets/shops_list_view.dart';

/// Écran « Boutiques » : annuaire de toutes les boutiques d'Asoukaa
/// (ouvert depuis la page d'accueil, carte « Toutes les boutiques »).
class ShopsListScreen extends StatefulWidget {
  const ShopsListScreen({super.key});

  @override
  State<ShopsListScreen> createState() => _ShopsListScreenState();
}

class _ShopsListScreenState extends State<ShopsListScreen> {
  int _cartCount = 0;

  @override
  void initState() {
    super.initState();
    _loadCartCount();
  }

  // Même source que la pastille panier de l'accueil (GET /api/v1/cart).
  Future<void> _loadCartCount() async {
    try {
      final isLoggedIn = await NestAuthService.instance
          .isLoggedIn()
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      if (!isLoggedIn) {
        if (mounted) setState(() => _cartCount = 0);
        return;
      }
      final response = await ApiService.instance.client.get('/api/v1/cart');
      final data = response.data;
      final count = (data is Map)
          ? (int.tryParse(data['itemCount']?.toString() ?? '') ??
              (data['items'] as List?)?.length ??
              0)
          : 0;
      if (mounted) setState(() => _cartCount = count);
    } catch (_) {
      if (mounted) setState(() => _cartCount = 0);
    }
  }

  Future<void> _openCart() async {
    await Navigator.pushNamed(context, AppRoutes.cart);
    if (mounted) _loadCartCount();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  _RoundIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Retour',
                    onTap: () => Navigator.maybePop(context),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Boutiques',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _RoundIconButton(
                        icon: Icons.shopping_cart_outlined,
                        tooltip: 'Panier',
                        onTap: _openCart,
                      ),
                      if (_cartCount > 0)
                        Positioned(
                          top: -2,
                          right: -2,
                          child: IgnorePointer(
                            child: Container(
                              constraints: const BoxConstraints(
                                minWidth: 18,
                                minHeight: 18,
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppTheme.primary,
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              child: Text(
                                _cartCount > 99 ? '99+' : '$_cartCount',
                                style: GoogleFonts.outfit(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
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
            const Expanded(child: ShopsListView(showSearch: true)),
          ],
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xFFF0ECE8),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, size: 22, color: AppTheme.textPrimary),
          ),
        ),
      ),
    );
  }
}
