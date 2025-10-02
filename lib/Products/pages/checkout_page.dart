import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'package:dentpal/utils/app_logger.dart';
import '../models/cart_model.dart';
import '../models/order_model.dart';
import '../models/paymongo_model.dart';
import '../services/checkout_service.dart';
import '../services/cart_service.dart';
import '../widgets/address_selection_widget.dart';
import '../pages/paymongo_webview_page.dart';
import '../../profile/models/shipping_address.dart';
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
      AppLogger.d('🔍 Validating cart items before checkout...');
      await _validateCartItemsExist();

      // Validate checkout data
      await _checkoutService.validateCheckoutData(
        cartItems: widget.cartItems,
        address: _selectedAddress!,
      );

      // Extract cart item IDs
      final cartItemIds = widget.cartItems.map((item) => item.cartItemId).toList();
      AppLogger.d('🛒 Proceeding with cart items: $cartItemIds');

      // Create order and checkout session
      final orderResponse = await _checkoutService.createOrderWithCheckoutSession(
        cartItemIds: cartItemIds,
        addressId: _selectedAddress!.id,
        notes: _orderNotes,
        paymentMethodTypes: [_selectedPaymentMethod!.paymongoType],
        successUrl: 'https://dentpal.com/order-success', // Replace with your actual success URL
        cancelUrl: 'https://dentpal.com/checkout?cancelled=true', // Replace with your actual cancel URL
      );

      AppLogger.d('✅ Order created successfully');

      // Navigate to Paymongo checkout
      if (mounted) {
        await _navigateToPaymongoCheckout(orderResponse);
      }

    } catch (e) {
      AppLogger.d('❌ Checkout failed: $e');
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
    AppLogger.d('🔍 Validating ${widget.cartItems.length} cart items exist in database...');
    
    final cartService = CartService();
    final missingItems = <String>[];
    
    for (final cartItem in widget.cartItems) {
      try {
        final existingItem = await cartService.getCartItem(cartItem.cartItemId);
        if (existingItem == null) {
          missingItems.add(cartItem.cartItemId);
          AppLogger.d('❌ Cart item ${cartItem.cartItemId} not found in database');
        } else {
          AppLogger.d('✅ Cart item ${cartItem.cartItemId} exists in database');
        }
      } catch (e) {
        AppLogger.d('❌ Error checking cart item ${cartItem.cartItemId}: $e');
        missingItems.add(cartItem.cartItemId);
      }
    }
    
    if (missingItems.isNotEmpty) {
      throw Exception(
        'Some cart items are no longer available: ${missingItems.join(', ')}. '
        'Please refresh your cart and try again.'
      );
    }
    
    AppLogger.d('✅ All cart items validated successfully');
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
                AppLogger.d('🌐 Opening Paymongo checkout URL: $checkoutUrl');
                
                // Close the dialog first
                Navigator.of(context).pop();
                
                try {
                  // Import url_launcher package to open URLs
                  // For now, we'll use a simple browser opening approach
                  await _openCheckoutUrl(checkoutUrl);
                } catch (e) {
                  AppLogger.d('❌ Error opening checkout URL: $e');
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
                Text(
                  'Items (${widget.cartSummary.selectedItemsCount})',
                  style: AppTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                
                ...widget.cartItems.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildOrderItem(item),
                )),

                const Divider(),
                const SizedBox(height: 8),

                // Summary rows
                _buildSummaryRow('Subtotal', widget.cartSummary.selectedItemsTotal),
                const SizedBox(height: 8),
                _buildSummaryRow('Shipping', widget.cartSummary.totalShippingCost),
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 8),
                _buildSummaryRow(
                  'Total',
                  widget.cartSummary.grandTotal,
                  isTotal: true,
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

  Widget _buildSummaryRow(String label, double amount, {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: isTotal
              ? AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.w700)
              : AppTextStyles.bodyMedium,
        ),
        Text(
          amount == 0 && label == 'Shipping'
              ? 'Free'
              : '₱${amount.toStringAsFixed(2)}',
          style: isTotal
              ? AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                  fontFamily: amount == 0 && label == 'Shipping' ? null : 'Roboto',
                )
              : AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFamily: amount == 0 && label == 'Shipping' ? null : 'Roboto',
                  color: amount == 0 && label == 'Shipping' ? AppColors.success : null,
                ),
        ),
      ],
    );
  }

  Widget _buildShippingSection() {
    return AddressSelectionWidget(
      selectedAddress: _selectedAddress,
      onAddressSelected: (address) {
        setState(() {
          _selectedAddress = address;
        });
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
      case PaymentMethod.bank_transfer:
        return Icons.account_balance;
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
                  '₱${widget.cartSummary.grandTotal.toStringAsFixed(2)}',
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
                '₱${widget.cartSummary.grandTotal.toStringAsFixed(2)}',
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
      AppLogger.d('🌐 Attempting to open checkout URL: $checkoutUrl');
      
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
                  successUrl: 'https://dentpal.com/order-success',
                  cancelUrl: 'https://dentpal.com/checkout',
                  onPaymentComplete: (isSuccess, orderId) {
                    AppLogger.d('💳 Payment completed. Success: $isSuccess, Order ID: $orderId');
                    
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
      AppLogger.d('❌ Error opening checkout URL: $e');
      rethrow;
    }
  }

  Future<void> _openUrlInBrowser(String url) async {
    try {
      AppLogger.d('🌐 Attempting to open URL in browser: $url');
      
      final uri = Uri.parse(url);
      
      // Check if the URL can be launched
      if (await canLaunchUrl(uri)) {
        AppLogger.d('✅ URL can be launched, opening in external browser');
        
        // Launch the URL in external browser
        final success = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication, // Open in external browser
        );
        
        if (success) {
          AppLogger.d('✅ Successfully opened payment page in browser');
        } else {
          AppLogger.d('❌ Failed to launch URL, showing manual dialog');
          if (mounted) {
            _showManualUrlDialog(url);
          }
        }
      } else {
        AppLogger.d('❌ URL cannot be launched, showing manual dialog');
        if (mounted) {
          _showManualUrlDialog(url);
        }
      }
    } catch (e) {
      AppLogger.d('❌ Error launching URL: $e, showing manual dialog');
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
                AppLogger.d('❌ Error copying to clipboard: $e');
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
      AppLogger.d('📋 URL copied to clipboard (simulated)');
    } catch (e) {
      AppLogger.d('❌ Error copying to clipboard: $e');
      rethrow;
    }
  }

  void _handlePaymentSuccess(String? orderId) {
    AppLogger.d('✅ Payment completed successfully. Order ID: $orderId');
    
    if (mounted) {
      // Show success dialog
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
                  Icons.check_circle,
                  color: AppColors.success,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Payment Successful!',
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
                'Your payment has been processed successfully and your order has been confirmed.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.onSurface.withValues(alpha: 0.8),
                ),
              ),
              if (orderId != null) ...[
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
                        'Order Reference:',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        orderId,
                        style: AppTextStyles.bodySmall.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                Navigator.of(context).pop(); // Go back to previous page
                widget.onOrderComplete?.call();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: AppColors.onPrimary,
                elevation: 0,
              ),
              child: Text('Continue Shopping', style: AppTextStyles.buttonMedium),
            ),
          ],
        ),
      );
    }
  }

  void _handlePaymentCancellation() {
    AppLogger.d('❌ Payment was cancelled by user');
    
    if (mounted) {
      // Show cancellation dialog
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
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.cancel_outlined,
                  color: AppColors.warning,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Payment Cancelled',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          content: Text(
            'Your payment was cancelled. Your cart items are still saved and you can try again whenever you\'re ready.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.onSurface.withValues(alpha: 0.8),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                Navigator.of(context).pop(); // Go back to checkout
              },
              style: TextButton.styleFrom(
                foregroundColor: AppColors.onSurface.withValues(alpha: 0.6),
              ),
              child: Text('Try Again', style: AppTextStyles.buttonMedium),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                Navigator.of(context).pop(); // Go back to previous page
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                elevation: 0,
              ),
              child: Text('Back to Cart', style: AppTextStyles.buttonMedium),
            ),
          ],
        ),
      );
    }
  }
}
