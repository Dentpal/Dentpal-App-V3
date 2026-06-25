import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/cart_model.dart';
import '../../core/app_theme/app_colors.dart';
import '../../core/app_theme/app_text_styles.dart';
import 'package:dentpal/utils/app_logger.dart';
import 'voucher_picker_sheet.dart';

class SellerGroupWidget extends StatefulWidget {
  final SellerGroup sellerGroup;
  final Function(CartItem, int) onUpdateQuantity;
  final Function(CartItem) onRemoveItem;
  final Function(CartItem, bool) onToggleItemSelection;
  final Function(SellerGroup) onToggleGroupSelection;
  final VoidCallback? onSellerNameTap;
  final Map<String, dynamic>? selectedDiscountVoucher;
  final void Function(Map<String, dynamic>?)? onDiscountVoucherSelected;
  final Map<String, dynamic>? selectedShippingVoucher;
  final void Function(Map<String, dynamic>?)? onShippingVoucherSelected;

  const SellerGroupWidget({
    super.key,
    required this.sellerGroup,
    required this.onUpdateQuantity,
    required this.onRemoveItem,
    required this.onToggleItemSelection,
    required this.onToggleGroupSelection,
    this.onSellerNameTap,
    this.selectedDiscountVoucher,
    this.onDiscountVoucherSelected,
    this.selectedShippingVoucher,
    this.onShippingVoucherSelected,
  });

  @override
  State<SellerGroupWidget> createState() => _SellerGroupWidgetState();
}

