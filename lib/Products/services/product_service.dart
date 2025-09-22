import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/product_model.dart';
import '../models/product_form_model.dart';
import 'package:dentpal/utils/app_logger.dart';

class ProductService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get all products (legacy method - kept for backward compatibility)
  Future<List<Product>> getProducts() async {
    try {
      AppLogger.d('Fetching all products from Firestore...');
      
      // Get the first page of products with a large limit
      final result = await getProductsPaginated(limit: 100);
      return result['products'] as List<Product>;
    } catch (e) {
      AppLogger.d('Error fetching all products: $e');
      AppLogger.d('Stack trace: ${StackTrace.current}');
      return [];
    }
  }

  // Get paginated products with optional last document for pagination
  Future<Map<String, dynamic>> getProductsPaginated({
    int limit = 15,
    DocumentSnapshot? lastDocument,
    String? categoryId,
  }) async {
    try {
      AppLogger.d('Fetching paginated products from Firestore...');
      
      // Start building the query
      Query query = _firestore
          .collection('Product')
          .orderBy('createdAt', descending: true);
      
      // Add category filter if specified
      if (categoryId != null && categoryId != 'All') {
        query = query.where('categoryId', isEqualTo: categoryId);
      }
      
      // Add pagination parameters
      query = query.limit(limit);
      
      // If we have a last document, start after it
      if (lastDocument != null) {
        query = query.startAfterDocument(lastDocument);
      }
      
      // Execute the query
      QuerySnapshot querySnapshot = await query.get();
      
      AppLogger.d('Fetched page with ${querySnapshot.docs.length} products');
      
      // Check if we've reached the end of the data
      bool hasMore = querySnapshot.docs.length == limit;
      
      // Get the last document for next pagination call
      DocumentSnapshot? lastVisibleDocument = 
          querySnapshot.docs.isNotEmpty ? querySnapshot.docs.last : null;

      List<Product> pageProducts = [];
      for (var doc in querySnapshot.docs) {
        Product product = Product.fromFirestore(doc);
        
        // Get variations for each product
        QuerySnapshot variationsSnapshot = await _firestore
            .collection('Product')
            .doc(product.productId)
            .collection('Variation')
            .get();
        
        if (variationsSnapshot.docs.isNotEmpty) {
          List<ProductVariation> variations = variationsSnapshot.docs
              .map((doc) => ProductVariation.fromFirestore(doc))
              .toList();
          
          product = Product(
            productId: product.productId,
            name: product.name,
            description: product.description,
            imageURL: product.imageURL,
            categoryId: product.categoryId,
            subCategoryId: product.subCategoryId,
            sellerId: product.sellerId,
            createdAt: product.createdAt,
            updatedAt: product.updatedAt,
            isActive: product.isActive,
            clickCounter: product.clickCounter,
            variations: variations,
          );
        }
        
        pageProducts.add(product);
      }
      
      AppLogger.d('Successfully fetched ${pageProducts.length} products');
      
      // Return a map with all pagination-related data
      return {
        'products': pageProducts,
        'lastDocument': lastVisibleDocument,
        'hasMore': hasMore
      };
    } catch (e) {
      AppLogger.d('Error fetching paginated products: $e');
      AppLogger.d('Stack trace: ${StackTrace.current}');
      return {
        'products': <Product>[],
        'lastDocument': null,
        'hasMore': false,
        'error': e.toString()
      };
    }
  }

  // Get a single product by ID
  Future<Product?> getProductById(String productId) async {
    try {
      DocumentSnapshot doc = await _firestore.collection('Product').doc(productId).get();
      
      if (!doc.exists) {
        return null;
      }
      
      Product product = Product.fromFirestore(doc);
      
      // Get variations
      QuerySnapshot variationsSnapshot = await _firestore
          .collection('Product')
          .doc(productId)
          .collection('Variation')
          .get();
      
      if (variationsSnapshot.docs.isNotEmpty) {
        List<ProductVariation> variations = variationsSnapshot.docs
            .map((doc) => ProductVariation.fromFirestore(doc))
            .toList();
        
        product = Product(
          productId: product.productId,
          name: product.name,
          description: product.description,
          imageURL: product.imageURL,
          categoryId: product.categoryId,
          subCategoryId: product.subCategoryId,
          sellerId: product.sellerId,
          createdAt: product.createdAt,
          updatedAt: product.updatedAt,
          isActive: product.isActive,
          clickCounter: product.clickCounter,
          variations: variations,
        );
      }
      
      return product;
    } catch (e) {
      AppLogger.d('Error fetching product: $e');
      return null;
    }
  }

  // Check if the current user is a seller
  Future<Map<String, dynamic>> checkSellerStatus() async {
    try {
      User? currentUser = _auth.currentUser;
      final userUID = currentUser?.uid;
      AppLogger.d('🔍 CheckSellerStatus: Current user UID: $userUID');
      
      if (currentUser == null || userUID == null) {
        AppLogger.d('❌ CheckSellerStatus: User is not logged in');
        return {
          'isSeller': false,
          'message': 'User is not logged in',
          'sellerId': null
        };
      }

      // First check if user exists in the users collection using the exact UID
      DocumentSnapshot userDoc = await _firestore
          .collection('User')
          .doc(userUID)
          .get();

      AppLogger.d('🔍 CheckSellerStatus: Looking for User doc with UID: $userUID');
      AppLogger.d('🔍 CheckSellerStatus: User doc exists: ${userDoc.exists}');
      
      if (!userDoc.exists) {
        AppLogger.d('❌ CheckSellerStatus: User profile not found for UID: $userUID');
        return {
          'isSeller': false,
          'message': 'User profile not found',
          'sellerId': null
        };
      }

      // Check the role field to see if the user is a seller
      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
      AppLogger.d('🔍 CheckSellerStatus: User data keys: ${userData.keys.toList()}');
      AppLogger.d('🔍 CheckSellerStatus: User role: ${userData['role']}');
      AppLogger.d('🔍 CheckSellerStatus: User UID from doc: ${userDoc.id}');
      
      if (userData['role'] != 'seller') {
        AppLogger.d('❌ CheckSellerStatus: User role is not seller - role is: ${userData['role']}');
        return {
          'isSeller': false,
          'message': 'User is not registered as a seller',
          'sellerId': null
        };
      }

      // Check if there's an entry in the Seller collection with the same UID
      DocumentSnapshot sellerDoc = await _firestore
          .collection('Seller')
          .doc(userUID)
          .get();

      AppLogger.d('🔍 CheckSellerStatus: Looking for Seller doc with UID: $userUID');
      AppLogger.d('🔍 CheckSellerStatus: Seller doc exists: ${sellerDoc.exists}');
      AppLogger.d('🔍 CheckSellerStatus: Seller doc ID: ${sellerDoc.id}');
      
      if (!sellerDoc.exists) {
        AppLogger.d('❌ CheckSellerStatus: Seller profile not found for UID: $userUID');
        return {
          'isSeller': false,
          'message': 'Seller profile not setup completely',
          'sellerId': null
        };
      }

      Map<String, dynamic> sellerData = sellerDoc.data() as Map<String, dynamic>;
      AppLogger.d('🔍 CheckSellerStatus: Seller data keys: ${sellerData.keys.toList()}');
      AppLogger.d('🔍 CheckSellerStatus: Seller isActive: ${sellerData['isActive']}');
      AppLogger.d('🔍 CheckSellerStatus: Seller isActive type: ${sellerData['isActive'].runtimeType}');
      
      // Verify UIDs match between User and Seller collections
      if (userDoc.id != sellerDoc.id) {
        AppLogger.d('❌ CheckSellerStatus: UID mismatch - User: ${userDoc.id}, Seller: ${sellerDoc.id}');
        return {
          'isSeller': false,
          'message': 'UID mismatch between User and Seller collections',
          'sellerId': null
        };
      }
      
      // Check if seller is active (handle both boolean and string values)
      bool isActive = false;
      if (sellerData['isActive'] is bool) {
        isActive = sellerData['isActive'] as bool;
      } else if (sellerData['isActive'] is String) {
        isActive = sellerData['isActive'].toString().toLowerCase() == 'true';
      }
      
      AppLogger.d('🔍 CheckSellerStatus: Parsed isActive value: $isActive');
      
      if (!isActive) {
        AppLogger.d('❌ CheckSellerStatus: Seller account is not active - isActive: ${sellerData['isActive']}');
        return {
          'isSeller': false,
          'message': 'Seller account is not active',
          'sellerId': null
        };
      }

      AppLogger.d('✅ CheckSellerStatus: User is verified seller with matching UIDs');
      AppLogger.d('✅ CheckSellerStatus: User UID: $userUID, Seller UID: ${sellerDoc.id}');
      return {
        'isSeller': true,
        'message': 'User is a verified seller',
        'sellerId': userUID
      };
    } catch (e) {
      AppLogger.d('❌ CheckSellerStatus Error: $e');
      AppLogger.d('❌ CheckSellerStatus Stack trace: ${StackTrace.current}');
      return {
        'isSeller': false,
        'message': 'Error: $e',
        'sellerId': null
      };
    }
  }

  // Add a new product to Firestore
  Future<Map<String, dynamic>> addProduct(
      ProductFormModel productForm, List<VariationFormModel> variations) async {
    try {
      // First check if the user is a seller
      Map<String, dynamic> sellerStatus = await checkSellerStatus();
      
      if (!sellerStatus['isSeller']) {
        return {
          'success': false,
          'message': sellerStatus['message'],
          'productId': null
        };
      }
      
      String sellerId = sellerStatus['sellerId'];
      
      // Create a new product document
      DocumentReference productRef = _firestore.collection('Product').doc();
      
      // Get the current time
      DateTime now = DateTime.now();
      
      // Create the product
      await productRef.set({
        'name': productForm.name,
        'description': productForm.description,
        'imageURL': productForm.imageURL,
        'categoryID': productForm.categoryId,
        'subCategoryID': productForm.subCategoryId,
        'sellerId': sellerId,
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
        'isActive': true,
        'clickCounter': 0,
      });
      
      // Add variations as a sub-collection
      for (var variationForm in variations) {
        DocumentReference variationRef = productRef.collection('Variation').doc();
        
        await variationRef.set({
          'productId': productRef.id,
          'name': variationForm.name,
          'imageURL': variationForm.imageURL,
          'price': variationForm.price,
          'stock': variationForm.stock,
          'SKU': variationForm.sku,
          'weight': variationForm.weight,
          'dimensions': variationForm.dimensions,
        });
      }
      
      return {
        'success': true,
        'message': 'Product added successfully',
        'productId': productRef.id
      };
    } catch (e) {
      AppLogger.d('Error adding product: $e');
      return {
        'success': false,
        'message': 'Error: $e',
        'productId': null
      };
    }
  }
}
