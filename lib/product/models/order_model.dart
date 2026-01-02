// ignore_for_file: constant_identifier_names

import 'package:cloud_firestore/cloud_firestore.dart';
import 'cart_model.dart';
import 'package:dentpal/utils/app_logger.dart';

enum OrderStatus {
  pending,
  confirmed,
  to_ship,
  shipping,
  delivered,
  completed,
  cancelled,
  refunded,
  payment_failed,
  expired,
  failed_delivery,
  return_requested,
  return_approved,
  return_rejected,
  returned
}

enum PaymentStatus {
  pending,
  paid,
  failed,
  refunded,
  partially_refunded
}

enum PaymentMethod {
  card,
  gcash,
  grabpay,
  paymaya,
  billEase,
  cashOnDelivery
}

class Order {
  final String orderId;
  final String userId; // Changed from buyerId to userId for clarity
  final List<String> sellerIds; // Changed to array to support multiple sellers
  final List<OrderItem> items;
  final OrderSummary summary;
  final ShippingInfo shippingInfo;
  final PaymongoData paymongo; // Changed from paymentInfo to paymongo
  final OrderStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? notes;
  final List<OrderStatusUpdate> statusHistory;
  final String? checkoutSessionId;

  Order({
    required this.orderId,
    required this.userId,
    required this.sellerIds,
    required this.items,
    required this.summary,
    required this.shippingInfo,
    required this.paymongo,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.notes,
    required this.statusHistory,
    this.checkoutSessionId,
  });

  factory Order.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    AppLogger.d('Order.fromFirestore - Processing document: ${doc.id}');
    AppLogger.d('Order.fromFirestore - Raw data keys: ${data.keys.toList()}');
    
