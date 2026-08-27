import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dentpal/utils/app_logger.dart';
import 'package:dentpal/utils/currency_formatter.dart';
import '../checkout_routes.dart';
import '../models/cart_model.dart';
import '../models/order_model.dart';
import '../models/paymongo_model.dart';
import '../services/checkout_service.dart';
import '../services/cart_service.dart';
import '../widgets/address_selection_widget.dart';
import '../widgets/voucher_picker_sheet.dart';
import 'paymongo_webview_page.dart';
import 'payment_success_page.dart';
import 'payment_failed_page.dart';
import '../../profile/models/shipping_address.dart';
import '../../profile/services/platform_policies_service.dart';
import '../../core/app_theme/app_text_styles.dart';
import '../../core/app_theme/ink_palette.dart';
import '../../core/app_theme/theme_utils.dart';
import '../../core/widgets/app_network_image.dart';
import '../../core/widgets/app_page_header.dart';
import '../widgets/loading_skeletons.dart';

typedef VouchersChangedCallback = void Function(
  Map<String, Map<String, dynamic>?> discountVouchers,
  Map<String, Map<String, dynamic>?> shippingVouchers,
);

class CheckoutPage extends StatefulWidget {
  final List<CartItem> cartItems;
  final CartSummary cartSummary;
  final Map<String, Map<String, dynamic>?> selectedDiscountVouchers;
  final Map<String, Map<String, dynamic>?> selectedShippingVouchers;
  final VouchersChangedCallback? onVouchersChanged;
  final VoidCallback? onOrderComplete;

  const CheckoutPage({
    super.key,
    required this.cartItems,
    required this.cartSummary,
    this.selectedDiscountVouchers = const {},
    this.selectedShippingVouchers = const {},
    this.onVouchersChanged,
    this.onOrderComplete,
  });

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final CheckoutService _checkoutService = CheckoutService();

  ShippingAddress? _selectedAddress;
  PaymentMethod? _selectedPaymentMethod;
  String? _orderNotes;
  bool _isProcessing = false;

  // Local mutable copies of the voucher maps (so checkout-side edits flow back via callback).
  late Map<String, Map<String, dynamic>?> _discountVouchers;
  late Map<String, Map<String, dynamic>?> _shippingVouchers;

  // Per-seller shipping mode: true = express, false = standard.
  // Replaces the old global `_isExpressShipping` so vouchers can lock one seller
  // independently of the others.
  final Map<String, bool> _sellerExpressShipping = {};

  // Per-seller pickup mode: when true the buyer picks up in store (no shipping cost).
  final Map<String, bool> _sellerPickupSelected = {};

  // Per-seller: whether the buyer has explicitly chosen a delivery method. There
  // is deliberately NO default — a seller stays unchosen (no radio selected, no
  // shipping cost added, Place Order blocked) until the buyer picks a mode, so
  // they can't accidentally place an order with no delivery method selected.
  final Map<String, bool> _sellerDeliveryModeChosen = {};

  // Per-seller Same Day Delivery (Lalamove) mode. When true, the buyer pays the
  // full Lalamove quote and no vouchers apply. Only available within Metro Manila.
  final Map<String, bool> _sellerSameDaySelected = {};
  // Per-seller Lalamove quote total (buyer-paid). Presence => same-day is offered.
  final Map<String, double> _sameDaySellerCosts = {};
  // Per-seller Lalamove quotationId (informational; the backend re-quotes at booking).
  final Map<String, String> _sameDayQuotationIds = {};
  bool _isCalculatingSameDay = false;

  // Per-seller shipping costs (active = chosen mode per seller)
  final Map<String, double> _sellerShippingCosts = {}; // sellerId -> active buyer's portion
  final Map<String, double> _sellerTotalShippingCosts = {}; // sellerId -> active total cost
  bool _isCalculatingShipping = false;
  // Sellers whose JRS (standard + express) rate failed after backend retries.
  // Tracked per-seller so a JRS outage only blocks sellers without a non-JRS
  // option (Pickup / Same Day) — others stay checkout-able.
  final Set<String> _jrsFailedSellers = {};
  int _shippingCalcGeneration = 0;

  final Map<String, double> _expressSellerShippingCosts = {};
  final Map<String, double> _expressSellerTotalShippingCosts = {};
  final Map<String, double> _standardSellerShippingCosts = {};
  final Map<String, double> _standardSellerTotalShippingCosts = {};

  // Per-seller insurance & evaluation costs (from JRS response)
  final Map<String, double> _sellerInsuranceCosts = {};
  final Map<String, double> _sellerEvaluationCosts = {};
  final Map<String, double> _expressSellerInsuranceCosts = {};
  final Map<String, double> _expressSellerEvaluationCosts = {};
  final Map<String, double> _standardSellerInsuranceCosts = {};
  final Map<String, double> _standardSellerEvaluationCosts = {};

  // Per-seller packaging size (locally-resolved productName from JRS calculator)
  final Map<String, String> _sellerPackagingSizes = {};
  final Map<String, String> _expressSellerPackagingSizes = {};
  final Map<String, String> _standardSellerPackagingSizes = {};

  final TextEditingController _notesController = TextEditingController();

  // Per-seller voucher discounts
  final Map<String, double> _sellerDiscountAmounts = {};

  @override
  void initState() {
    super.initState();
    _discountVouchers = Map.of(widget.selectedDiscountVouchers);
    _shippingVouchers = Map.of(widget.selectedShippingVouchers);
    _initializeSellerShippingModes();
    _computeVoucherDiscounts();
    // No payment method is pre-selected on purpose — the buyer must choose one,
    // so they can't accidentally place an order with no payment method set.
  }

  /// Set each seller's initial mode based on its (optional) shipping voucher
  /// and its checkoutOptions (delivery modes). Pickup is initialized to false;
  /// delivery mode defaults to standard when allowed, else express.
  void _initializeSellerShippingModes() {
    final sellerIds = widget.cartItems
        .map((item) => item.sellerId ?? 'unknown')
        .toSet();
    for (final sellerId in sellerIds) {
      _sellerPickupSelected[sellerId] = false;
      _sellerSameDaySelected[sellerId] = false;

      final voucherModes = _coveredModes(_shippingVouchers[sellerId]);
      if (voucherModes.length == 1 && voucherModes.contains('express')) {
        _sellerExpressShipping[sellerId] = true;
      } else if (voucherModes.length == 1 && voucherModes.contains('standard')) {
        _sellerExpressShipping[sellerId] = false;
      } else {
        // Baseline for cost math only (not a visible selection): standard if
        // allowed, otherwise express. The buyer must still pick a mode.
        final allowsStd = _sellerAllowsDelivery(sellerId, 'standard');
        _sellerExpressShipping[sellerId] = !allowsStd;
      }
      // No delivery mode is pre-selected. Exception: an express-only shipping
      // voucher locks the seller to express (nothing left to choose), so treat
      // that as already chosen.
      _sellerDeliveryModeChosen[sellerId] =
          voucherModes.length == 1 && voucherModes.contains('express');
    }
  }

  // ── Checkout-options helpers ────────────────────────────────────────────────

  /// Returns the first cart item's checkoutOptions for the given seller.
  Map<String, dynamic>? _getSellerCheckoutOptions(String sellerId) {
    try {
      return widget.cartItems
          .firstWhere((it) => (it.sellerId ?? 'unknown') == sellerId)
          .checkoutOptions;
    } catch (_) {
      return null;
    }
  }

  /// Whether this seller allows [mode] ('standard', 'express', 'pickup').
  /// Returns true when checkoutOptions is absent (backwards compat).
  bool _sellerAllowsDelivery(String sellerId, String mode) {
    final opts = _getSellerCheckoutOptions(sellerId);
    if (opts == null) return true;
    final delivery = opts['delivery'] as Map?;
    if (delivery == null) return true;
    return delivery[mode] == true;
  }

  /// Whether [method] is in the intersection of all sellers' allowed payment
  /// methods.  Methods with no checkoutOptions key (billEase) are never offered.
  bool _isPaymentMethodAllowed(PaymentMethod method) {
    final key = _paymentMethodKey(method);
    if (key == null) return false; // billEase — not configurable, excluded
    return _allowedPaymentKeys.contains(key);
  }

