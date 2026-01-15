import 'package:dentpal/core/app_theme/index.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/product_model.dart';

class ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = product.variations?.isNotEmpty == true 
        ? (product.variations!.first.imageURL ?? product.imageURL)
        : product.imageURL;

    final lowestPrice = product.lowestPrice;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWebView = screenWidth > 900;

    // Use different layouts for mobile vs web
    return isWebView 
        ? _buildWebCard(imageUrl, lowestPrice)
        : _buildMobileCard(imageUrl, lowestPrice);
  }

  // Mobile-optimized card (compact)
  Widget _buildMobileCard(String imageUrl, double? lowestPrice) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Product Image
            AspectRatio(
              aspectRatio: 1.3,
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
                child: _buildImage(imageUrl, 32),
              ),
            ),
            // Product Details
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Product Name
                  Text(
                    product.name,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                      fontSize: 13,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Price and Stock
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: _buildPrice(lowestPrice, 12, 11),
                      ),
                      if (product.variations?.isNotEmpty == true)
                        _buildVariationBadge(18, 9),
                    ],
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

  // Web-optimized card (spacious)
  Widget _buildWebCard(String imageUrl, double? lowestPrice) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Image
            SizedBox(
              height: 140,
              width: double.infinity,
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
                child: _buildImage(imageUrl, 40),
              ),
            ),
            // Product Details
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product Name
                  Text(
                    product.name,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                      fontSize: 16,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  // Price and Stock
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: _buildPrice(lowestPrice, 14, 13),
                      ),
                      if (product.variations?.isNotEmpty == true)
                        _buildVariationBadge(20, 10),
                    ],
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

  // Shared image widget
  Widget _buildImage(String imageUrl, double iconSize) {
    return imageUrl.isNotEmpty
        ? CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(
              color: Colors.grey.shade100,
              child: const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
            ),
            errorWidget: (context, url, error) => Container(
              color: Colors.grey.shade100,
              child: Icon(
                Icons.image_not_supported,
                color: Colors.grey,
                size: iconSize,
              ),
            ),
          )
        : Container(
            color: Colors.grey.shade100,
            child: Icon(
              Icons.image_not_supported,
              color: Colors.grey,
              size: iconSize,
            ),
          );
  }

  // Shared price widget
  Widget _buildPrice(double? lowestPrice, double priceSize, double variesSize) {
    return lowestPrice != null
        ? Text(
            '₱${lowestPrice.toStringAsFixed(2)}',
            style: AppTextStyles.bodySmall.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
              fontFamily: 'Roboto',
              fontSize: priceSize,
            ),
            overflow: TextOverflow.ellipsis,
          )
        : Text(
            'Price varies',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.onSurface.withOpacity(0.6),
              fontSize: variesSize,
            ),
            overflow: TextOverflow.ellipsis,
          );
  }

  // Shared variation badge widget
  Widget _buildVariationBadge(double size, double fontSize) {
    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.only(left: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          '${product.variations!.length}',
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.primary,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}