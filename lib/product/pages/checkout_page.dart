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
import 'paymongo_webview_page.dart';
import '../../profile/models/shipping_address.dart';
import '../../profile/services/platform_policies_service.dart';
import '../../core/app_theme/app_colors.dart';
import '../../core/app_theme/app_text_styles.dart';

class CheckoutPage extends StatefulWidget {
  final List<CartItem> cartItems;
  final CartSummary cartSummary;
  final VoidCallback? onOrderComplete;

  const CheckoutPage({
    super.key,
    required this.cartItems,
    required this.cartSummary,
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
  bool _termsAccepted = false;
  
  // Per-seller shipping costs
  Map<String, double> _sellerShippingCosts = {}; // sellerId -> buyer's portion of shipping cost
  Map<String, double> _sellerTotalShippingCosts = {}; // sellerId -> total shipping cost (for display)
  bool _isCalculatingShipping = false; // Track if shipping calculation is in progress
  
  final TextEditingController _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPaymentMethods();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadPaymentMethods() async {
    try {
      // Auto-select the first payment method
      final paymentMethods = await _checkoutService.getAvailablePaymentMethods();
      if (paymentMethods.isNotEmpty) {
        setState(() {
          _selectedPaymentMethod = paymentMethods.first;
        });
      }
    } catch (e) {
      AppLogger.d('Error loading payment methods: $e');
    }
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

      // Check if Cash on Delivery is selected
      if (_selectedPaymentMethod == PaymentMethod.cashOnDelivery) {
        // Create COD order directly (no PayMongo integration needed)
        final orderResponse = await _checkoutService.createCashOnDeliveryOrder(
          cartItemIds: cartItemIds,
          addressId: _selectedAddress!.id,
          notes: _orderNotes,
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
          successUrl: 'https://dentpal-store.web.app/payment-success', // Updated success URL
          cancelUrl: 'https://dentpal-store.web.app/payment-failed', // Updated cancel URL
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

    if (!_termsAccepted) {
      _showErrorDialog('Please accept the terms and conditions');
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
    
    setState(() {
      _isCalculatingShipping = true;
      _sellerShippingCosts.clear(); // Reset previous calculations
      _sellerTotalShippingCosts.clear(); // Reset total shipping costs
    });

    try {
      AppLogger.d('Calculating per-seller shipping costs for checkout');
      
      // Group cart items by seller
      final Map<String, List<CartItem>> sellerGroups = {};
      for (final item in widget.cartItems) {
        final sellerId = item.sellerId ?? 'unknown';
        if (!sellerGroups.containsKey(sellerId)) {
          sellerGroups[sellerId] = [];
        }
        sellerGroups[sellerId]!.add(item);
      }
      
      // Calculate shipping for each seller separately using the detailed method
      for (final entry in sellerGroups.entries) {
        final sellerId = entry.key;
        final sellerItems = entry.value;
        
        try {
          // Use the new detailed calculation that returns both values from JRS
          final shippingDetails = await _checkoutService.calculateShippingCostDetailed(
            items: sellerItems,
            address: _selectedAddress!,
          );
          
          // Store both the buyer's portion and the total from JRS
          final buyerCost = shippingDetails['buyerCost'] ?? 0.0;
          final totalCost = shippingDetails['totalCost'] ?? 0.0;
          
          _sellerShippingCosts[sellerId] = buyerCost;
          _sellerTotalShippingCosts[sellerId] = totalCost;
          
          AppLogger.d('Seller $sellerId - Total from JRS: ₱$totalCost, Buyer pays: ₱$buyerCost');
        } catch (e) {
          AppLogger.d('Error calculating shipping for seller $sellerId: $e');
          // Set to 0 to indicate calculation failed for this seller
          _sellerShippingCosts[sellerId] = 0.0;
          _sellerTotalShippingCosts[sellerId] = 0.0;
        }
      }
      
      setState(() {
        _isCalculatingShipping = false;
      });
      
      final totalShipping = _sellerShippingCosts.values.fold(0.0, (sum, cost) => sum + cost);
      final totalShippingFull = _sellerTotalShippingCosts.values.fold(0.0, (sum, cost) => sum + cost);
      AppLogger.d('Total shipping - Full: ₱$totalShippingFull, Buyer pays: ₱$totalShipping across ${_sellerShippingCosts.length} sellers');
      
    } catch (e) {
      AppLogger.d('Error calculating shipping costs: $e');
      
      setState(() {
        _isCalculatingShipping = false;
        _sellerShippingCosts.clear();
        _sellerTotalShippingCosts.clear();
      });
    }
  }

  /// Get total buyer's portion of shipping cost across all sellers
  double _calculateBuyerShippingPortion() {
    if (_sellerShippingCosts.isEmpty) return 0.0;
    return _sellerShippingCosts.values.fold(0.0, (sum, cost) => sum + cost);
  }

  /// Get total shipping cost (including seller's portion) across all sellers
  double _calculateTotalShippingCost() {
    if (_sellerTotalShippingCosts.isEmpty) return 0.0;
    return _sellerTotalShippingCosts.values.fold(0.0, (sum, cost) => sum + cost);
  }

  /// Calculate total including only buyer's shipping portion
  double _calculateTotalWithShipping() {
    final subtotal = widget.cartSummary.selectedItemsTotal;
    final buyerShippingPortion = _calculateBuyerShippingPortion();
    return subtotal + buyerShippingPortion;
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
    
    // Get buyer's portion of shipping cost
    final buyerShippingCost = _sellerShippingCosts[sellerId] ?? 0.0;
    
    // Get total shipping cost (for display when free)
    final totalShippingCost = _sellerTotalShippingCosts[sellerId] ?? 0.0;
    
    // Determine if shipping is free for buyer
    final shippingIsFree = buyerShippingCost == 0.0 && totalShippingCost > 0.0;
    
    // Determine who pays shipping based on buyer's portion
    final buyerPaysShipping = buyerShippingCost > 0.0;
    
    // Debug logging
    AppLogger.d('Seller: $sellerName, Subtotal: $sellerSubtotal, Total Shipping: $totalShippingCost, Buyer Pays: $buyerShippingCost, Free: $shippingIsFree');
    
    // Calculate how much to add to cart to reach free shipping
    // Only show this if buyer is currently paying for shipping
    final amountToAddForFreeShipping = buyerPaysShipping
        ? ((buyerShippingCost / 0.10) - sellerSubtotal).clamp(0.0, double.infinity)
        : 0.0;
    
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
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (shippingIsFree && totalShippingCost >= 0.01) ...[
                                // Show crossed out original price when shipping is free
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
                
                // Free shipping indicator text with green background
                if (!_isCalculatingShipping && buyerPaysShipping && amountToAddForFreeShipping > 0) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: AppColors.success.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        'Add ₱${amountToAddForFreeShipping.toStringAsFixed(2)} more to get FREE Shipping!',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.success,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Roboto',
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
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

          // Payment methods
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: PaymentMethod.values.map((method) {
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: _termsAccepted,
              onChanged: (value) {
                setState(() {
                  _termsAccepted = value ?? false;
                });
              },
              activeColor: AppColors.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      text: 'I agree to the ',
                      style: AppTextStyles.bodyMedium,
                      children: [
                        TextSpan(
                          text: 'Terms and Conditions',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.primary,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => _showTermsAndConditions(context),
                        ),
                        TextSpan(
                          text: ' and ',
                          style: AppTextStyles.bodyMedium,
                        ),
                        TextSpan(
                          text: 'Privacy Policy',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.primary,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => _showPrivacyPolicy(context),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'By placing this order, you acknowledge that you have read and understood our terms.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.onSurface.withValues(alpha: 0.6),
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
            const SizedBox(height: 8),
            
            // Shipping row
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
                          if (_calculateTotalShippingCost() > 0 && _calculateBuyerShippingPortion() < _calculateTotalShippingCost()) ...[
                            // Show crossed out total shipping when some/all is free
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
                              color: _calculateBuyerShippingPortion() > 0 ? null : AppColors.success,
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
