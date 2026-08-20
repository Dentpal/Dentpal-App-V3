import 'package:flutter/material.dart';

import '../../core/app_theme/ink_palette.dart';
import '../../core/widgets/skeleton.dart';

/// Placeholder layouts shown while a page's first payload is in flight.
///
/// Each one mirrors the real layout closely enough that the content lands in
/// roughly the same place, so the page fills in rather than jumping. They all
/// wrap themselves in a [SkeletonShimmer], so callers just drop them in.

/// Card chrome shared by the list skeletons.
///
/// Takes a [context] so it can follow the theme: it used to paint the light
/// theme's surface unconditionally, which flashed a white card on every
/// dark-mode load before the real content arrived.
Widget _card({
  required BuildContext context,
  required Widget child,
  EdgeInsetsGeometry? margin,
  double radius = 16,
}) {
  final ink = InkPalette.of(context);
  return Container(
    margin: margin,
    decoration: BoxDecoration(
      color: ink.surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: ink.border),
    ),
    child: child,
  );
}

// ── Product listing ─────────────────────────────────────────────────────────

/// Mirrors a trader card: 8:3 cover, store name, location row, ETA pill.
class TraderCardSkeleton extends StatelessWidget {
  const TraderCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return _card(
      context: context,
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ClipRRect(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
            child: AspectRatio(
              aspectRatio: 8 / 3,
              child: SkeletonBox(radius: 0),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLine(widthFactor: 0.55, height: 16),
                SizedBox(height: 10),
                SkeletonLine(widthFactor: 0.32, height: 12),
                SizedBox(height: 14),
                Row(
                  children: [
                    SkeletonBox(width: 92, height: 24, radius: 6),
                    SizedBox(width: 8),
                    SkeletonBox(width: 120, height: 24, radius: 6),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A short stack of [TraderCardSkeleton]s for the listing / search results.
class TraderListSkeleton extends StatelessWidget {
  const TraderListSkeleton({
    super.key,
    this.count = 3,
    this.padding = EdgeInsets.zero,
  });

  final int count;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: Padding(
        padding: padding,
        child: Column(
          children: List.generate(count, (_) => const TraderCardSkeleton()),
        ),
      ),
    );
  }
}

/// Stand-in for the wide promo banner at the top of the listing.
class BannerSkeleton extends StatelessWidget {
  const BannerSkeleton({super.key, this.aspectRatio = 8 / 3});

  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: _card(
        context: context,
        margin: const EdgeInsets.only(bottom: 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: const SkeletonBox(radius: 0),
          ),
        ),
      ),
    );
  }
}

// ── Product grids ───────────────────────────────────────────────────────────

/// Single grid cell: image on top, name / price lines below.
class ProductCardSkeleton extends StatelessWidget {
  const ProductCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: InkPalette.of(context).surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: InkPalette.of(context).border),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Expanded rather than a fixed ratio so the cell can never overflow,
          // whatever aspect ratio the grid hands us.
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              child: SkeletonBox(radius: 0),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLine(widthFactor: 0.9, height: 11),
                SizedBox(height: 6),
                SkeletonLine(widthFactor: 0.55, height: 11),
                SizedBox(height: 10),
                SkeletonLine(width: 64, height: 13),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Grid of [ProductCardSkeleton]s using the same responsive column count and
/// aspect ratio as the real product grids.
class ProductGridSkeleton extends StatelessWidget {
  const ProductGridSkeleton({
    super.key,
    this.itemCount = 6,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
  });

  final int itemCount;
  final EdgeInsetsGeometry padding;

  static int _crossAxisCount(double width) {
    if (width >= 1200) return 6;
    if (width >= 900) return 5;
    if (width >= 600) return 4;
    if (width >= 480) return 3;
    return 2;
  }

