import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/cart_model.dart';
import '../models/product_model.dart';
import 'package:dentpal/utils/app_logger.dart';

class CartService {
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

  // Get cart reference for current user
  CollectionReference _getCartRef() {
    final userId = _getCurrentUserId();
    return _firestore.collection('User').doc(userId).collection('Cart');
  }

  // Add item to cart
  Future<String?> addToCart({
    required String productId, 
    required int quantity,
    String? variationId
  }) async {
    try {
      final cartRef = _getCartRef();
      
      // Check if the product is already in the cart
      QuerySnapshot existingItems = await cartRef
          .where('productId', isEqualTo: productId)
          .where('variationId', isEqualTo: variationId)
          .get();
      
      if (existingItems.docs.isNotEmpty) {
        // Update quantity of existing item
        DocumentReference docRef = cartRef.doc(existingItems.docs.first.id);
        await docRef.update({
          'quantity': FieldValue.increment(quantity),
          'addedAt': FieldValue.serverTimestamp(),
        });
        return existingItems.docs.first.id;
      } else {
        // Add new item to cart
        DocumentReference newDoc = await cartRef.add({
          'productId': productId,
          'quantity': quantity,
          'addedAt': FieldValue.serverTimestamp(),
          'isSelected': true, // Default to selected when adding new items
          if (variationId != null) 'variationId': variationId,
        });
        return newDoc.id;
      }
    } catch (e) {
      AppLogger.d('Error adding to cart: $e');
      rethrow;
    }
  }
  
  // Get user's cart items with product details
  Future<List<CartItem>> getCartItems() async {
    try {
      final cartRef = _getCartRef();
      QuerySnapshot cartSnapshot = await cartRef.orderBy('addedAt', descending: true).get();
      
      List<CartItem> cartItems = cartSnapshot.docs.map((doc) => CartItem.fromFirestore(doc)).toList();
      
      // Fetch product details for each cart item
      for (var item in cartItems) {
        DocumentSnapshot productDoc = await _firestore
            .collection('Product')
            .doc(item.productId)
            .get();
            
        if (productDoc.exists) {
          Product product = Product.fromFirestore(productDoc);
          item.productName = product.name;
          item.productImage = product.imageURL;
          item.sellerId = product.sellerId; // Add seller info
          
          // Fetch seller name
          try {
            DocumentSnapshot sellerDoc = await _firestore
                .collection('Seller')
                .doc(product.sellerId)
                .get();
            if (sellerDoc.exists) {
              final sellerData = sellerDoc.data() as Map<String, dynamic>;
              item.sellerName = sellerData['shopName'] ?? 'Unknown Seller';
            }
          } catch (e) {
            AppLogger.d('Error fetching seller info: $e');
            item.sellerName = 'Unknown Seller';
          }
          
          // If there's a variation, get its details
          if (item.variationId != null) {
            DocumentSnapshot variationDoc = await _firestore
                .collection('Product')
                .doc(item.productId)
                .collection('Variation')
                .doc(item.variationId)
                .get();
                
            if (variationDoc.exists) {
              ProductVariation variation = ProductVariation.fromFirestore(variationDoc);
              item.productPrice = variation.price;
              item.availableStock = variation.stock;
              if (variation.imageURL != null && variation.imageURL!.isNotEmpty) {
                item.productImage = variation.imageURL;
              }
            }
          } else {
            // If no variation, try to get the first variation's price
            QuerySnapshot variationsSnapshot = await _firestore
                .collection('Product')
                .doc(item.productId)
                .collection('Variation')
                .limit(1)
                .get();
                
            if (variationsSnapshot.docs.isNotEmpty) {
              ProductVariation variation = ProductVariation.fromFirestore(variationsSnapshot.docs.first);
              item.productPrice = variation.price;
              item.availableStock = variation.stock;
            }
          }
        }
      }
      
      return cartItems;
    } catch (e) {
      AppLogger.d('Error getting cart items: $e');
      return [];
    }
  }
  
  // Get user's cart items organized by seller
  Future<List<SellerGroup>> getCartItemsGroupedBySeller() async {
    try {
      final cartItems = await getCartItems();
      
      // Group items by seller
      Map<String, List<CartItem>> sellerItemsMap = {};
      Map<String, String> sellerNames = {};
      
      for (var item in cartItems) {
        final sellerId = item.sellerId ?? 'unknown';
        if (!sellerItemsMap.containsKey(sellerId)) {
          sellerItemsMap[sellerId] = [];
        }
        sellerItemsMap[sellerId]!.add(item);
        
        if (item.sellerName != null) {
          sellerNames[sellerId] = item.sellerName!;
        }
      }
      
      // Create seller groups with shipping cost calculation
      List<SellerGroup> sellerGroups = [];
      for (var entry in sellerItemsMap.entries) {
        final sellerId = entry.key;
        final items = entry.value;
        final sellerName = sellerNames[sellerId] ?? 'Unknown Seller';
        final shippingCost = await _calculateShippingCost(sellerId, items);
        
        sellerGroups.add(SellerGroup(
          sellerId: sellerId,
          sellerName: sellerName,
          items: items,
          shippingCost: shippingCost,
        ));
      }
      
      // Sort by seller name
      sellerGroups.sort((a, b) => a.sellerName.compareTo(b.sellerName));
      
      return sellerGroups;
    } catch (e) {
      AppLogger.d('Error getting cart items grouped by seller: $e');
      return [];
    }
  }
  
