import 'package:cloud_firestore/cloud_firestore.dart';

class CartItem {
  final String cartItemId;
  final String productId;
  int quantity;
  final DateTime addedAt;
  
  // These fields will be populated from the product
  String? productName;
  String? productImage;
  double? productPrice;
  int? availableStock;
  String? variationId;

  CartItem({
    required this.cartItemId,
    required this.productId,
    required this.quantity,
    required this.addedAt,
    this.productName,
    this.productImage,
    this.productPrice,
    this.availableStock,
    this.variationId,
  });

  factory CartItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    return CartItem(
      cartItemId: doc.id,
      productId: data['productId'] ?? '',
      quantity: data['quantity'] ?? 1,
      addedAt: (data['addedAt'] as Timestamp).toDate(),
      variationId: data['variationId'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'quantity': quantity,
      'addedAt': Timestamp.fromDate(addedAt),
      if (variationId != null) 'variationId': variationId,
    };
  }

  double get totalPrice => (productPrice ?? 0) * quantity;
}
