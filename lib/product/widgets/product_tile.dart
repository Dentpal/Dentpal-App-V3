import 'package:flutter/material.dart';

import 'package:dentpal/core/app_theme/app_text_styles.dart';
import 'package:dentpal/core/app_theme/ink_palette.dart';
import 'package:dentpal/core/widgets/app_network_image.dart';
import 'package:dentpal/utils/currency_formatter.dart';

import '../models/product_model.dart';

/// One catalogue tile: the shape a product wears everywhere it appears in a
/// grid or a row.
///
/// It was Browse's private `_buildProductCard`, which meant the "similar
/// products" row on the detail page would have been a second drawing of the
/// same card — and the two would have drifted the way the page headers did.
/// The tap is the caller's: Browse records a click before it navigates, the
/// detail page does not.
class ProductTile extends StatelessWidget {
  const ProductTile({
    super.key,
    required this.product,
    required this.width,
    required this.onTap,
    this.rank,
  });

  final Product product;

  /// The width the tile is laid out at. Decides how large a thumbnail is
  /// decoded, so pass the real cell width rather than an estimate.
  final double width;

  final VoidCallback onTap;

  /// Position in a ranked list — the amber "#1" badge on Most Popular. Null
  /// everywhere else.
  final int? rank;

  /// The shape of a tile, given the width of the row it sits in.
  ///
  /// Two columns on a phone leaves each tile about 170pt across, and at the old
  /// flat 0.74 the shot got barely 110pt of that — the one thing that tells one
  /// product from the next, at thumbnail size. A narrow row gives the tile more
  /// height instead, and all of it goes to the image.
  static double aspectRatioFor(double rowWidth) => rowWidth < 520 ? 0.62 : 0.74;

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);

    final variation = product.variations?.isNotEmpty == true
        ? product.variations!.first
        : null;
    final imageUrl =
        variation?.thumbnailURL ??
        product.thumbnailURL ??
        variation?.imageURL ??
        product.imageURL;
    final price = product.lowestPrice;
    final brand = product.brand ?? '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: ink.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ink.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The shot fills the top of the tile edge to edge. The backdrop
            // still sits under it, for the sources that arrive with
            // transparency rather than a white cut-out.
            Expanded(
              child: Container(
                decoration: BoxDecoration(gradient: ink.productBackdrop),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AppNetworkImage(
                      url: imageUrl,
                      width: width,
                      height: width,
                      backgroundColor: Colors.transparent,
                    ),
                    if (rank != null)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: ink.amber,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '#$rank',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: ink.onAmber,
                              fontWeight: FontWeight.w800,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (brand.isNotEmpty)
                    Text(
                      brand.toUpperCase(),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: ink.text.withValues(alpha: 0.45),
                        fontWeight: FontWeight.w700,
                        fontSize: 9,
                        letterSpacing: 0.7,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  Text(
                    product.name,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: ink.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      height: 1.25,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    price != null
                        ? CurrencyFormatter.formatWithPeso(price)
                        : 'Price on request',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: ink.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