    try {
      // Parse basic fields
      final userId = data['userId'] ?? data['buyerId'] ?? '';
      AppLogger.d('Order.fromFirestore - userId: $userId');
      
      final sellerIds = List<String>.from(data['sellerIds'] ?? [data['sellerId'] ?? '']).where((id) => id.isNotEmpty).toList();
      AppLogger.d('Order.fromFirestore - sellerIds: $sellerIds');
      
      // Parse items
      AppLogger.d('Order.fromFirestore - Parsing items...');
      final items = (data['items'] as List<dynamic>?)
          ?.map((item) {
            AppLogger.d('Order.fromFirestore - Item data: $item');
            return OrderItem.fromMap(item as Map<String, dynamic>);
          })
          .toList() ?? [];
      AppLogger.d('Order.fromFirestore - Items parsed: ${items.length} items');
      
      // Parse summary
      AppLogger.d('Order.fromFirestore - Parsing summary...');
      AppLogger.d('Order.fromFirestore - Summary data: ${data['summary']}');
      final summary = OrderSummary.fromMap(data['summary'] as Map<String, dynamic>);
      
      // Parse shipping info
      AppLogger.d('Order.fromFirestore - Parsing shippingInfo...');
      AppLogger.d('Order.fromFirestore - ShippingInfo data: ${data['shippingInfo']}');
      final shippingInfo = ShippingInfo.fromMap(data['shippingInfo'] as Map<String, dynamic>);
      
      // Parse paymongo data (supports both new 'paymongo' and legacy 'paymentInfo' keys)
      AppLogger.d('Order.fromFirestore - Parsing paymongo...');
      final paymongoData = data['paymongo'] ?? data['paymentInfo'];
      AppLogger.d('Order.fromFirestore - Paymongo data: $paymongoData');
      final paymongo = PaymongoData.fromMap(paymongoData as Map<String, dynamic>);
      
      // Parse status
      AppLogger.d('Order.fromFirestore - Parsing status...');
      AppLogger.d('Order.fromFirestore - Status value: ${data['status']} (type: ${data['status'].runtimeType})');
      String statusString = (data['status']?.toString() ?? 'pending').replaceAll('-', '_');
      
      final status = OrderStatus.values.firstWhere(
        (e) => e.toString().split('.').last == statusString,
        orElse: () => OrderStatus.pending,
      );
      
      // Parse timestamps
      AppLogger.d('Order.fromFirestore - Parsing timestamps...');
      AppLogger.d('Order.fromFirestore - CreatedAt: ${data['createdAt']} (type: ${data['createdAt'].runtimeType})');
      AppLogger.d('Order.fromFirestore - UpdatedAt: ${data['updatedAt']} (type: ${data['updatedAt'].runtimeType})');
      final createdAt = (data['createdAt'] as Timestamp).toDate();
      final updatedAt = (data['updatedAt'] as Timestamp).toDate();
      
      // Parse status history
      AppLogger.d('Order.fromFirestore - Parsing statusHistory...');
      AppLogger.d('Order.fromFirestore - StatusHistory data: ${data['statusHistory']}');
      final statusHistory = (data['statusHistory'] as List<dynamic>?)
          ?.map((item) {
            AppLogger.d('Order.fromFirestore - StatusHistory item: $item');
            return OrderStatusUpdate.fromMap(item as Map<String, dynamic>);
          })
          .toList() ?? [];
      
      AppLogger.d('Order.fromFirestore - All parsing completed successfully');
      
      return Order(
        orderId: doc.id,
        userId: userId,
        sellerIds: sellerIds,
        items: items,
        summary: summary,
        shippingInfo: shippingInfo,
        paymongo: paymongo,
        status: status,
        createdAt: createdAt,
        updatedAt: updatedAt,
        notes: data['notes'],
        statusHistory: statusHistory,
        checkoutSessionId: data['checkoutSessionId'],
      );
    } catch (e, stackTrace) {
      AppLogger.d('Order.fromFirestore - Error occurred: $e');
      AppLogger.d('Order.fromFirestore - Stack trace: $stackTrace');
      AppLogger.d('Order.fromFirestore - Document data: $data');
      rethrow;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'sellerIds': sellerIds,
      'items': items.map((item) => item.toMap()).toList(),
      'summary': summary.toMap(),
      'shippingInfo': shippingInfo.toMap(),
      'paymongo': paymongo.toMap(),
      'status': status.toString().split('.').last,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'notes': notes,
      'statusHistory': statusHistory.map((update) => update.toMap()).toList(),
      'checkoutSessionId': checkoutSessionId, // Deprecated - kept for backward compatibility
    };
  }

  Order copyWith({
    String? orderId,
    String? userId,
    List<String>? sellerIds,
    List<OrderItem>? items,
    OrderSummary? summary,
    ShippingInfo? shippingInfo,
    PaymongoData? paymongo,
    OrderStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? notes,
    List<OrderStatusUpdate>? statusHistory,
    String? checkoutSessionId,
  }) {
    return Order(
      orderId: orderId ?? this.orderId,
      userId: userId ?? this.userId,
      sellerIds: sellerIds ?? this.sellerIds,
      items: items ?? this.items,
      summary: summary ?? this.summary,
      shippingInfo: shippingInfo ?? this.shippingInfo,
      paymongo: paymongo ?? this.paymongo,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      notes: notes ?? this.notes,
      statusHistory: statusHistory ?? this.statusHistory,
      checkoutSessionId: checkoutSessionId ?? this.checkoutSessionId,
    );
  }
}

class OrderItem {
  final String productId;
  final String productName;
  final String productImage;
  final double price;
  final int quantity;
  final String? variationId;
  final String? variationName;
  final String sellerId; // Added seller ID for each item
  final String sellerName; // Added seller name for each item