  static double _aspectRatio(double width) {
    if (width >= 1200) return 0.70;
    if (width >= 900) return 0.65;
    if (width >= 600) return 0.68;
    return 0.65;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return SkeletonShimmer(
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _crossAxisCount(width),
          childAspectRatio: _aspectRatio(width),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: itemCount,
        itemBuilder: (context, index) => const ProductCardSkeleton(),
      ),
    );
  }
}

// ── Product detail ──────────────────────────────────────────────────────────

/// Full-page placeholder for the product detail screen. Switches to a
/// two-column shape at the same breakpoint the real page uses.
class ProductDetailSkeleton extends StatelessWidget {
  const ProductDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 768;
    return SkeletonShimmer(
      child: isWide ? const _DetailWideSkeleton() : const _DetailNarrowSkeleton(),
    );
  }
}

class _DetailNarrowSkeleton extends StatelessWidget {
  const _DetailNarrowSkeleton();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          // Floating back / share buttons that sit over the image.
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                SkeletonBox(width: 40, height: 40, radius: 12),
                Spacer(),
                SkeletonBox(width: 92, height: 40, radius: 12),
              ],
            ),
          ),
          const AspectRatio(aspectRatio: 1, child: SkeletonBox(radius: 0)),
          const Expanded(
            child: SingleChildScrollView(
              physics: NeverScrollableScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: _DetailInfoSkeleton(),
              ),
            ),
          ),
          // Fixed add-to-cart bar.
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            color: InkPalette.of(context).surface,
            child: const Row(
              children: [
                SkeletonBox(width: 110, height: 44, radius: 12),
                SizedBox(width: 12),
                Expanded(child: SkeletonBox(height: 44, radius: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailWideSkeleton extends StatelessWidget {
  const _DetailWideSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        children: [
          // Stands in for the app bar the loaded page adds, so the content
          // below doesn't jump once it arrives.
          Container(
            height: 56,
            color: InkPalette.of(context).surface,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: const Row(
              children: [
                SkeletonBox(width: 24, height: 24, radius: 6),
                SizedBox(width: 20),
                SkeletonBox(width: 220, height: 16),
              ],
            ),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: const Padding(
                padding: EdgeInsets.all(32),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: SkeletonBox(radius: 16),
                      ),
                    ),
                    SizedBox(width: 32),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _DetailInfoSkeleton(),
                          SizedBox(height: 28),
                          SkeletonBox(height: 48, radius: 12),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Title, price, seller row, variation chips and description lines — shared by
/// both detail layouts.
class _DetailInfoSkeleton extends StatelessWidget {
  const _DetailInfoSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonLine(widthFactor: 0.85, height: 18),
        SizedBox(height: 10),
        SkeletonLine(widthFactor: 0.5, height: 18),
        SizedBox(height: 20),
        SkeletonBox(width: 140, height: 26),
        SizedBox(height: 24),
        Row(
          children: [
            SkeletonCircle(size: 44),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonLine(widthFactor: 0.55, height: 13),
                  SizedBox(height: 8),
                  SkeletonLine(widthFactor: 0.3, height: 11),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: 24),
        Row(
          children: [
            SkeletonBox(width: 78, height: 34, radius: 10),
            SizedBox(width: 10),
            SkeletonBox(width: 78, height: 34, radius: 10),
            SizedBox(width: 10),
            SkeletonBox(width: 78, height: 34, radius: 10),
          ],
        ),
        SizedBox(height: 26),
        SkeletonLine(height: 12),
        SizedBox(height: 10),
        SkeletonLine(height: 12),
        SizedBox(height: 10),
        SkeletonLine(widthFactor: 0.7, height: 12),
      ],
    );
  }
}

// ── Store page ──────────────────────────────────────────────────────────────

/// Full-page placeholder for a seller's storefront: banner, overlapping store
/// icon, vouchers, search bar, category strip and the product grid.
class StorePageSkeleton extends StatelessWidget {
  const StorePageSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    const double iconDiameter = 80;

    return SkeletonShimmer(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.bottomCenter,
              children: [
                const AspectRatio(
                  aspectRatio: 8 / 3,
                  child: SkeletonBox(radius: 0),
                ),
                Positioned(
                  bottom: -(iconDiameter / 2),
                  child: Container(
                    width: iconDiameter,
                    height: iconDiameter,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: InkPalette.of(context).surface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const SkeletonBox(radius: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: iconDiameter / 2 + 10),
            const SkeletonLine(
              width: 180,
              height: 16,
              alignment: Alignment.center,
            ),
            const SizedBox(height: 10),
            const SkeletonLine(
              width: 220,
              height: 12,
              alignment: Alignment.center,
            ),
            const SizedBox(height: 20),
            // Voucher strip — scrolls horizontally in the real page, so the
            // placeholders are allowed to run past the right edge too.
            SizedBox(
              height: 64,
              // ListView rather than a scroll view + Row: it pins the strip to
              // the leading edge instead of centring it when it happens to be
              // narrower than the screen.
              child: ListView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: const [
                  SkeletonBox(width: 200, height: 64, radius: 12),
                  SizedBox(width: 12),
                  SkeletonBox(width: 200, height: 64, radius: 12),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Search bar.
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SkeletonBox(height: 44, radius: 12),
            ),
            const SizedBox(height: 16),
            // Category tabs.
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                children: const [
                  SkeletonBox(width: 84, height: 36, radius: 18),
                  SizedBox(width: 8),
                  SkeletonBox(width: 118, height: 36, radius: 18),
                  SizedBox(width: 8),
                  SkeletonBox(width: 96, height: 36, radius: 18),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const ProductGridSkeleton(itemCount: 6),
          ],
        ),
      ),
    );
  }
}

// ── Cart ────────────────────────────────────────────────────────────────────

/// Placeholder for the cart's seller groups and their line items.
class CartSkeleton extends StatelessWidget {
  const CartSkeleton({super.key, this.groupCount = 2, this.itemsPerGroup = 2});

  final int groupCount;
  final int itemsPerGroup;

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: List.generate(
            groupCount,
            (_) => _CartGroupSkeleton(itemCount: itemsPerGroup),
          ),
        ),
      ),
    );
  }
}

class _CartGroupSkeleton extends StatelessWidget {
  const _CartGroupSkeleton({required this.itemCount});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return _card(
      context: context,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Seller header: select-all box, store icon, store name.
            const Row(
              children: [
                SkeletonBox(width: 20, height: 20, radius: 4),
                SizedBox(width: 12),
                SkeletonCircle(size: 28),
                SizedBox(width: 10),
                Expanded(child: SkeletonLine(widthFactor: 0.5, height: 14)),
              ],
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < itemCount; i++) ...[
              const _CartItemSkeleton(),
              if (i < itemCount - 1) const SizedBox(height: 16),
            ],
            const SizedBox(height: 16),
            // Group subtotal.
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SkeletonBox(width: 90, height: 12),
                SkeletonBox(width: 70, height: 16),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CartItemSkeleton extends StatelessWidget {
  const _CartItemSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonBox(width: 20, height: 20, radius: 4),
        SizedBox(width: 12),
        SkeletonBox(width: 72, height: 72, radius: 10),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonLine(widthFactor: 0.9, height: 12),
              SizedBox(height: 8),
              SkeletonLine(widthFactor: 0.45, height: 12),
              SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: SkeletonLine(widthFactor: 0.6, height: 16)),
                  SizedBox(width: 8),
                  SkeletonBox(width: 96, height: 28, radius: 8),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Checkout ────────────────────────────────────────────────────────────────

/// Stand-in for a currency amount that is still being calculated — used in the
/// checkout summary while shipping rates are in flight.
class AmountSkeleton extends StatelessWidget {
  const AmountSkeleton({super.key, this.width = 72, this.height = 14});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => SkeletonShimmer(
        child: SkeletonBox(width: width, height: height, radius: 4),
      );
}
