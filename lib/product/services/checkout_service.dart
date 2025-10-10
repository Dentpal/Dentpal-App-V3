import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:dentpal/utils/app_logger.dart';
import '../models/order_model.dart';
import '../models/paymongo_model.dart';
import '../models/cart_model.dart';
import '../../profile/models/shipping_address.dart';

class CheckoutService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get current user ID or throw error if not authenticated
  String _getCurrentUserId() {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }
    return user.uid;
  }

  // Create orders and checkout session using Paymongo's preferred checkout API
  Future<CreateOrderResponse> createOrderWithCheckoutSession({
    required List<String> cartItemIds,
    required String addressId,
    String? notes,
    List<String> paymentMethodTypes = const ['card', 'gcash', 'grab_pay', 'paymaya'],
    String? successUrl,
    String? cancelUrl,
  }) async {
    try {
      AppLogger.d('🛒 Creating order with checkout session for ${cartItemIds.length} items');

      // Get Firebase Auth token for authentication
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }
      
      final idToken = await user.getIdToken();

      final createCheckoutRequest = CreateCheckoutOrderRequest(
        cartItemIds: cartItemIds,
        addressId: addressId,
        notes: notes,
        paymentMethodTypes: paymentMethodTypes,
        successUrl: successUrl,
        cancelUrl: cancelUrl,
      );

      // Call Firebase Function via HTTP
      final response = await http.post(
        Uri.parse('https://us-central1-dentpal-161e5.cloudfunctions.net/createCheckoutSession'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: json.encode(createCheckoutRequest.toJson()),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to create checkout session: ${response.body}');
      }

      AppLogger.d('🐛 RAW Response body: ${response.body}');
      
      final responseData = json.decode(response.body) as Map<String, dynamic>;
      AppLogger.d('🐛 Parsed response data: $responseData');
      
      if (responseData['success'] != true) {
        throw Exception(responseData['error'] ?? 'Failed to create checkout session');
      }

      AppLogger.d('🐛 About to parse CreateOrderResponse from: ${responseData['data']}');
      final orderResponse = CreateOrderResponse.fromJson(responseData['data'] as Map<String, dynamic>);
      AppLogger.d('🐛 Successfully parsed CreateOrderResponse: ${orderResponse.toString()}');
      
      AppLogger.d('✅ Order created successfully with checkout session: ${orderResponse.checkoutSession?.id}');
      return orderResponse;

    } catch (e) {
      AppLogger.d('❌ Error creating order with checkout session: $e');
      rethrow;
    }
  }

  // Create orders and payment intent for selected cart items using HTTP calls (Legacy method)
  Future<CreateOrderResponse> createOrderWithPaymentIntent({
    required List<String> cartItemIds,
    required String addressId,
    String? notes,
    List<String> paymentMethodAllowed = const ['card', 'gcash', 'grab_pay', 'paymaya'],
  }) async {
    try {
      AppLogger.d('🛒 Creating order with payment intent for ${cartItemIds.length} items');

      // Get Firebase Auth token for authentication
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }
      
      final idToken = await user.getIdToken();

      final createOrderRequest = CreateOrderRequest(
        cartItemIds: cartItemIds,
        addressId: addressId,
        notes: notes,
        paymentMethodAllowed: paymentMethodAllowed,
      );

      // Call Firebase Function via HTTP
      final response = await http.post(
        Uri.parse('https://us-central1-dentpal-161e5.cloudfunctions.net/createPaymentIntent'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: json.encode(createOrderRequest.toJson()),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to create order: ${response.body}');
      }

      final responseData = json.decode(response.body) as Map<String, dynamic>;
      
      if (responseData['success'] != true) {
        throw Exception(responseData['error'] ?? 'Failed to create order');
      }

      final orderResponse = CreateOrderResponse.fromJson(responseData['data'] as Map<String, dynamic>);
      
      AppLogger.d('✅ Order created successfully with payment intent: ${orderResponse.paymentIntent?.id ?? "N/A"}');
      return orderResponse;

    } catch (e) {
      AppLogger.d('❌ Error creating order with payment intent: $e');
      rethrow;
    }
  }

  // Process payment using Paymongo (this would typically be handled by Paymongo SDK or web interface)
  Future<PaymentResult> processPayment({
    required String paymentIntentClientKey,
    required String paymentMethod,
    Map<String, dynamic>? paymentDetails,
  }) async {
    try {
      AppLogger.d('💳 Processing payment with method: $paymentMethod');

      // Note: In a real implementation, this would integrate with Paymongo's client SDK
      // For now, we'll simulate the payment process
      
      // The actual payment processing would happen on the client side using:
      // - Paymongo.js for web
      // - Native mobile SDKs for mobile
      // - WebView integration for Flutter apps
      
      // This method serves as a placeholder for payment processing logic
      // The actual payment confirmation will come through webhooks handled by Firebase Functions
      
      return PaymentResult.success(
        paymentIntentId: paymentIntentClientKey,
        paymentMethodId: paymentMethod,
        additionalData: paymentDetails,
      );

    } catch (e) {
      AppLogger.d('❌ Error processing payment: $e');
      return PaymentResult.failure(
        errorMessage: e.toString(),
        additionalData: {'payment_method': paymentMethod},
      );
    }
  }

  // Get order by ID using Firestore directly (for checkout verification purposes only)
  Future<Order?> getOrder(String orderId) async {
    try {
      AppLogger.d('📦 Fetching order: $orderId');

      final userId = _getCurrentUserId();
      final orderDoc = await _firestore.collection('Order').doc(orderId).get();
      
      if (!orderDoc.exists) {
        AppLogger.d('❌ Order not found: $orderId');
        return null;
      }

      final orderData = orderDoc.data() as Map<String, dynamic>;
      
      // Check if user is authorized to view this order
      final sellerIds = orderData['sellerIds'] as List<dynamic>?;
      if (orderData['userId'] != userId && 
          (sellerIds == null || !sellerIds.contains(userId))) {
        throw Exception('Not authorized to view this order');
      }
      
      return Order.fromFirestore(orderDoc);

    } catch (e) {
      AppLogger.d('❌ Error fetching order: $e');
      return null;
    }
  }

  // Calculate shipping cost (placeholder implementation)
  Future<double> calculateShippingCost({
    required List<CartItem> items,
    required ShippingAddress address,
  }) async {
    try {
      // Simple shipping calculation - in a real app, this might involve:
      // - Distance calculation
      // - Weight/size calculation
      // - Carrier API integration
      // - Different rates for different sellers
      // For now, return a fixed rate per seller
      final sellers = items.map((item) => item.sellerId).toSet();
      const shippingCostPerSeller = 50.0;
      
      return sellers.length * shippingCostPerSeller;

    } catch (e) {
      AppLogger.d('❌ Error calculating shipping cost: $e');
      return 50.0; // Default shipping cost
    }
  }

  // Validate checkout data before creating order
  Future<bool> validateCheckoutData({
    required List<CartItem> cartItems,
    required ShippingAddress address,
  }) async {
    try {
      // Validate cart items
      if (cartItems.isEmpty) {
        throw Exception('Cart is empty');
      }

      // Check if all items are still available
      for (final cartItem in cartItems) {
        final productDoc = await _firestore
            .collection('Product')
            .doc(cartItem.productId)
            .get();

        if (!productDoc.exists) {
          throw Exception('Product ${cartItem.productName} is no longer available');
        }

        final productData = productDoc.data() as Map<String, dynamic>;
        
        // Check if product is still active
        if (productData['isActive'] != true) {
          throw Exception('Product ${cartItem.productName} is no longer available');
        }

        // Check stock availability (if stock tracking is implemented)
        // This would depend on your product model structure
        if (productData['stock'] != null) {
          final availableStock = productData['stock'] as int;
          if (availableStock < cartItem.quantity) {
            throw Exception('Insufficient stock for ${cartItem.productName}');
          }
        }
      }

      // Validate address
      if (address.fullName.isEmpty ||
          address.addressLine1.isEmpty ||
          address.city.isEmpty ||
          address.state.isEmpty ||
          address.postalCode.isEmpty ||
          address.phoneNumber.isEmpty) {
        throw Exception('Incomplete shipping address');
      }

      return true;

    } catch (e) {
      AppLogger.d('❌ Checkout validation failed: $e');
      rethrow;
    }
  }

  // Get payment methods available for the user
  Future<List<PaymentMethod>> getAvailablePaymentMethods() async {
    try {
      // In a real app, this might depend on:
      // - User's location
      // - User's payment history
      // - Merchant configuration
      // - Available payment processors

      return [
        PaymentMethod.card,
        PaymentMethod.gcash,
        PaymentMethod.grabpay,
        PaymentMethod.paymaya,
      ];

    } catch (e) {
      AppLogger.d('❌ Error getting payment methods: $e');
      return [PaymentMethod.card]; // Fallback to card only
    }
  }

  // Verify payment status with Paymongo and update order if needed
  Future<bool> verifyPaymentStatus(String orderId) async {
    try {
      AppLogger.d('🔍 Verifying payment status for order: $orderId');

      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final idToken = await user.getIdToken();

      final response = await http.post(
        Uri.parse('https://us-central1-dentpal-161e5.cloudfunctions.net/verifyPaymentStatus'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: json.encode({
          'orderId': orderId,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to verify payment status: ${response.body}');
      }

      final responseData = json.decode(response.body) as Map<String, dynamic>;
      
      if (responseData['success'] != true) {
        throw Exception(responseData['error'] ?? 'Failed to verify payment status');
      }

      final data = responseData['data'] as Map<String, dynamic>;
      final paymentStatus = data['paymentStatus'] as String;
      final updatedStatus = data['status'] as String;

      AppLogger.d('✅ Payment verification complete - Status: $paymentStatus, Order Status: $updatedStatus');
      
      // Return true if payment was confirmed and order was updated
      return paymentStatus == 'paid' && updatedStatus == 'confirmed';

    } catch (e) {
      AppLogger.d('❌ Error verifying payment status: $e');
      rethrow;
    }
  }

  // Cancel order (if payment is still pending)
  Future<bool> cancelOrder(String orderId) async {
    try {
      AppLogger.d('❌ Cancelling order: $orderId');

      // Check if order exists and belongs to current user
      final order = await getOrder(orderId);
      if (order == null) {
        throw Exception('Order not found');
      }

      final userId = _getCurrentUserId();
      if (order.userId != userId) {
        throw Exception('Not authorized to cancel this order');
      }

      // Check if order can be cancelled (only if payment is pending)
      if (order.paymentInfo.status != PaymentStatus.pending) {
        throw Exception('Order cannot be cancelled. Payment has already been processed.');
      }

      // Update order status
      await _firestore.collection('Order').doc(orderId).update({
        'status': OrderStatus.cancelled.toString().split('.').last,
        'updatedAt': FieldValue.serverTimestamp(),
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': OrderStatus.cancelled.toString().split('.').last,
            'timestamp': FieldValue.serverTimestamp(),
            'note': 'Cancelled by customer',
          }
        ]),
      });

      AppLogger.d('✅ Order cancelled successfully');
      return true;

    } catch (e) {
      AppLogger.d('❌ Error cancelling order: $e');
      rethrow;
    }
  }
}
