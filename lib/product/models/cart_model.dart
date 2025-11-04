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
  String? sellerAddress; // Seller's shipping address (city, province)
  
  // Shipping information for JRS calculation
  double? weight; // Weight in grams
  double? length; // Length in cm
  double? width; // Width in cm
  double? height; // Height in cm
  
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
    this.sellerAddress,
    this.weight,
    this.length,
    this.width,
    this.height,
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
  
  // Get total weight for all quantity
  double get totalWeight => (weight ?? 100.0) * quantity; // Default 100g per item if not specified
  
  // Helper method to toggle selection
  void toggleSelection() {
    isSelected = !isSelected;
  }
  
  // Convert to JRS shipping item format
  Map<String, dynamic> toJRSShippingItem() {
    return {
      'productId': productId,
      'quantity': quantity,
      'price': productPrice ?? 0.0,
      'weight': weight ?? 100.0, // Default 100g
      'length': length ?? 10.0, // Default 10cm
      'width': width ?? 10.0, // Default 10cm
      'height': height ?? 5.0, // Default 5cm
    };
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
  
  // Get seller's shipping address (city, province format)
  String? get sellerShippingAddress {
    if (items.isNotEmpty && items.first.sellerAddress != null) {
      return items.first.sellerAddress;
    }
    return null; // Will fall back to default address in Firebase function
  }
  
  // Convert selected items to JRS shipping format
  List<Map<String, dynamic>> getSelectedItemsForShipping() {
    return items
        .where((item) => item.isSelected)
        .map((item) => item.toJRSShippingItem())
        .toList();
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