  OrderItem({
    required this.productId,
    required this.productName,
    required this.productImage,
    required this.price,
    required this.quantity,
    this.variationId,
    this.variationName,
    required this.sellerId,
    required this.sellerName,
  });

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    return OrderItem(
      productId: map['productId'] ?? '',
      productName: map['productName'] ?? '',
      productImage: map['productImage'] ?? '',
      price: (map['price'] ?? 0.0).toDouble(),
      quantity: map['quantity'] ?? 0,
      variationId: map['variationId'],
      variationName: map['variationName'],
      sellerId: map['sellerId'] ?? '',
      sellerName: map['sellerName'] ?? '',
    );
  }

  factory OrderItem.fromCartItem(CartItem cartItem, {required String sellerId, required String sellerName}) {
    return OrderItem(
      productId: cartItem.productId,
      productName: cartItem.productName ?? '',
      productImage: cartItem.productImage ?? '',
      price: cartItem.productPrice ?? 0.0,
      quantity: cartItem.quantity,
      variationId: cartItem.variationId,
      variationName: null, // TODO: Get variation name from product
      sellerId: sellerId,
      sellerName: sellerName,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'productName': productName,
      'productImage': productImage,
      'price': price,
      'quantity': quantity,
      'variationId': variationId,
      'variationName': variationName,
      'sellerId': sellerId,
      'sellerName': sellerName,
    };
  }

  double get total => price * quantity;
}

class OrderSummary {
  final double subtotal;
  final double shippingCost;
  final double taxAmount;
  final double discountAmount;
  final double total;
  final int totalItems;
  final double sellerShippingCharge; // Amount charged to seller
  final double buyerShippingCharge; // Amount charged to buyer

  OrderSummary({
    required this.subtotal,
    required this.shippingCost,
    required this.taxAmount,
    required this.discountAmount,
    required this.total,
    required this.totalItems,
    this.sellerShippingCharge = 0.0,
    this.buyerShippingCharge = 0.0,
  });

  factory OrderSummary.fromMap(Map<String, dynamic> map) {
    return OrderSummary(
      subtotal: (map['subtotal'] ?? 0.0).toDouble(),
      shippingCost: (map['shippingCost'] ?? 0.0).toDouble(),
      taxAmount: (map['taxAmount'] ?? 0.0).toDouble(),
      discountAmount: (map['discountAmount'] ?? 0.0).toDouble(),
      total: (map['total'] ?? 0.0).toDouble(),
      totalItems: map['totalItems'] ?? 0,
      sellerShippingCharge: (map['sellerShippingCharge'] ?? 0.0).toDouble(),
      buyerShippingCharge: (map['buyerShippingCharge'] ?? 0.0).toDouble(),
    );
  }

  factory OrderSummary.fromCartSummary(CartSummary cartSummary) {
    return OrderSummary(
      subtotal: cartSummary.selectedItemsTotal,
      shippingCost: cartSummary.totalShippingCost,
      taxAmount: 0.0, // TODO: Add tax calculation
      discountAmount: 0.0,
      total: cartSummary.grandTotal,
      totalItems: cartSummary.selectedItemsCount,
      sellerShippingCharge: 0.0, // Will be calculated during checkout
      buyerShippingCharge: 0.0, // Will be calculated during checkout
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'subtotal': subtotal,
      'shippingCost': shippingCost,
      'taxAmount': taxAmount,
      'discountAmount': discountAmount,
      'total': total,
      'totalItems': totalItems,
      'sellerShippingCharge': sellerShippingCharge,
      'buyerShippingCharge': buyerShippingCharge,
    };
  }
}

class ShippingInfo {
  final String addressId;
  final String fullName;
  final String addressLine1;
  final String? addressLine2;
  final String city;
  final String state;
  final String postalCode;
  final String country;
  final String phoneNumber;
  final String? notes;
  final String? trackingId; // JRS tracking ID

  ShippingInfo({
    required this.addressId,
    required this.fullName,
    required this.addressLine1,
    this.addressLine2,
    required this.city,
    required this.state,
    required this.postalCode,
    required this.country,
    required this.phoneNumber,
    this.notes,
    this.trackingId,
  });

