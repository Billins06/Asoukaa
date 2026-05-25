import 'package:flutter/material.dart';

class LoadingSkeletonWidget extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const LoadingSkeletonWidget({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<LoadingSkeletonWidget> createState() => _LoadingSkeletonWidgetState();
}

class _LoadingSkeletonWidgetState extends State<LoadingSkeletonWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _shimmerPosition;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _shimmerPosition = Tween<double>(
      begin: -0.5,
      end: 1.5,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shimmerPosition,
      builder: (_, __) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              colors: const [
                Color(0xFFEEEEEE),
                Color(0xFFF5F5F5),
                Color(0xFFEEEEEE),
              ],
              stops: [
                (_shimmerPosition.value - 0.3).clamp(0.0, 1.0),
                _shimmerPosition.value.clamp(0.0, 1.0),
                (_shimmerPosition.value + 0.3).clamp(0.0, 1.0),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        );
      },
    );
  }
}

// ─── Product Card Skeleton ───────────────────────────────────────────────────

class ProductCardSkeleton extends StatelessWidget {
  const ProductCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LoadingSkeletonWidget(
            width: double.infinity,
            height: 140,
            borderRadius: 16,
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LoadingSkeletonWidget(
                  width: double.infinity,
                  height: 14,
                  borderRadius: 4,
                ),
                const SizedBox(height: 6),
                LoadingSkeletonWidget(width: 80, height: 14, borderRadius: 4),
                const SizedBox(height: 8),
                LoadingSkeletonWidget(width: 60, height: 18, borderRadius: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Home Screen Skeleton ────────────────────────────────────────────────────

class HomeScreenSkeleton extends StatelessWidget {
  const HomeScreenSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          // Banner skeleton
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LoadingSkeletonWidget(
              width: double.infinity,
              height: 160,
              borderRadius: 20,
            ),
          ),
          const SizedBox(height: 20),
          // Categories skeleton
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LoadingSkeletonWidget(
              width: 120,
              height: 18,
              borderRadius: 4,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 6,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, __) => Column(
                children: [
                  LoadingSkeletonWidget(
                    width: 52,
                    height: 52,
                    borderRadius: 16,
                  ),
                  const SizedBox(height: 6),
                  LoadingSkeletonWidget(width: 44, height: 10, borderRadius: 4),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Flash deals skeleton
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                LoadingSkeletonWidget(width: 120, height: 18, borderRadius: 4),
                const Spacer(),
                LoadingSkeletonWidget(width: 60, height: 14, borderRadius: 4),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 4,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, __) => SizedBox(
                width: 150,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(10),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LoadingSkeletonWidget(
                        width: double.infinity,
                        height: 130,
                        borderRadius: 16,
                      ),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LoadingSkeletonWidget(
                              width: double.infinity,
                              height: 12,
                              borderRadius: 4,
                            ),
                            const SizedBox(height: 6),
                            LoadingSkeletonWidget(
                              width: 60,
                              height: 16,
                              borderRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Trending skeleton
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LoadingSkeletonWidget(
              width: 140,
              height: 18,
              borderRadius: 4,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.72,
              ),
              itemCount: 4,
              itemBuilder: (_, __) => const ProductCardSkeleton(),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─── Search Results Skeleton ─────────────────────────────────────────────────

class SearchResultsSkeleton extends StatelessWidget {
  const SearchResultsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.68,
        ),
        itemCount: 6,
        itemBuilder: (_, __) => Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(10),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LoadingSkeletonWidget(
                width: double.infinity,
                height: 140,
                borderRadius: 16,
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LoadingSkeletonWidget(
                      width: double.infinity,
                      height: 12,
                      borderRadius: 4,
                    ),
                    const SizedBox(height: 5),
                    LoadingSkeletonWidget(
                      width: 70,
                      height: 10,
                      borderRadius: 4,
                    ),
                    const SizedBox(height: 6),
                    LoadingSkeletonWidget(
                      width: 50,
                      height: 14,
                      borderRadius: 4,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Product Detail Skeleton ─────────────────────────────────────────────────

class ProductDetailSkeleton extends StatelessWidget {
  const ProductDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Gallery skeleton
          LoadingSkeletonWidget(
            width: double.infinity,
            height: 320,
            borderRadius: 0,
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                LoadingSkeletonWidget(
                  width: double.infinity,
                  height: 22,
                  borderRadius: 6,
                ),
                const SizedBox(height: 8),
                LoadingSkeletonWidget(width: 200, height: 18, borderRadius: 6),
                const SizedBox(height: 16),
                // Price row
                Row(
                  children: [
                    LoadingSkeletonWidget(
                      width: 100,
                      height: 28,
                      borderRadius: 6,
                    ),
                    const SizedBox(width: 12),
                    LoadingSkeletonWidget(
                      width: 70,
                      height: 18,
                      borderRadius: 6,
                    ),
                    const SizedBox(width: 8),
                    LoadingSkeletonWidget(
                      width: 50,
                      height: 22,
                      borderRadius: 8,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Rating row
                Row(
                  children: [
                    LoadingSkeletonWidget(
                      width: 80,
                      height: 14,
                      borderRadius: 4,
                    ),
                    const SizedBox(width: 8),
                    LoadingSkeletonWidget(
                      width: 60,
                      height: 14,
                      borderRadius: 4,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Seller card skeleton
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(8),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      LoadingSkeletonWidget(
                        width: 48,
                        height: 48,
                        borderRadius: 12,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LoadingSkeletonWidget(
                              width: 120,
                              height: 14,
                              borderRadius: 4,
                            ),
                            const SizedBox(height: 6),
                            LoadingSkeletonWidget(
                              width: 80,
                              height: 12,
                              borderRadius: 4,
                            ),
                          ],
                        ),
                      ),
                      LoadingSkeletonWidget(
                        width: 70,
                        height: 32,
                        borderRadius: 8,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Price tiers skeleton
                LoadingSkeletonWidget(width: 100, height: 16, borderRadius: 4),
                const SizedBox(height: 10),
                Row(
                  children: List.generate(
                    4,
                    (i) => Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: i < 3 ? 8 : 0),
                        child: LoadingSkeletonWidget(
                          width: double.infinity,
                          height: 56,
                          borderRadius: 10,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Tabs skeleton
                Row(
                  children: List.generate(
                    3,
                    (i) => Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
                        child: LoadingSkeletonWidget(
                          width: double.infinity,
                          height: 36,
                          borderRadius: 8,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                LoadingSkeletonWidget(
                  width: double.infinity,
                  height: 14,
                  borderRadius: 4,
                ),
                const SizedBox(height: 6),
                LoadingSkeletonWidget(
                  width: double.infinity,
                  height: 14,
                  borderRadius: 4,
                ),
                const SizedBox(height: 6),
                LoadingSkeletonWidget(width: 200, height: 14, borderRadius: 4),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Dashboard Order Card Skeleton ───────────────────────────────────────────

class DashboardOrderSkeleton extends StatelessWidget {
  const DashboardOrderSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                LoadingSkeletonWidget(width: 100, height: 14, borderRadius: 4),
                const Spacer(),
                LoadingSkeletonWidget(width: 70, height: 22, borderRadius: 8),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                LoadingSkeletonWidget(width: 64, height: 64, borderRadius: 10),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LoadingSkeletonWidget(
                        width: double.infinity,
                        height: 14,
                        borderRadius: 4,
                      ),
                      const SizedBox(height: 6),
                      LoadingSkeletonWidget(
                        width: 100,
                        height: 12,
                        borderRadius: 4,
                      ),
                      const SizedBox(height: 6),
                      LoadingSkeletonWidget(
                        width: 80,
                        height: 16,
                        borderRadius: 4,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LoadingSkeletonWidget(
              width: double.infinity,
              height: 8,
              borderRadius: 4,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Dashboard Product Card Skeleton ─────────────────────────────────────────

class DashboardProductSkeleton extends StatelessWidget {
  const DashboardProductSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            LoadingSkeletonWidget(width: 72, height: 72, borderRadius: 10),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LoadingSkeletonWidget(
                    width: double.infinity,
                    height: 14,
                    borderRadius: 4,
                  ),
                  const SizedBox(height: 6),
                  LoadingSkeletonWidget(width: 80, height: 12, borderRadius: 4),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      LoadingSkeletonWidget(
                        width: 60,
                        height: 20,
                        borderRadius: 6,
                      ),
                      const SizedBox(width: 8),
                      LoadingSkeletonWidget(
                        width: 50,
                        height: 20,
                        borderRadius: 6,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            LoadingSkeletonWidget(width: 28, height: 28, borderRadius: 8),
          ],
        ),
      ),
    );
  }
}

// ─── Dashboard Mission Card Skeleton ─────────────────────────────────────────

class DashboardMissionSkeleton extends StatelessWidget {
  const DashboardMissionSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                LoadingSkeletonWidget(width: 80, height: 14, borderRadius: 4),
                const Spacer(),
                LoadingSkeletonWidget(width: 60, height: 22, borderRadius: 8),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                LoadingSkeletonWidget(width: 16, height: 16, borderRadius: 4),
                const SizedBox(width: 8),
                LoadingSkeletonWidget(width: 160, height: 12, borderRadius: 4),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                LoadingSkeletonWidget(width: 16, height: 16, borderRadius: 4),
                const SizedBox(width: 8),
                LoadingSkeletonWidget(width: 140, height: 12, borderRadius: 4),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                LoadingSkeletonWidget(width: 70, height: 28, borderRadius: 8),
                const SizedBox(width: 8),
                LoadingSkeletonWidget(width: 70, height: 28, borderRadius: 8),
                const Spacer(),
                LoadingSkeletonWidget(width: 90, height: 36, borderRadius: 10),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Chat Conversation List Skeleton ─────────────────────────────────────────

class ChatListSkeleton extends StatelessWidget {
  const ChatListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            LoadingSkeletonWidget(width: 48, height: 48, borderRadius: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      LoadingSkeletonWidget(
                        width: 100,
                        height: 14,
                        borderRadius: 4,
                      ),
                      const Spacer(),
                      LoadingSkeletonWidget(
                        width: 40,
                        height: 10,
                        borderRadius: 4,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LoadingSkeletonWidget(
                    width: double.infinity,
                    height: 12,
                    borderRadius: 4,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Buyer Profile Skeleton ───────────────────────────────────────────────────

class BuyerProfileSkeleton extends StatelessWidget {
  const BuyerProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const NeverScrollableScrollPhysics(),
      slivers: [
        // AppBar skeleton
        SliverAppBar(
          expandedHeight: 200,
          pinned: true,
          backgroundColor: Colors.white,
          automaticallyImplyLeading: false,
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFFF3EE),
                    Color(0xFFFFEDE3),
                    Color(0xFFFFF8F5),
                  ],
                ),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    LoadingSkeletonWidget(
                      width: 80,
                      height: 80,
                      borderRadius: 40,
                    ),
                    const SizedBox(height: 10),
                    LoadingSkeletonWidget(
                      width: 130,
                      height: 16,
                      borderRadius: 4,
                    ),
                    const SizedBox(height: 6),
                    LoadingSkeletonWidget(
                      width: 180,
                      height: 12,
                      borderRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                _buildSkeletonCard(
                  children: [
                    _skeletonRow(labelWidth: 100, valueWidth: 160),
                    const SizedBox(height: 14),
                    _skeletonRow(labelWidth: 80, valueWidth: 140),
                    const SizedBox(height: 14),
                    _skeletonRow(labelWidth: 90, valueWidth: 120),
                  ],
                ),
                const SizedBox(height: 16),
                _buildSkeletonCard(
                  children: [
                    _skeletonRow(labelWidth: 80, valueWidth: 150),
                    const SizedBox(height: 14),
                    _skeletonRow(labelWidth: 100, valueWidth: 130),
                  ],
                ),
                const SizedBox(height: 16),
                _buildSkeletonCard(
                  children: [
                    _skeletonAddressItem(),
                    const Divider(height: 20),
                    _skeletonAddressItem(),
                  ],
                ),
                const SizedBox(height: 16),
                _buildSkeletonCard(
                  children: [
                    _skeletonPaymentItem(),
                    const Divider(height: 20),
                    _skeletonPaymentItem(),
                  ],
                ),
                const SizedBox(height: 16),
                _buildSkeletonCard(
                  children: [
                    _skeletonToggleRow(),
                    const Divider(height: 20),
                    _skeletonToggleRow(),
                    const Divider(height: 20),
                    _skeletonToggleRow(),
                  ],
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSkeletonCard({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              LoadingSkeletonWidget(width: 32, height: 32, borderRadius: 8),
              const SizedBox(width: 10),
              LoadingSkeletonWidget(width: 120, height: 15, borderRadius: 4),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _skeletonRow({
    required double labelWidth,
    required double valueWidth,
  }) {
    return Row(
      children: [
        LoadingSkeletonWidget(width: labelWidth, height: 12, borderRadius: 4),
        const Spacer(),
        LoadingSkeletonWidget(width: valueWidth, height: 12, borderRadius: 4),
      ],
    );
  }

  Widget _skeletonAddressItem() {
    return Row(
      children: [
        LoadingSkeletonWidget(width: 40, height: 40, borderRadius: 10),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LoadingSkeletonWidget(width: 80, height: 13, borderRadius: 4),
              const SizedBox(height: 5),
              LoadingSkeletonWidget(
                width: double.infinity,
                height: 11,
                borderRadius: 4,
              ),
              const SizedBox(height: 4),
              LoadingSkeletonWidget(width: 120, height: 11, borderRadius: 4),
            ],
          ),
        ),
      ],
    );
  }

  Widget _skeletonPaymentItem() {
    return Row(
      children: [
        LoadingSkeletonWidget(width: 40, height: 40, borderRadius: 10),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LoadingSkeletonWidget(width: 100, height: 13, borderRadius: 4),
              const SizedBox(height: 5),
              LoadingSkeletonWidget(width: 130, height: 11, borderRadius: 4),
            ],
          ),
        ),
        LoadingSkeletonWidget(width: 60, height: 22, borderRadius: 6),
      ],
    );
  }

  Widget _skeletonToggleRow() {
    return Row(
      children: [
        LoadingSkeletonWidget(width: 140, height: 13, borderRadius: 4),
        const Spacer(),
        LoadingSkeletonWidget(width: 44, height: 24, borderRadius: 12),
      ],
    );
  }
}

// ─── Seller Profile Skeleton ──────────────────────────────────────────────────

class SellerProfileSkeleton extends StatelessWidget {
  const SellerProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const NeverScrollableScrollPhysics(),
      slivers: [
        SliverAppBar(
          expandedHeight: 210,
          pinned: true,
          backgroundColor: Colors.white,
          automaticallyImplyLeading: false,
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFFF3EE),
                    Color(0xFFFFEDE3),
                    Color(0xFFFFF8F5),
                  ],
                ),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 44),
                    LoadingSkeletonWidget(
                      width: 84,
                      height: 84,
                      borderRadius: 42,
                    ),
                    const SizedBox(height: 10),
                    LoadingSkeletonWidget(
                      width: 160,
                      height: 16,
                      borderRadius: 4,
                    ),
                    const SizedBox(height: 6),
                    LoadingSkeletonWidget(
                      width: 200,
                      height: 12,
                      borderRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                // Stats row
                Row(
                  children: List.generate(
                    3,
                    (i) => Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: i < 2 ? 10.0 : 0),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(8),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              LoadingSkeletonWidget(
                                width: 50,
                                height: 20,
                                borderRadius: 4,
                              ),
                              const SizedBox(height: 6),
                              LoadingSkeletonWidget(
                                width: 60,
                                height: 11,
                                borderRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildSkeletonCard(
                  children: [
                    _skeletonRow(labelWidth: 100, valueWidth: 150),
                    const SizedBox(height: 14),
                    _skeletonRow(labelWidth: 80, valueWidth: 120),
                    const SizedBox(height: 14),
                    _skeletonRow(labelWidth: 110, valueWidth: 140),
                  ],
                ),
                const SizedBox(height: 16),
                _buildSkeletonCard(
                  children: [
                    _skeletonRow(labelWidth: 90, valueWidth: 130),
                    const SizedBox(height: 14),
                    _skeletonRow(labelWidth: 100, valueWidth: 110),
                  ],
                ),
                const SizedBox(height: 16),
                // Payment history skeleton
                _buildSkeletonCard(
                  children: List.generate(
                    3,
                    (i) => Padding(
                      padding: EdgeInsets.only(bottom: i < 2 ? 12.0 : 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                LoadingSkeletonWidget(
                                  width: 100,
                                  height: 13,
                                  borderRadius: 4,
                                ),
                                const SizedBox(height: 5),
                                LoadingSkeletonWidget(
                                  width: 80,
                                  height: 11,
                                  borderRadius: 4,
                                ),
                              ],
                            ),
                          ),
                          LoadingSkeletonWidget(
                            width: 80,
                            height: 16,
                            borderRadius: 4,
                          ),
                          const SizedBox(width: 8),
                          LoadingSkeletonWidget(
                            width: 60,
                            height: 22,
                            borderRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildSkeletonCard(
                  children: [
                    _skeletonToggleRow(),
                    const Divider(height: 20),
                    _skeletonToggleRow(),
                    const Divider(height: 20),
                    _skeletonToggleRow(),
                  ],
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSkeletonCard({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              LoadingSkeletonWidget(width: 32, height: 32, borderRadius: 8),
              const SizedBox(width: 10),
              LoadingSkeletonWidget(width: 130, height: 15, borderRadius: 4),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _skeletonRow({
    required double labelWidth,
    required double valueWidth,
  }) {
    return Row(
      children: [
        LoadingSkeletonWidget(width: labelWidth, height: 12, borderRadius: 4),
        const Spacer(),
        LoadingSkeletonWidget(width: valueWidth, height: 12, borderRadius: 4),
      ],
    );
  }

  Widget _skeletonToggleRow() {
    return Row(
      children: [
        LoadingSkeletonWidget(width: 140, height: 13, borderRadius: 4),
        const Spacer(),
        LoadingSkeletonWidget(width: 44, height: 24, borderRadius: 12),
      ],
    );
  }
}

// ─── Deliverer Profile Skeleton ───────────────────────────────────────────────

class DelivererProfileSkeleton extends StatelessWidget {
  const DelivererProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const NeverScrollableScrollPhysics(),
      slivers: [
        SliverAppBar(
          expandedHeight: 220,
          pinned: true,
          backgroundColor: Colors.white,
          automaticallyImplyLeading: false,
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFF0F7FF),
                    Color(0xFFE3EFFF),
                    Color(0xFFF5F9FF),
                  ],
                ),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 44),
                    LoadingSkeletonWidget(
                      width: 84,
                      height: 84,
                      borderRadius: 42,
                    ),
                    const SizedBox(height: 10),
                    LoadingSkeletonWidget(
                      width: 150,
                      height: 16,
                      borderRadius: 4,
                    ),
                    const SizedBox(height: 6),
                    LoadingSkeletonWidget(
                      width: 100,
                      height: 22,
                      borderRadius: 10,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Earnings summary 4-tile grid
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.6,
                  children: List.generate(
                    4,
                    (_) => Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(8),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          LoadingSkeletonWidget(
                            width: 60,
                            height: 20,
                            borderRadius: 4,
                          ),
                          const SizedBox(height: 6),
                          LoadingSkeletonWidget(
                            width: 80,
                            height: 11,
                            borderRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Delivery stats 6-item grid
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.3,
                  children: List.generate(
                    6,
                    (_) => Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(8),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          LoadingSkeletonWidget(
                            width: 40,
                            height: 18,
                            borderRadius: 4,
                          ),
                          const SizedBox(height: 5),
                          LoadingSkeletonWidget(
                            width: 55,
                            height: 10,
                            borderRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildSkeletonCard(
                  children: [
                    _skeletonRow(labelWidth: 80, valueWidth: 140),
                    const SizedBox(height: 14),
                    _skeletonRow(labelWidth: 100, valueWidth: 120),
                    const SizedBox(height: 14),
                    _skeletonRow(labelWidth: 90, valueWidth: 150),
                  ],
                ),
                const SizedBox(height: 16),
                // Vehicle chips skeleton
                _buildSkeletonCard(
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(
                        5,
                        (i) => LoadingSkeletonWidget(
                          width: [70.0, 60.0, 80.0, 100.0, 65.0][i],
                          height: 36,
                          borderRadius: 20,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildSkeletonCard(
                  children: [
                    _skeletonRow(labelWidth: 100, valueWidth: 130),
                    const SizedBox(height: 14),
                    _skeletonRow(labelWidth: 110, valueWidth: 130),
                  ],
                ),
                const SizedBox(height: 16),
                _buildSkeletonCard(
                  children: [
                    _skeletonRow(labelWidth: 80, valueWidth: 120),
                    const SizedBox(height: 14),
                    _skeletonRow(labelWidth: 90, valueWidth: 110),
                  ],
                ),
                const SizedBox(height: 16),
                // Earnings history
                _buildSkeletonCard(
                  children: List.generate(
                    3,
                    (i) => Padding(
                      padding: EdgeInsets.only(bottom: i < 2 ? 12.0 : 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                LoadingSkeletonWidget(
                                  width: 100,
                                  height: 13,
                                  borderRadius: 4,
                                ),
                                const SizedBox(height: 5),
                                LoadingSkeletonWidget(
                                  width: 80,
                                  height: 11,
                                  borderRadius: 4,
                                ),
                              ],
                            ),
                          ),
                          LoadingSkeletonWidget(
                            width: 80,
                            height: 16,
                            borderRadius: 4,
                          ),
                          const SizedBox(width: 8),
                          LoadingSkeletonWidget(
                            width: 60,
                            height: 22,
                            borderRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildSkeletonCard(
                  children: [
                    _skeletonToggleRow(),
                    const Divider(height: 20),
                    _skeletonToggleRow(),
                    const Divider(height: 20),
                    _skeletonToggleRow(),
                    const Divider(height: 20),
                    _skeletonToggleRow(),
                  ],
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSkeletonCard({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              LoadingSkeletonWidget(width: 32, height: 32, borderRadius: 8),
              const SizedBox(width: 10),
              LoadingSkeletonWidget(width: 130, height: 15, borderRadius: 4),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _skeletonRow({
    required double labelWidth,
    required double valueWidth,
  }) {
    return Row(
      children: [
        LoadingSkeletonWidget(width: labelWidth, height: 12, borderRadius: 4),
        const Spacer(),
        LoadingSkeletonWidget(width: valueWidth, height: 12, borderRadius: 4),
      ],
    );
  }

  Widget _skeletonToggleRow() {
    return Row(
      children: [
        LoadingSkeletonWidget(width: 140, height: 13, borderRadius: 4),
        const Spacer(),
        LoadingSkeletonWidget(width: 44, height: 24, borderRadius: 12),
      ],
    );
  }
}
