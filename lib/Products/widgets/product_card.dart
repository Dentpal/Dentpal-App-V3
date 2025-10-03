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
    final isWebView = screenWidth > 800;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Image
            Expanded(
              flex: 7,
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                  child: imageUrl.isNotEmpty
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
                            child: const Icon(
                              Icons.image_not_supported,
                              color: Colors.grey,
                              size: 32,
                            ),
                          ),
                        )
                      : Container(
                          color: Colors.grey.shade100,
                          child: const Icon(
                            Icons.image_not_supported,
                            color: Colors.grey,
                            size: 32,
                          ),
                        ),
                ),
              ),
            ),
            
            // Product Details
            Expanded(
              flex: isWebView ? 2 : 3,
              child: Padding(
                padding: isWebView ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6) : const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: isWebView ? MainAxisAlignment.start : MainAxisAlignment.spaceBetween,
                  children: [
                    // Product Name
                    Text(
                      product.name,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                        fontSize: isWebView ? 16 : 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    
                    // Conditional spacing for web
                    if (isWebView) const SizedBox(height: 4),
                    
                    // Price and Stock
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: lowestPrice != null
                              ? Text(
                                  '₱${lowestPrice.toStringAsFixed(2)}',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                    fontFamily: 'Roboto', // For peso sign support
                                    fontSize: isWebView? 14 : 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                )
                              : Text(
                                  'Price varies',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.onSurface.withValues(alpha: 0.6),
                                    fontSize: isWebView? 14 :  12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                        ),
                        
                        if (product.variations?.isNotEmpty == true) ...[
                          const SizedBox(width: 4),
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${product.variations!.length}',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
