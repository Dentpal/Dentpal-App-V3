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
  
  // Seller information
  String? sellerId;
  String? sellerName;
  
  // Selection state for multi-seller checkout
  bool isSelected;

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
    this.sellerId,
    this.sellerName,
    this.isSelected = true, // Default to selected
  });

  factory CartItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    return CartItem(
      cartItemId: doc.id,
      productId: data['productId'] ?? '',
      quantity: data['quantity'] ?? 1,
      addedAt: (data['addedAt'] as Timestamp).toDate(),
      variationId: data['variationId'],
      isSelected: data['isSelected'] ?? true, // Default to selected if not set
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'quantity': quantity,
      'addedAt': Timestamp.fromDate(addedAt),
      'isSelected': isSelected,
      if (variationId != null) 'variationId': variationId,
    };
  }

  double get totalPrice => (productPrice ?? 0) * quantity;
  
  // Helper method to toggle selection
  void toggleSelection() {
    isSelected = !isSelected;
  }
}

// Class to group cart items by seller
class SellerGroup {
  final String sellerId;
  final String sellerName;
  final List<CartItem> items;
  final double shippingCost;
  bool isSelected; // If all items in this seller group are selected

  SellerGroup({
    required this.sellerId,
    required this.sellerName,
    required this.items,
    this.shippingCost = 0.0,
    this.isSelected = true,
  });

  // Calculate total for selected items only
  double get selectedItemsTotal => items
      .where((item) => item.isSelected)
      .fold(0.0, (total, item) => total + item.totalPrice);

  // Calculate total for all items
  double get totalItemsPrice => items
      .fold(0.0, (total, item) => total + item.totalPrice);

  // Get total including shipping for selected items
  double get totalWithShipping => hasSelectedItems ? selectedItemsTotal + shippingCost : 0.0;

  // Check if any items are selected
  bool get hasSelectedItems => items.any((item) => item.isSelected);

  // Check if all items are selected
  bool get allItemsSelected => items.isNotEmpty && items.every((item) => item.isSelected);

  // Get count of selected items
  int get selectedItemsCount => items.where((item) => item.isSelected).length;

  // Toggle all items selection
  void toggleAllItems() {
    final shouldSelect = !allItemsSelected;
    for (var item in items) {
      item.isSelected = shouldSelect;
    }
    isSelected = shouldSelect;
  }

  // Update group selection state based on individual items
  void updateGroupSelection() {
    isSelected = allItemsSelected;
  }
}

// Class to manage cart totals and shipping
class CartSummary {
  final List<SellerGroup> sellerGroups;

  CartSummary({required this.sellerGroups});

  // Calculate total for all selected items across all sellers
  double get selectedItemsTotal => sellerGroups
      .fold(0.0, (total, group) => total + group.selectedItemsTotal);

  // Calculate total shipping cost for sellers with selected items
  double get totalShippingCost => sellerGroups
      .where((group) => group.hasSelectedItems)
      .fold(0.0, (total, group) => total + group.shippingCost);

  // Calculate grand total including shipping
  double get grandTotal => selectedItemsTotal + totalShippingCost;

  // Get total number of selected items
  int get selectedItemsCount => sellerGroups
      .fold(0, (total, group) => total + group.selectedItemsCount);

  // Check if any items are selected
  bool get hasSelectedItems => sellerGroups.any((group) => group.hasSelectedItems);

  // Get sellers with selected items
  List<SellerGroup> get sellersWithSelectedItems => sellerGroups
      .where((group) => group.hasSelectedItems)
      .toList();
}