  // Calculate shipping cost for a seller based on items
  Future<double> _calculateShippingCost(String sellerId, List<CartItem> items) async {
    try {
      // Fetch seller's shipping settings
      DocumentSnapshot sellerDoc = await _firestore
          .collection('Seller')
          .doc(sellerId)
          .get();
      
      if (!sellerDoc.exists) {
        return 50.0; // Default shipping cost
      }
      
      final sellerData = sellerDoc.data() as Map<String, dynamic>;
      final shippingSettings = sellerData['shippingSettings'] as Map<String, dynamic>?;
      
      if (shippingSettings == null) {
        return 50.0; // Default shipping cost
      }
      
      // Calculate total value of items for shipping calculation
      double totalValue = items.fold(0.0, (sum, item) => sum + item.totalPrice);
      
      // Get shipping cost based on weight or value
      double baseCost = (shippingSettings['baseCost'] ?? 50.0).toDouble();
      double freeShippingThreshold = (shippingSettings['freeShippingThreshold'] ?? 100.0).toDouble();
      
      // Free shipping if order value exceeds threshold
      if (totalValue >= freeShippingThreshold) {
        return 0.0;
      }
      
      return baseCost;
    } catch (e) {
      AppLogger.d('Error calculating shipping cost: $e');
      return 50.0; // Default shipping cost
    }
  }
  
  // Update item selection state
  Future<void> updateItemSelection(String cartItemId, bool isSelected) async {
    try {
      await _getCartRef().doc(cartItemId).update({
        'isSelected': isSelected,
      });
    } catch (e) {
      AppLogger.d('Error updating item selection: $e');
      rethrow;
    }
  }

  // Batch update multiple item selections for better performance
  Future<void> batchUpdateItemSelections(Map<String, bool> itemSelections) async {
    try {
      WriteBatch batch = _firestore.batch();
      final cartRef = _getCartRef();
      
      for (var entry in itemSelections.entries) {
        batch.update(cartRef.doc(entry.key), {'isSelected': entry.value});
      }
      
      await batch.commit();
      AppLogger.d('✅ Batch updated ${itemSelections.length} item selections');
    } catch (e) {
      AppLogger.d('Error batch updating item selections: $e');
      rethrow;
    }
  }
  
  // Update cart item quantity
  Future<void> updateCartItemQuantity(String cartItemId, int quantity) async {
    try {
      if (quantity <= 0) {
        await removeCartItem(cartItemId);
      } else {
        await _getCartRef().doc(cartItemId).update({'quantity': quantity});
      }
    } catch (e) {
      AppLogger.d('Error updating cart item: $e');
      rethrow;
    }
  }
  
  // Remove item from cart
  Future<void> removeCartItem(String cartItemId) async {
    try {
      await _getCartRef().doc(cartItemId).delete();
    } catch (e) {
      AppLogger.d('Error removing cart item: $e');
      rethrow;
    }
  }
  
  // Get a single cart item with product details (for background sync)
  Future<CartItem?> getCartItem(String cartItemId) async {
    try {
      final cartRef = _getCartRef();
      DocumentSnapshot cartDoc = await cartRef.doc(cartItemId).get();
      
      if (!cartDoc.exists) {
        return null;
      }
      
      CartItem cartItem = CartItem.fromFirestore(cartDoc);
      
      // Fetch product details
      DocumentSnapshot productDoc = await _firestore
          .collection('Product')
          .doc(cartItem.productId)
          .get();
          
      if (productDoc.exists) {
        Product product = Product.fromFirestore(productDoc);
        cartItem.productName = product.name;
        cartItem.productImage = product.imageURL;
        cartItem.sellerId = product.sellerId;
        
        // Fetch seller name
        try {
          DocumentSnapshot sellerDoc = await _firestore
              .collection('Seller')
              .doc(product.sellerId)
              .get();
          if (sellerDoc.exists) {
            final sellerData = sellerDoc.data() as Map<String, dynamic>;
            cartItem.sellerName = sellerData['shopName'] ?? 'Unknown Seller';
          }
        } catch (e) {
          AppLogger.d('Error fetching seller info: $e');
          cartItem.sellerName = 'Unknown Seller';
        }
        
        // If there's a variation, get its details
        if (cartItem.variationId != null) {
          DocumentSnapshot variationDoc = await _firestore
              .collection('Product')
              .doc(cartItem.productId)
              .collection('Variation')
              .doc(cartItem.variationId)
              .get();
              
          if (variationDoc.exists) {
            ProductVariation variation = ProductVariation.fromFirestore(variationDoc);
            cartItem.productPrice = variation.price;
            cartItem.availableStock = variation.stock;
            if (variation.imageURL != null && variation.imageURL!.isNotEmpty) {
              cartItem.productImage = variation.imageURL;
            }
          }
        } else {
          // If no variation, try to get the first variation's price
          QuerySnapshot variationsSnapshot = await _firestore
              .collection('Product')
              .doc(cartItem.productId)
              .collection('Variation')
              .limit(1)
              .get();
              
          if (variationsSnapshot.docs.isNotEmpty) {
            ProductVariation variation = ProductVariation.fromFirestore(variationsSnapshot.docs.first);
            cartItem.productPrice = variation.price;
            cartItem.availableStock = variation.stock;
          }
        }
      }
      
      return cartItem;
    } catch (e) {
      AppLogger.d('Error getting cart item: $e');
      return null;
    }
  }
  
  // Clear the entire cart
  Future<void> clearCart() async {
    try {
      QuerySnapshot cartSnapshot = await _getCartRef().get();
      
      for (var doc in cartSnapshot.docs) {
        await doc.reference.delete();
      }
    } catch (e) {
      AppLogger.d('Error clearing cart: $e');
      rethrow;
    }
  }
  
  // Get cart summary with selected items only
  Future<CartSummary> getCartSummary() async {
    final sellerGroups = await getCartItemsGroupedBySeller();
    return CartSummary(sellerGroups: sellerGroups);
  }
}