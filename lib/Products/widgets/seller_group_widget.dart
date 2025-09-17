import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/cart_model.dart';
import '../../core/app_theme/app_colors.dart';
import '../../core/app_theme/app_text_styles.dart';

class SellerGroupWidget extends StatelessWidget {
  final SellerGroup sellerGroup;
  final Function(CartItem, int) onUpdateQuantity;
  final Function(CartItem) onRemoveItem;
  final Function(CartItem, bool) onToggleItemSelection;
  final Function(SellerGroup) onToggleGroupSelection;

  const SellerGroupWidget({
    super.key,
    required this.sellerGroup,
    required this.onUpdateQuantity,
    required this.onRemoveItem,
    required this.onToggleItemSelection,
    required this.onToggleGroupSelection,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSellerHeader(),
          if (sellerGroup.items.isNotEmpty) ...[
            const Divider(height: 1, color: AppColors.grey200),
            _buildItemsList(context),
            const Divider(height: 1, color: AppColors.grey200),
            _buildSellerSummary(),
          ],
        ],
      ),
    );
  }

  Widget _buildSellerHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Seller selection checkbox
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onToggleGroupSelection(sellerGroup),
              child: Container(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  sellerGroup.allItemsSelected
                      ? Icons.check_circle
                      : sellerGroup.hasSelectedItems
                      ? Icons.indeterminate_check_box
                      : Icons.circle_outlined,
                  color: sellerGroup.allItemsSelected
                      ? AppColors.primary
                      : sellerGroup.hasSelectedItems
                      ? AppColors.warning
                      : AppColors.grey400,
                  size: 24,
                ),
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Seller info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.store, size: 14, color: AppColors.primary),
                          const SizedBox(width: 4),
                          Text(
                            'SELLER',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (sellerGroup.shippingCost == 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'FREE SHIPPING',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.success,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  sellerGroup.sellerName,
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${sellerGroup.items.length} item${sellerGroup.items.length != 1 ? 's' : ''}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),

          // Shipping cost display
          if (sellerGroup.shippingCost > 0)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Shipping',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                Text(
                  '₱${sellerGroup.shippingCost.toStringAsFixed(2)}',
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                    fontFamily: 'Roboto', // Use Roboto for peso sign
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildItemsList(BuildContext context) {
    return Column(
      children: sellerGroup.items
          .map((item) => _buildCartItem(context, item))
          .toList(),
    );
  }

  Widget _buildCartItem(BuildContext context, CartItem item) {
    return Dismissible(
      key: Key(item.cartItemId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.error,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const Icon(Icons.delete_outline, color: Colors.white, size: 24),
            const SizedBox(width: 8),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        // Show confirmation dialog
        return await _showDeleteConfirmation(context, item);
      },
      onDismissed: (direction) {
        onRemoveItem(item);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Item selection checkbox
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onToggleItemSelection(item, !item.isSelected),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    item.isSelected
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                    color: item.isSelected
                        ? AppColors.primary
                        : AppColors.grey400,
                    size: 20,
                  ),
                ),
              ),
            ),

            const SizedBox(width: 12),

            // Product image
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.grey100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: item.productImage != null
                    ? CachedNetworkImage(
                        imageUrl: item.productImage!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: AppColors.grey100,
                          child: const Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: AppColors.grey100,
                          child: const Icon(
                            Icons.image_not_supported,
                            color: AppColors.grey400,
                            size: 24,
                          ),
                        ),
                      )
                    : const Icon(
                        Icons.image_not_supported,
                        color: AppColors.grey400,
                        size: 24,
                      ),
              ),
            ),

            const SizedBox(width: 12),

            // Product details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productName ?? 'Loading...',
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₱${(item.productPrice ?? 0).toStringAsFixed(2)}',
                    style: AppTextStyles.titleSmall.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Roboto', // Use Roboto for peso sign
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Stock warning if quantity exceeds available stock
                  if (item.availableStock != null &&
                      item.quantity > item.availableStock!)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Only ${item.availableStock} in stock',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // Quantity controls
            _buildQuantitySelector(item),
          ],
        ),
      ),
    );
  }

  Widget _buildQuantitySelector(CartItem item) {
    final bool canDecrease = item.quantity > 1;
    final bool canIncrease =
        item.availableStock == null || item.quantity < item.availableStock!;
    final bool exceedsStock =
        item.availableStock != null && item.quantity > item.availableStock!;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: exceedsStock ? AppColors.error : AppColors.grey300,
          width: exceedsStock ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
        color: AppColors.surface,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Decrease button
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
              onTap: canDecrease
                  ? () => onUpdateQuantity(item, item.quantity - 1)
                  : null,
              child: Container(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.remove,
                  size: 16,
                  color: canDecrease ? AppColors.onSurface : AppColors.grey400,
                ),
              ),
            ),
          ),

          // Quantity display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: exceedsStock
                  ? AppColors.error.withValues(alpha: 0.1)
                  : AppColors.grey50,
            ),
            child: Text(
              '${item.quantity}',
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
                color: exceedsStock ? AppColors.error : AppColors.onSurface,
              ),
            ),
          ),

          // Increase button
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
              onTap: canIncrease
                  ? () => onUpdateQuantity(item, item.quantity + 1)
                  : null,
              child: Container(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.add,
                  size: 16,
                  color: canIncrease ? AppColors.onSurface : AppColors.grey400,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSellerSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Subtotal (${sellerGroup.selectedItemsCount} item${sellerGroup.selectedItemsCount != 1 ? 's' : ''})',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.onSurface.withValues(alpha: 0.8),
                ),
              ),
              Text(
                '₱${sellerGroup.selectedItemsTotal.toStringAsFixed(2)}',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Roboto', // Use Roboto for peso sign
                ),
              ),
            ],
          ),

          if (sellerGroup.hasSelectedItems && sellerGroup.shippingCost > 0) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Shipping',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.onSurface.withValues(alpha: 0.8),
                  ),
                ),
                Text(
                  '₱${sellerGroup.shippingCost.toStringAsFixed(2)}',
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Roboto', // Use Roboto for peso sign
                  ),
                ),
              ],
            ),
          ],

          if (sellerGroup.hasSelectedItems) ...[
            const SizedBox(height: 8),
            const Divider(height: 1, color: AppColors.grey200),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total from ${sellerGroup.sellerName}',
                  style: AppTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '₱${sellerGroup.totalWithShipping.toStringAsFixed(2)}',
                  style: AppTextStyles.titleSmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Roboto', // Use Roboto for peso sign
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<bool?> _showDeleteConfirmation(
    BuildContext context,
    CartItem item,
  ) async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.delete_outline,
                color: AppColors.error,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Remove Item',
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to remove "${item.productName ?? 'this item'}" from your cart?',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'This action cannot be undone.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.6),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: AppTextStyles.labelLarge.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Remove',
              style: AppTextStyles.labelLarge.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