class _SellerGroupWidgetState extends State<SellerGroupWidget> {
  Map<String, dynamic>? _freeDeliveryVoucher;
  bool _voucherLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchFreeDeliveryVoucher();
  }

  @override
  void didUpdateWidget(SellerGroupWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sellerGroup.sellerId != widget.sellerGroup.sellerId) {
      _freeDeliveryVoucher = null;
      _voucherLoading = true;
      _fetchFreeDeliveryVoucher();
    }
  }

  Set<String> _cartBrands() {
    final brands = <String>{};
    for (final item in widget.sellerGroup.items) {
      final b = item.brand?.trim().toLowerCase();
      if (b != null && b.isNotEmpty) brands.add(b);
    }
    return brands;
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  Future<void> _fetchFreeDeliveryVoucher() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('Vouchers')
          .where('sellerId', isEqualTo: widget.sellerGroup.sellerId)
          .where('discountType', isEqualTo: 'free_delivery')
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();

      if (mounted) {
        final now = DateTime.now();
        final cartBrands = _cartBrands();
        final validDocs = snapshot.docs.where((d) {
          final data = d.data();
          final start = _parseDate(data['startDate']);
          final end = _parseDate(data['endDate']);
          if (start != null && now.isBefore(start)) return false;
          if (end != null && now.isAfter(end)) return false;
          if (!voucherMatchesBrands(data, cartBrands)) return false;
          return true;
        }).toList();
        setState(() {
          if (validDocs.isNotEmpty) {
            _freeDeliveryVoucher = {...validDocs.first.data(), 'id': validDocs.first.id};
          } else {
            _freeDeliveryVoucher = null;
          }
          _voucherLoading = false;
        });
      }
    } catch (e) {
      AppLogger.d('Error fetching free delivery voucher: $e');
      if (mounted) {
        setState(() {
          _freeDeliveryVoucher = null;
          _voucherLoading = false;
        });
      }
    }
  }

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
          if (widget.sellerGroup.items.isNotEmpty) ...[
            const Divider(height: 1, color: AppColors.grey200),
            _buildItemsList(context),
            const Divider(height: 1, color: AppColors.grey200),
            _buildSellerSummary(),
            const Divider(height: 1, color: AppColors.grey200),
            _buildDiscountVoucherRow(),
            const Divider(height: 1, color: AppColors.grey200),
            _buildShippingVoucherRow(),
          ],
        ],
      ),
    );
  }

  Widget _buildSellerHeader() {
    final hideProgressBar = widget.selectedShippingVoucher != null;
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Seller selection checkbox
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => widget.onToggleGroupSelection(widget.sellerGroup),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      widget.sellerGroup.allItemsSelected
                          ? Icons.check_circle
                          : widget.sellerGroup.hasSelectedItems
                          ? Icons.indeterminate_check_box
                          : Icons.circle_outlined,
                      color: widget.sellerGroup.allItemsSelected
                          ? AppColors.primary
                          : widget.sellerGroup.hasSelectedItems
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
                    GestureDetector(
                      onTap: widget.onSellerNameTap,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
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
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              widget.sellerGroup.sellerName,
                              style: AppTextStyles.titleMedium.copyWith(
                                fontWeight: FontWeight.w600,
                                color: widget.onSellerNameTap != null
                                    ? AppColors.primary
                                    : AppColors.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (widget.onSellerNameTap != null) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.chevron_right,
                              size: 20,
                              color: AppColors.primary,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.sellerGroup.items.length} item${widget.sellerGroup.items.length != 1 ? 's' : ''}',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    // Free Shipping Progress Bar — hidden when a shipping voucher is already selected
                    if (!_voucherLoading && _freeDeliveryVoucher != null && !hideProgressBar)
                      _buildFreeShippingProgressBar(),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFreeShippingProgressBar() {
    final minAmount = _freeDeliveryVoucher!['minimumOrderAmount'] as num? ?? 0;
    if (minAmount <= 0) return SizedBox.shrink();

    final progress = (widget.sellerGroup.selectedItemsTotal / minAmount).clamp(0.0, 1.0);
    final remaining = (minAmount - widget.sellerGroup.selectedItemsTotal).clamp(0, double.infinity);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (remaining > 0)
            Text(
              'Add ₱${remaining.toStringAsFixed(2)} to get free shipping',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.7),
                fontSize: 12,
                fontFamily: 'Roboto'
              ),
            )
          else
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: "You've enjoyed ",
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.primary,
                      fontSize: 12,
                    ),
                  ),
                  TextSpan(
                    text: "Free Shipping",
                    style: AppTextStyles.bodySmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      fontSize: 12,
                    ),
                  ),
                  TextSpan(
                    text: "!",
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.primary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppColors.grey200,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  String _voucherCodeSuffix(Map<String, dynamic> voucher) {
    final code = (voucher['code'] as String?)?.trim();
    if (code == null || code.isEmpty) return '';
    return ' ($code)';
  }

  String? _formatDiscountVoucherLabel(Map<String, dynamic>? voucher) {
    if (voucher == null) return null;
    final discountType = voucher['discountType'] as String? ?? '';
    final discountValue = voucher['discountValue'] as num? ?? 0;

    String? benefit;
    if (discountType == 'percentage') {
      benefit = '-${discountValue.toStringAsFixed(0)}%';
    } else if (discountType == 'fixed') {
      benefit = '-₱${discountValue.toStringAsFixed(2)}';
    }

    if (benefit == null) return null;
    return '$benefit${_voucherCodeSuffix(voucher)}';
  }

  String? _formatShippingVoucherLabel(Map<String, dynamic>? voucher) {
    if (voucher == null) return null;
    final modes = parseShippingCoverage(voucher['shippingOption']);

    String label;
    if (modes.contains('standard') && modes.contains('express')) {
      label = 'Free Standard/Express Shipping';
    } else if (modes.contains('express')) {
      label = 'Free Express Shipping';
    } else {
      label = 'Free Standard Shipping';
    }

    return '$label${_voucherCodeSuffix(voucher)}';
  }

  Widget _buildDiscountVoucherRow() {
    final discountLabel = _formatDiscountVoucherLabel(widget.selectedDiscountVoucher);
    final baseStyle = AppTextStyles.bodyMedium.copyWith(
      fontWeight: FontWeight.w500,
      fontFamily: 'Roboto',
    );
    final selectedStyle = baseStyle.copyWith(
      color: AppColors.primary,
      fontWeight: FontWeight.w700,
    );

    return InkWell(
      onTap: () => _openVoucherPicker(VoucherPickerMode.discount),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.local_offer_outlined, color: AppColors.primary, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: 'Add Shop Voucher Code',
                  style: baseStyle,
                  children: discountLabel == null
                      ? const []
                      : [
                          const TextSpan(text: ' - '),
                          TextSpan(text: discountLabel, style: selectedStyle),
                        ],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              color: AppColors.grey400,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShippingVoucherRow() {
    final shippingLabel = _formatShippingVoucherLabel(widget.selectedShippingVoucher);
    final baseStyle = AppTextStyles.bodyMedium.copyWith(
      fontWeight: FontWeight.w500,
      fontFamily: 'Roboto',
    );
    final selectedStyle = baseStyle.copyWith(
      color: AppColors.primary,
      fontWeight: FontWeight.w700,
    );

    return InkWell(
      onTap: () => _openVoucherPicker(VoucherPickerMode.shipping),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.local_shipping_outlined, color: AppColors.primary, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: 'Add Shipping Voucher Code',
                  style: baseStyle,
                  children: shippingLabel == null
                      ? const []
                      : [
                          const TextSpan(text: ' - '),
                          TextSpan(text: shippingLabel, style: selectedStyle),
                        ],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              color: AppColors.grey400,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  void _openVoucherPicker(VoucherPickerMode mode) {
    final isShipping = mode == VoucherPickerMode.shipping;
    final current = isShipping ? widget.selectedShippingVoucher : widget.selectedDiscountVoucher;
    final callback = isShipping ? widget.onShippingVoucherSelected : widget.onDiscountVoucherSelected;
    VoucherPickerSheet.show(
      context: context,
      mode: mode,
      sellerId: widget.sellerGroup.sellerId,
      sellerName: widget.sellerGroup.sellerName,
      selectedItemsTotal: widget.sellerGroup.selectedItemsTotal,
      cartBrands: _cartBrands(),
      currentSelectedVoucher: current,
      onVoucherSelected: (voucher) {
        callback?.call(voucher);
      },
    );
  }

  Widget _buildItemsList(BuildContext context) {
    return Column(
      children: widget.sellerGroup.items
          .map((item) => _buildCartItem(context, item))
          .toList(),
    );
  }

  Widget _buildCartItem(BuildContext context, CartItem item) {
    final bool isUnavailable = item.isUnavailable;

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
        return await _showDeleteConfirmation(context, item);
      },
      onDismissed: (direction) {
        widget.onRemoveItem(item);
      },
      child: Opacity(
        opacity: isUnavailable ? 0.5 : 1.0,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: isUnavailable ? BoxDecoration(
            color: AppColors.grey100.withValues(alpha: 0.5),
          ) : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isUnavailable) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: AppColors.error,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.unavailableReason ?? 'This product is unavailable',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              Row(
                children: [
                  Tooltip(
                    message: isUnavailable
                        ? item.unavailableReason ?? 'This product is unavailable'
                        : 'Select item',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: isUnavailable
                            ? null
                            : () => widget.onToggleItemSelection(item, !item.isSelected),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            isUnavailable
                                ? Icons.block
                                : item.isSelected
                                    ? Icons.check_circle
                                    : Icons.circle_outlined,
                            color: isUnavailable
                                ? AppColors.error
                                : item.isSelected
                                    ? AppColors.primary
                                    : AppColors.grey400,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

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
                        if (item.variationName != null && item.variationName!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            item.variationName!,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.onSurface.withValues(alpha: 0.6),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          '₱${(item.productPrice ?? 0).toStringAsFixed(2)}',
                          style: AppTextStyles.titleSmall.copyWith(
                            color: isUnavailable ? AppColors.grey400 : AppColors.primary,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Roboto',
                          ),
                        ),
                        const SizedBox(height: 8),

                        if (!isUnavailable && item.availableStock != null &&
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

                  _buildQuantitySelector(item, isUnavailable: isUnavailable),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuantitySelector(CartItem item, {bool isUnavailable = false}) {
    final bool canDecrease = item.quantity > 1 && !isUnavailable;
    final bool canIncrease = !isUnavailable &&
        (item.availableStock == null || item.quantity < item.availableStock!);
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
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
              onTap: canDecrease
                  ? () => widget.onUpdateQuantity(item, item.quantity - 1)
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

          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
              onTap: canIncrease
                  ? () => widget.onUpdateQuantity(item, item.quantity + 1)
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
                'Subtotal (${widget.sellerGroup.selectedItemsCount} item${widget.sellerGroup.selectedItemsCount != 1 ? 's' : ''})',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.onSurface.withValues(alpha: 0.8),
                ),
              ),
              Text(
                '₱${widget.sellerGroup.selectedItemsTotal.toStringAsFixed(2)}',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),

          if (widget.sellerGroup.hasSelectedItems) ...[
            const SizedBox(height: 8),
            const Divider(height: 1, color: AppColors.grey200),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total from ${widget.sellerGroup.sellerName}',
                  style: AppTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '₱${widget.sellerGroup.selectedItemsTotal.toStringAsFixed(2)}',
                  style: AppTextStyles.titleSmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Roboto',
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
