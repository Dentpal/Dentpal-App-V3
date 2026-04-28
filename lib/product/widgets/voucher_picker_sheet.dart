import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dentpal/utils/app_logger.dart';
import '../../core/app_theme/app_colors.dart';
import '../../core/app_theme/app_text_styles.dart';

enum VoucherPickerMode { discount, shipping }

/// Bottom sheet voucher picker shared between cart and checkout.
///
/// Discount mode lists `percentage` and `fixed` vouchers; shipping mode lists
/// `free_delivery` vouchers (rendered with a `shippingOption`-aware label).
class VoucherPickerSheet extends StatefulWidget {
  final VoucherPickerMode mode;
  final String sellerId;
  final String sellerName;
  final double selectedItemsTotal;
  final Map<String, dynamic>? currentSelectedVoucher;
  final void Function(Map<String, dynamic>?) onVoucherSelected;

  const VoucherPickerSheet({
    super.key,
    required this.mode,
    required this.sellerId,
    required this.sellerName,
    required this.selectedItemsTotal,
    this.currentSelectedVoucher,
    required this.onVoucherSelected,
  });

  static Future<void> show({
    required BuildContext context,
    required VoucherPickerMode mode,
    required String sellerId,
    required String sellerName,
    required double selectedItemsTotal,
    Map<String, dynamic>? currentSelectedVoucher,
    required void Function(Map<String, dynamic>?) onVoucherSelected,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => VoucherPickerSheet(
        mode: mode,
        sellerId: sellerId,
        sellerName: sellerName,
        selectedItemsTotal: selectedItemsTotal,
        currentSelectedVoucher: currentSelectedVoucher,
        onVoucherSelected: (voucher) {
          onVoucherSelected(voucher);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  @override
  State<VoucherPickerSheet> createState() => _VoucherPickerSheetState();
}

class _VoucherPickerSheetState extends State<VoucherPickerSheet> {
  Map<String, dynamic>? _tempSelected;
  String _searchQuery = '';
  List<Map<String, dynamic>> _vouchers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tempSelected = widget.currentSelectedVoucher;
    _fetchVouchers();
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  Future<void> _fetchVouchers() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('Vouchers')
          .where('sellerId', isEqualTo: widget.sellerId)
          .where('status', isEqualTo: 'active')
          .get();

      if (!mounted) return;
      final now = DateTime.now();
      final all = snapshot.docs
          .map((d) => {...d.data(), 'id': d.id})
          .where((data) {
            final start = _parseDate(data['startDate']);
            final end = _parseDate(data['endDate']);
            if (start != null && now.isBefore(start)) return false;
            if (end != null && now.isAfter(end)) return false;
            return true;
          })
          .where(_matchesMode)
          .toList();
      setState(() {
        _vouchers = all;
        _loading = false;
      });
    } catch (e) {
      AppLogger.d('Error fetching vouchers: $e');
      if (mounted) {
        setState(() {
          _vouchers = [];
          _loading = false;
        });
      }
    }
  }

  bool _matchesMode(Map<String, dynamic> v) {
    final type = (v['discountType'] as String? ?? '').toLowerCase();
    if (widget.mode == VoucherPickerMode.shipping) {
      return type == 'free_delivery';
    }
    return type == 'percentage' || type == 'fixed';
  }

  List<Map<String, dynamic>> get _filteredVouchers {
    if (_searchQuery.isEmpty) return _vouchers;
    final query = _searchQuery.toLowerCase();
    return _vouchers.where((v) {
      final code = (v['code'] as String? ?? '').toLowerCase();
      final type = (v['discountType'] as String? ?? '').toLowerCase();
      final value = v['discountValue'].toString().toLowerCase();
      return code.contains(query) || type.contains(query) || value.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final headerText = widget.mode == VoucherPickerMode.shipping
        ? '${widget.sellerName} - Shipping Vouchers'
        : '${widget.sellerName} - Vouchers';
    final searchHint = widget.mode == VoucherPickerMode.shipping
        ? 'Please enter shipping voucher code'
        : 'Please enter shop voucher code';

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.5,
      maxChildSize: 0.85,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        headerText,
                        style: AppTextStyles.titleMedium.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 24),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.grey200),
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  onChanged: (value) => setState(() => _searchQuery = value),
                  decoration: InputDecoration(
                    hintText: searchHint,
                    hintStyle: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.onSurface.withValues(alpha: 0.5),
                    ),
                    prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.primary),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? GestureDetector(
                            onTap: () => setState(() => _searchQuery = ''),
                            child: const Icon(Icons.close, size: 18, color: AppColors.primary),
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.grey300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.grey300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.primary, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  style: AppTextStyles.bodySmall,
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: AppColors.primary),
                      )
                    : _filteredVouchers.isEmpty
                        ? Center(
                            child: Text(
                              'No vouchers available',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.onSurface.withValues(alpha: 0.5),
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _filteredVouchers.length,
                            itemBuilder: (context, index) {
                              final voucher = _filteredVouchers[index];
                              final isDisabled = widget.selectedItemsTotal <
                                  (voucher['minimumOrderAmount'] as num? ?? 0);
                              final isSelected = _tempSelected?['code'] == voucher['code'];
                              return _buildVoucherTile(voucher, isSelected, isDisabled);
                            },
                          ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton(
                  onPressed: () {
                    widget.onVoucherSelected(_tempSelected);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Apply',
                    style: AppTextStyles.labelLarge.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVoucherTile(
    Map<String, dynamic> voucher,
    bool isSelected,
    bool isDisabled,
  ) {
    final discountType = voucher['discountType'] as String? ?? '';
    final discountValue = voucher['discountValue'] as num? ?? 0;
    final minimumOrderAmount = voucher['minimumOrderAmount'] as num? ?? 0;
    final maximumSpend = voucher['maximumSpend'] as num?;

    String titleText;
    String subtitle1Text;
    String? subtitle2Text;

    if (widget.mode == VoucherPickerMode.shipping) {
      final coverage = _shippingCoverageLabel(voucher['shippingOption']);
      titleText = coverage;
      subtitle1Text = 'Min Spend ₱${minimumOrderAmount.toStringAsFixed(2)}';
      subtitle2Text = 'Code: ${voucher['code'] ?? ''}';
    } else if (discountType == 'percentage') {
      titleText = '${discountValue.toStringAsFixed(0)}% OFF';
      subtitle1Text = maximumSpend != null ? 'Max ₱${maximumSpend.toStringAsFixed(2)} OFF' : '';
      subtitle2Text = 'Min Spend ₱${minimumOrderAmount.toStringAsFixed(2)}';
    } else {
      titleText = '₱${discountValue.toStringAsFixed(2)} OFF';
      subtitle1Text = 'Min Spend ₱${minimumOrderAmount.toStringAsFixed(2)}';
      subtitle2Text = null;
    }

    return Opacity(
      opacity: isDisabled ? 0.4 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          onTap: isDisabled
              ? null
              : () {
                  setState(() {
                    if (isSelected) {
                      _tempSelected = null;
                    } else {
                      _tempSelected = voucher;
                    }
                  });
                },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(
                color: isSelected ? AppColors.warning : AppColors.grey300,
                width: isSelected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(12),
              color: AppColors.surface,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titleText,
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontFamily: 'Roboto',
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                      ),
                      if (subtitle1Text.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle1Text,
                          style: AppTextStyles.bodySmall.copyWith(
                            fontFamily: 'Roboto',
                            color: AppColors.onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                      if (subtitle2Text != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle2Text,
                          style: AppTextStyles.bodySmall.copyWith(
                            fontFamily: 'Roboto',
                            color: AppColors.onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected && !isDisabled ? AppColors.warning : AppColors.grey400,
                      width: 2,
                    ),
                  ),
                  child: isSelected && !isDisabled
                      ? const Icon(
                          Icons.check,
                          size: 14,
                          color: AppColors.warning,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _shippingCoverageLabel(dynamic shippingOption) {
    final modes = parseShippingCoverage(shippingOption);
    if (modes.contains('standard') && modes.contains('express')) {
      return 'Free Shipping (Standard or Express)';
    }
    if (modes.contains('express')) {
      return 'Free Express Shipping';
    }
    return 'Free Standard Shipping';
  }
}

/// Parse a voucher's `shippingOption` field into the set of covered modes.
///
/// Treats null/missing/empty as `{'standard'}` (legacy fallback). The literal
/// string `'both'` expands to `{'standard', 'express'}`.
Set<String> parseShippingCoverage(dynamic shippingOption) {
  if (shippingOption == null) return {'standard'};
  if (shippingOption is! List || shippingOption.isEmpty) return {'standard'};
  final set = <String>{};
  for (final raw in shippingOption) {
    final value = raw is String ? raw.toLowerCase().trim() : '';
    if (value == 'both') {
      set.add('standard');
      set.add('express');
    } else if (value == 'standard' || value == 'express') {
      set.add(value);
    }
  }
  if (set.isEmpty) return {'standard'};
  return set;
}