  /// Firestore `checkoutOptions.payment` key for [method]. These match PayMongo's
  /// own `payment_method_types` strings so the seller config, the checkout-session
  /// payload and the webhook's stored paymentMethod all share one vocabulary.
  static String? _paymentMethodKey(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.cashOnDelivery: return 'cod';
      case PaymentMethod.gcash:          return 'gcash';
      case PaymentMethod.card:           return 'card';
      case PaymentMethod.grabpay:        return 'grab_pay';
      case PaymentMethod.paymaya:        return 'paymaya';
      case PaymentMethod.shopeePay:      return 'shopee_pay';
      case PaymentMethod.billEase:       return null;
    }
  }

  /// Payment method keys that are enabled by ALL sellers in the cart.
  /// When a seller has no checkoutOptions, it imposes no restriction.
  Set<String> get _allowedPaymentKeys {
    final sellerIds = widget.cartItems
        .map((it) => it.sellerId ?? 'unknown')
        .toSet();
    Set<String>? intersection;
    for (final sellerId in sellerIds) {
      final opts = _getSellerCheckoutOptions(sellerId);
      final paymentRaw = opts?['payment'];
      if (paymentRaw is! Map) continue; // no restriction from this seller
      final allowed = paymentRaw.entries
          .where((e) => e.value == true)
          .map((e) => e.key.toString())
          .toSet();
      intersection = intersection == null
          ? allowed
          : intersection.intersection(allowed);
    }
    // Fallback: allow all known keys when no seller has restrictions.
    return intersection ?? {'cod', 'gcash', 'card'};
  }

  bool _isPickupSelectedFor(String sellerId) =>
      _sellerPickupSelected[sellerId] ?? false;

  bool _isSameDaySelectedFor(String sellerId) =>
      _sellerSameDaySelected[sellerId] ?? false;

  /// True when any seller in the cart currently has Same Day Delivery selected.
  /// Same Day (Lalamove) is online-payment only, so COD is disabled whenever
  /// this is true.
  bool _anySameDaySelected() =>
      _sellerSameDaySelected.values.any((selected) => selected);

  /// First allowed online payment method (card / e-wallet), or null if the
  /// sellers only allow COD. Mirrors the exclusions applied in the payment
  /// selector.
  PaymentMethod? _firstOnlinePaymentMethod() {
    for (final m in PaymentMethod.values) {
      if (m == PaymentMethod.cashOnDelivery || m == PaymentMethod.billEase) {
        continue;
      }
      if (_isPaymentMethodAllowed(m)) return m;
    }
    return null;
  }

  /// Whether an online payment method is available for the cart. Same Day
  /// Delivery is only offered when this is true (COD-only carts can't use it).
  bool get _hasOnlinePaymentAvailable => _firstOnlinePaymentMethod() != null;

  /// All distinct seller ids represented in the cart.
  Set<String> _cartSellerIds() => widget.cartItems
      .map((item) => item.sellerId ?? 'unknown')
      .toSet();

  /// Whether this seller currently has no usable shipping option, so the order
  /// can't proceed for it. A JRS failure only blocks a seller while it has no
  /// chosen non-JRS alternative (Pickup / a live Same-Day quote). Returns false
  /// while rates are still loading so we don't flash an error mid-calc.
  bool _sellerShippingBlocked(String sellerId) {
    if (_isCalculatingShipping || _isCalculatingSameDay) return false;
    if (_isPickupSelectedFor(sellerId)) return false;
    if (_isSameDaySelectedFor(sellerId) && _isSameDayAvailableFor(sellerId)) {
      return false;
    }
    // Still on a JRS mode (standard/express): blocked iff JRS failed for it.
    return _jrsFailedSellers.contains(sellerId);
  }

  /// True when at least one cart seller has no usable shipping option.
  bool get _anyShippingBlocked => _cartSellerIds().any(_sellerShippingBlocked);

  /// Whether a seller presents at least one selectable delivery option (mirrors
  /// what the shipping-method UI actually renders). Used to require an explicit
  /// delivery pick before checkout can proceed.
  bool _sellerHasShippingChoice(String sellerId) {
    final hasStandard = _sellerAllowsDelivery(sellerId, 'standard') &&
        _standardSellerTotalShippingCosts.containsKey(sellerId);
    final hasExpress = _sellerAllowsDelivery(sellerId, 'express') &&
        _expressSellerTotalShippingCosts.containsKey(sellerId);
    final hasPickup = _sellerAllowsDelivery(sellerId, 'pickup');
    final hasSameDay = _sellerAllowsDelivery(sellerId, 'sameDay') &&
        _hasOnlinePaymentAvailable &&
        _isSameDayAvailableFor(sellerId);
    return hasStandard || hasExpress || hasPickup || hasSameDay;
  }

  /// True while any seller that has delivery options still has no mode picked.
  bool get _anyShippingModeUnchosen => _cartSellerIds().any((sellerId) =>
      _sellerHasShippingChoice(sellerId) &&
      !(_sellerDeliveryModeChosen[sellerId] ?? false));

  /// Same-day is offered only when the seller enabled it, a live Lalamove quote
  /// succeeded (which also enforces Metro Manila coverage on the backend), AND
  /// the current time is within the seller's Same Day ordering window.
  bool _isSameDayAvailableFor(String sellerId) =>
      _sellerAllowsDelivery(sellerId, 'sameDay') &&
      _sameDaySellerCosts.containsKey(sellerId) &&
      _isSameDayWithinWindow(sellerId);

  /// The seller's Same Day ordering schedule from checkoutOptions, with defaults
  /// (Mon–Fri, 10:00 AM–3:00 PM) applied for any missing pieces.
  Map<String, dynamic> _sellerSameDaySchedule(String sellerId) {
    const defaultDays = {
      'mon': true, 'tue': true, 'wed': true, 'thu': true, 'fri': true,
      'sat': false, 'sun': false,
    };
    final raw = _getSellerCheckoutOptions(sellerId)?['sameDaySchedule'];
    if (raw is! Map) {
      return {
        'days': Map<String, dynamic>.from(defaultDays),
        'startTime': '10:00',
        'endTime': '15:00',
      };
    }
    final rawDays = raw['days'] is Map ? Map<String, dynamic>.from(raw['days'] as Map) : const {};
    final days = <String, dynamic>{};
    defaultDays.forEach((k, v) {
      days[k] = rawDays.containsKey(k) ? rawDays[k] == true : v;
    });
    final start = (raw['startTime'] is String && (raw['startTime'] as String).isNotEmpty)
        ? raw['startTime'] as String
        : '10:00';
    final end = (raw['endTime'] is String && (raw['endTime'] as String).isNotEmpty)
        ? raw['endTime'] as String
        : '15:00';
    return {'days': days, 'startTime': start, 'endTime': end};
  }

  int _hmToMinutes(String hm) {
    final parts = hm.split(':');
    if (parts.length != 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  /// Whether Same Day ordering is currently open for [sellerId], evaluated in
  /// Philippine time (UTC+8) so it's independent of the device timezone.
  bool _isSameDayWithinWindow(String sellerId) {
    final schedule = _sellerSameDaySchedule(sellerId);
    final phNow = DateTime.now().toUtc().add(const Duration(hours: 8));
    const keys = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
    final todayKey = keys[phNow.weekday - 1]; // DateTime.weekday: Mon=1..Sun=7
    if ((schedule['days'] as Map)[todayKey] != true) return false;
    final nowMin = phNow.hour * 60 + phNow.minute;
    return nowMin >= _hmToMinutes(schedule['startTime'] as String) &&
        nowMin <= _hmToMinutes(schedule['endTime'] as String);
  }

  String _formatTime12h(String hm) {
    final parts = hm.split(':');
    if (parts.length != 2) return hm;
    var h = int.tryParse(parts[0]) ?? 0;
    final period = h >= 12 ? 'PM' : 'AM';
    h = h % 12;
    if (h == 0) h = 12;
    return '$h:${parts[1]} $period';
  }

  /// Ordering-window message shown in the disabled Same Day row's info tooltip.
  String _sameDayWindowLabel(String sellerId) {
    final schedule = _sellerSameDaySchedule(sellerId);
    final days = schedule['days'] as Map;
    const order = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
    const labels = {
      'mon': 'Mon', 'tue': 'Tue', 'wed': 'Wed', 'thu': 'Thu', 'fri': 'Fri',
      'sat': 'Sat', 'sun': 'Sun',
    };
    final active = order.where((k) => days[k] == true).map((k) => labels[k]).toList();
    final daysLabel = active.isEmpty
        ? 'Unavailable'
        : active.length == 7
            ? 'Daily'
            : active.join(', ');
    return 'Same Day ordering hours\n$daysLabel · '
        '${_formatTime12h(schedule['startTime'] as String)}–${_formatTime12h(schedule['endTime'] as String)}';
  }

  void _onSellerPickupToggled(String sellerId, bool pickupSelected) {
    setState(() {
      _sellerPickupSelected[sellerId] = pickupSelected;
      if (pickupSelected) {
        _sellerSameDaySelected[sellerId] = false;
        _sellerDeliveryModeChosen[sellerId] = true; // explicit buyer choice
      }
      // Reset express/standard map when switching to/from pickup so costs
      // are correctly reflected in the summary.
      _refreshActiveMapsForSeller(sellerId);
    });
  }

  /// Toggle Same Day Delivery for a seller. Turning it on clears pickup; turning
  /// it off falls back to the seller's standard/express selection.
  void _onSellerSameDayToggled(String sellerId, bool sameDay) {
    setState(() {
      _sellerSameDaySelected[sellerId] = sameDay;
      if (sameDay) {
        _sellerPickupSelected[sellerId] = false;
        _sellerDeliveryModeChosen[sellerId] = true; // explicit buyer choice
        // Same Day Delivery requires online payment — COD isn't supported. If
        // COD was selected, clear the payment selection so the buyer must
        // consciously pick an online method (no silent default).
        if (_selectedPaymentMethod == PaymentMethod.cashOnDelivery) {
          _selectedPaymentMethod = null;
        }
      }
      _refreshActiveMapsForSeller(sellerId);
    });
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  /// Compute per-seller discount amounts from selected vouchers (for display).
  void _computeVoucherDiscounts() {
    _sellerDiscountAmounts.clear();

    final Map<String, List<CartItem>> sellerGroups = {};
    for (final item in widget.cartItems) {
      final sellerId = item.sellerId ?? 'unknown';
      sellerGroups.putIfAbsent(sellerId, () => []).add(item);
    }

    for (final entry in sellerGroups.entries) {
      final sellerId = entry.key;
      final items = entry.value;
      final sellerSubtotal = items.fold<double>(
        0.0, (sum, item) => sum + ((item.productPrice ?? 0) * item.quantity));

      final voucher = _discountVouchers[sellerId];
      if (voucher == null) {
        _sellerDiscountAmounts[sellerId] = 0.0;
        continue;
      }

      final discountType = voucher['discountType'] as String? ?? '';
      final discountValue = (voucher['discountValue'] as num? ?? 0).toDouble();
      final minimumOrderAmount = (voucher['minimumOrderAmount'] as num? ?? 0).toDouble();
      final maximumSpend = (voucher['maximumSpend'] as num?)?.toDouble();

      if (sellerSubtotal < minimumOrderAmount) {
        _sellerDiscountAmounts[sellerId] = 0.0;
        continue;
      }

      if (discountType == 'percentage') {
        double discount = sellerSubtotal * (discountValue / 100.0);
        if (maximumSpend != null && discount > maximumSpend) {
          discount = maximumSpend;
        }
        _sellerDiscountAmounts[sellerId] = discount.clamp(0.0, sellerSubtotal);
      } else if (discountType == 'fixed') {
        _sellerDiscountAmounts[sellerId] = discountValue.clamp(0.0, sellerSubtotal);
      } else {
        // free_delivery or unknown — no monetary discount
        _sellerDiscountAmounts[sellerId] = 0.0;
      }
    }
  }

  /// Modes covered by a seller's currently-selected shipping voucher.
  /// Defaults to `{'standard'}` for legacy/missing vouchers.
  Set<String> _coveredModes(Map<String, dynamic>? voucher) {
    if (voucher == null) return const {};
    return parseShippingCoverage(voucher['shippingOption']);
  }

  bool _hasShippingVoucher(String sellerId) => _shippingVouchers[sellerId] != null;

  bool _isLockedToExpress(String sellerId) {
    final modes = _coveredModes(_shippingVouchers[sellerId]);
    return modes.length == 1 && modes.contains('express');
  }

  bool _isExpressFor(String sellerId) => _sellerExpressShipping[sellerId] ?? false;

  /// Buyer's portion of shipping for a seller, after applying any shipping voucher rules.
  ///
  /// Rules:
  /// - Pickup selected → 0 (buyer picks up in store).
  /// - No shipping voucher → buyer pays whatever the chosen-mode buyer-portion is.
  /// - Voucher covers chosen mode → buyer pays 0 (seller absorbs full cost).
  /// - Chosen express, voucher covers standard only → buyer pays (expressTotal - standardTotal).
  /// - Otherwise → buyer pays the chosen-mode buyer portion.
  double _buyerShippingForSeller(String sellerId) {
    // No mode chosen yet → no shipping fee shown (Place Order is blocked too).
    if (!(_sellerDeliveryModeChosen[sellerId] ?? false)) return 0.0;
    if (_isPickupSelectedFor(sellerId)) return 0.0;
    // Same Day Delivery: buyer always pays the full Lalamove quote. No vouchers.
    if (_isSameDaySelectedFor(sellerId)) {
      return _sameDaySellerCosts[sellerId] ?? 0.0;
    }
    final express = _isExpressFor(sellerId);
    final expCost = _expressSellerTotalShippingCosts[sellerId] ?? 0.0;
    final stdCost = _standardSellerTotalShippingCosts[sellerId] ?? 0.0;
    final buyerNoVoucher = (express
            ? _expressSellerShippingCosts[sellerId]
            : _standardSellerShippingCosts[sellerId]) ??
        0.0;

    if (!_hasShippingVoucher(sellerId)) return buyerNoVoucher;

    final modes = _coveredModes(_shippingVouchers[sellerId]);
    final coversStandard = modes.contains('standard');
    final coversExpress = modes.contains('express');

    if (express) {
      if (coversExpress) return 0.0;
      if (coversStandard) {
        final diff = expCost - stdCost;
        return diff > 0 ? double.parse(diff.toStringAsFixed(2)) : 0.0;
      }
      return buyerNoVoucher;
    }
    if (coversStandard) return 0.0;
    return buyerNoVoucher;
  }

  /// Total cost for a seller in the chosen shipping mode (display, before voucher split).
  double _totalShippingForSeller(String sellerId) {
    // No mode chosen yet → no shipping fee shown (Place Order is blocked too).
    if (!(_sellerDeliveryModeChosen[sellerId] ?? false)) return 0.0;
    if (_isPickupSelectedFor(sellerId)) return 0.0;
    if (_isSameDaySelectedFor(sellerId)) {
      return _sameDaySellerCosts[sellerId] ?? 0.0;
    }
    final express = _isExpressFor(sellerId);
    return (express
            ? _expressSellerTotalShippingCosts[sellerId]
            : _standardSellerTotalShippingCosts[sellerId]) ??
        0.0;
  }

  /// Total discount across all sellers.
  double _calculateTotalDiscount() {
    return _sellerDiscountAmounts.values.fold(0.0, (sum, d) => sum + d);
  }

  Future<void> _processCheckout() async {
    if (!_validateCheckout()) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      // First, validate that all cart items still exist in the database
      AppLogger.d('Validating cart items before checkout...');
      await _validateCartItemsExist();

      // Validate checkout data
      await _checkoutService.validateCheckoutData(
        cartItems: widget.cartItems,
        address: _selectedAddress!,
      );

      // Extract cart item IDs
      final cartItemIds = widget.cartItems.map((item) => item.cartItemId).toList();
      AppLogger.d('Proceeding with cart items: $cartItemIds');

      // Build per-seller buyer-shipping costs after voucher coverage is applied,
      // so the backend cross-checks with the same numbers the buyer saw.
      final adjustedSellerShippingCosts = <String, double>{};
      // Include every seller (same-day-only sellers may not be in
      // _sellerShippingCosts, which is JRS-derived).
      final allSellerIds = <String>{
        ..._sellerShippingCosts.keys,
        ..._sellerExpressShipping.keys,
        ..._sameDaySellerCosts.keys,
      };
      for (final sellerId in allSellerIds) {
        adjustedSellerShippingCosts[sellerId] = _buyerShippingForSeller(sellerId);
      }

      // Check if Cash on Delivery is selected
      if (_selectedPaymentMethod == PaymentMethod.cashOnDelivery) {
        // Create COD order directly (no PayMongo integration needed)
        final orderResponse = await _checkoutService.createCashOnDeliveryOrder(
          cartItemIds: cartItemIds,
          addressId: _selectedAddress!.id,
          notes: _orderNotes,
          sellerShippingCosts: adjustedSellerShippingCosts,
          sellerInsuranceCosts: _sellerInsuranceCosts,
          sellerEvaluationCosts: _sellerEvaluationCosts,
          sellerPackagingSizes: _sellerPackagingSizes,
          sellerExpressShipping: Map.of(_sellerExpressShipping),
          sellerPickupSelected: Map.of(_sellerPickupSelected),
          sellerSameDaySelected: Map.of(_sellerSameDaySelected),
          expressSellerShippingCosts: Map.of(_expressSellerShippingCosts),
          standardSellerShippingCosts: Map.of(_standardSellerShippingCosts),
          expressSellerTotalShippingCosts: Map.of(_expressSellerTotalShippingCosts),
          standardSellerTotalShippingCosts: Map.of(_standardSellerTotalShippingCosts),
          selectedDiscountVouchers: _discountVouchers,
          selectedShippingVouchers: _shippingVouchers,
        );

        AppLogger.d('COD order created successfully');

        // Navigate to success page directly
        if (mounted) {
          await _navigateToCodOrderSuccess(orderResponse);
        }
      } else {
        // Create order with PayMongo checkout session
        final orderResponse = await _checkoutService.createOrderWithCheckoutSession(
          cartItemIds: cartItemIds,
          addressId: _selectedAddress!.id,
          notes: _orderNotes,
          paymentMethodTypes: [_selectedPaymentMethod!.paymongoType],
          successUrl: 'https://dentpal-store.web.app/payment-success',
          cancelUrl: 'https://dentpal-store.web.app/payment-failed',
          sellerShippingCosts: adjustedSellerShippingCosts,
          sellerInsuranceCosts: _sellerInsuranceCosts,
          sellerEvaluationCosts: _sellerEvaluationCosts,
          sellerPackagingSizes: _sellerPackagingSizes,
          sellerExpressShipping: Map.of(_sellerExpressShipping),
          sellerPickupSelected: Map.of(_sellerPickupSelected),
          sellerSameDaySelected: Map.of(_sellerSameDaySelected),
          expressSellerShippingCosts: Map.of(_expressSellerShippingCosts),
          standardSellerShippingCosts: Map.of(_standardSellerShippingCosts),
          expressSellerTotalShippingCosts: Map.of(_expressSellerTotalShippingCosts),
          standardSellerTotalShippingCosts: Map.of(_standardSellerTotalShippingCosts),
          selectedDiscountVouchers: _discountVouchers,
          selectedShippingVouchers: _shippingVouchers,
        );

        AppLogger.d('Order created successfully');

        // Navigate to Paymongo checkout
        if (mounted) {
          await _navigateToPaymongoCheckout(orderResponse);
        }
      }

    } catch (e) {
      AppLogger.d('Checkout failed: $e');
      if (mounted) {
        _showErrorDialog(e.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  bool _validateCheckout() {
    if (_selectedAddress == null) {
      _showErrorDialog('Please select a shipping address');
      return false;
    }

    if (_selectedPaymentMethod == null) {
      _showErrorDialog('Please select a payment method');
      return false;
    }

    // Same Day Delivery (Lalamove) is online-payment only.
    if (_anySameDaySelected() &&
        _selectedPaymentMethod == PaymentMethod.cashOnDelivery) {
      _showErrorDialog(
        'Cash on Delivery isn\'t available for Same Day Delivery. Please choose '
        'an online payment method (card or e-wallet).',
      );
      return false;
    }

    if (_isCalculatingShipping) {
      _showErrorDialog('Please wait for the shipping cost to finish calculating.');
      return false;
    }

    if (_isCalculatingSameDay) {
      _showErrorDialog('Please wait for delivery options to finish loading.');
      return false;
    }

    if (_anyShippingModeUnchosen) {
      _showErrorDialog(
        'Please select a delivery method for every item before placing your order.',
      );
      return false;
    }

    // A Same Day selection must still be inside the seller's ordering window
    // (e.g. the window may have closed while the buyer was on this page).
    for (final sellerId in _cartSellerIds()) {
      if (_isSameDaySelectedFor(sellerId) && !_isSameDayWithinWindow(sellerId)) {
        _showErrorDialog(
          'Same Day Delivery is outside its ordering hours for one of your sellers. '
          'Please choose another delivery option.',
        );
        return false;
      }
    }

    if (_anyShippingBlocked) {
      _showErrorDialog(
        'Some sellers\' delivery rate is unavailable. Please choose another delivery '
        'option (or tap "Retry") for the highlighted sellers before placing your order.',
      );
      return false;
    }

    return true;
  }

  Future<void> _validateCartItemsExist() async {
    AppLogger.d('Validating ${widget.cartItems.length} cart items exist in database...');

    final cartService = CartService();
    final missingItems = <String>[];

    for (final cartItem in widget.cartItems) {
      try {
        final existingItem = await cartService.getCartItem(cartItem.cartItemId);
        if (existingItem == null) {
          missingItems.add(cartItem.cartItemId);
          AppLogger.d('Cart item ${cartItem.cartItemId} not found in database');
        } else {
          AppLogger.d('Cart item ${cartItem.cartItemId} exists in database');
        }
      } catch (e) {
        AppLogger.d('Error checking cart item ${cartItem.cartItemId}: $e');
        missingItems.add(cartItem.cartItemId);
      }
    }

    if (missingItems.isNotEmpty) {
      throw Exception(
        'Some cart items are no longer available: ${missingItems.join(', ')}. '
        'Please refresh your cart and try again.'
      );
    }

    AppLogger.d('All cart items validated successfully');
  }

  /// Calculate shipping cost when address is selected - per seller
  Future<void> _calculateShippingCost() async {
    if (_selectedAddress == null) return;
    if (!mounted) return;

    // Generation token: if this function is called again while a prior call is
    // still in-flight, the prior call detects the mismatch and discards its
    // stale result instead of clearing the spinner for the new call.
    final myGeneration = ++_shippingCalcGeneration;

    setState(() {
      _isCalculatingShipping = true;
      _jrsFailedSellers.clear();
      _expressSellerShippingCosts.clear();
      _expressSellerTotalShippingCosts.clear();
      _standardSellerShippingCosts.clear();
      _standardSellerTotalShippingCosts.clear();
      _sellerShippingCosts.clear();
      _sellerTotalShippingCosts.clear();
      _expressSellerInsuranceCosts.clear();
      _expressSellerEvaluationCosts.clear();
      _standardSellerInsuranceCosts.clear();
      _standardSellerEvaluationCosts.clear();
      _sellerInsuranceCosts.clear();
      _sellerEvaluationCosts.clear();
      _expressSellerPackagingSizes.clear();
      _standardSellerPackagingSizes.clear();
      _sellerPackagingSizes.clear();
    });

    // Kick off the Same Day (Lalamove) quotes now so they load concurrently with
    // the JRS rates instead of only after JRS finishes. Independent of JRS and
    // honors the same generation token, so a superseded call discards its result.
    _fetchSameDayQuotes(myGeneration);

    try {
      AppLogger.d('Calculating per-seller shipping costs (express + standard) for checkout');

      // Group cart items by seller
      final Map<String, List<CartItem>> sellerGroups = {};
      for (final item in widget.cartItems) {
        final sellerId = item.sellerId ?? 'unknown';
        sellerGroups.putIfAbsent(sellerId, () => []).add(item);
      }

      // For each seller, fetch express and standard rates in parallel
      for (final entry in sellerGroups.entries) {
        final sellerId = entry.key;
        final sellerItems = entry.value;

        try {
          final results = await Future.wait([
            _checkoutService.calculateShippingCostDetailed(
              items: sellerItems,
              address: _selectedAddress!,
              express: true,
            ),
            _checkoutService.calculateShippingCostDetailed(
              items: sellerItems,
              address: _selectedAddress!,
              express: false,
            ),
          ]);

          // Discard results from a superseded calculation.
          if (!mounted || _shippingCalcGeneration != myGeneration) return;

          final expressDetails = results[0];
          final standardDetails = results[1];

          _expressSellerShippingCosts[sellerId] = (expressDetails['buyerCost'] as double?) ?? 0.0;
          _expressSellerTotalShippingCosts[sellerId] = (expressDetails['totalCost'] as double?) ?? 0.0;
          _expressSellerInsuranceCosts[sellerId] = (expressDetails['insuranceCost'] as double?) ?? 0.0;
          _expressSellerEvaluationCosts[sellerId] = (expressDetails['evaluationCost'] as double?) ?? 0.0;
          final expressPackaging = expressDetails['packagingName'] as String?;
          if (expressPackaging != null && expressPackaging.isNotEmpty) {
            _expressSellerPackagingSizes[sellerId] = expressPackaging;
          }
          _standardSellerShippingCosts[sellerId] = (standardDetails['buyerCost'] as double?) ?? 0.0;
          _standardSellerTotalShippingCosts[sellerId] = (standardDetails['totalCost'] as double?) ?? 0.0;
          _standardSellerInsuranceCosts[sellerId] = (standardDetails['insuranceCost'] as double?) ?? 0.0;
          _standardSellerEvaluationCosts[sellerId] = (standardDetails['evaluationCost'] as double?) ?? 0.0;
          final standardPackaging = standardDetails['packagingName'] as String?;
          if (standardPackaging != null && standardPackaging.isNotEmpty) {
            _standardSellerPackagingSizes[sellerId] = standardPackaging;
          }

          AppLogger.d('Seller $sellerId - Express: ₱${expressDetails['totalCost']}, Standard: ₱${standardDetails['totalCost']}');
        } catch (e) {
          // JRS could not return a rate for this seller (even after the backend
          // retried). Record it per-seller and keep going — other sellers, and
          // this seller's non-JRS options (Pickup / Same Day), stay available.
          // Its standard/express maps were cleared above and never populated, so
          // those rows simply won't render. No placeholder rate is charged.
          AppLogger.d('Error calculating shipping for seller $sellerId: $e');
          if (!mounted || _shippingCalcGeneration != myGeneration) return;
          _jrsFailedSellers.add(sellerId);
          continue;
        }
      }

      if (!mounted || _shippingCalcGeneration != myGeneration) return;

      // Set active maps per-seller based on each seller's shipping mode.
      _refreshAllActiveMaps();

      setState(() {
        _isCalculatingShipping = false;
      });

      // Same Day (Lalamove) quotes were already kicked off above, concurrently.

      AppLogger.d('Express total: ₱${_expressSellerShippingCosts.values.fold(0.0, (s, c) => s + c)}, '
          'Standard total: ₱${_standardSellerShippingCosts.values.fold(0.0, (s, c) => s + c)}');
    } catch (e) {
      AppLogger.d('Error calculating shipping costs: $e');
      if (!mounted || _shippingCalcGeneration != myGeneration) return;
      setState(() {
        _isCalculatingShipping = false;
        // Unexpected/global failure — mark every seller so the buyer can still
        // fall back to any non-JRS option or retry.
        _jrsFailedSellers.addAll(_cartSellerIds());
        _expressSellerShippingCosts.clear();
        _expressSellerTotalShippingCosts.clear();
        _standardSellerShippingCosts.clear();
        _standardSellerTotalShippingCosts.clear();
        _sellerShippingCosts.clear();
        _sellerTotalShippingCosts.clear();
      });
    }
  }

  /// Fetch Lalamove same-day quotes for sellers that enabled Same Day Delivery.
  /// Quotes that fail (out of Metro Manila coverage / not serviceable) simply
  /// leave the seller without a same-day option. Honors the calc generation so
  /// stale results from a previous address are discarded.
  Future<void> _fetchSameDayQuotes(int generation) async {
    if (_selectedAddress == null) return;
    final addressId = _selectedAddress!.id;

    final sellerIds = widget.cartItems
        .map((item) => item.sellerId ?? 'unknown')
        .toSet()
        // Only quote sellers that enabled Same Day AND are within their ordering
        // window right now — no point quoting when it can't be ordered.
        .where((sellerId) =>
            _sellerAllowsDelivery(sellerId, 'sameDay') && _isSameDayWithinWindow(sellerId))
        .toList();
    if (sellerIds.isEmpty) return;

    if (!mounted || _shippingCalcGeneration != generation) return;
    setState(() {
      _isCalculatingSameDay = true;
      _sameDaySellerCosts.clear();
      _sameDayQuotationIds.clear();
    });

    for (final sellerId in sellerIds) {
      try {
        final quote = await _checkoutService.getLalamoveQuote(
          sellerId: sellerId,
          addressId: addressId,
        );
        if (!mounted || _shippingCalcGeneration != generation) return;
        if (quote['success'] == true && quote['total'] != null) {
          _sameDaySellerCosts[sellerId] = (quote['total'] as num).toDouble();
          if (quote['quotationId'] != null) {
            _sameDayQuotationIds[sellerId] = quote['quotationId'].toString();
          }
        } else {
          // Not serviceable / out of coverage — ensure same-day isn't selected.
          _sellerSameDaySelected[sellerId] = false;
        }
      } catch (e) {
        AppLogger.d('Same-day quote error for seller $sellerId: $e');
        if (!mounted || _shippingCalcGeneration != generation) return;
        _sellerSameDaySelected[sellerId] = false;
      }
    }

    if (!mounted || _shippingCalcGeneration != generation) return;
    setState(() {
      _isCalculatingSameDay = false;
    });
  }

  /// Repopulate all active per-seller cost maps from the express/standard caches
  /// based on each seller's mode. Called after an address calc completes or the
  /// per-seller toggle flips.
  void _refreshAllActiveMaps() {
    _sellerShippingCosts.clear();
    _sellerTotalShippingCosts.clear();
    _sellerInsuranceCosts.clear();
    _sellerEvaluationCosts.clear();
    _sellerPackagingSizes.clear();
    final allSellers = <String>{
      ..._expressSellerShippingCosts.keys,
      ..._standardSellerShippingCosts.keys,
    };
    for (final sellerId in allSellers) {
      _refreshActiveMapsForSeller(sellerId);
    }
  }

  void _refreshActiveMapsForSeller(String sellerId) {
    final express = _isExpressFor(sellerId);
    final shipping = express
        ? _expressSellerShippingCosts[sellerId]
        : _standardSellerShippingCosts[sellerId];
    final total = express
        ? _expressSellerTotalShippingCosts[sellerId]
        : _standardSellerTotalShippingCosts[sellerId];
    final insurance = express
        ? _expressSellerInsuranceCosts[sellerId]
        : _standardSellerInsuranceCosts[sellerId];
    final evaluation = express
        ? _expressSellerEvaluationCosts[sellerId]
        : _standardSellerEvaluationCosts[sellerId];
    final packaging = express
        ? _expressSellerPackagingSizes[sellerId]
        : _standardSellerPackagingSizes[sellerId];
    if (shipping != null) _sellerShippingCosts[sellerId] = shipping;
    if (total != null) _sellerTotalShippingCosts[sellerId] = total;
    if (insurance != null) _sellerInsuranceCosts[sellerId] = insurance;
    if (evaluation != null) _sellerEvaluationCosts[sellerId] = evaluation;
    if (packaging != null && packaging.isNotEmpty) {
      _sellerPackagingSizes[sellerId] = packaging;
    }
  }

  /// Toggle a single seller's shipping mode. No-op if the seller's voucher
  /// locks the mode (express-only).
  void _onSellerShippingModeToggled(String sellerId, bool isExpress) {
    if (_isLockedToExpress(sellerId) && !isExpress) return;
    setState(() {
      _sellerExpressShipping[sellerId] = isExpress;
      _sellerDeliveryModeChosen[sellerId] = true; // explicit Standard/Express pick
      _refreshActiveMapsForSeller(sellerId);
    });
  }

  /// Get total buyer's portion of shipping cost across all sellers, applying
  /// per-seller shipping voucher coverage rules.
  double _calculateBuyerShippingPortion() {
    if (_sellerShippingCosts.isEmpty && _sellerExpressShipping.isEmpty) return 0.0;
    final sellerIds = <String>{
      ..._sellerShippingCosts.keys,
      ..._sellerExpressShipping.keys,
    };
    double total = 0.0;
    for (final sellerId in sellerIds) {
      total += _buyerShippingForSeller(sellerId);
    }
    return double.parse(total.toStringAsFixed(2));
  }

  /// Get total shipping cost (including seller's portion) across all sellers
  double _calculateTotalShippingCost() {
    if (_sellerTotalShippingCosts.isEmpty) return 0.0;
    return _sellerTotalShippingCosts.values.fold(0.0, (sum, cost) => sum + cost);
  }

  /// Calculate total including only buyer's shipping portion, minus voucher discounts
  double _calculateTotalWithShipping() {
    final subtotal = widget.cartSummary.selectedItemsTotal;
    final totalDiscount = _calculateTotalDiscount();
    final buyerShippingPortion = _calculateBuyerShippingPortion();
    return subtotal - totalDiscount + buyerShippingPortion;
  }

  // ── Palette ──────────────────────────────────────────────────────────────

  InkPalette get ink => InkPalette.of(context);

  /// Destructive red. [InkPalette] reserves amber for urgency, so danger needs
  /// its own tone that still reads in both themes. Same value the cart uses, so
  /// an error looks identical on both sides of "Proceed to checkout".
  Color get _danger =>
      ink.isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);

  /// Every message this page raises, in one shape — matching the cart's, so the
  /// two screens of a single purchase don't speak in two voices.
  void _showSnack(String message, {Color? tone, int seconds = 3}) {
    final background = tone ?? ink.emerald;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: background == ink.amber ? ink.onAmber : Colors.white,
          ),
        ),
        backgroundColor: background,
        duration: Duration(seconds: seconds),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ── Dialogs ──────────────────────────────────────────────────────────────

  /// One shape for every dialog this page raises.
  ///
  /// There were seven, in four different styles — some with a tinted icon tile,
  /// some without, three different corner radii — and all of them hardcoded
  /// light, so in dark mode a checkout error arrived as a white slab. One
  /// builder now.
  Widget _dialog({
    required IconData icon,
    required Color tone,
    required String title,
    required Widget content,
    required List<Widget> actions,
  }) {
    return AlertDialog(
      backgroundColor: ink.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: tone, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: AppTextStyles.titleMedium.copyWith(
                color: ink.text,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      content: content,
      actions: actions,
    );
  }

  Widget _dialogBody(String text) => Text(
    text,
    style: AppTextStyles.bodyMedium.copyWith(
      color: ink.text.withValues(alpha: 0.75),
      height: 1.45,
    ),
  );

  /// Labelled facts inside a dialog — an order id, an amount — on one tile.
  /// The last flag emphasises a row as money rather than a reference.
  Widget _dialogFacts(List<(String, String, bool)> rows) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ink.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ink.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            Text(
              rows[i].$1,
              style: AppTextStyles.bodySmall.copyWith(
                color: ink.text.withValues(alpha: 0.55),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              rows[i].$2,
              style: rows[i].$3
                  ? AppTextStyles.titleMedium.copyWith(
                      color: ink.emerald,
                      fontWeight: FontWeight.w800,
                    )
                  : AppTextStyles.bodySmall.copyWith(
                      color: ink.text,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
            ),
          ],
        ],
      ),
    );
  }

  TextButton _dialogTextAction(String label, VoidCallback onPressed) =>
      TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: ink.text.withValues(alpha: 0.7),
        ),
        child: Text(label, style: AppTextStyles.buttonMedium),
      );

  ElevatedButton _dialogPrimaryAction(String label, VoidCallback onPressed) =>
      ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: ink.emerald,
          foregroundColor: ink.onEmerald,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(label, style: AppTextStyles.buttonMedium),
      );

  Future<void> _navigateToPaymongoCheckout(CreateOrderResponse orderResponse) async {
    if (orderResponse.checkoutSession != null) {
      final session = orderResponse.checkoutSession!;
      final checkoutUrl = session.attributes.checkoutUrl;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _dialog(
          icon: Icons.lock_outline,
          tone: ink.emerald,
          title: 'Ready to pay',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _dialogBody(
                'Your order is reserved. The next step opens PayMongo\'s secure '
                'payment page to complete it.',
              ),
              const SizedBox(height: 16),
              _dialogFacts([
                ('Order ID', orderResponse.orderId, false),
                (
                  'Total amount',
                  CurrencyFormatter.formatWithPeso(orderResponse.totalAmount),
                  true,
                ),
              ]),
            ],
          ),
          actions: [
            _dialogTextAction('Not now', () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(); // Go back to cart/previous page
              widget.onOrderComplete?.call();
            }),
            _dialogPrimaryAction('Continue to payment', () async {
              AppLogger.d('Opening Paymongo checkout URL: $checkoutUrl');

              // Close the dialog first
              Navigator.of(context).pop();

              try {
                await _openCheckoutUrl(checkoutUrl, sessionId: session.id);
              } catch (e) {
                AppLogger.d('Error opening checkout URL: $e');
                if (mounted) {
                  _showErrorDialog('Failed to open payment page. Please try again.');
                }
              }
            }),
          ],
        ),
      );
    } else {
      // Fallback to the old payment intent flow
      await _navigateToPaymentIntent(orderResponse);
    }
  }

  Future<void> _navigateToPaymentIntent(CreateOrderResponse orderResponse) async {
    // Legacy payment intent flow (kept for backward compatibility)
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _dialog(
        icon: Icons.check_circle_outline,
        tone: ink.emerald,
        title: 'Order created',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _dialogBody('Your order has been created successfully.'),
            const SizedBox(height: 16),
            _dialogFacts([
              ('Payment Intent ID', orderResponse.paymentIntent?.id ?? 'N/A', false),
            ]),
          ],
        ),
        actions: [
          _dialogPrimaryAction('Continue', () {
            Navigator.of(context).pop(); // Close dialog
            Navigator.of(context).pop(); // Go back to cart/previous page
            widget.onOrderComplete?.call();
          }),
        ],
      ),
    );
  }

  /// A Cash on Delivery order is placed the moment it is created — there is no
  /// payment page to visit — so it lands on the same receipt screen an online
  /// payment does, rather than on a dialog of its own. One ending for the flow,
  /// one URL for it.
  Future<void> _navigateToCodOrderSuccess(CreateOrderResponse orderResponse) async {
    widget.onOrderComplete?.call();
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        settings: const RouteSettings(name: kCheckoutSuccessPath),
        builder: (context) => PaymentSuccessPage(
          orderId: orderResponse.orderId,
          totalAmount: orderResponse.totalAmount,
          isCashOnDelivery: true,
        ),
      ),
    );
  }

  void _showTermsAndConditions(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) => _PolicyDialog(
        title: 'Terms and Conditions',
        icon: Icons.description_outlined,
        fetchContent: () => PlatformPoliciesService.getTermsAndConditions(),
      ),
    );
  }

  void _showPrivacyPolicy(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) => _PolicyDialog(
        title: 'Privacy Policy',
        icon: Icons.shield_outlined,
        fetchContent: () => PlatformPoliciesService.getPrivacyPolicy(),
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => _dialog(
        icon: Icons.error_outline,
        tone: _danger,
        title: 'Checkout error',
        content: _dialogBody(message),
        actions: [
          _dialogTextAction('OK', () => Navigator.pop(context)),
        ],
      ),
    );
  }

  // ── Layout ───────────────────────────────────────────────────────────────

  /// The money column, matching the cart's so the two screens of one purchase
  /// share a spine: the same content width, the same gutter, the same summary
  /// column on the right.
  static const double _kSummaryWidth = 360;

  @override
  Widget build(BuildContext context) {
    final isWide = context.isWideLayout;

    return Scaffold(
      backgroundColor: ink.bg,
      body: SafeArea(
        bottom: false,
        // Header inside the centred column, not above it — otherwise on a wide
        // window the title hugs the window edge while the cards start an inch
        // further in. Same frame the cart uses.
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppLayout.maxContentWidth,
            ),
            child: Column(
              children: [
                _buildHeader(),
                Expanded(child: _buildBody(isWide)),
              ],
            ),
          ),
        ),
      ),
      // On a phone the total and the action that commits to it ride at the
      // bottom edge. On desktop they live inside the summary column instead, so
      // the number and the button never separate.
      bottomNavigationBar: isWide ? null : _buildMobileCheckoutBar(),
    );
  }

  Widget _buildHeader() {
    final itemCount = widget.cartItems.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );
    final sellerCount = _cartSellerIds().length;

    return AppPageHeader(
      title: 'Checkout',
      subtitle: '$itemCount item${itemCount == 1 ? '' : 's'} · '
          '$sellerCount seller${sellerCount == 1 ? '' : 's'}',
    );
  }

  /// Two columns on desktop — what you are agreeing to on the left, what it
  /// costs on the right, so the running total stays put while the form scrolls.
  /// One column on a phone, with the summary at the end of it.
  Widget _buildBody(bool isWide) {
    final form = ListView(
      padding: EdgeInsets.fromLTRB(
        AppLayout.gutter,
        14,
        isWide ? 8 : AppLayout.gutter,
        24,
      ),
      children: [
        _buildAddressSection(),
        const SizedBox(height: 14),
        ..._buildGroupedSellerItems(),
        _buildPaymentSection(),
        const SizedBox(height: 14),
        _buildOrderNotesSection(),
        const SizedBox(height: 14),
        _buildTermsSection(),
        if (!isWide) ...[
          const SizedBox(height: 14),
          _buildSummaryCard(includeButton: false),
        ],
      ],
    );

    if (!isWide) return form;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: form),
        SizedBox(
          width: _kSummaryWidth,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(8, 14, AppLayout.gutter, 24),
            child: _buildSummaryCard(includeButton: true),
          ),
        ),
      ],
    );
  }

  // ── Card primitives ──────────────────────────────────────────────────────

  /// The one card shape on this page.
  ///
  /// Every section used to carry a tinted header band in brand green, which on
  /// a five-section page meant five green bars competing with the one control
  /// that matters — the Place Order button. A heading is now just a heading.
  Widget _card({
    required IconData icon,
    required String title,
    String? trailingNote,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: ink.emerald),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.titleMedium.copyWith(
                    color: ink.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              if (trailingNote != null)
                Text(
                  trailingNote,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: ink.text.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  /// A tinted strip carrying one sentence — an error, a caution, a note.
  Widget _notice({
    required IconData icon,
    required Color tone,
    required String text,
    Widget? action,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: ink.isDark ? 0.14 : 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: tone),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodySmall.copyWith(
                color: tone,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
          if (action != null) ...[const SizedBox(width: 6), action],
        ],
      ),
    );
  }

  Widget _retryButton(Color tone) {
    return TextButton.icon(
      onPressed: _isCalculatingShipping ? null : _calculateShippingCost,
      icon: const Icon(Icons.refresh, size: 15),
      label: Text(
        'Retry',
        style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w700),
      ),
      style: TextButton.styleFrom(
        foregroundColor: tone,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  /// Label on the left, value on the right, sitting on a shared baseline.
  Widget _moneyRow(
    String label,
    String value, {
    bool good = false,
    bool muted = false,
    Widget? valueWidget,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          label,
          style: AppTextStyles.bodyMedium.copyWith(
            color: ink.text.withValues(alpha: 0.65),
            fontSize: 13.5,
          ),
        ),
        const Spacer(),
        valueWidget ??
            Text(
              value,
              style: AppTextStyles.bodyMedium.copyWith(
                color: good
                    ? ink.emerald
                    : ink.text.withValues(alpha: muted ? 0.55 : 1),
                fontWeight: muted ? FontWeight.w500 : FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
      ],
    );
  }

  // ── Address ──────────────────────────────────────────────────────────────

  Widget _buildAddressSection() {
    return AddressSelectionWidget(
      selectedAddress: _selectedAddress,
      onAddressSelected: (address) {
        setState(() {
          _selectedAddress = address;
        });
        // Calculate shipping cost when address is selected
        _calculateShippingCost();
      },
      title: 'Shipping address',
    );
  }

  // ── Order (grouped by seller) ────────────────────────────────────────────

  /// Group cart items by seller and build a card per seller.
  List<Widget> _buildGroupedSellerItems() {
    final Map<String, List<CartItem>> sellerGroups = {};

    for (final item in widget.cartItems) {
      final sellerId = item.sellerId ?? 'unknown';
      sellerGroups.putIfAbsent(sellerId, () => []).add(item);
    }

    final List<Widget> widgets = [];
    sellerGroups.forEach((sellerId, items) {
      final sellerName = items.first.sellerName ?? 'Unknown Seller';
      widgets.add(_buildSellerGroup(sellerId, sellerName, items));
      widgets.add(const SizedBox(height: 14));
    });

    return widgets;
  }

  /// One seller's slice of the order: what they are shipping, how, and for how
  /// much. Each seller is its own consignment with its own rate and its own
  /// vouchers, so each gets a card rather than a row in a shared list.
  Widget _buildSellerGroup(String sellerId, String sellerName, List<CartItem> items) {
    // Calculate seller's subtotal
    final sellerSubtotal = items.fold<double>(
      0.0,
      (sum, item) => sum + ((item.productPrice ?? 0) * item.quantity),
    );

    // Per-seller voucher discount
    final sellerDiscount = _sellerDiscountAmounts[sellerId] ?? 0.0;

    // Buyer's portion after shipping voucher coverage rules
    final buyerShippingCost = _buyerShippingForSeller(sellerId);

    // Total cost in the chosen shipping mode
    final totalShippingCost = _totalShippingForSeller(sellerId);

    // Whether the buyer pays anything for shipping
    final buyerPaysShipping = buyerShippingCost > 0.0;
    final shippingDiscounted =
        totalShippingCost > 0.0 && buyerShippingCost < totalShippingCost;

    AppLogger.d('Seller: $sellerName, Subtotal: $sellerSubtotal, Discount: $sellerDiscount, Total Shipping: $totalShippingCost, Buyer Pays: $buyerShippingCost');

    return Container(
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          // A seller with no usable delivery option is the reason the order
          // can't proceed, so its card is what carries the alarm.
          color: _sellerShippingBlocked(sellerId)
              ? _danger.withValues(alpha: 0.5)
              : ink.border,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Seller header
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: ink.emerald.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(Icons.storefront_outlined, size: 16, color: ink.emerald),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sellerName,
                      style: AppTextStyles.titleMedium.copyWith(
                        color: ink.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${items.length} item${items.length != 1 ? 's' : ''}',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: ink.text.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
          Divider(height: 1, thickness: 1, color: ink.border),
          const SizedBox(height: 14),

          // Products for this seller
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _buildOrderItem(items[i]),
          ],

          const SizedBox(height: 14),
          _buildSellerShippingModeToggle(sellerId),
          const SizedBox(height: 10),
          _buildSellerVoucherChips(sellerId),

          const SizedBox(height: 14),
          Divider(height: 1, thickness: 1, color: ink.border),
          const SizedBox(height: 12),

          // Seller subtotal and shipping
          _moneyRow('Subtotal', CurrencyFormatter.formatWithPeso(sellerSubtotal)),
          if (sellerDiscount > 0) ...[
            const SizedBox(height: 8),
            _moneyRow(
              'Voucher discount',
              '-${CurrencyFormatter.formatWithPeso(sellerDiscount)}',
              good: true,
            ),
          ],
          const SizedBox(height: 8),
          _moneyRow(
            'Shipping',
            '',
            valueWidget: _isCalculatingShipping
                ? const AmountSkeleton(width: 64, height: 13)
                : _sellerShippingBlocked(sellerId)
                    ? Text(
                        'Unavailable',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: _danger,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          if (shippingDiscounted) ...[
                            Text(
                              CurrencyFormatter.formatWithPeso(totalShippingCost),
                              style: AppTextStyles.bodySmall.copyWith(
                                decoration: TextDecoration.lineThrough,
                                decorationColor: ink.text.withValues(alpha: 0.45),
                                color: ink.text.withValues(alpha: 0.45),
                                fontSize: 12.5,
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            buyerPaysShipping
                                ? CurrencyFormatter.formatWithPeso(buyerShippingCost)
                                : 'FREE',
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              color: buyerPaysShipping ? ink.text : ink.emerald,
                            ),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItem(CartItem item) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Product image
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(gradient: ink.productBackdrop),
            child: AppNetworkImage(
              url: item.productImage,
              width: 52,
              height: 52,
              fit: BoxFit.cover,
              maxDecodeDimension: 140,
              backgroundColor: Colors.transparent,
              errorWidget: (context) => Icon(
                Icons.image_outlined,
                color: ink.text.withValues(alpha: 0.3),
                size: 20,
              ),
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
                item.productName ?? 'Unknown Product',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: ink.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (item.variationName != null && item.variationName!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  item.variationName!,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: ink.text.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 3),
              Text(
                'Qty ${item.quantity}',
                style: AppTextStyles.bodySmall.copyWith(
                  color: ink.text.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),

        // Price
        Text(
          CurrencyFormatter.formatWithPeso(
            (item.productPrice ?? 0) * item.quantity,
          ),
          style: AppTextStyles.bodyMedium.copyWith(
            color: ink.text,
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
          ),
        ),
      ],
    );
  }

  // ── Delivery method ──────────────────────────────────────────────────────

  /// Per-seller delivery mode picker. Shows only the modes the seller allows
  /// (standard, express, same day, pickup). Locks to express when the seller's
  /// shipping voucher only covers express.
  Widget _buildSellerShippingModeToggle(String sellerId) {
    final allowsStandard = _sellerAllowsDelivery(sellerId, 'standard');
    final allowsExpress  = _sellerAllowsDelivery(sellerId, 'express');
    final allowsPickup   = _sellerAllowsDelivery(sellerId, 'pickup');
    final allowsSameDay  = _sellerAllowsDelivery(sellerId, 'sameDay');
    final sameDayAvailable = _isSameDayAvailableFor(sellerId);
    final sameDayWithinWindow = _isSameDayWithinWindow(sellerId);

    final hasExpressCost  = _expressSellerTotalShippingCosts.containsKey(sellerId);
    final hasStandardCost = _standardSellerTotalShippingCosts.containsKey(sellerId);
    final hasAnyCost = hasExpressCost || hasStandardCost;
    final jrsFailed = _jrsFailedSellers.contains(sellerId);

    // Nothing to show when no delivery options exist.
    if (!allowsStandard && !allowsExpress && !allowsPickup && !allowsSameDay) {
      return const SizedBox.shrink();
    }
    // Bail only when there's genuinely nothing to render: no JRS cost, no
    // pickup/same-day, and JRS didn't fail (a failure still needs its notice).
    if (!hasAnyCost && !allowsPickup && !allowsSameDay && !jrsFailed) {
      return const SizedBox.shrink();
    }

    // No default: nothing is selected until the buyer explicitly picks a mode.
    final chosen = _sellerDeliveryModeChosen[sellerId] ?? false;
    final isSameDay = chosen && _isSameDaySelectedFor(sellerId);
    final isPickup  = chosen && !isSameDay && _isPickupSelectedFor(sellerId);
    final isExpress = chosen && !isSameDay && !isPickup && _isExpressFor(sellerId);
    final isStandard = chosen && !isSameDay && !isPickup && !isExpress;
    final lockedExpress = _isLockedToExpress(sellerId);
    final sameDayCost = _sameDaySellerCosts[sellerId] ?? 0.0;

    final expressTotal  = _expressSellerTotalShippingCosts[sellerId] ?? 0.0;
    final standardTotal = _standardSellerTotalShippingCosts[sellerId] ?? 0.0;

    final rows = <Widget>[];

    if (allowsStandard && hasStandardCost) {
      rows.add(_deliveryOption(
        selected: isStandard,
        disabled: _isCalculatingShipping || lockedExpress,
        onTap: () {
          _onSellerSameDayToggled(sellerId, false);
          _onSellerPickupToggled(sellerId, false);
          _onSellerShippingModeToggled(sellerId, false);
        },
        icon: Icons.local_shipping_outlined,
        label: 'Standard',
        sublabel: lockedExpress ? 'Locked by voucher' : null,
        trailing: _costLabel(standardTotal, isStandard),
      ));
    }
    if (allowsExpress && hasExpressCost) {
      rows.add(_deliveryOption(
        selected: isExpress,
        disabled: _isCalculatingShipping,
        onTap: () {
          _onSellerSameDayToggled(sellerId, false);
          _onSellerPickupToggled(sellerId, false);
          _onSellerShippingModeToggled(sellerId, true);
        },
        icon: Icons.bolt_outlined,
        label: 'Express',
        trailing: _costLabel(expressTotal, isExpress),
      ));
    }
    // Same Day Delivery (Lalamove) — shown when the seller enabled it and an
    // online payment method is available (COD isn't supported for Same Day).
    // Outside the seller's ordering window it renders disabled with the hours;
    // otherwise it needs a live quote (Metro Manila only) and the buyer pays
    // the full fee.
    if (allowsSameDay && _hasOnlinePaymentAvailable &&
        (sameDayAvailable || _isCalculatingSameDay || !sameDayWithinWindow)) {
      rows.add(_deliveryOption(
        selected: isSameDay && sameDayWithinWindow,
        disabled: _isCalculatingShipping || _isCalculatingSameDay ||
            !sameDayAvailable || !sameDayWithinWindow,
        onTap: () => _onSellerSameDayToggled(sellerId, true),
        icon: Icons.motorcycle_outlined,
        label: 'Same Day',
        sublabel: sameDayWithinWindow && _isCalculatingSameDay && !sameDayAvailable
            ? 'Checking availability…'
            : null,
        // Off-hours: hide the long day/time list behind an info tooltip.
        tooltip: !sameDayWithinWindow ? _sameDayWindowLabel(sellerId) : null,
        trailing: !sameDayWithinWindow
            ? Text(
                'Closed',
                style: AppTextStyles.bodySmall.copyWith(
                  color: ink.text.withValues(alpha: 0.45),
                  fontWeight: FontWeight.w600,
                ),
              )
            : (_isCalculatingSameDay && !sameDayAvailable
                ? const AmountSkeleton(width: 64, height: 14)
                : _costLabel(sameDayCost, isSameDay)),
      ));
    }
    if (allowsPickup) {
      rows.add(_deliveryOption(
        selected: isPickup,
        disabled: false,
        onTap: () {
          _onSellerSameDayToggled(sellerId, false);
          _onSellerPickupToggled(sellerId, true);
        },
        icon: Icons.store_outlined,
        label: 'Pickup',
        sublabel: 'Collect from the seller',
        trailing: Text(
          'FREE',
          style: AppTextStyles.bodyMedium.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
            color: isPickup ? ink.emerald : ink.text.withValues(alpha: 0.5),
          ),
        ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Delivery method',
              style: AppTextStyles.titleSmall.copyWith(
                color: ink.text.withValues(alpha: 0.7),
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(width: 6),
            // The buyer must pick one — say so, rather than letting them meet a
            // disabled Place Order button with no explanation.
            if (!chosen && rows.isNotEmpty)
              Text(
                'Required',
                style: AppTextStyles.bodySmall.copyWith(
                  color: ink.amber,
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        // JRS rate unavailable for this seller — explain and offer a retry.
        // Pickup / Same Day rows below (if the seller enabled them) remain
        // selectable so the order can still proceed.
        if (jrsFailed) ...[
          _notice(
            icon: Icons.error_outline,
            tone: _danger,
            text: (allowsPickup || sameDayAvailable)
                ? 'Standard and Express are unavailable right now. Choose another option below, or retry.'
                : 'Standard and Express are unavailable right now. Please retry.',
            action: _retryButton(_danger),
          ),
          if (rows.isNotEmpty) const SizedBox(height: 8),
        ],
        for (int i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          rows[i],
        ],
      ],
    );
  }

  /// One selectable delivery option.
  ///
  /// Selection is carried by the whole tile — border, tint and a filled check —
  /// rather than by a Material radio dot alone, which at this size was the only
  /// thing distinguishing a chosen delivery method from an unchosen one.
  Widget _deliveryOption({
    required bool selected,
    required bool disabled,
    required VoidCallback onTap,
    required IconData icon,
    required String label,
    String? sublabel,
    String? tooltip,
    required Widget trailing,
  }) {
    return Opacity(
      opacity: disabled && !selected ? 0.5 : 1,
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? ink.emerald.withValues(alpha: ink.isDark ? 0.14 : 0.08)
                : ink.surfaceHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? ink.emerald : ink.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              // The selection mark: a filled tick when chosen, an empty ring
              // when not.
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? ink.emerald : Colors.transparent,
                  border: Border.all(
                    color: selected
                        ? ink.emerald
                        : ink.text.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: selected
                    ? Icon(Icons.check, size: 12, color: ink.onEmerald)
                    : null,
              ),
              const SizedBox(width: 10),
              Icon(
                icon,
                size: 17,
                color: selected ? ink.emerald : ink.text.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 8),
              Expanded(
                // Label on top with the (optional) sublabel wrapping beneath, so
                // long sublabels never overflow the row horizontally. A tooltip
                // (tap the ⓘ) carries longer details like the Same Day hours.
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            label,
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              color: selected
                                  ? ink.emerald
                                  : ink.text.withValues(alpha: 0.85),
                            ),
                          ),
                        ),
                        if (tooltip != null) ...[
                          const SizedBox(width: 5),
                          Tooltip(
                            message: tooltip,
                            triggerMode: TooltipTriggerMode.tap,
                            child: Icon(
                              Icons.info_outline,
                              size: 14,
                              color: ink.text.withValues(alpha: 0.45),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (sublabel != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          sublabel,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: ink.text.withValues(alpha: 0.5),
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing,
            ],
          ),
        ),
      ),
    );
  }

  Widget _costLabel(double cost, bool selected) => Text(
    cost > 0 ? CurrencyFormatter.formatWithPeso(cost) : 'FREE',
    style: AppTextStyles.bodyMedium.copyWith(
      fontWeight: FontWeight.w700,
      fontSize: 13.5,
      color: selected
          ? (cost > 0 ? ink.text : ink.emerald)
          : ink.text.withValues(alpha: 0.55),
    ),
  );

  // ── Vouchers ─────────────────────────────────────────────────────────────

  /// Two voucher chips per seller — discount and shipping. Each is editable.
  Widget _buildSellerVoucherChips(String sellerId) {
    final sellerName = widget.cartItems
        .firstWhere((it) => it.sellerId == sellerId, orElse: () => widget.cartItems.first)
        .sellerName ??
        'Seller';
    final sellerSubtotal = widget.cartItems
        .where((it) => it.sellerId == sellerId)
        .fold<double>(0.0, (sum, item) => sum + ((item.productPrice ?? 0) * item.quantity));
    return Column(
      children: [
        _buildVoucherChip(
          icon: Icons.local_offer_outlined,
          label: 'Discount voucher',
          mode: VoucherPickerMode.discount,
          sellerId: sellerId,
          sellerName: sellerName,
          sellerSubtotal: sellerSubtotal,
          voucher: _discountVouchers[sellerId],
        ),
        const SizedBox(height: 6),
        _buildVoucherChip(
          icon: Icons.local_shipping_outlined,
          label: 'Shipping voucher',
          mode: VoucherPickerMode.shipping,
          sellerId: sellerId,
          sellerName: sellerName,
          sellerSubtotal: sellerSubtotal,
          voucher: _shippingVouchers[sellerId],
        ),
      ],
    );
  }

  Widget _buildVoucherChip({
    required IconData icon,
    required String label,
    required VoucherPickerMode mode,
    required String sellerId,
    required String sellerName,
    required double sellerSubtotal,
    required Map<String, dynamic>? voucher,
  }) {
    String trailingLabel;
    if (voucher == null) {
      trailingLabel = 'Add';
    } else if (mode == VoucherPickerMode.shipping) {
      final modes = parseShippingCoverage(voucher['shippingOption']);
      if (modes.contains('standard') && modes.contains('express')) {
        trailingLabel = 'Free Shipping';
      } else if (modes.contains('express')) {
        trailingLabel = 'Free Express';
      } else {
        trailingLabel = 'Free Standard';
      }
    } else {
      final type = voucher['discountType'] as String? ?? '';
      final value = voucher['discountValue'] as num? ?? 0;
      trailingLabel = type == 'percentage'
          ? '-${value.toStringAsFixed(0)}%'
          : '-${CurrencyFormatter.formatWithPeso(value.toDouble())}';
    }

    final applied = voucher != null;

    return InkWell(
      onTap: () => _openCheckoutVoucherPicker(
        mode: mode,
        sellerId: sellerId,
        sellerName: sellerName,
        sellerSubtotal: sellerSubtotal,
      ),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: applied
              ? ink.emerald.withValues(alpha: ink.isDark ? 0.12 : 0.07)
              : ink.surfaceHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: applied ? ink.emerald.withValues(alpha: 0.45) : ink.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: applied ? ink.emerald : ink.text.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 9),
            Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: ink.text.withValues(alpha: 0.8),
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
            const Spacer(),
            Text(
              trailingLabel,
              style: AppTextStyles.bodySmall.copyWith(
                color: applied ? ink.emerald : ink.text.withValues(alpha: 0.55),
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 16,
              color: ink.text.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCheckoutVoucherPicker({
    required VoucherPickerMode mode,
    required String sellerId,
    required String sellerName,
    required double sellerSubtotal,
  }) async {
    final cartBrands = <String>{};
    for (final item in widget.cartItems) {
      if (item.sellerId != sellerId) continue;
      final b = item.brand?.trim().toLowerCase();
      if (b != null && b.isNotEmpty) cartBrands.add(b);
    }
    await VoucherPickerSheet.show(
      context: context,
      mode: mode,
      sellerId: sellerId,
      sellerName: sellerName,
      selectedItemsTotal: sellerSubtotal,
      cartBrands: cartBrands,
      currentSelectedVoucher: mode == VoucherPickerMode.shipping
          ? _shippingVouchers[sellerId]
          : _discountVouchers[sellerId],
      onVoucherSelected: (voucher) {
        setState(() {
          if (mode == VoucherPickerMode.shipping) {
            _shippingVouchers[sellerId] = voucher;
            // Re-evaluate the seller's mode lock when its shipping voucher changes.
            final modes = _coveredModes(voucher);
            if (modes.length == 1 && modes.contains('express')) {
              _sellerExpressShipping[sellerId] = true;
              // Express-only voucher locks the mode — nothing left to choose.
              _sellerDeliveryModeChosen[sellerId] = true;
            } else if (modes.length == 1 && modes.contains('standard')) {
              _sellerExpressShipping[sellerId] = false;
            }
            _refreshActiveMapsForSeller(sellerId);
          } else {
            _discountVouchers[sellerId] = voucher;
            _computeVoucherDiscounts();
          }
          widget.onVouchersChanged?.call(_discountVouchers, _shippingVouchers);
        });
      },
    );
  }

  // ── Payment ──────────────────────────────────────────────────────────────

  Widget _buildPaymentSection() {
    final methods = PaymentMethod.values
        .where((method) =>
            method != PaymentMethod.billEase &&
            _isPaymentMethodAllowed(method) &&
            // Same Day Delivery (Lalamove) is online-payment only —
            // hide Cash on Delivery while any seller uses Same Day.
            !(method == PaymentMethod.cashOnDelivery && _anySameDaySelected()))
        .toList();

    return _card(
      icon: Icons.credit_card_outlined,
      title: 'Payment method',
      trailingNote: _selectedPaymentMethod == null ? 'Required' : null,
      child: Column(
        children: [
          if (methods.isEmpty)
            _notice(
              icon: Icons.info_outline,
              tone: ink.amber,
              text: 'No payment method is available for this combination of '
                  'sellers and delivery options.',
            ),
          for (int i = 0; i < methods.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _buildPaymentOption(methods[i]),
          ],
          // Same Day removed COD from the list — say why, rather than leaving
          // the buyer to notice an option they had a moment ago is now gone.
          if (_anySameDaySelected() && _allowedPaymentKeys.contains('cod')) ...[
            const SizedBox(height: 10),
            _notice(
              icon: Icons.info_outline,
              tone: ink.text.withValues(alpha: 0.6),
              text: 'Cash on Delivery isn\'t available with Same Day Delivery.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPaymentOption(PaymentMethod method) {
    final isSelected = _selectedPaymentMethod == method;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedPaymentMethod = method;
        });
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: isSelected
              ? ink.emerald.withValues(alpha: ink.isDark ? 0.14 : 0.08)
              : ink.surfaceHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? ink.emerald : ink.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isSelected
                    ? ink.emerald.withValues(alpha: 0.16)
                    : ink.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: ink.border),
              ),
              child: Icon(
                _getPaymentMethodIcon(method),
                color: isSelected ? ink.emerald : ink.text.withValues(alpha: 0.55),
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                method.displayName,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  color: isSelected ? ink.emerald : ink.text,
                ),
              ),
            ),
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? ink.emerald : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? ink.emerald
                      : ink.text.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: isSelected
                  ? Icon(Icons.check, size: 12, color: ink.onEmerald)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  IconData _getPaymentMethodIcon(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.card:
        return Icons.credit_card;
      case PaymentMethod.gcash:
        return Icons.account_balance_wallet;
      case PaymentMethod.grabpay:
        return Icons.local_taxi;
      case PaymentMethod.paymaya:
        return Icons.account_balance_wallet_outlined;
      case PaymentMethod.shopeePay:
        return Icons.shopping_bag_outlined;
      case PaymentMethod.billEase:
        return Icons.account_balance;
      case PaymentMethod.cashOnDelivery:
        return Icons.payments_outlined;
    }
  }

  // ── Notes & terms ────────────────────────────────────────────────────────

  Widget _buildOrderNotesSection() {
    return _card(
      icon: Icons.sticky_note_2_outlined,
      title: 'Order notes',
      trailingNote: 'Optional',
      child: TextField(
        controller: _notesController,
        onChanged: (value) {
          setState(() {
            _orderNotes = value.isEmpty ? null : value;
          });
        },
        maxLines: 3,
        style: AppTextStyles.bodyMedium.copyWith(
          color: ink.text,
          fontSize: 13.5,
        ),
        cursorColor: ink.emerald,
        decoration: InputDecoration(
          hintText: 'Any special instructions for your order…',
          hintStyle: AppTextStyles.bodyMedium.copyWith(
            color: ink.text.withValues(alpha: 0.4),
            fontSize: 13.5,
          ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: ink.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: ink.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: ink.emerald, width: 1.5),
          ),
          filled: true,
          fillColor: ink.surfaceHigh,
        ),
      ),
    );
  }

  Widget _buildTermsSection() {
    final bodyStyle = AppTextStyles.bodySmall.copyWith(
      color: ink.text.withValues(alpha: 0.65),
      fontSize: 12.5,
      height: 1.5,
    );
    final linkStyle = AppTextStyles.bodySmall.copyWith(
      color: ink.emerald,
      fontSize: 12.5,
      height: 1.5,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      decorationColor: ink.emerald.withValues(alpha: 0.5),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: ink.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ink.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.gavel_outlined,
            size: 16,
            color: ink.text.withValues(alpha: 0.45),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: 'By placing this order you agree to the ',
                style: bodyStyle,
                children: [
                  TextSpan(
                    text: 'Terms and Conditions',
                    style: linkStyle,
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => _showTermsAndConditions(context),
                  ),
                  TextSpan(text: ' and ', style: bodyStyle),
                  TextSpan(
                    text: 'Privacy Policy',
                    style: linkStyle,
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => _showPrivacyPolicy(context),
                  ),
                  TextSpan(text: '.', style: bodyStyle),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Summary & commit ─────────────────────────────────────────────────────

  /// Everything the buyer is about to be charged, in one card.
  ///
  /// On desktop it carries the Place Order button; on a phone the button rides
  /// in the bottom bar instead, so the total and the commitment stay together
  /// in both layouts.
  Widget _buildSummaryCard({required bool includeButton}) {
    final totalDiscount = _calculateTotalDiscount();
    final totalShipping = _calculateTotalShippingCost();
    final buyerShipping = _calculateBuyerShippingPortion();
    final shippingDiscounted = !_anyShippingModeUnchosen &&
        totalShipping > 0 &&
        buyerShipping < totalShipping;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Order summary',
            style: AppTextStyles.titleMedium.copyWith(
              color: ink.text,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 14),

          _moneyRow(
            'Subtotal (${widget.cartSummary.selectedItemsCount} item'
            '${widget.cartSummary.selectedItemsCount != 1 ? 's' : ''})',
            CurrencyFormatter.formatWithPeso(
              widget.cartSummary.selectedItemsTotal,
            ),
          ),
          if (totalDiscount > 0) ...[
            const SizedBox(height: 10),
            _moneyRow(
              'Shop vouchers',
              '-${CurrencyFormatter.formatWithPeso(totalDiscount)}',
              good: true,
            ),
          ],
          const SizedBox(height: 10),
          _moneyRow(
            'Shipping',
            '',
            valueWidget: _isCalculatingShipping
                ? const AmountSkeleton(width: 72, height: 14)
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      if (shippingDiscounted) ...[
                        Text(
                          CurrencyFormatter.formatWithPeso(totalShipping),
                          style: AppTextStyles.bodySmall.copyWith(
                            decoration: TextDecoration.lineThrough,
                            decorationColor: ink.text.withValues(alpha: 0.45),
                            color: ink.text.withValues(alpha: 0.45),
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        _anyShippingModeUnchosen
                            ? '—'
                            : buyerShipping > 0
                                ? CurrencyFormatter.formatWithPeso(buyerShipping)
                                : 'FREE',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          color: _anyShippingModeUnchosen
                              ? ink.text.withValues(alpha: 0.5)
                              : buyerShipping > 0
                                  ? ink.text
                                  : ink.emerald,
                        ),
                      ),
                    ],
                  ),
          ),

          const SizedBox(height: 14),
          Divider(height: 1, thickness: 1, color: ink.border),
          const SizedBox(height: 14),

          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'Total',
                style: AppTextStyles.titleMedium.copyWith(
                  color: ink.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              Text(
                CurrencyFormatter.formatWithPeso(_calculateTotalWithShipping()),
                style: AppTextStyles.headlineSmall.copyWith(
                  color: ink.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 25,
                ),
              ),
            ],
          ),

          // Savings sit BELOW the total, not in the deduction column: the
          // subtotal above is the list price and the discount is already taken
          // off the figure shown, so repeating it as a deduction line would
          // imply a second reduction that never happens. Same reasoning, and
          // same wording, as the cart.
          if (totalDiscount > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.sell_outlined, size: 14, color: ink.emerald),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'You saved '
                    '${CurrencyFormatter.formatWithPeso(totalDiscount)} '
                    'with shop vouchers',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: ink.emerald,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ],

          ..._buildBlockingNotices(),

          if (includeButton) ...[
            const SizedBox(height: 16),
            _buildPlaceOrderButton(),
          ],
        ],
      ),
    );
  }

  /// Everything currently standing between the buyer and a placed order.
  ///
  /// Shown in both layouts, so a buyer never meets a disabled button without
  /// being told why.
  List<Widget> _buildBlockingNotices() {
    final notices = <Widget>[];

    if (_anyShippingBlocked) {
      notices.add(_notice(
        icon: Icons.error_outline,
        tone: _danger,
        text: 'Some delivery rates couldn\'t be calculated. Choose another '
            'option for the highlighted sellers, or retry.',
        action: _retryButton(_danger),
      ));
    } else if (_anyShippingModeUnchosen) {
      notices.add(_notice(
        icon: Icons.local_shipping_outlined,
        tone: ink.amber,
        text: 'Choose a delivery method for every seller.',
      ));
    }

    if (_selectedAddress == null) {
      notices.add(_notice(
        icon: Icons.location_on_outlined,
        tone: ink.amber,
        text: 'Select a shipping address.',
      ));
    }

    if (_selectedPaymentMethod == null) {
      notices.add(_notice(
        icon: Icons.credit_card_outlined,
        tone: ink.amber,
        text: 'Select a payment method.',
      ));
    }

    return [
      for (final notice in notices) ...[const SizedBox(height: 12), notice],
    ];
  }

  Widget _buildPlaceOrderButton() {
    final busy = _isProcessing || _isCalculatingShipping || _isCalculatingSameDay;

    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: busy ? null : _processCheckout,
        style: ElevatedButton.styleFrom(
          backgroundColor: ink.emerald,
          foregroundColor: ink.onEmerald,
          disabledBackgroundColor: ink.surfaceHigh,
          disabledForegroundColor: ink.text.withValues(alpha: 0.38),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy) ...[
              SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: ink.text.withValues(alpha: 0.38),
                ),
              ),
              const SizedBox(width: 10),
            ] else ...[
              const Icon(Icons.lock_outline, size: 17),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                _isProcessing
                    ? 'Placing order…'
                    : (_isCalculatingShipping || _isCalculatingSameDay)
                        ? 'Getting rates…'
                        : 'Place order',
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.buttonLarge.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The phone's committed action: total on the left, button on the right.
  /// Same shape as the cart's, so the last two screens of a purchase put the
  /// same thing in the same place.
  Widget _buildMobileCheckoutBar() {
    return Container(
      decoration: BoxDecoration(
        color: ink.surface,
        border: Border(top: BorderSide(color: ink.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Total',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: ink.text.withValues(alpha: 0.55),
                      fontSize: 11.5,
                    ),
                  ),
                  Text(
                    CurrencyFormatter.formatWithPeso(
                      _calculateTotalWithShipping(),
                    ),
                    style: AppTextStyles.titleLarge.copyWith(
                      color: ink.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 19,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(child: _buildPlaceOrderButton()),
            ],
          ),
        ),
      ),
    );
  }

  // ── Payment hand-off ─────────────────────────────────────────────────────

  Future<void> _openCheckoutUrl(
    String checkoutUrl, {
    required String sessionId,
  }) async {
    try {
      AppLogger.d('Attempting to open checkout URL: $checkoutUrl');

      if (checkoutUrl.isNotEmpty) {
        // Check if running on web platform
        if (kIsWeb) {
          // For web platform, use external browser
          await _openUrlInBrowser(checkoutUrl);

          // After opening the URL, show a message to the user
          if (mounted) {
            _showPaymentInProgressDialog();
          }
        } else {
          // For mobile platforms, use WebView
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                // The session is the page's identity, so the URL says which
                // one is open: /cart/checkout/<sessionId>.
                settings: RouteSettings(name: checkoutSessionPath(sessionId)),
                builder: (context) => PaymongoWebViewPage(
                  checkoutUrl: checkoutUrl,
                  successUrl: 'https://dentpal-store.web.app/payment-success',
                  cancelUrl: 'https://dentpal-store.web.app/payment-failed',
                  onPaymentComplete: (isSuccess, orderId) {
                    AppLogger.d('Payment completed. Success: $isSuccess, Order ID: $orderId');

                    if (isSuccess) {
                      // Handle successful payment
                      _handlePaymentSuccess(orderId, sessionId);
                    } else {
                      // Handle payment cancellation
                      _handlePaymentCancellation(orderId, sessionId);
                    }
                  },
                ),
              ),
            );
          }
        }
      } else {
        throw Exception('Invalid checkout URL');
      }
    } catch (e) {
      AppLogger.d('Error opening checkout URL: $e');
      rethrow;
    }
  }

  Future<void> _openUrlInBrowser(String url) async {
    try {
      AppLogger.d('Attempting to open URL in browser: $url');

      final uri = Uri.parse(url);

      // Check if the URL can be launched
      if (await canLaunchUrl(uri)) {
        AppLogger.d('URL can be launched, opening in external browser');

        // Launch the URL in external browser
        final success = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication, // Open in external browser
        );

        if (success) {
          AppLogger.d('Successfully opened payment page in browser');
        } else {
          AppLogger.d('Failed to launch URL, showing manual dialog');
          if (mounted) {
            _showManualUrlDialog(url);
          }
        }
      } else {
        AppLogger.d('URL cannot be launched, showing manual dialog');
        if (mounted) {
          _showManualUrlDialog(url);
        }
      }
    } catch (e) {
      AppLogger.d('Error launching URL: $e, showing manual dialog');
      if (mounted) {
        _showManualUrlDialog(url);
      }
    }
  }

  void _showPaymentInProgressDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _dialog(
        icon: Icons.open_in_new,
        tone: ink.emeraldSoft,
        title: 'Payment in progress',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _dialogBody(
              'The PayMongo payment page has opened in a new tab. Complete your '
              'payment there, then come back to this tab.',
            ),
            const SizedBox(height: 12),
            Text(
              'Your order stays reserved while you pay.',
              style: AppTextStyles.bodySmall.copyWith(
                color: ink.text.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          _dialogPrimaryAction('Continue shopping', () {
            Navigator.of(context).pop(); // Close this dialog
            Navigator.of(context).pop(); // Go back to cart
            widget.onOrderComplete?.call();
          }),
        ],
      ),
    );
  }

  void _showManualUrlDialog(String url) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _dialog(
        icon: Icons.link,
        tone: ink.amber,
        title: 'Complete payment',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _dialogBody(
              'Your order has been created. The payment page couldn\'t be opened '
              'automatically — copy this link and open it in a new tab:',
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ink.surfaceHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ink.border),
              ),
              child: SelectableText(
                url,
                style: AppTextStyles.bodySmall.copyWith(
                  fontFamily: 'monospace',
                  color: ink.text.withValues(alpha: 0.85),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        actions: [
          _dialogTextAction('Copy link', () async {
            await _copyToClipboard(url);
            if (mounted) {
              _showSnack('Payment link copied');
            }
          }),
          _dialogPrimaryAction('Continue shopping', () {
            Navigator.of(context).pop(); // Close this dialog
            Navigator.of(context).pop(); // Go back to cart
            widget.onOrderComplete?.call();
          }),
        ],
      ),
    );
  }

  Future<void> _copyToClipboard(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      AppLogger.d('URL copied to clipboard');
    } catch (e) {
      AppLogger.d('Error copying to clipboard: $e');
    }
  }

  /// Both endings replace the checkout route rather than stacking on it: the
  /// order is placed, so Back must not walk into a form that would place it
  /// again.
  void _handlePaymentSuccess(String? orderId, String? sessionId) {
    AppLogger.d('Payment completed successfully. Order ID: $orderId');
    if (!mounted) return;

    // Payment status is updated by PayMongo's webhooks — there is nothing for
    // the app to verify, so it goes straight to the receipt.
    widget.onOrderComplete?.call();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        settings: const RouteSettings(name: kCheckoutSuccessPath),
        builder: (context) => PaymentSuccessPage(
          orderId: orderId,
          sessionId: sessionId,
        ),
      ),
    );
  }

  void _handlePaymentCancellation(String? orderId, String? sessionId) {
    AppLogger.d('Payment was cancelled by user');
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        settings: const RouteSettings(name: kCheckoutFailedPath),
        builder: (context) => PaymentFailedPage(
          orderId: orderId,
          sessionId: sessionId,
        ),
      ),
    );
  }
}