  factory ShippingInfo.fromMap(Map<String, dynamic> map) {
    return ShippingInfo(
      addressId: map['addressId'] ?? '',
      fullName: map['fullName'] ?? '',
      addressLine1: map['addressLine1'] ?? '',
      addressLine2: map['addressLine2'],
      city: map['city'] ?? '',
      state: map['state'] ?? '',
      postalCode: map['postalCode'] ?? '',
      country: map['country'] ?? '',
      phoneNumber: map['phoneNumber'] ?? '',
      notes: map['notes'],
      trackingId: map['trackingId'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'addressId': addressId,
      'fullName': fullName,
      'addressLine1': addressLine1,
      'addressLine2': addressLine2,
      'city': city,
      'state': state,
      'postalCode': postalCode,
      'country': country,
      'phoneNumber': phoneNumber,
      'notes': notes,
      'trackingId': trackingId,
    };
  }

  String get formattedAddress {
    final parts = [
      addressLine1,
      if (addressLine2?.isNotEmpty == true) addressLine2,
      city,
      state,
      postalCode,
      country,
    ];
    return parts.join(', ');
  }
}

class PaymongoData {
  final String? paymentId; // Payment ID (pay_xxx) - Required for refunds
  final String? paymentIntentId; // Payment Intent ID (pi_xxx) - For reference
  final String? checkoutSessionId; // Paymongo checkout session ID
  final String? checkoutUrl; // PayMongo checkout URL
  final PaymentMethod paymentMethod; // Changed from 'method' to 'paymentMethod'
  final PaymentStatus paymentStatus; // Changed from 'status' to 'paymentStatus'
  final double amount;
  final String currency;
  final DateTime? paidAt;
  final String? failureReason;

  PaymongoData({
    this.paymentId,
    this.paymentIntentId,
    this.checkoutSessionId,
    this.checkoutUrl,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.amount,
    required this.currency,
    this.paidAt,
    this.failureReason,
  });

  factory PaymongoData.fromMap(Map<String, dynamic> map) {
    AppLogger.d('PaymongoData.fromMap - Raw map: $map');
    
    try {
      // Handle paidAt timestamp conversion
      DateTime? paidAt;
      final paidAtValue = map['paidAt'];
      AppLogger.d('PaymongoData.fromMap - paidAt value: $paidAtValue (type: ${paidAtValue.runtimeType})');
      
      if (paidAtValue != null) {
        if (paidAtValue is Timestamp) {
          paidAt = paidAtValue.toDate();
        } else if (paidAtValue is int) {
          paidAt = DateTime.fromMillisecondsSinceEpoch(paidAtValue);
        } else if (paidAtValue is double) {
          paidAt = DateTime.fromMillisecondsSinceEpoch(paidAtValue.toInt());
        } else if (paidAtValue is String) {
          paidAt = DateTime.parse(paidAtValue);
        }
      }

      // Parse paymentMethod enum (supports both 'method' and 'paymentMethod' keys for backward compatibility)
      final methodValue = map['paymentMethod'] ?? map['method'];
      AppLogger.d('PaymongoData.fromMap - paymentMethod value: $methodValue (type: ${methodValue.runtimeType})');
      final paymentMethod = PaymentMethod.values.firstWhere(
        (e) => e.toString().split('.').last == (methodValue?.toString() ?? 'card'),
        orElse: () => PaymentMethod.card,
      );

      // Parse paymentStatus enum (supports both 'status' and 'paymentStatus' keys for backward compatibility)
      final statusValue = map['paymentStatus'] ?? map['status'];
      AppLogger.d('PaymongoData.fromMap - paymentStatus value: $statusValue (type: ${statusValue.runtimeType})');
      final paymentStatus = PaymentStatus.values.firstWhere(
        (e) => e.toString().split('.').last == (statusValue?.toString() ?? 'pending'),
        orElse: () => PaymentStatus.pending,
      );

      AppLogger.d('PaymongoData.fromMap - Parsing completed successfully');
      
      return PaymongoData(
        paymentId: map['paymentId'], // Payment ID for refunds
        paymentIntentId: map['paymentIntentId'], // Payment Intent ID for reference
        checkoutSessionId: map['checkoutSessionId'],
        checkoutUrl: map['checkoutUrl'],
        paymentMethod: paymentMethod,
        paymentStatus: paymentStatus,
        amount: (map['amount'] ?? 0.0).toDouble(),
        currency: map['currency'] ?? 'PHP',
        paidAt: paidAt,
        failureReason: map['failureReason'],
      );
    } catch (e, stackTrace) {
      AppLogger.d('PaymongoData.fromMap - Error occurred: $e');
      AppLogger.d('PaymongoData.fromMap - Stack trace: $stackTrace');
      AppLogger.d('PaymongoData.fromMap - Input map: $map');
      rethrow;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'paymentId': paymentId, // Payment ID for refunds
      'paymentIntentId': paymentIntentId, // Payment Intent ID for reference
      'checkoutSessionId': checkoutSessionId,
      'checkoutUrl': checkoutUrl,
      'paymentMethod': paymentMethod.toString().split('.').last,
      'paymentStatus': paymentStatus.toString().split('.').last,
      'amount': amount,
      'currency': currency,
      'paidAt': paidAt != null ? Timestamp.fromDate(paidAt!) : null,
      'failureReason': failureReason,
    };
  }
}

class OrderStatusUpdate {
  final OrderStatus status;
  final DateTime timestamp;
  final String? note;
  final String? updatedBy;

