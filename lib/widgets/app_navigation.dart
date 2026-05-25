import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';

class AsoukaaBottomNav extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final int unreadMessages;

  const AsoukaaBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.unreadMessages = 0,
  });

  @override
  State<AsoukaaBottomNav> createState() => _AsoukaaBottomNavState();
}

class _AsoukaaBottomNavState extends State<AsoukaaBottomNav> {
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
  }

  Future<void> _loadUnreadCount() async {
    final user = AuthService.instance.currentUser;
    if (user == null) return;
    try {
      final result = await Supabase.instance.client
          .from('conversations')
          .select('buyer_unread, seller_unread, buyer_id')
          .or('buyer_id.eq.${user.id},seller_id.eq.${user.id}');
      int total = 0;
      for (final c in (result as List)) {
        final isBuyer = c['buyer_id'] == user.id;
        total += isBuyer
            ? (c['buyer_unread'] as int? ?? 0)
            : (c['seller_unread'] as int? ?? 0);
      }
      if (mounted) setState(() => _unreadCount = total);
    } catch (_) {}
  }

  static const List<_NavItem> _items = [
    _NavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: 'Accueil',
    ),
    _NavItem(
      icon: Icons.storefront_outlined,
      activeIcon: Icons.storefront_rounded,
      label: 'Marché',
    ),
    _NavItem(
      icon: Icons.chat_bubble_outline_rounded,
      activeIcon: Icons.chat_bubble_rounded,
      label: 'Messages',
    ),
    _NavItem(
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long_rounded,
      label: 'Commandes',
    ),
    _NavItem(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: 'Profil',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final effectiveUnread = widget.unreadMessages > 0
        ? widget.unreadMessages
        : _unreadCount;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(15),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final tabWidth = constraints.maxWidth / _items.length;
              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOutCubic,
                    left: widget.currentIndex * tabWidth + (tabWidth - 52) / 2,
                    top: 8,
                    child: Container(
                      width: 52,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEDE3),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Row(
                    children: List.generate(_items.length, (index) {
                      final isActive = index == widget.currentIndex;
                      final showBadge = index == 2 && effectiveUnread > 0;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => widget.onTap(index),
                          behavior: HitTestBehavior.opaque,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    child: Icon(
                                      isActive
                                          ? _items[index].activeIcon
                                          : _items[index].icon,
                                      key: ValueKey(isActive),
                                      size: 22,
                                      color: isActive
                                          ? const Color(0xFFFF6210)
                                          : const Color(0xFF9E9E9E),
                                    ),
                                  ),
                                  if (showBadge)
                                    Positioned(
                                      right: -6,
                                      top: -4,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFF6210),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          effectiveUnread > 9
                                              ? '9+'
                                              : '$effectiveUnread',
                                          style: GoogleFonts.outfit(
                                            fontSize: 8,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _items[index].label,
                                style: GoogleFonts.outfit(
                                  fontSize: 10,
                                  fontWeight: isActive
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: isActive
                                      ? const Color(0xFFFF6210)
                                      : const Color(0xFF9E9E9E),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

// Navigation Rail for Tablet
class AsoukaaNavigationRail extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AsoukaaNavigationRail({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      selectedIndex: currentIndex,
      onDestinationSelected: onTap,
      backgroundColor: Colors.white,
      indicatorColor: const Color(0xFFFFEDE3),
      selectedIconTheme: const IconThemeData(color: Color(0xFFFF6210)),
      unselectedIconTheme: const IconThemeData(color: Color(0xFF9E9E9E)),
      selectedLabelTextStyle: GoogleFonts.outfit(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: const Color(0xFFFF6210),
      ),
      unselectedLabelTextStyle: GoogleFonts.outfit(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: const Color(0xFF9E9E9E),
      ),
      labelType: NavigationRailLabelType.all,
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard_rounded),
          label: Text('Dashboard'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.manage_accounts_outlined),
          selectedIcon: Icon(Icons.manage_accounts_rounded),
          label: Text('Compte'),
        ),
      ],
    );
  }
}