/// Terms / Privacy, fetched and shown full-height.
class _PolicyDialog extends StatefulWidget {
  final String title;
  final IconData icon;
  final Future<String?> Function() fetchContent;

  const _PolicyDialog({
    required this.title,
    required this.icon,
    required this.fetchContent,
  });

  @override
  State<_PolicyDialog> createState() => _PolicyDialogState();
}

class _PolicyDialogState extends State<_PolicyDialog> {
  String? _content;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final content = await widget.fetchContent();

      if (mounted) {
        setState(() {
          _content = content;
          _isLoading = false;

          if (content == null) {
            _errorMessage = '${widget.title} not available at the moment.';
          }
        });
      }
    } catch (e) {
      AppLogger.d('Error loading ${widget.title}: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load ${widget.title}. Please try again later.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);
    final danger = ink.isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);

    return Dialog(
      backgroundColor: ink.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 700,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 10),
              child: Row(
                children: [
                  Icon(widget.icon, color: ink.emerald, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: AppTextStyles.titleMedium.copyWith(
                        color: ink.text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: ink.text.withValues(alpha: 0.6)),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: ink.border),

            // Content
            Flexible(
              child: _isLoading
                  ? Padding(
                      padding: const EdgeInsets.all(40),
                      child: Center(
                        child: CircularProgressIndicator(color: ink.emerald),
                      ),
                    )
                  : _errorMessage != null
                      ? Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.error_outline, size: 40, color: danger),
                              const SizedBox(height: 14),
                              Text(
                                _errorMessage!,
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: ink.text.withValues(alpha: 0.7),
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 14),
                              TextButton(
                                onPressed: _loadContent,
                                style: TextButton.styleFrom(
                                  foregroundColor: ink.emerald,
                                ),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: SelectableText(
                            _content ?? '',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: ink.text.withValues(alpha: 0.85),
                              fontSize: 13.5,
                              height: 1.6,
                            ),
                          ),
                        ),
            ),

            // Footer
            Divider(height: 1, thickness: 1, color: ink.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(foregroundColor: ink.emerald),
                    child: Text('Close', style: AppTextStyles.buttonMedium),
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
