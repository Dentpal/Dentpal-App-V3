// Paymongo Payment Intent response model
class PaymongoPaymentIntent {
  final String id;
  final String type;
  final PaymongoPaymentIntentAttributes attributes;

  PaymongoPaymentIntent({
    required this.id,
    required this.type,
    required this.attributes,
  });

  factory PaymongoPaymentIntent.fromJson(Map<String, dynamic> json) {
    return PaymongoPaymentIntent(
      id: json['id'] ?? '',
      type: json['type'] ?? '',
      attributes: PaymongoPaymentIntentAttributes.fromJson(
        json['attributes'] as Map<String, dynamic>,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'attributes': attributes.toJson(),
    };
  }
}

// Paymongo Checkout Session response model  
class PaymongoCheckoutSession {
  final String id;
  final String type;
  final PaymongoCheckoutSessionAttributes attributes;

  PaymongoCheckoutSession({
    required this.id,
    required this.type,
    required this.attributes,
  });

  factory PaymongoCheckoutSession.fromJson(Map<String, dynamic> json) {
    print('🐛 PaymongoCheckoutSession.fromJson - Raw JSON: $json');
    
    try {
      final id = json['id'] ?? '';
      final type = json['type'] ?? '';
      print('🐛 PaymongoCheckoutSession.fromJson - id: $id, type: $type');
      
      print('🐛 PaymongoCheckoutSession.fromJson - About to parse attributes...');
      final attributes = PaymongoCheckoutSessionAttributes.fromJson(
        json['attributes'] as Map<String, dynamic>,
      );
      print('🐛 PaymongoCheckoutSession.fromJson - Successfully parsed attributes');
      
      return PaymongoCheckoutSession(
        id: id,
        type: type,
        attributes: attributes,
      );
    } catch (e, stackTrace) {
      print('🐛 ❌ PaymongoCheckoutSession.fromJson - Error occurred: $e');
      print('🐛 ❌ PaymongoCheckoutSession.fromJson - Stack trace: $stackTrace');
      print('🐛 ❌ PaymongoCheckoutSession.fromJson - Input JSON: $json');
      rethrow;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'attributes': attributes.toJson(),
    };
  }
}

class PaymongoCheckoutSessionAttributes {
  final String checkoutUrl;
  final String referenceNumber;
  final String status;
  final DateTime? expiresAt;
  final Map<String, dynamic>? metadata;
  final PaymongoCheckoutBilling? billing;
  final List<PaymongoLineItem> lineItems;
  final List<String> paymentMethodTypes;
  final String? successUrl;
  final String? cancelUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  PaymongoCheckoutSessionAttributes({
    required this.checkoutUrl,
    required this.referenceNumber,
    required this.status,
    this.expiresAt,
    this.metadata,
    this.billing,
    required this.lineItems,
    required this.paymentMethodTypes,
    this.successUrl,
    this.cancelUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PaymongoCheckoutSessionAttributes.fromJson(Map<String, dynamic> json) {
    print('🐛 PaymongoCheckoutSessionAttributes.fromJson - Raw JSON: $json');
    
    try {
      // Parse basic string fields
      final checkoutUrl = json['checkout_url'] ?? '';
      final referenceNumber = json['reference_number'] ?? '';
      final status = json['status'] ?? '';
      print('🐛 PaymongoCheckoutSessionAttributes.fromJson - Basic fields parsed');
      
      // Parse expires_at
      DateTime? expiresAt;
      final expiresAtValue = json['expires_at'];
      print('🐛 PaymongoCheckoutSessionAttributes.fromJson - expires_at: $expiresAtValue (type: ${expiresAtValue.runtimeType})');
      if (expiresAtValue != null) {
        if (expiresAtValue is int) {
          expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresAtValue * 1000);
        } else if (expiresAtValue is String) {
          expiresAt = DateTime.parse(expiresAtValue);
        }
      }
      
      // Parse metadata
      final metadata = json['metadata'];
      print('🐛 PaymongoCheckoutSessionAttributes.fromJson - metadata: $metadata');
      
      // Parse billing
      PaymongoCheckoutBilling? billing;
      final billingData = json['billing'];
      print('🐛 PaymongoCheckoutSessionAttributes.fromJson - billing data: $billingData');
      if (billingData != null) {
        billing = PaymongoCheckoutBilling.fromJson(billingData as Map<String, dynamic>);
      }
      
      // Parse line_items
      final lineItemsData = json['line_items'] as List<dynamic>?;
      print('🐛 PaymongoCheckoutSessionAttributes.fromJson - line_items: $lineItemsData');
      final lineItems = lineItemsData?.map((item) => PaymongoLineItem.fromJson(item as Map<String, dynamic>)).toList() ?? [];
      
      // Parse payment_method_types
      final paymentMethodTypes = List<String>.from(json['payment_method_types'] ?? []);
      print('🐛 PaymongoCheckoutSessionAttributes.fromJson - payment_method_types: $paymentMethodTypes');
      
      // Parse URLs
      final successUrl = json['success_url'];
      final cancelUrl = json['cancel_url'];
      print('🐛 PaymongoCheckoutSessionAttributes.fromJson - URLs parsed');
      
      // Parse created_at
      final createdAtValue = json['created_at'];
      print('🐛 PaymongoCheckoutSessionAttributes.fromJson - created_at: $createdAtValue (type: ${createdAtValue.runtimeType})');
      DateTime createdAt;
      if (createdAtValue is int) {
        createdAt = DateTime.fromMillisecondsSinceEpoch(createdAtValue * 1000);
      } else if (createdAtValue is String) {
        createdAt = DateTime.parse(createdAtValue);
      } else {
        throw Exception('Invalid created_at format: $createdAtValue');
      }
      
      // Parse updated_at
      final updatedAtValue = json['updated_at'];
      print('🐛 PaymongoCheckoutSessionAttributes.fromJson - updated_at: $updatedAtValue (type: ${updatedAtValue.runtimeType})');
      DateTime updatedAt;
      if (updatedAtValue is int) {
        updatedAt = DateTime.fromMillisecondsSinceEpoch(updatedAtValue * 1000);
      } else if (updatedAtValue is String) {
        updatedAt = DateTime.parse(updatedAtValue);
      } else {
        throw Exception('Invalid updated_at format: $updatedAtValue');
      }
      
      print('🐛 PaymongoCheckoutSessionAttributes.fromJson - All fields parsed successfully');
      
      return PaymongoCheckoutSessionAttributes(
        checkoutUrl: checkoutUrl,
        referenceNumber: referenceNumber,
        status: status,
        expiresAt: expiresAt,
        metadata: metadata,
        billing: billing,
        lineItems: lineItems,
        paymentMethodTypes: paymentMethodTypes,
        successUrl: successUrl,
        cancelUrl: cancelUrl,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
    } catch (e, stackTrace) {
      print('🐛 ❌ PaymongoCheckoutSessionAttributes.fromJson - Error occurred: $e');
      print('🐛 ❌ PaymongoCheckoutSessionAttributes.fromJson - Stack trace: $stackTrace');
      print('🐛 ❌ PaymongoCheckoutSessionAttributes.fromJson - Input JSON: $json');
      rethrow;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'checkout_url': checkoutUrl,
      'reference_number': referenceNumber,
      'status': status,
      'expires_at': expiresAt?.toIso8601String(),
      'metadata': metadata,
      'billing': billing?.toJson(),
      'line_items': lineItems.map((item) => item.toJson()).toList(),
      'payment_method_types': paymentMethodTypes,
      'success_url': successUrl,
      'cancel_url': cancelUrl,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class PaymongoCheckoutBilling {
  final String? name;
  final String? email;
  final String? phone;
  final PaymongoAddress? address;

  PaymongoCheckoutBilling({
    this.name,
    this.email,
    this.phone,
    this.address,
  });

  factory PaymongoCheckoutBilling.fromJson(Map<String, dynamic> json) {
    return PaymongoCheckoutBilling(
      name: json['name'],
      email: json['email'],
      phone: json['phone'],
      address: json['address'] != null 
          ? PaymongoAddress.fromJson(json['address'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'address': address?.toJson(),
    };
  }
}

class PaymongoAddress {
  final String? line1;
  final String? line2;
  final String? city;
  final String? state;
  final String? postalCode;
  final String? country;

  PaymongoAddress({
    this.line1,
    this.line2,
    this.city,
    this.state,
    this.postalCode,
    this.country,
  });

  factory PaymongoAddress.fromJson(Map<String, dynamic> json) {
    return PaymongoAddress(
      line1: json['line1'],
      line2: json['line2'],
      city: json['city'],
      state: json['state'],
      postalCode: json['postal_code'],
      country: json['country'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'line1': line1,
      'line2': line2,
      'city': city,
      'state': state,
      'postal_code': postalCode,
      'country': country,
    };
  }
}

class PaymongoLineItem {
  final String name;
  final int quantity;
  final int amount;
  final String currency;
  final String? description;
  final List<String>? images;

  PaymongoLineItem({
    required this.name,
    required this.quantity,
    required this.amount,
    this.currency = 'PHP',
    this.description,
    this.images,
  });

  factory PaymongoLineItem.fromJson(Map<String, dynamic> json) {
    return PaymongoLineItem(
      name: json['name'] ?? '',
      quantity: json['quantity'] ?? 1,
      amount: json['amount'] ?? 0,
      currency: json['currency'] ?? 'PHP',
      description: json['description'],
      images: json['images'] != null ? List<String>.from(json['images']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'quantity': quantity,
      'amount': amount,
      'currency': currency,
      'description': description,
      'images': images,
    };
  }
}

class PaymongoPaymentIntentAttributes {
  final int amount;
  final String currency;
  final String description;
  final String status;
  final String? clientKey;
  final List<String> paymentMethodAllowed;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  PaymongoPaymentIntentAttributes({
    required this.amount,
    required this.currency,
    required this.description,
    required this.status,
    this.clientKey,
    required this.paymentMethodAllowed,
    this.metadata,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PaymongoPaymentIntentAttributes.fromJson(Map<String, dynamic> json) {
    return PaymongoPaymentIntentAttributes(
      amount: json['amount'] ?? 0,
      currency: json['currency'] ?? 'PHP',
      description: json['description'] ?? '',
      status: json['status'] ?? '',
      clientKey: json['client_key'],
      paymentMethodAllowed: List<String>.from(json['payment_method_allowed'] ?? []),
      metadata: json['metadata'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'amount': amount,
      'currency': currency,
      'description': description,
      'status': status,
      'client_key': clientKey,
      'payment_method_allowed': paymentMethodAllowed,
      'metadata': metadata,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

// Payment Intent creation request model
class CreatePaymentIntentRequest {
  final double amount;
  final String currency;
  final String description;
  final List<String> paymentMethodAllowed;
  final Map<String, dynamic>? metadata;
  final String? orderId;
  final String? buyerId;

  CreatePaymentIntentRequest({
    required this.amount,
    this.currency = 'PHP',
    required this.description,
    required this.paymentMethodAllowed,
    this.metadata,
    this.orderId,
    this.buyerId,
  });

  Map<String, dynamic> toJson() {
    return {
      'amount': (amount * 100).round(), // Convert to centavos
      'currency': currency,
      'description': description,
      'payment_method_allowed': paymentMethodAllowed,
      'metadata': {
        ...?metadata,
        if (orderId != null) 'order_id': orderId,
        if (buyerId != null) 'buyer_id': buyerId,
      },
    };
  }
}

// Paymongo Webhook event model
class PaymongoWebhookEvent {
  final String id;
  final String type;
  final PaymongoWebhookEventData data;
  final DateTime createdAt;

  PaymongoWebhookEvent({
    required this.id,
    required this.type,
    required this.data,
    required this.createdAt,
  });

  factory PaymongoWebhookEvent.fromJson(Map<String, dynamic> json) {
    return PaymongoWebhookEvent(
      id: json['id'] ?? '',
      type: json['type'] ?? '',
      data: PaymongoWebhookEventData.fromJson(
        json['data'] as Map<String, dynamic>,
      ),
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'data': data.toJson(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class PaymongoWebhookEventData {
  final String id;
  final String type;
  final Map<String, dynamic> attributes;

  PaymongoWebhookEventData({
    required this.id,
    required this.type,
    required this.attributes,
  });

  factory PaymongoWebhookEventData.fromJson(Map<String, dynamic> json) {
    return PaymongoWebhookEventData(
      id: json['id'] ?? '',
      type: json['type'] ?? '',
      attributes: json['attributes'] as Map<String, dynamic>? ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'attributes': attributes,
    };
  }
}

// Payment method configuration
class PaymongoPaymentMethodConfig {
  static const List<String> allPaymentMethods = [
    'card',
    'gcash',
    'grab_pay',
    'paymaya',
    'billease',
  ];

  static const Map<String, String> paymentMethodNames = {
    'card': 'Credit/Debit Card',
    'gcash': 'GCash',
    'grab_pay': 'GrabPay',
    'paymaya': 'PayMaya',
    'billease': 'Bank Transfer',
  };

  static const Map<String, String> paymentMethodIcons = {
    'card': 'assets/icons/card.png',
    'gcash': 'assets/icons/gcash.png',
    'grab_pay': 'assets/icons/grabpay.png',
    'paymaya': 'assets/icons/paymaya.png',
    'billease': 'assets/icons/bank.png',
  };

  static String getPaymentMethodName(String method) {
    return paymentMethodNames[method] ?? method;
  }

  static String getPaymentMethodIcon(String method) {
    return paymentMethodIcons[method] ?? 'assets/icons/card.png';
  }
}

// Payment result model
class PaymentResult {
  final bool success;
  final String? paymentIntentId;
  final String? paymentMethodId;
  final String? errorMessage;
  final Map<String, dynamic>? additionalData;

  PaymentResult({
    required this.success,
    this.paymentIntentId,
    this.paymentMethodId,
    this.errorMessage,
    this.additionalData,
  });

  factory PaymentResult.success({
    required String paymentIntentId,
    String? paymentMethodId,
    Map<String, dynamic>? additionalData,
  }) {
    return PaymentResult(
      success: true,
      paymentIntentId: paymentIntentId,
      paymentMethodId: paymentMethodId,
      additionalData: additionalData,
    );
  }

  factory PaymentResult.failure({
    required String errorMessage,
    Map<String, dynamic>? additionalData,
  }) {
    return PaymentResult(
      success: false,
      errorMessage: errorMessage,
      additionalData: additionalData,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'payment_intent_id': paymentIntentId,
      'payment_method_id': paymentMethodId,
      'error_message': errorMessage,
      'additional_data': additionalData,
    };
  }
}

// Firebase function response model
class FirebaseFunctionResponse<T> {
  final bool success;
  final T? data;
  final String? error;
  final String? message;

  FirebaseFunctionResponse({
    required this.success,
    this.data,
    this.error,
    this.message,
  });

  factory FirebaseFunctionResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>)? fromJsonT,
  ) {
    return FirebaseFunctionResponse(
      success: json['success'] ?? false,
      data: json['data'] != null && fromJsonT != null
          ? fromJsonT(json['data'] as Map<String, dynamic>)
          : json['data'] as T?,
      error: json['error'],
      message: json['message'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'data': data,
      'error': error,
      'message': message,
    };
  }
}

// Checkout Session creation request model
class CreateCheckoutSessionRequest {
  final String description;
  final List<PaymongoLineItem> lineItems;
  final List<String> paymentMethodTypes;
  final String? successUrl;
  final String? cancelUrl;
  final Map<String, dynamic>? metadata;
  final PaymongoCheckoutBilling? billing;

  CreateCheckoutSessionRequest({
    required this.description,
    required this.lineItems,
    required this.paymentMethodTypes,
    this.successUrl,
    this.cancelUrl,
    this.metadata,
    this.billing,
  });

  Map<String, dynamic> toJson() {
    return {
      'description': description,
      'line_items': lineItems.map((item) => item.toJson()).toList(),
      'payment_method_types': paymentMethodTypes,
      'success_url': successUrl,
      'cancel_url': cancelUrl,
      'metadata': metadata,
      'billing': billing?.toJson(),
    };
  }
}

// Order creation request for Firebase function
class CreateOrderRequest {
  final List<String> cartItemIds;
  final String addressId;
  final String? notes;
  final List<String> paymentMethodAllowed;

  CreateOrderRequest({
    required this.cartItemIds,
    required this.addressId,
    this.notes,
    required this.paymentMethodAllowed,
  });

  Map<String, dynamic> toJson() {
    return {
      'cart_item_ids': cartItemIds,
      'address_id': addressId,
      'notes': notes,
      'payment_method_allowed': paymentMethodAllowed,
    };
  }
}

// Checkout Session creation request for Firebase function
class CreateCheckoutOrderRequest {
  final List<String> cartItemIds;
  final String addressId;
  final String? notes;
  final List<String> paymentMethodTypes;
  final String? successUrl;
  final String? cancelUrl;

  CreateCheckoutOrderRequest({
    required this.cartItemIds,
    required this.addressId,
    this.notes,
    required this.paymentMethodTypes,
    this.successUrl,
    this.cancelUrl,
  });

  Map<String, dynamic> toJson() {
    return {
      'cart_item_ids': cartItemIds,
      'address_id': addressId,
      'notes': notes,
      'payment_method_types': paymentMethodTypes,
      'success_url': successUrl,
      'cancel_url': cancelUrl,
    };
  }
}

// Order confirmation response from Firebase function (updated for checkout sessions)
class CreateOrderResponse {
  final String orderId;
  final PaymongoPaymentIntent? paymentIntent; // Made optional for checkout sessions
  final PaymongoCheckoutSession? checkoutSession; // Added for checkout sessions
  final double totalAmount;
  final String currency;

  CreateOrderResponse({
    required this.orderId,
    this.paymentIntent,
    this.checkoutSession,
    required this.totalAmount,
    required this.currency,
  });

  factory CreateOrderResponse.fromJson(Map<String, dynamic> json) {
    print('🐛 CreateOrderResponse.fromJson - Raw JSON: $json');
    
    try {
      // Parse order_id
      final orderId = json['order_id'] ?? '';
      print('🐛 CreateOrderResponse.fromJson - orderId: $orderId');
      
      // Parse payment_intent
      PaymongoPaymentIntent? paymentIntent;
      final paymentIntentData = json['payment_intent'];
      print('🐛 CreateOrderResponse.fromJson - payment_intent data: $paymentIntentData (type: ${paymentIntentData.runtimeType})');
      
      if (paymentIntentData != null) {
        print('🐛 CreateOrderResponse.fromJson - About to parse PaymongoPaymentIntent...');
        paymentIntent = PaymongoPaymentIntent.fromJson(paymentIntentData as Map<String, dynamic>);
        print('🐛 CreateOrderResponse.fromJson - Successfully parsed PaymongoPaymentIntent');
      }
      
      // Parse checkout_session
      PaymongoCheckoutSession? checkoutSession;
      final checkoutSessionData = json['checkout_session'];
      print('🐛 CreateOrderResponse.fromJson - checkout_session data: $checkoutSessionData (type: ${checkoutSessionData.runtimeType})');
      
      if (checkoutSessionData != null) {
        print('🐛 CreateOrderResponse.fromJson - About to parse PaymongoCheckoutSession...');
        checkoutSession = PaymongoCheckoutSession.fromJson(checkoutSessionData as Map<String, dynamic>);
        print('🐛 CreateOrderResponse.fromJson - Successfully parsed PaymongoCheckoutSession');
      }
      
      // Parse total_amount
      final totalAmountValue = json['total_amount'];
      print('🐛 CreateOrderResponse.fromJson - total_amount: $totalAmountValue (type: ${totalAmountValue.runtimeType})');
      final totalAmount = (totalAmountValue ?? 0.0).toDouble();
      
      // Parse currency
      final currency = json['currency'] ?? 'PHP';
      print('🐛 CreateOrderResponse.fromJson - currency: $currency');
      
      print('🐛 CreateOrderResponse.fromJson - Creating CreateOrderResponse object...');
      return CreateOrderResponse(
        orderId: orderId,
        paymentIntent: paymentIntent,
        checkoutSession: checkoutSession,
        totalAmount: totalAmount,
        currency: currency,
      );
    } catch (e, stackTrace) {
      print('🐛 ❌ CreateOrderResponse.fromJson - Error occurred: $e');
      print('🐛 ❌ CreateOrderResponse.fromJson - Stack trace: $stackTrace');
      print('🐛 ❌ CreateOrderResponse.fromJson - Input JSON: $json');
      rethrow;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'order_id': orderId,
      'payment_intent': paymentIntent?.toJson(),
      'checkout_session': checkoutSession?.toJson(),
      'total_amount': totalAmount,
      'currency': currency,
    };
  }
}