  OrderStatusUpdate({
    required this.status,
    required this.timestamp,
    this.note,
    this.updatedBy,
  });

  factory OrderStatusUpdate.fromMap(Map<String, dynamic> map) {
    AppLogger.d('OrderStatusUpdate.fromMap - Raw map: $map');
    
    try {
      // Handle both Firestore Timestamp and Unix timestamp (from Firebase Functions)
      DateTime timestamp;
      final timestampValue = map['timestamp'];
      AppLogger.d('OrderStatusUpdate.fromMap - timestamp value: $timestampValue (type: ${timestampValue.runtimeType})');
      
      if (timestampValue is Timestamp) {
        timestamp = timestampValue.toDate();
      } else if (timestampValue is int) {
        timestamp = DateTime.fromMillisecondsSinceEpoch(timestampValue);
      } else if (timestampValue is double) {
        timestamp = DateTime.fromMillisecondsSinceEpoch(timestampValue.toInt());
      } else if (timestampValue is String) {
        timestamp = DateTime.parse(timestampValue);
      } else {
        AppLogger.d('OrderStatusUpdate.fromMap - Unexpected timestamp type, using current time');
        timestamp = DateTime.now(); // Fallback
      }

      // Parse status enum
      final statusValue = map['status'];
      AppLogger.d('OrderStatusUpdate.fromMap - status value: $statusValue (type: ${statusValue.runtimeType})');
      String statusString = (statusValue?.toString() ?? 'pending').replaceAll('-', '_');
      
      // Handle specific case for to_hand_over -> to_ship (normalize to existing enum value)
      if (statusString == 'to_hand_over') {
        statusString = 'to_ship';
      }
      
      final status = OrderStatus.values.firstWhere(
        (e) => e.toString().split('.').last == statusString,
        orElse: () => OrderStatus.pending,
      );

      AppLogger.d('OrderStatusUpdate.fromMap - Parsing completed successfully');

      return OrderStatusUpdate(
        status: status,
        timestamp: timestamp,
        note: map['note'],
        updatedBy: map['updatedBy'],
      );
    } catch (e, stackTrace) {
      AppLogger.d('OrderStatusUpdate.fromMap - Error occurred: $e');
      AppLogger.d('OrderStatusUpdate.fromMap - Stack trace: $stackTrace');
      AppLogger.d('OrderStatusUpdate.fromMap - Input map: $map');
      rethrow;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'status': status.toString().split('.').last,
      'timestamp': Timestamp.fromDate(timestamp),
      'note': note,
      'updatedBy': updatedBy,
    };
  }
}

// Extension methods for display
extension OrderStatusExtension on OrderStatus {
  String get displayName {
    switch (this) {
      case OrderStatus.pending:
        return 'Pending Payment';
      case OrderStatus.confirmed:
        return 'Payment Confirmed';
      case OrderStatus.to_ship:
        return 'Ready to Ship';
      case OrderStatus.shipping:
        return 'Shipping';
      case OrderStatus.delivered:
        return 'Delivered';
      case OrderStatus.completed:
        return 'Completed';
      case OrderStatus.cancelled:
        return 'Cancelled';
      case OrderStatus.refunded:
        return 'Refunded';
      case OrderStatus.payment_failed:
        return 'Payment Failed';
      case OrderStatus.expired:
        return 'Expired Payment';
      case OrderStatus.failed_delivery:
        return 'Failed Delivery';
      case OrderStatus.return_requested:
        return 'Return Requested';
      case OrderStatus.return_approved:
        return 'Return Approved';
      case OrderStatus.return_rejected:
        return 'Return Rejected';
      case OrderStatus.returned:
        return 'Returned';
    }
  }

