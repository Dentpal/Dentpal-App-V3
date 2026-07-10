import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dentpal/utils/app_logger.dart';
import '../models/cart_model.dart';
import '../models/order_model.dart';
import '../models/paymongo_model.dart';
import '../services/checkout_service.dart';
import '../services/cart_service.dart';
import '../widgets/address_selection_widget.dart';
import '../widgets/voucher_picker_sheet.dart';
import 'paymongo_webview_page.dart';
import '../../profile/models/shipping_address.dart';
import '../../profile/services/platform_policies_service.dart';
import '../../core/app_theme/app_colors.dart';
import '../../core/app_theme/app_text_styles.dart';

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

  Map<String, double> _expressSellerShippingCosts = {};
  Map<String, double> _expressSellerTotalShippingCosts = {};
  Map<String, double> _standardSellerShippingCosts = {};
  Map<String, double> _standardSellerTotalShippingCosts = {};

  // Per-seller insurance & evaluation costs (from JRS response)
  final Map<String, double> _sellerInsuranceCosts = {};
  final Map<String, double> _sellerEvaluationCosts = {};
  Map<String, double> _expressSellerInsuranceCosts = {};
  Map<String, double> _expressSellerEvaluationCosts = {};
  Map<String, double> _standardSellerInsuranceCosts = {};
  Map<String, double> _standardSellerEvaluationCosts = {};

  // Per-seller packaging size (locally-resolved productName from JRS calculator)
  final Map<String, String> _sellerPackagingSizes = {};
  Map<String, String> _expressSellerPackagingSizes = {};
  Map<String, String> _standardSellerPackagingSizes = {};

  final TextEditingController _notesController = TextEditingController();

  // Per-seller voucher discounts
  Map<String, double> _sellerDiscountAmounts = {};

  @override
  void initState() {
    super.initState();
    _discountVouchers = Map.of(widget.selectedDiscountVouchers);
    _shippingVouchers = Map.of(widget.selectedShippingVouchers);
    _initializeSellerShippingModes();
    _computeVoucherDiscounts();
    _loadPaymentMethods();
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
        // Respect seller's allowed delivery modes: default to standard if
        // allowed, otherwise express.
        final allowsStd = _sellerAllowsDelivery(sellerId, 'standard');
        _sellerExpressShipping[sellerId] = !allowsStd;
      }
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
  /// methods.  Returns true for methods not configurable via checkoutOptions
  /// (grabpay, paymaya, billEase) so existing hard-coded filters still apply.
  bool _isPaymentMethodAllowed(PaymentMethod method) {
    final key = _paymentMethodKey(method);
    if (key == null) return false; // grabbed / paymaya / billEase — excluded elsewhere
    return _allowedPaymentKeys.contains(key);
  }

  static String? _paymentMethodKey(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.cashOnDelivery: return 'cod';
      case PaymentMethod.gcash:          return 'gcash';
      case PaymentMethod.card:           return 'card';
      default:                           return null;
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

  /// Same-day is offered only when the seller enabled it AND a live Lalamove
  /// quote succeeded (which also enforces Metro Manila coverage on the backend).
  bool _isSameDayAvailableFor(String sellerId) =>
      _sellerAllowsDelivery(sellerId, 'sameDay') &&
      _sameDaySellerCosts.containsKey(sellerId);

  void _onSellerPickupToggled(String sellerId, bool pickupSelected) {
    setState(() {
      _sellerPickupSelected[sellerId] = pickupSelected;
      if (pickupSelected) _sellerSameDaySelected[sellerId] = false;
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
      if (sameDay) _sellerPickupSelected[sellerId] = false;
      _refreshActiveMapsForSeller(sellerId);
    });
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadPaymentMethods() async {
    try {
      final paymentMethods = await _checkoutService.getAvailablePaymentMethods();
      // Auto-select the first method that all sellers allow.
      final firstAllowed = paymentMethods.firstWhere(
        (m) => _isPaymentMethodAllowed(m),
        orElse: () => paymentMethods.isNotEmpty ? paymentMethods.first : PaymentMethod.cashOnDelivery,
      );
      setState(() {
        _selectedPaymentMethod = firstAllowed;
      });
    } catch (e) {
      AppLogger.d('Error loading payment methods: $e');
    }
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

    if (_isCalculatingShipping) {
      _showErrorDialog('Please wait for the shipping cost to finish calculating.');
      return false;
    }

    if (_isCalculatingSameDay) {
      _showErrorDialog('Please wait for delivery options to finish loading.');
      return false;
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
        .where((sellerId) => _sellerAllowsDelivery(sellerId, 'sameDay'))
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

  Future<void> _navigateToPaymongoCheckout(CreateOrderResponse orderResponse) async {
    if (orderResponse.checkoutSession != null) {
      // Navigate to external Paymongo checkout URL
      final checkoutUrl = orderResponse.checkoutSession!.attributes.checkoutUrl;
      
      // In a real implementation, you would:
      // 1. Open the checkout URL in a browser or WebView
      // 2. Handle the success/cancel redirects
      // 3. Update the order status based on the payment result
      
      // For now, show the checkout URL in a dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.payment,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Paymongo Checkout',
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
                'Your order has been created successfully! You will be redirected to Paymongo to complete your payment.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.onSurface.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.grey50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order ID:',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      orderResponse.orderId,
                      style: AppTextStyles.bodySmall.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Total Amount:',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₱${orderResponse.totalAmount.toStringAsFixed(2)}',
                      style: AppTextStyles.titleMedium.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Checkout URL: ${checkoutUrl.length > 50 ? '${checkoutUrl.substring(0, 50)}...' : checkoutUrl}',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.info,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                Navigator.of(context).pop(); // Go back to cart/previous page
                widget.onOrderComplete?.call();
              },
              child: Text('Close', style: AppTextStyles.buttonMedium),
            ),
            ElevatedButton(
              onPressed: () async {
                AppLogger.d('Opening Paymongo checkout URL: $checkoutUrl');
                
                // Close the dialog first
                Navigator.of(context).pop();
                
                try {
                  // Import url_launcher package to open URLs
                  // For now, we'll use a simple browser opening approach
                  await _openCheckoutUrl(checkoutUrl);
                } catch (e) {
                  AppLogger.d('Error opening checkout URL: $e');
                  if (mounted) {
                    _showErrorDialog('Failed to open payment page. Please try again.');
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                elevation: 0,
              ),
              child: Text('Proceed to Payment', style: AppTextStyles.buttonMedium),
            ),
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
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.check_circle_outlined,
                color: AppColors.success,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Order Created',
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
              'Your order has been created successfully!',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.grey50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Payment Intent ID:',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    orderResponse.paymentIntent?.id ?? 'N/A',
                    style: AppTextStyles.bodySmall.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'In a real implementation, you would be redirected to Paymongo\'s payment interface to complete the payment.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.info,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(); // Go back to cart/previous page
              widget.onOrderComplete?.call();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              elevation: 0,
            ),
            child: Text('Continue', style: AppTextStyles.buttonMedium),
          ),
        ],
      ),
    );
  }

  Future<void> _navigateToCodOrderSuccess(CreateOrderResponse orderResponse) async {
    // Show success dialog for Cash on Delivery orders
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.check_circle_outlined,
                color: AppColors.success,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Order Placed',
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
              'Your Cash on Delivery order has been placed successfully!',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.grey50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.receipt_long, size: 16, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Order ID:',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    orderResponse.orderId,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.money, size: 16, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Total Amount:',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₱${orderResponse.totalAmount.toStringAsFixed(2)}',
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.info.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18, color: AppColors.info),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Please prepare the exact amount for payment upon delivery. Our rider will contact you when your order is on the way.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.info,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(); // Go back to cart/previous page
              widget.onOrderComplete?.call();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
            child: Text('Continue Shopping', style: AppTextStyles.buttonMedium),
          ),
        ],
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
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.error_outline,
                color: AppColors.error,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Checkout Error',
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.onSurface.withValues(alpha: 0.8),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: AppTextStyles.buttonMedium),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWebView = screenWidth > 1024;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Row(
          children: [
            Icon(Icons.shopping_bag, color: AppColors.primary, size: 24),
            const SizedBox(width: 8),
            Text(
              'Checkout',
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
        ),
      ),
      body: isWebView ? _buildWebLayout() : _buildMobileLayout(),
      bottomNavigationBar: !isWebView ? _buildBottomCheckoutBar() : null,
    );
  }

  Widget _buildWebLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Main content area
        Expanded(
          flex: 2,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildShippingSection(),
                const SizedBox(height: 24),
                _buildPaymentSection(),
                const SizedBox(height: 24),
                _buildOrderNotesSection(),
                const SizedBox(height: 24),
                _buildTermsSection(),
              ],
            ),
          ),
        ),

        // Sidebar with order summary
        Container(
          width: 400,
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(
              left: BorderSide(
                color: AppColors.onSurface.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
          ),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: _buildOrderSummary(),
                ),
              ),
              _buildWebCheckoutButton(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOrderSummary(),
          const SizedBox(height: 24),
          _buildShippingSection(),
          const SizedBox(height: 24),
          _buildPaymentSection(),
          const SizedBox(height: 24),
          _buildOrderNotesSection(),
          const SizedBox(height: 24),
          _buildTermsSection(),
          const SizedBox(height: 100), // Space for bottom bar
        ],
      ),
    );
  }

  Widget _buildOrderSummary() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.onSurface.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.receipt_long, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Order Summary',
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          // Items
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ..._buildGroupedSellerItems(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItem(CartItem item) {
    return Row(
      children: [
        // Product image
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: AppColors.grey100,
            borderRadius: BorderRadius.circular(8),
            image: item.productImage?.isNotEmpty == true
                ? DecorationImage(
                    image: NetworkImage(item.productImage!),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: item.productImage?.isEmpty != false
              ? Icon(
                  Icons.image,
                  color: AppColors.onSurface.withValues(alpha: 0.4),
                  size: 20,
                )
              : null,
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
                  fontWeight: FontWeight.w500,
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
                'Qty: ${item.quantity}',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
        
        // Price
        Text(
          '₱${((item.productPrice ?? 0) * item.quantity).toStringAsFixed(2)}',
          style: AppTextStyles.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
            fontFamily: 'Roboto',
          ),
        ),
      ],
    );
  }

  /// Group cart items by seller and build seller sections
  List<Widget> _buildGroupedSellerItems() {
    // Group items by seller
    final Map<String, List<CartItem>> sellerGroups = {};
    
    for (final item in widget.cartItems) {
      final sellerId = item.sellerId ?? 'unknown';
      if (!sellerGroups.containsKey(sellerId)) {
        sellerGroups[sellerId] = [];
      }
      sellerGroups[sellerId]!.add(item);
    }

    // Build widgets for each seller group
    final List<Widget> widgets = [];
    
    sellerGroups.forEach((sellerId, items) {
      // Get seller name from first item
      final sellerName = items.first.sellerName ?? 'Unknown Seller';
      
      widgets.add(_buildSellerGroup(sellerId, sellerName, items));
      widgets.add(const SizedBox(height: 16));
    });

    return widgets;
  }

  /// Build a seller group with clickable seller name and their products
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
    final shippingDiscounted = totalShippingCost > 0.0 && buyerShippingCost < totalShippingCost;

    AppLogger.d('Seller: $sellerName, Subtotal: $sellerSubtotal, Discount: $sellerDiscount, Total Shipping: $totalShippingCost, Buyer Pays: $buyerShippingCost');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.onSurface.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Seller header with inline name
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.store, size: 12, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      'Seller',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  sellerName,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 4),
          Text(
            '${items.length} item${items.length != 1 ? 's' : ''}',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.onSurface.withValues(alpha: 0.6),
            ),
          ),
          
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          
          // Products for this seller
          ...items.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildOrderItem(item),
          )),
          
          // Seller subtotal and shipping
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.onSurface.withValues(alpha: 0.1),
              ),
            ),
            child: Column(
              children: [
                // Subtotal row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Subtotal',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    Text(
                      '₱${sellerSubtotal.toStringAsFixed(2)}',
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ],
                ),

                // Voucher discount row (per seller)
                if (sellerDiscount > 0) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Voucher Discount',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                      Text(
                        '-₱${sellerDiscount.toStringAsFixed(2)}',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Roboto',
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),

                // Shipping row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Shipping',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    _isCalculatingShipping
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Calculating...',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.onSurface.withValues(alpha: 0.6),
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          )
                        : _sellerShippingBlocked(sellerId)
                        ? Text(
                            'Unavailable',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.error,
                              fontStyle: FontStyle.italic,
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (shippingDiscounted) ...[
                                Text(
                                  '₱${totalShippingCost.toStringAsFixed(2)}',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    fontFamily: 'Roboto',
                                    decoration: TextDecoration.lineThrough,
                                    decorationColor: AppColors.error,
                                    decorationThickness: 2,
                                    color: AppColors.onSurface.withValues(alpha: 0.5),
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Text(
                                buyerPaysShipping
                                    ? '₱${buyerShippingCost.toStringAsFixed(2)}'
                                    : 'FREE',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontFamily: buyerPaysShipping ? 'Roboto' : null,
                                  color: buyerPaysShipping ? null : AppColors.success,
                                ),
                              ),
                            ],
                          ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildSellerShippingModeToggle(sellerId),
                const SizedBox(height: 12),
                _buildSellerVoucherChips(sellerId),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Per-seller delivery mode toggle. Shows only the modes the seller allows
  /// (standard, express, pickup). Locks to express when the seller's shipping
  /// voucher only covers express.
  Widget _buildSellerShippingModeToggle(String sellerId) {
    final allowsStandard = _sellerAllowsDelivery(sellerId, 'standard');
    final allowsExpress  = _sellerAllowsDelivery(sellerId, 'express');
    final allowsPickup   = _sellerAllowsDelivery(sellerId, 'pickup');
    final allowsSameDay  = _sellerAllowsDelivery(sellerId, 'sameDay');
    final sameDayAvailable = _isSameDayAvailableFor(sellerId);

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

    final isSameDay = _isSameDaySelectedFor(sellerId);
    final isPickup  = !isSameDay && _isPickupSelectedFor(sellerId);
    final isExpress = !isSameDay && !isPickup && _isExpressFor(sellerId);
    final isStandard = !isSameDay && !isPickup && !isExpress;
    final lockedExpress = _isLockedToExpress(sellerId);
    final sameDayCost = _sameDaySellerCosts[sellerId] ?? 0.0;

    final expressTotal  = _expressSellerTotalShippingCosts[sellerId] ?? 0.0;
    final standardTotal = _standardSellerTotalShippingCosts[sellerId] ?? 0.0;

    Widget radioRow({
      required bool selected,
      required bool disabled,
      required VoidCallback onTap,
      required IconData icon,
      required String label,
      String? sublabel,
      required Widget trailing,
    }) {
      return InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Radio<bool>(
                value: true,
                groupValue: selected,
                onChanged: disabled ? null : (_) => onTap(),
                activeColor: AppColors.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
              Icon(icon, size: 16,
                color: selected
                    ? AppColors.primary
                    : AppColors.onSurface.withValues(alpha: 0.4)),
              const SizedBox(width: 4),
              Expanded(
                child: Row(
                  children: [
                    Text(label,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                        color: selected
                            ? AppColors.primary
                            : AppColors.onSurface.withValues(alpha: 0.5),
                      )),
                    if (sublabel != null) ...[
                      const SizedBox(width: 6),
                      Text(sublabel,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.onSurface.withValues(alpha: 0.5),
                          fontStyle: FontStyle.italic,
                        )),
                    ],
                  ],
                ),
              ),
              trailing,
            ],
          ),
        ),
      );
    }

    Widget costLabel(double cost, bool selected) => Text(
      cost > 0 ? '₱${cost.toStringAsFixed(2)}' : 'FREE',
      style: AppTextStyles.bodyMedium.copyWith(
        fontFamily: 'Roboto',
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        color: selected
            ? AppColors.primary
            : AppColors.onSurface.withValues(alpha: 0.5),
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.onSurface.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          // JRS rate unavailable for this seller — explain and offer a retry.
          // Pickup / Same Day rows below (if the seller enabled them) remain
          // selectable so the order can still proceed.
          if (jrsFailed) ...[
            Row(
              children: [
                Icon(Icons.error_outline, size: 16, color: AppColors.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    (allowsPickup || sameDayAvailable)
                        ? 'Standard/Express delivery is unavailable right now. Choose another option below, or retry.'
                        : 'Standard/Express delivery is unavailable right now. Please retry.',
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
                  ),
                ),
                const SizedBox(width: 6),
                TextButton.icon(
                  onPressed: _isCalculatingShipping ? null : _calculateShippingCost,
                  icon: const Icon(Icons.refresh, size: 14),
                  label: Text('Retry', style: AppTextStyles.bodySmall),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.error,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            if (allowsPickup || allowsSameDay)
              const Divider(height: 16),
          ],
          if (allowsStandard && hasStandardCost)
            radioRow(
              selected: isStandard,
              disabled: _isCalculatingShipping || lockedExpress,
              onTap: () {
                _onSellerSameDayToggled(sellerId, false);
                _onSellerPickupToggled(sellerId, false);
                _onSellerShippingModeToggled(sellerId, false);
              },
              icon: Icons.local_shipping_outlined,
              label: 'Standard',
              sublabel: lockedExpress ? '(locked by voucher)' : null,
              trailing: costLabel(standardTotal, isStandard),
            ),
          if (allowsExpress && hasExpressCost)
            radioRow(
              selected: isExpress,
              disabled: _isCalculatingShipping,
              onTap: () {
                _onSellerSameDayToggled(sellerId, false);
                _onSellerPickupToggled(sellerId, false);
                _onSellerShippingModeToggled(sellerId, true);
              },
              icon: Icons.flash_on,
              label: 'Express',
              trailing: costLabel(expressTotal, isExpress),
            ),
          // Same Day Delivery (Lalamove) — only when the seller enabled it and a
          // live quote succeeded (Metro Manila only). Buyer pays the full fee.
          if (allowsSameDay && (sameDayAvailable || _isCalculatingSameDay))
            radioRow(
              selected: isSameDay,
              disabled: _isCalculatingShipping || _isCalculatingSameDay || !sameDayAvailable,
              onTap: () => _onSellerSameDayToggled(sellerId, true),
              icon: Icons.motorcycle_outlined,
              label: 'Same Day Delivery',
              sublabel: _isCalculatingSameDay && !sameDayAvailable ? '(checking…)' : null,
              trailing: _isCalculatingSameDay && !sameDayAvailable
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : costLabel(sameDayCost, isSameDay),
            ),
          if (allowsPickup)
            radioRow(
              selected: isPickup,
              disabled: false,
              onTap: () {
                _onSellerSameDayToggled(sellerId, false);
                _onSellerPickupToggled(sellerId, true);
              },
              icon: Icons.store_outlined,
              label: 'Pickup',
              trailing: Text(
                'FREE',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: isPickup ? FontWeight.w600 : FontWeight.normal,
                  color: isPickup ? AppColors.success : AppColors.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

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
          label: 'Discount Voucher',
          mode: VoucherPickerMode.discount,
          sellerId: sellerId,
          sellerName: sellerName,
          sellerSubtotal: sellerSubtotal,
          voucher: _discountVouchers[sellerId],
        ),
        const SizedBox(height: 6),
        _buildVoucherChip(
          icon: Icons.local_shipping_outlined,
          label: 'Shipping Voucher',
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
          : '-₱${value.toStringAsFixed(2)}';
    }

    return InkWell(
      onTap: () => _openCheckoutVoucherPicker(
        mode: mode,
        sellerId: sellerId,
        sellerName: sellerName,
        sellerSubtotal: sellerSubtotal,
      ),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: voucher != null
                ? AppColors.primary.withValues(alpha: 0.4)
                : AppColors.onSurface.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Text(
              trailingLabel,
              style: AppTextStyles.bodySmall.copyWith(
                color: voucher != null ? AppColors.primary : AppColors.onSurface.withValues(alpha: 0.6),
                fontWeight: FontWeight.w600,
                fontFamily: 'Roboto',
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.edit, size: 14, color: AppColors.onSurface.withValues(alpha: 0.5)),
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

  Widget _buildShippingSection() {
    return AddressSelectionWidget(
      selectedAddress: _selectedAddress,
      onAddressSelected: (address) {
        setState(() {
          _selectedAddress = address;
        });
        // Calculate shipping cost when address is selected
        _calculateShippingCost();
      },
      title: 'Shipping Address',
    );
  }

  Widget _buildPaymentSection() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.onSurface.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.payment, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Payment Method',
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          // Payment methods — filtered to the intersection of all sellers' allowed options
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: PaymentMethod.values
                  .where((method) =>
                      method != PaymentMethod.grabpay &&
                      method != PaymentMethod.billEase &&
                      method != PaymentMethod.paymaya &&
                      _isPaymentMethodAllowed(method))
                  .map((method) {
                final isSelected = _selectedPaymentMethod == method;
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedPaymentMethod = method;
                      });
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isSelected 
                            ? AppColors.primary.withValues(alpha: 0.05)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected 
                              ? AppColors.primary
                              : AppColors.onSurface.withValues(alpha: 0.1),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppColors.grey100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              _getPaymentMethodIcon(method),
                              color: AppColors.primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              method.displayName,
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.w500,
                                color: isSelected 
                                    ? AppColors.primary 
                                    : AppColors.onSurface,
                              ),
                            ),
                          ),
                          if (isSelected)
                            Icon(
                              Icons.check_circle,
                              color: AppColors.primary,
                              size: 20,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
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
      case PaymentMethod.billEase:
        return Icons.account_balance;
      case PaymentMethod.cashOnDelivery:
        return Icons.money;
    }
  }

  Widget _buildOrderNotesSection() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.onSurface.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.note_outlined, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Order Notes (Optional)',
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          // Notes field
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _notesController,
              onChanged: (value) {
                setState(() {
                  _orderNotes = value.isEmpty ? null : value;
                });
              },
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Add any special instructions for your order...',
                hintStyle: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.onSurface.withValues(alpha: 0.5),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppColors.onSurface.withValues(alpha: 0.2),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppColors.primary,
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: AppColors.background,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTermsSection() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.onSurface.withValues(alpha: 0.1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Terms and Conditions',
                  style: AppTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text.rich(
              TextSpan(
                text: 'By placing this order, I agree to the ',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.onSurface.withValues(alpha: 0.8),
                ),
                children: [
                  TextSpan(
                    text: 'Terms and Conditions',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.primary,
                      decoration: TextDecoration.underline,
                      fontWeight: FontWeight.w600,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => _showTermsAndConditions(context),
                  ),
                  TextSpan(
                    text: ' and ',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                  TextSpan(
                    text: 'Privacy Policy',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.primary,
                      decoration: TextDecoration.underline,
                      fontWeight: FontWeight.w600,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => _showPrivacyPolicy(context),
                  ),
                  TextSpan(
                    text: '.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shown when at least one seller has no usable shipping option (its JRS rate
  /// failed and no Pickup / Same Day alternative is selected). Lets the buyer
  /// re-trigger the calculation; those sellers stay blocked until resolved.
  Widget _buildShippingRetryBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: AppColors.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Some delivery rates couldn\'t be calculated. Choose another option below, or retry.',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _isCalculatingShipping ? null : _calculateShippingCost,
            icon: const Icon(Icons.refresh, size: 16),
            label: Text('Retry', style: AppTextStyles.buttonMedium),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: BorderSide(color: AppColors.error.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomCheckoutBar() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_anyShippingBlocked) ...[
              _buildShippingRetryBanner(),
              const SizedBox(height: 12),
            ],
            // Subtotal row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Subtotal',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                Text(
                  '₱${widget.cartSummary.selectedItemsTotal.toStringAsFixed(2)}',
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Roboto',
                  ),
                ),
              ],
            ),

            // Voucher discount row (grand total)
            if (_calculateTotalDiscount() > 0) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Voucher Discount',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  Text(
                    '-₱${_calculateTotalDiscount().toStringAsFixed(2)}',
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Roboto',
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),

            // Shipping row — reflects active selection (express or standard)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Shipping',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                _isCalculatingShipping
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Calculating...',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.onSurface.withValues(alpha: 0.6),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_calculateTotalShippingCost() > 0 &&
                              _calculateBuyerShippingPortion() < _calculateTotalShippingCost()) ...[
                            Text(
                              '₱${_calculateTotalShippingCost().toStringAsFixed(2)}',
                              style: AppTextStyles.bodySmall.copyWith(
                                fontFamily: 'Roboto',
                                decoration: TextDecoration.lineThrough,
                                decorationColor: AppColors.error,
                                decorationThickness: 2,
                                color: AppColors.onSurface.withValues(alpha: 0.5),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            _calculateBuyerShippingPortion() > 0
                                ? '₱${_calculateBuyerShippingPortion().toStringAsFixed(2)}'
                                : 'FREE',
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                              fontFamily: _calculateBuyerShippingPortion() > 0 ? 'Roboto' : null,
                              color: _calculateBuyerShippingPortion() > 0
                                  ? null
                                  : AppColors.success,
                            ),
                          ),
                        ],
                      ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            
            // Total row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total',
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '₱${_calculateTotalWithShipping().toStringAsFixed(2)}',
                  style: AppTextStyles.titleLarge.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Roboto',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _processCheckout,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isProcessing
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: AppColors.onPrimary,
                              strokeWidth: 2,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Processing...',
                            style: AppTextStyles.buttonLarge,
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.lock),
                          const SizedBox(width: 8),
                          Text(
                            'Place Order',
                            style: AppTextStyles.buttonLarge.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
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

  Widget _buildWebCheckoutButton() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: AppColors.onSurface.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          if (_anyShippingBlocked) ...[
            _buildShippingRetryBanner(),
            const SizedBox(height: 12),
          ],
          // Subtotal row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Subtotal',
                style: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.onSurface.withValues(alpha: 0.7),
                ),
              ),
              Text(
                '₱${widget.cartSummary.selectedItemsTotal.toStringAsFixed(2)}',
                style: AppTextStyles.bodyLarge.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Shipping row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Shipping',
                style: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.onSurface.withValues(alpha: 0.7),
                ),
              ),
              _isCalculatingShipping
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Calculating...',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.onSurface.withValues(alpha: 0.6),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_calculateTotalShippingCost() > 0 && _calculateBuyerShippingPortion() < _calculateTotalShippingCost()) ...[
                          // Show crossed out total shipping when some/all is free
                          Text(
                            '₱${_calculateTotalShippingCost().toStringAsFixed(2)}',
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontFamily: 'Roboto',
                              decoration: TextDecoration.lineThrough,
                              decorationColor: AppColors.error,
                              decorationThickness: 2,
                              color: AppColors.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          _calculateBuyerShippingPortion() > 0
                              ? '₱${_calculateBuyerShippingPortion().toStringAsFixed(2)}'
                              : 'FREE',
                          style: AppTextStyles.bodyLarge.copyWith(
                            fontWeight: FontWeight.w600,
                            fontFamily: _calculateBuyerShippingPortion() > 0 ? 'Roboto' : null,
                            color: _calculateBuyerShippingPortion() > 0 ? null : AppColors.success,
                          ),
                        ),
                      ],
                    ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
          
          // Total row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total',
                style: AppTextStyles.titleLarge.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '₱${_calculateTotalWithShipping().toStringAsFixed(2)}',
                style: AppTextStyles.titleLarge.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isProcessing ? null : _processCheckout,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isProcessing
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: AppColors.onPrimary,
                            strokeWidth: 2,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Processing...',
                          style: AppTextStyles.buttonLarge,
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.lock),
                        const SizedBox(width: 8),
                        Text(
                          'Place Order',
                          style: AppTextStyles.buttonLarge.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openCheckoutUrl(String checkoutUrl) async {
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
                builder: (context) => PaymongoWebViewPage(
                  checkoutUrl: checkoutUrl,
                  successUrl: 'https://dentpal-store.web.app/payment-success',
                  cancelUrl: 'https://dentpal-store.web.app/payment-failed',
                  onPaymentComplete: (isSuccess, orderId) {
                    AppLogger.d('Payment completed. Success: $isSuccess, Order ID: $orderId');
                    
                    if (isSuccess) {
                      // Handle successful payment
                      _handlePaymentSuccess(orderId);
                    } else {
                      // Handle payment cancellation
                      _handlePaymentCancellation();
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
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.payment,
                color: AppColors.info,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Payment in Progress',
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.open_in_new,
              size: 48,
              color: AppColors.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'The Paymongo payment page has been opened in a new tab. Please complete your payment there.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'After completing payment, you can return to this page.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close this dialog
              Navigator.of(context).pop(); // Go back to cart
              widget.onOrderComplete?.call();
            },
            child: Text('Continue Shopping', style: AppTextStyles.buttonMedium),
          ),
        ],
      ),
    );
  }

  void _showManualUrlDialog(String url) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.payment,
                color: AppColors.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Complete Payment',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your order has been created successfully! Please copy the URL below and open it in a new tab to complete your payment:',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.grey50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.onSurface.withValues(alpha: 0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Payment URL:',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.onSurface.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    url,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontFamily: 'monospace',
                      color: AppColors.info,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: AppColors.info,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'After completing payment, you can return to the app to continue shopping.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.info,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                // Copy URL to clipboard
                await _copyToClipboard(url);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Payment URL copied to clipboard!'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              } catch (e) {
                AppLogger.d('Error copying to clipboard: $e');
              }
            },
            child: Text('Copy URL', style: AppTextStyles.buttonMedium),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close this dialog
              Navigator.of(context).pop(); // Go back to cart
              widget.onOrderComplete?.call();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
            ),
            child: Text('Continue Shopping', style: AppTextStyles.buttonMedium),
          ),
        ],
      ),
    );
  }

  Future<void> _copyToClipboard(String text) async {
    try {
      // Use Flutter's clipboard functionality
      // This should work across platforms
      await Future.delayed(Duration.zero); // Simple placeholder
      // In a real implementation, you would use:
      // await Clipboard.setData(ClipboardData(text: text));
      AppLogger.d('URL copied to clipboard (simulated)');
    } catch (e) {
      AppLogger.d('Error copying to clipboard: $e');
      rethrow;
    }
  }

  void _handlePaymentSuccess(String? orderId) async {
    AppLogger.d('Payment completed successfully. Order ID: $orderId');
    
    if (mounted && orderId != null) {
      // Show loading dialog while verifying payment
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Verifying payment...',
                style: AppTextStyles.bodyMedium,
              ),
            ],
          ),
        ),
      );

      // Payment status will be updated automatically by PayMongo webhooks
      // No need to manually verify - just navigate to success page
      await Future.delayed(const Duration(milliseconds: 500)); // Brief delay for better UX
      
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        
        AppLogger.d('Payment completed, webhooks will update order status');
        
        // Navigate to success page
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/payment-success',
          (route) => route.settings.name == '/', // Clear stack until home
        );
        
        // Call completion callback
        widget.onOrderComplete?.call();
      }
    } else if (mounted) {
      // Navigate to success page even without order ID
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/payment-success',
        (route) => route.settings.name == '/', // Clear stack until home
      );
      
      // Call completion callback
      widget.onOrderComplete?.call();
    }
  }

  void _handlePaymentCancellation() {
    AppLogger.d('Payment was cancelled by user');
    
    if (mounted) {
      // Navigate to dedicated payment failed page instead of showing popup
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/payment-failed',
        (route) => route.settings.name == '/', // Clear stack until home
      );
    }
  }
}

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
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: kIsWeb ? 700 : double.infinity,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Icon(widget.icon, color: AppColors.primary, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: AppTextStyles.titleLarge.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: AppColors.onSurface),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            
            // Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 48,
                                  color: AppColors.error,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _errorMessage!,
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: AppColors.onSurface.withValues(alpha: 0.7),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                TextButton(
                                  onPressed: _loadContent,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(20.0),
                          child: SelectableText(
                            _content ?? '',
                            style: AppTextStyles.bodyMedium.copyWith(
                              height: 1.6,
                            ),
                          ),
                        ),
            ),
            
            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: AppColors.onSurface.withValues(alpha: 0.1),
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                    ),
                    child: const Text('Close'),
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
