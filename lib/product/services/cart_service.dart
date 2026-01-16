import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/cart_model.dart';
import '../models/product_model.dart';
import 'jrs_shipping_service.dart';
import 'package:dentpal/utils/app_logger.dart';

class CartService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get current user ID or throw error if not authenticated (for methods that require auth)
  String _getCurrentUserIdRequired() {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }
    return user.uid;
  }

  // Get cart reference for current user (throws if not authenticated)
  CollectionReference _getCartRefRequired() {
    final userId = _getCurrentUserIdRequired();
    return _firestore.collection('User').doc(userId).collection('Cart');
  }

  // Add item to cart
  Future<String?> addToCart({
    required String productId, 
    required int quantity,
    String? variationId
  }) async {
    try {
      final cartRef = _getCartRefRequired();
      
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
  
  // Get user's cart items with product details (OPTIMIZED VERSION)
  Future<List<CartItem>> getCartItems() async {
    try {
      final cartRef = _getCartRefRequired();
      QuerySnapshot cartSnapshot = await cartRef.orderBy('addedAt', descending: true).get();
      
      List<CartItem> cartItems = cartSnapshot.docs.map((doc) => CartItem.fromFirestore(doc)).toList();
      
      if (cartItems.isEmpty) {
        return cartItems;
      }

      AppLogger.d('Loading ${cartItems.length} cart items with optimized queries');
      
      // Extract unique product IDs and seller IDs for batch fetching
      Set<String> productIds = cartItems.map((item) => item.productId).toSet();
      Set<String> sellerIds = <String>{};
      
      // STEP 1: Batch fetch all product documents in parallel
      AppLogger.d('Step 1: Fetching ${productIds.length} products in parallel');
      Map<String, Product> productsMap = {};
      List<Future<void>> productFutures = productIds.map((productId) async {
        try {
          DocumentSnapshot productDoc = await _firestore.collection('Product').doc(productId).get();
          if (productDoc.exists) {
            Product product = Product.fromFirestore(productDoc);
            productsMap[productId] = product;
            sellerIds.add(product.sellerId); // Collect seller IDs
          }
        } catch (e) {
          AppLogger.d('Error fetching product $productId: $e');
        }
      }).toList();
      
      await Future.wait(productFutures);
      AppLogger.d('Fetched ${productsMap.length} products');

      // STEP 2: Batch fetch all seller documents in parallel
      AppLogger.d('Step 2: Fetching ${sellerIds.length} sellers in parallel');
      Map<String, Map<String, dynamic>> sellersMap = {};
      List<Future<void>> sellerFutures = sellerIds.map((sellerId) async {
        try {
          DocumentSnapshot sellerDoc = await _firestore.collection('Seller').doc(sellerId).get();
          if (sellerDoc.exists) {
            final data = sellerDoc.data() as Map<String, dynamic>;
            
            // Extract shop name from nested structure: vendor.company.storeName
            final vendor = (data['vendor'] is Map)
                ? data['vendor'] as Map<String, dynamic>
                : const {};
            final company = (vendor['company'] is Map)
                ? vendor['company'] as Map<String, dynamic>
                : const {};
            
            final String storeName =
                (company['storeName'] as String?) ??
                (data['storeName'] as String?) ??
                (data['shopName'] as String?) ??
                'Unknown Seller';
            
            // Create a modified data map with the extracted shop name
            final modifiedData = Map<String, dynamic>.from(data);
            modifiedData['shopName'] = storeName;
            
            sellersMap[sellerId] = modifiedData;
          }
        } catch (e) {
          AppLogger.d('Error fetching seller $sellerId: $e');
        }
      }).toList();
      
      await Future.wait(sellerFutures);
      AppLogger.d('Fetched ${sellersMap.length} sellers');

      // STEP 3: Batch fetch all variation documents in parallel
      AppLogger.d('Step 3: Fetching variations in parallel');
      Map<String, ProductVariation> variationsMap = {};
      List<Future<void>> variationFutures = cartItems.map((item) async {
        try {
          if (item.variationId != null) {
            // Fetch specific variation
            DocumentSnapshot variationDoc = await _firestore
                .collection('Product')
                .doc(item.productId)
                .collection('Variation')
                .doc(item.variationId)
                .get();
                
            if (variationDoc.exists) {
              ProductVariation variation = ProductVariation.fromFirestore(variationDoc);
              variationsMap['${item.productId}_${item.variationId}'] = variation;
            }
          } else {
            // Fetch first variation for this product
            QuerySnapshot variationsSnapshot = await _firestore
                .collection('Product')
                .doc(item.productId)
                .collection('Variation')
                .limit(1)
                .get();
                
            if (variationsSnapshot.docs.isNotEmpty) {
              ProductVariation variation = ProductVariation.fromFirestore(variationsSnapshot.docs.first);
              variationsMap['${item.productId}_first'] = variation;
            }
          }
        } catch (e) {
          AppLogger.d('Error fetching variation for ${item.productId}: $e');
        }
      }).toList();
      
      await Future.wait(variationFutures);
      AppLogger.d('Fetched ${variationsMap.length} variations');

      // STEP 4: Populate cart items with fetched data (fast, no network calls)
      AppLogger.d('Step 4: Populating cart items with fetched data');
      for (var item in cartItems) {
        final product = productsMap[item.productId];
        if (product != null) {
          item.productName = product.name;
          item.productImage = product.imageURL;
          item.sellerId = product.sellerId;
          
          // Get seller info from cache
          final sellerData = sellersMap[product.sellerId];
          if (sellerData != null) {
            item.sellerName = sellerData['shopName'] ?? 'Unknown Seller';
            
            // Get seller's shipping address - handle both Map and String formats
            try {
              final addressField = sellerData['address'];
              if (addressField is Map<String, dynamic>) {
                // Address is stored as a map with city/state
                final city = addressField['city'] as String?;
                final state = addressField['state'] as String?;
                item.sellerAddress = JRSShippingService.formatAddressForJRS(city, state);
              } else if (addressField is String && addressField.isNotEmpty) {
                // Address is stored as a string
                item.sellerAddress = JRSShippingService.formatShippingAddressForJRS(addressField);
              } else {
                // Try alternative address field
                final shippingAddress = sellerData['shippingAddress'] as String?;
                if (shippingAddress != null && shippingAddress.isNotEmpty) {
                  item.sellerAddress = JRSShippingService.formatShippingAddressForJRS(shippingAddress);
                }
              }
            } catch (e) {
              AppLogger.d('Error parsing seller address for ${product.sellerId}: $e');
              // Try alternative address field as fallback
              final shippingAddress = sellerData['shippingAddress'] as String?;
              if (shippingAddress != null && shippingAddress.isNotEmpty) {
                item.sellerAddress = JRSShippingService.formatShippingAddressForJRS(shippingAddress);
              }
            }
          } else {
            item.sellerName = 'Unknown Seller';
          }
          
          // Get variation info from cache
          ProductVariation? variation;
          if (item.variationId != null) {
            variation = variationsMap['${item.productId}_${item.variationId}'];
          } else {
            variation = variationsMap['${item.productId}_first'];
          }
          
          if (variation != null) {
            item.productPrice = variation.price;
            item.availableStock = variation.stock;
            
            // Set shipping information from variation
            item.weight = variation.weight; // Weight in grams
            
            // Get dimensions from variation
            if (variation.dimensions != null) {
              final dimensions = variation.dimensions!;
              item.length = (dimensions['length'] as num?)?.toDouble();
              item.width = (dimensions['width'] as num?)?.toDouble();
              item.height = (dimensions['height'] as num?)?.toDouble();
            }
            
            if (variation.imageURL != null && variation.imageURL!.isNotEmpty) {
              item.productImage = variation.imageURL;
            }
          }
        }
      }
      
      AppLogger.d('Cart loading completed successfully with ${cartItems.length} items');
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
      
      // Create seller groups without shipping cost calculation
      // Shipping costs will be calculated in checkout page
      List<SellerGroup> sellerGroups = [];
      for (var entry in sellerItemsMap.entries) {
        final sellerId = entry.key;
        final items = entry.value;
        final sellerName = sellerNames[sellerId] ?? 'Unknown Seller';
        // No shipping cost calculation in cart - handled in checkout
        
        sellerGroups.add(SellerGroup(
          sellerId: sellerId,
          sellerName: sellerName,
          items: items,
          shippingCost: 0.0, // Always 0.0 - shipping calculated in checkout
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
  
  
  // Update item selection state
  Future<void> updateItemSelection(String cartItemId, bool isSelected) async {
    try {
      await _getCartRefRequired().doc(cartItemId).update({
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
      final cartRef = _getCartRefRequired();
      
      for (var entry in itemSelections.entries) {
        batch.update(cartRef.doc(entry.key), {'isSelected': entry.value});
      }
      
      await batch.commit();
      AppLogger.d('Batch updated ${itemSelections.length} item selections');
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
        await _getCartRefRequired().doc(cartItemId).update({'quantity': quantity});
      }
    } catch (e) {
      AppLogger.d('Error updating cart item: $e');
      rethrow;
    }
  }
  
  // Remove item from cart
  Future<void> removeCartItem(String cartItemId) async {
    try {
      await _getCartRefRequired().doc(cartItemId).delete();
    } catch (e) {
      AppLogger.d('Error removing cart item: $e');
      rethrow;
    }
  }
  
  // Get a single cart item with product details (for background sync)
  Future<CartItem?> getCartItem(String cartItemId) async {
    try {
      final cartRef = _getCartRefRequired();
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
        
        // Fetch seller name and address
        try {
          DocumentSnapshot sellerDoc = await _firestore
              .collection('Seller')
              .doc(product.sellerId)
              .get();
          if (sellerDoc.exists) {
            final sellerData = sellerDoc.data() as Map<String, dynamic>;
            
            // Extract shop name from nested structure: vendor.company.storeName
            final vendor = (sellerData['vendor'] is Map)
                ? sellerData['vendor'] as Map<String, dynamic>
                : const {};
            final company = (vendor['company'] is Map)
                ? vendor['company'] as Map<String, dynamic>
                : const {};
            
            cartItem.sellerName = (company['storeName'] as String?) ??
                (sellerData['storeName'] as String?) ??
                (sellerData['shopName'] as String?) ??
                'Unknown Seller';
            
            // Get seller's shipping address - handle both Map and String formats
            try {
              final addressField = sellerData['address'];
              if (addressField is Map<String, dynamic>) {
                // Address is stored as a map with city/state
                final city = addressField['city'] as String?;
                final state = addressField['state'] as String?;
                cartItem.sellerAddress = JRSShippingService.formatAddressForJRS(city, state);
              } else if (addressField is String && addressField.isNotEmpty) {
                // Address is stored as a string
                cartItem.sellerAddress = JRSShippingService.formatShippingAddressForJRS(addressField);
              } else {
                // Try alternative address field
                final shippingAddress = sellerData['shippingAddress'] as String?;
                if (shippingAddress != null && shippingAddress.isNotEmpty) {
                  cartItem.sellerAddress = JRSShippingService.formatShippingAddressForJRS(shippingAddress);
                }
              }
            } catch (e) {
              AppLogger.d('Error parsing seller address: $e');
              // Try alternative address field as fallback
              final shippingAddress = sellerData['shippingAddress'] as String?;
              if (shippingAddress != null && shippingAddress.isNotEmpty) {
                cartItem.sellerAddress = JRSShippingService.formatShippingAddressForJRS(shippingAddress);
              }
            }
          }
        } catch (e) {
          AppLogger.d('Error fetching seller info: $e');
          cartItem.sellerName = 'Unknown Seller';
        }
        
        // If there's a variation, get its details including shipping info
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
            
            // Set shipping information from variation
            cartItem.weight = variation.weight; // Weight in grams
            
            // Get dimensions from variation
            if (variation.dimensions != null) {
              final dimensions = variation.dimensions!;
              cartItem.length = (dimensions['length'] as num?)?.toDouble();
              cartItem.width = (dimensions['width'] as num?)?.toDouble();
              cartItem.height = (dimensions['height'] as num?)?.toDouble();
            }
            
            if (variation.imageURL != null && variation.imageURL!.isNotEmpty) {
              cartItem.productImage = variation.imageURL;
            }
          }
        } else {
          // If no variation, try to get the first variation's details
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
            
            // Set shipping information from variation
            cartItem.weight = variation.weight; // Weight in grams
            
            // Get dimensions from variation
            if (variation.dimensions != null) {
              final dimensions = variation.dimensions!;
              cartItem.length = (dimensions['length'] as num?)?.toDouble();
              cartItem.width = (dimensions['width'] as num?)?.toDouble();
              cartItem.height = (dimensions['height'] as num?)?.toDouble();
            }
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
      QuerySnapshot cartSnapshot = await _getCartRefRequired().get();
      
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
  
  // Calculate shipping cost with actual recipient address (for checkout)
  // Returns full JRSShippingResult with both total cost and buyer's portion
  Future<JRSShippingResult> calculateShippingCostWithAddress({
    required String sellerId,
    required List<CartItem> items,
    required String recipientAddress,
  }) async {
    try {
      AppLogger.d('Calculating shipping cost with recipient address');
      AppLogger.d('   Seller: $sellerId');
      AppLogger.d('   Recipient: $recipientAddress');
      AppLogger.d('   Items: ${items.length}');

      if (items.isEmpty) {
        return JRSShippingResult(
          success: true,
          shippingCost: 0.0,
          buyerShippingCharge: 0.0,
          sellerShippingCharge: 0.0,
          message: 'No items to ship',
        );
      }

      // Get seller's shipping address
      String sellerAddress = 'Makati, Metro Manila'; // Default fallback
      
      try {
        DocumentSnapshot sellerDoc = await _firestore
            .collection('Seller')
            .doc(sellerId)
            .get();
        
        if (sellerDoc.exists) {
          final sellerData = sellerDoc.data() as Map<String, dynamic>;
          
          // Try to get address from seller profile - handle both Map and String formats
          try {
            final addressField = sellerData['address'];
            if (addressField is Map<String, dynamic>) {
              // Address is stored as a map with city/state
              final city = addressField['city'] as String?;
              final state = addressField['state'] as String?;
              if (city != null && city.isNotEmpty) {
                sellerAddress = JRSShippingService.formatAddressForJRS(city, state);
              }
            } else if (addressField is String && addressField.isNotEmpty) {
              // Address is stored as a string
              sellerAddress = JRSShippingService.formatShippingAddressForJRS(addressField);
            }
          } catch (e) {
            AppLogger.d('Error parsing seller address: $e');
          }
          
          // Alternative: check if seller has a direct shipping address field
          if (sellerAddress == 'Makati, Metro Manila') { // Still using default
            final shippingAddress = sellerData['shippingAddress'] as String?;
            if (shippingAddress != null && shippingAddress.isNotEmpty) {
              sellerAddress = JRSShippingService.formatShippingAddressForJRS(shippingAddress);
            }
          }
        }
      } catch (e) {
        AppLogger.d('Error fetching seller address, using default: $e');
      }

      // Format recipient address for JRS
      final formattedRecipientAddress = JRSShippingService.formatShippingAddressForJRS(recipientAddress);

      AppLogger.d(' Seller address: $sellerAddress');
      AppLogger.d(' Recipient address: $formattedRecipientAddress');

      // Calculate shipping using JRS API
      final result = await JRSShippingService.calculateShippingCost(
        sellerAddress: sellerAddress,
        recipientAddress: formattedRecipientAddress,
        cartItems: items,
        express: true,
        insurance: true,
        valuation: true,
      );

      AppLogger.d('JRS shipping result: $result');

      if (result.success) {
        // Return the full JRS result with both total cost and buyer's portion
        AppLogger.d('JRS shipping: full=₱${result.shippingCost}, buyerPays=₱${result.buyerShippingCharge}');
        return result;
      } else {
        AppLogger.d('JRS calculation failed, using fallback: ${result.message}');
        return result; // Return the full fallback result
      }

    } catch (e) {
      AppLogger.d('Error calculating JRS shipping cost with address: $e');
      
      // Fallback to simple logic
      double totalValue = items.fold(0.0, (sum, item) => sum + item.totalPrice);
      
      // Free shipping if order value exceeds ₱1000
      if (totalValue >= 1000.0) {
        return JRSShippingResult(
          success: true,
          shippingCost: 50.0, // Estimated cost
          buyerShippingCharge: 0.0, // Free for buyer
          sellerShippingCharge: 50.0, // Seller pays
          shippingSplitRule: 'seller_pays_full',
          message: 'Free shipping (fallback)',
        );
      }
      
      // Default shipping cost
      return JRSShippingResult(
        success: true,
        shippingCost: 50.0,
        buyerShippingCharge: 50.0,
        sellerShippingCharge: 0.0,
        shippingSplitRule: 'buyer_pays_full',
        message: 'Default shipping (fallback)',
      );
    }
  }
}