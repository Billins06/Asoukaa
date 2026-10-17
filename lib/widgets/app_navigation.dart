import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/unread_messages_notifier.dart';

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
  // Le compteur (nombre de DISCUSSIONS avec au moins un message non lu)
  // vient de UnreadMessagesNotifier : une seule source partagée par toutes
  // les barres du bas, rafraîchie toutes les 30 s et à chaque lecture d'une
  // discussion.
  @override
  void initState() {
    super.initState();
    UnreadMessagesNotifier.instance.attach();
  }

  @override
  void dispose() {
    UnreadMessagesNotifier.instance.detach();
    super.dispose();
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
      label: 'Catégories',
    ),
    _NavItem(
      icon: Icons.chat_bubble_outline_rounded,
      activeIcon: Icons.chat_bubble_rounded,
      label: 'Messages',
    ),
    _NavItem(
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long_rounded,
      label: 'Tableau de bord',
    ),
    _NavItem(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: 'Profil',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: UnreadMessagesNotifier.instance.count,
      builder: (context, unreadCount, _) {
        final effectiveUnread = widget.unreadMessages > 0
            ? widget.unreadMessages
            : unreadCount;
        return _buildBar(effectiveUnread);
      },
    );
  }

  Widget _buildBar(int effectiveUnread) {
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
                                      right: -9,
                                      top: -6,
                                      child: IgnorePointer(
                                        child: Semantics(
                                          label: effectiveUnread == 1
                                              ? '1 discussion non lue'
                                              : '$effectiveUnread discussions non lues',
                                          child: ExcludeSemantics(
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                  ),
                                              constraints: const BoxConstraints(
                                                minWidth: 16,
                                                minHeight: 16,
                                              ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFF6210),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                                border: Border.all(
                                                  color: Colors.white,
                                                  width: 1.5,
                                                ),
                                              ),
                                              child: Center(
                                                child: Text(
                                                  effectiveUnread > 9
                                                      ? '9+'
                                                      : '$effectiveUnread',
                                                  style: GoogleFonts.outfit(
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.white,
                                                    height: 1.2,
                                                  ),
                                                ),
                                              ),
                                            ),
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
    // ⚠️ Ce rail n'a que 2 destinations (Dashboard, Compte), mais les
    // écrans appelants réutilisent souvent le même index que la barre
    // de navigation du téléphone (0=Accueil, 1=Catégories, 2=Messages,
    // 3=Commandes, 4=Profil). Un index hors bornes (3 ou 4, par ex. sur
    // BuyerDashboardScreen ou DelivererDashboardScreen) faisait planter
    // NavigationRail (assertion sur selectedIndex >= destinations.length),
    // ce qui cassait tout le layout tablette/desktop (contenu invisible,
    // "RenderFlex overflowed by Infinity pixels"). On normalise ici :
    // seul l'index "Profil" (4) sélectionne "Compte", tout le reste
    // (y compris les valeurs déjà valides 0/1) sélectionne "Dashboard".
    final safeIndex = currentIndex == 4 ? 1 : 0;
    return NavigationRail(
      selectedIndex: safeIndex,
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
