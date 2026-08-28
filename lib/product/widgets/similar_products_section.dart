import 'package:flutter/material.dart';

import 'package:dentpal/core/app_theme/app_text_styles.dart';
import 'package:dentpal/core/app_theme/ink_palette.dart';
import 'package:dentpal/core/app_theme/theme_utils.dart';
import 'package:dentpal/core/widgets/skeleton.dart';

import '../models/product_model.dart';
import 'product_tile.dart';

/// "Similar Products" — four more from the category you are already looking at,
/// under the specifications.
///
/// The page hands it a future rather than a list: the row is the last thing on
/// a long screen, so it can fill in while the specifications above it are being
/// read. It renders nothing at all when the category holds nothing else — a
/// heading over blank space reads as a section that failed to load.
class SimilarProductsSection extends StatelessWidget {
  const SimilarProductsSection({
    super.key,
    required this.products,
    required this.onOpen,
  });

  /// Resolves to the products to show, already filtered and capped by the
  /// caller. An empty list hides the section.
  final Future<List<Product>> products;

  final void Function(Product) onOpen;

  /// How many tiles the row shows: one row on a wide window, two on a phone.
  static const int count = 4;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Product>>(
      future: products,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _frame(
            context,
            child: SkeletonShimmer(
              child: _grid(
                context,
                itemCount: count,
                itemBuilder: (context, index) => const SkeletonBox(
                  height: double.infinity,
                  width: double.infinity,
                  radius: 18,
                ),
              ),
            ),
          );
        }

        final items = snapshot.data ?? const <Product>[];
        if (items.isEmpty) return const SizedBox.shrink();

        return _frame(
          context,
          child: _grid(
            context,
            itemCount: items.length,
            itemBuilder: (context, index) => LayoutBuilder(
              builder: (context, constraints) => ProductTile(
                product: items[index],
                width: constraints.maxWidth,
                onTap: () => onOpen(items[index]),
              ),
            ),
          ),
        );
      },
    );
  }

  /// The card every section on the detail page is drawn in.
  Widget _frame(BuildContext context, {required Widget child}) {
    final ink = InkPalette.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppLayout.gutter,
        4,
        AppLayout.gutter,
        8,
      ),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ink.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: ink.emerald.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.grid_view_rounded,
                  color: ink.emerald,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Similar Products',
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.bold,
                    color: ink.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  /// Cut to the same aspect ratio Browse uses, so a tile is the same shape
  /// wherever it appears.
  Widget _grid(
    BuildContext context, {
    required int itemCount,
    required Widget Function(BuildContext, int) itemBuilder,
  }) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: context.isWideLayout ? 4 : 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: ProductTile.aspectRatioFor(
          MediaQuery.of(context).size.width,
        ),
      ),
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    );
  }
}
