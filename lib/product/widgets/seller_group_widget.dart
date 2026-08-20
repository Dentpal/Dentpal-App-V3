import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/cart_model.dart';
import '../../core/app_theme/app_text_styles.dart';
import '../../core/app_theme/ink_palette.dart';
import '../../core/widgets/app_network_image.dart';
import 'package:dentpal/utils/app_logger.dart';
import 'package:dentpal/utils/currency_formatter.dart';
import 'voucher_picker_sheet.dart';

/// One supplier's slice of the cart.
///
/// Grouped by seller because a real order routinely splits across two
/// distributors with different lead times and different vouchers. Hiding that
/// until checkout is how a marketplace loses a purchasing manager's trust — the
/// split, and what each seller's total comes to, belongs on this screen.
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

  InkPalette get ink => InkPalette.of(context);

  /// Destructive red. [InkPalette] has no error tone of its own, and amber is
  /// reserved for urgency rather than danger.
  Color get _danger =>
      ink.isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);

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
            _freeDeliveryVoucher = {
              ...validDocs.first.data(),
              'id': validDocs.first.id,
            };
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
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSellerHeader(),
          if (widget.sellerGroup.items.isNotEmpty) ...[
            _buildShipsFrom(),
            _buildItemsList(context),
            _divider(),
            _buildSellerSummary(),
            _divider(),
            _buildDiscountVoucherRow(),
            _divider(),
            _buildShippingVoucherRow(),
          ],
        ],
      ),
    );
  }

  Widget _divider() => Divider(height: 1, thickness: 1, color: ink.border);

  // ── Header ───────────────────────────────────────────────────────────────

  /// Supplier strip: select-all, store name, and a way through to the store.
  Widget _buildSellerHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: ink.surfaceHigh,
        border: Border(bottom: BorderSide(color: ink.border)),
      ),
      child: Row(
        children: [
          _QuietCheckbox(
            ink: ink,
            state: widget.sellerGroup.allItemsSelected
                ? _CheckState.checked
                : widget.sellerGroup.hasSelectedItems
                ? _CheckState.partial
                : _CheckState.unchecked,
            onTap: () => widget.onToggleGroupSelection(widget.sellerGroup),
            semanticLabel: 'Select all items from '
                '${widget.sellerGroup.sellerName}',
          ),
          const SizedBox(width: 10),
          Icon(
            Icons.storefront_outlined,
            size: 16,
            color: ink.text.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: widget.onSellerNameTap,
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      widget.sellerGroup.sellerName,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: ink.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.onSellerNameTap != null)
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: ink.text.withValues(alpha: 0.45),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${widget.sellerGroup.items.length} item'
            '${widget.sellerGroup.items.length != 1 ? 's' : ''}',
            style: AppTextStyles.bodySmall.copyWith(
              color: ink.text.withValues(alpha: 0.5),
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  /// Where the order ships from, plus the free-shipping bar when this seller is
  /// running one. Both are lead-time information a buyer needs before checkout,
  /// not after.
  Widget _buildShipsFrom() {
    final address = widget.sellerGroup.sellerShippingAddress?.trim();
    final hideProgressBar = widget.selectedShippingVoucher != null;
    final showBar =
        !_voucherLoading && _freeDeliveryVoucher != null && !hideProgressBar;

    if ((address == null || address.isEmpty) && !showBar) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (address != null && address.isNotEmpty)
            Text(
              'Ships from $address',
              style: AppTextStyles.bodySmall.copyWith(
                color: ink.text.withValues(alpha: 0.55),
                fontSize: 11.5,
              ),
            ),
          if (showBar) _buildFreeShippingProgressBar(),
        ],
      ),
    );
  }

  Widget _buildFreeShippingProgressBar() {
    final minAmount = _freeDeliveryVoucher!['minimumOrderAmount'] as num? ?? 0;
    if (minAmount <= 0) return const SizedBox.shrink();

    final total = widget.sellerGroup.selectedItemsTotal;
    final progress = (total / minAmount).clamp(0.0, 1.0);
    final remaining = (minAmount - total).clamp(0, double.infinity);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (remaining > 0)
            Text(
              'Add ${CurrencyFormatter.formatWithPeso(remaining.toDouble())} '
              'to get free shipping',
              style: AppTextStyles.bodySmall.copyWith(
                color: ink.text.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            )
          else
            Row(
              children: [
                Icon(Icons.check_circle, size: 14, color: ink.emerald),
                const SizedBox(width: 6),
                Text(
                  "You've earned free shipping",
                  style: AppTextStyles.bodySmall.copyWith(
                    color: ink.emerald,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: ink.border,
              valueColor: AlwaysStoppedAnimation<Color>(ink.emerald),
            ),
          ),
        ],
      ),
    );
  }

  // ── Vouchers ─────────────────────────────────────────────────────────────

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
      benefit = '-${CurrencyFormatter.formatWithPeso(discountValue.toDouble())}';
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

  Widget _buildDiscountVoucherRow() => _buildVoucherRow(
    icon: Icons.local_offer_outlined,
    prompt: 'Add shop voucher',
    value: _formatDiscountVoucherLabel(widget.selectedDiscountVoucher),
    mode: VoucherPickerMode.discount,
  );

  Widget _buildShippingVoucherRow() => _buildVoucherRow(
    icon: Icons.local_shipping_outlined,
    prompt: 'Add shipping voucher',
    value: _formatShippingVoucherLabel(widget.selectedShippingVoucher),
    mode: VoucherPickerMode.shipping,
  );

  Widget _buildVoucherRow({
    required IconData icon,
    required String prompt,
    required String? value,
    required VoucherPickerMode mode,
  }) {
    final applied = value != null;

    return InkWell(
      onTap: () => _openVoucherPicker(mode),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: ink.emerald, size: 17),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                applied ? value : prompt,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: applied ? ink.emerald : ink.text.withValues(alpha: 0.7),
                  fontWeight: applied ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              color: ink.text.withValues(alpha: 0.4),
              size: 19,
            ),
          ],
        ),
      ),
    );
  }

  void _openVoucherPicker(VoucherPickerMode mode) {
    final isShipping = mode == VoucherPickerMode.shipping;
    final current = isShipping
        ? widget.selectedShippingVoucher
        : widget.selectedDiscountVoucher;
    final callback = isShipping
        ? widget.onShippingVoucherSelected
        : widget.onDiscountVoucherSelected;
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

  // ── Items ────────────────────────────────────────────────────────────────

  Widget _buildItemsList(BuildContext context) {
    final items = widget.sellerGroup.items;
    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) _divider(),
          _buildCartItem(context, items[i]),
        ],
      ],
    );
  }

  Widget _buildCartItem(BuildContext context, CartItem item) {
    final isUnavailable = item.isUnavailable;

    // Swipe right-to-left to remove, with a confirmation. Kept deliberately:
    // it is the fastest way to prune a cart on a phone.
    return Dismissible(
      key: Key(item.cartItemId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        color: _danger,
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 22),
      ),
      confirmDismiss: (_) => _showDeleteConfirmation(context, item),
      onDismissed: (_) => widget.onRemoveItem(item),
      child: Opacity(
        opacity: isUnavailable ? 0.55 : 1.0,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isUnavailable) ...[
                _buildNotice(
                  icon: Icons.warning_amber_rounded,
                  tone: _danger,
                  text: item.unavailableReason ?? 'This product is unavailable',
                ),
                const SizedBox(height: 10),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 22),
                    child: _QuietCheckbox(
                      ink: ink,
                      state: isUnavailable
                          ? _CheckState.blocked
                          : item.isSelected
                          ? _CheckState.checked
                          : _CheckState.unchecked,
                      onTap: isUnavailable
                          ? null
                          : () => widget.onToggleItemSelection(
                              item,
                              !item.isSelected,
                            ),
                      semanticLabel: 'Select ${item.productName ?? 'item'}',
                    ),
                  ),
                  const SizedBox(width: 10),
                  _buildThumbnail(item),
                  const SizedBox(width: 12),
                  Expanded(child: _buildItemBody(item, isUnavailable)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(CartItem item) {
    return Container(
      width: 62,
      height: 62,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: ink.isDark ? ink.surfaceHigh : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ink.border),
      ),
      child: AppNetworkImage(
        url: item.productImage,
        width: 62,
        height: 62,
        fit: BoxFit.cover,
        maxDecodeDimension: 160,
        backgroundColor: ink.isDark ? ink.surfaceHigh : Colors.white,
      ),
    );
  }

  Widget _buildItemBody(CartItem item, bool isUnavailable) {
    final brand = item.brand?.trim();
    final variation = item.variationName?.trim();
    final lineTotal = (item.productPrice ?? 0) * item.quantity;
    final exceedsStock =
        item.availableStock != null && item.quantity > item.availableStock!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (brand != null && brand.isNotEmpty)
          Text(
            brand.toUpperCase(),
            style: AppTextStyles.labelSmall.copyWith(
              color: ink.text.withValues(alpha: 0.5),
              fontWeight: FontWeight.w800,
              fontSize: 10,
              letterSpacing: 0.9,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        Text(
          item.productName ?? 'Loading…',
          style: AppTextStyles.bodyMedium.copyWith(
            color: ink.text,
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
            height: 1.25,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (variation != null && variation.isNotEmpty)
          Text(
            variation,
            style: AppTextStyles.bodySmall.copyWith(
              color: ink.text.withValues(alpha: 0.5),
              fontSize: 11,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        if (exceedsStock && !isUnavailable) ...[
          const SizedBox(height: 5),
          Text(
            'Only ${item.availableStock} in stock',
            style: AppTextStyles.labelSmall.copyWith(
              color: _danger,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
        const SizedBox(height: 9),
        Row(
          children: [
            _buildQuantitySelector(item, isUnavailable: isUnavailable),
            const Spacer(),
            Text(
              CurrencyFormatter.formatWithPeso(lineTotal),
              style: AppTextStyles.titleSmall.copyWith(
                color: ink.text,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            const SizedBox(width: 2),
            IconButton(
              onPressed: () async {
                final confirmed = await _showDeleteConfirmation(context, item);
                if (confirmed == true) widget.onRemoveItem(item);
              },
              icon: const Icon(Icons.delete_outline, size: 18),
              color: ink.text.withValues(alpha: 0.45),
              splashRadius: 18,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              tooltip: 'Remove ${item.productName ?? 'item'}',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuantitySelector(CartItem item, {bool isUnavailable = false}) {
    final canDecrease = item.quantity > 1 && !isUnavailable;
    final canIncrease =
        !isUnavailable &&
        (item.availableStock == null || item.quantity < item.availableStock!);
    final exceedsStock =
        item.availableStock != null && item.quantity > item.availableStock!;

    return Container(
      decoration: BoxDecoration(
        color: ink.surfaceHigh,
        border: Border.all(color: exceedsStock ? _danger : ink.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stepButton(
            icon: Icons.remove,
            enabled: canDecrease,
            onTap: () => widget.onUpdateQuantity(item, item.quantity - 1),
          ),
          SizedBox(
            width: 30,
            child: Text(
              '${item.quantity}',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: exceedsStock ? _danger : ink.text,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          _stepButton(
            icon: Icons.add,
            enabled: canIncrease,
            onTap: () => widget.onUpdateQuantity(item, item.quantity + 1),
          ),
        ],
      ),
    );
  }

  Widget _stepButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Icon(
          icon,
          size: 15,
          color: ink.text.withValues(alpha: enabled ? 0.85 : 0.3),
        ),
      ),
    );
  }

  // ── Per-seller total ─────────────────────────────────────────────────────

  Widget _buildSellerSummary() {
    final count = widget.sellerGroup.selectedItemsCount;
    final total = widget.sellerGroup.selectedItemsTotal;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(
            'Subtotal ($count item${count != 1 ? 's' : ''})',
            style: AppTextStyles.bodyMedium.copyWith(
              color: ink.text.withValues(alpha: 0.65),
              fontSize: 13,
            ),
          ),
          const Spacer(),
          Text(
            CurrencyFormatter.formatWithPeso(total),
            style: AppTextStyles.bodyMedium.copyWith(
              color: ink.text,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotice({
    required IconData icon,
    required Color tone,
    required String text,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tone.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: tone, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodySmall.copyWith(
                color: tone,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
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
      builder: (dialogContext) => AlertDialog(
        backgroundColor: ink.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _danger.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.delete_outline, color: _danger, size: 22),
            ),
            const SizedBox(width: 12),
            Text(
              'Remove item',
              style: AppTextStyles.titleMedium.copyWith(
                color: ink.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Text(
          'Remove "${item.productName ?? 'this item'}" from your cart?',
          style: AppTextStyles.bodyMedium.copyWith(
            color: ink.text.withValues(alpha: 0.8),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'Cancel',
              style: AppTextStyles.labelLarge.copyWith(
                color: ink.text.withValues(alpha: 0.6),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _danger,
              foregroundColor: Colors.white,
              elevation: 0,
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

enum _CheckState { checked, unchecked, partial, blocked }

/// A small, low-contrast selection control.
///
/// Selection drives what actually gets checked out, so it cannot go away — but
/// it is a mechanic, not the point of the row. Drawn at 18px in the ink tone
/// rather than as a filled brand-coloured circle, so the product is what reads
/// first.
class _QuietCheckbox extends StatelessWidget {
  const _QuietCheckbox({
    required this.ink,
    required this.state,
    required this.onTap,
    required this.semanticLabel,
  });

  final InkPalette ink;
  final _CheckState state;
  final VoidCallback? onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final selected =
        state == _CheckState.checked || state == _CheckState.partial;

    Widget box;
    if (state == _CheckState.blocked) {
      box = Icon(Icons.block, size: 18, color: ink.text.withValues(alpha: 0.3));
    } else {
      box = Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: selected ? ink.emerald : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? ink.emerald : ink.text.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: selected
            ? Icon(
                state == _CheckState.partial ? Icons.remove : Icons.check,
                size: 13,
                color: ink.onEmerald,
              )
            : null,
      );
    }

    return Semantics(
      label: semanticLabel,
      checked: state == _CheckState.checked,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(padding: const EdgeInsets.all(3), child: box),
      ),
    );
  }
}
