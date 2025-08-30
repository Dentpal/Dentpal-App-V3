import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/cart_model.dart';
import '../models/product_model.dart';

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
  Future<void> addToCart({
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
      } else {
        // Add new item to cart
        await cartRef.add({
          'productId': productId,
          'quantity': quantity,
          'addedAt': FieldValue.serverTimestamp(),
          if (variationId != null) 'variationId': variationId,
        });
      }
    } catch (e) {
      print('Error adding to cart: $e');
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
      print('Error getting cart items: $e');
      return [];
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
      print('Error updating cart item: $e');
      rethrow;
    }
  }
  
  // Remove item from cart
  Future<void> removeCartItem(String cartItemId) async {
    try {
      await _getCartRef().doc(cartItemId).delete();
    } catch (e) {
      print('Error removing cart item: $e');
      rethrow;
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
      print('Error clearing cart: $e');
      rethrow;
    }
  }
}