  String get description {
    switch (this) {
      case OrderStatus.pending:
        return 'Order has been placed and is awaiting confirmation';
      case OrderStatus.confirmed:
        return 'Payment confirmed, order is being processed';
      case OrderStatus.to_ship:
        return 'Order is being prepared for shipment';
      case OrderStatus.shipping:
        return 'Order has been shipped and is on its way';
      case OrderStatus.delivered:
        return 'Order has been delivered';
      case OrderStatus.completed:
        return 'Order has been completed successfully';
      case OrderStatus.cancelled:
        return 'Order has been cancelled';
      case OrderStatus.refunded:
        return 'Order has been refunded';
      case OrderStatus.payment_failed:
        return 'Payment failed for this order';
      case OrderStatus.expired:
        return 'Payment expired due to timeout';
      case OrderStatus.failed_delivery:
        return 'Delivery attempt failed';
      case OrderStatus.return_requested:
        return 'Return has been requested by the customer';
      case OrderStatus.return_approved:
        return 'Return request has been approved';
      case OrderStatus.return_rejected:
        return 'Return request has been rejected';
      case OrderStatus.returned:
        return 'Order has been returned';
    }
  }
}

extension PaymentStatusExtension on PaymentStatus {
  String get displayName {
    switch (this) {
      case PaymentStatus.pending:
        return 'Pending';
      case PaymentStatus.paid:
        return 'Paid';
      case PaymentStatus.failed:
        return 'Failed';
      case PaymentStatus.refunded:
        return 'Refunded';
      case PaymentStatus.partially_refunded:
        return 'Partially Refunded';
    }
  }
}

extension PaymentMethodExtension on PaymentMethod {
  String get displayName {
    switch (this) {
      case PaymentMethod.card:
        return 'Credit/Debit Card';
      case PaymentMethod.gcash:
        return 'GCash';
      case PaymentMethod.grabpay:
        return 'Grab Pay';
      case PaymentMethod.paymaya:
        return 'PayMaya';
      case PaymentMethod.billEase:
        return 'BillEase (Buy Now Pay Later)';
      case PaymentMethod.cashOnDelivery:
        return 'Cash on Delivery';
    }
  }

  String get paymongoType {
    switch (this) {
      case PaymentMethod.card:
        return 'card';
      case PaymentMethod.gcash:
        return 'gcash';
      case PaymentMethod.grabpay:
        return 'grab_pay';
      case PaymentMethod.paymaya:
        return 'paymaya';
      case PaymentMethod.billEase:
        return 'Buy Now, Pay Later (BillEase)';
      case PaymentMethod.cashOnDelivery:
        return 'cash_on_delivery'; // Not used for PayMongo but provided for consistency
    }
  }
}
