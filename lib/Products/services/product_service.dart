import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/product_model.dart';
import '../models/product_form_model.dart';

class ProductService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get all products (legacy method - kept for backward compatibility)
  Future<List<Product>> getProducts() async {
    try {
      print('Fetching all products from Firestore...');
      
      // Get the first page of products with a large limit
      final result = await getProductsPaginated(limit: 100);
      return result['products'] as List<Product>;
    } catch (e) {
      print('Error fetching all products: $e');
      print('Stack trace: ${StackTrace.current}');
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
      print('Fetching paginated products from Firestore...');
      
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
      
      print('Fetched page with ${querySnapshot.docs.length} products');
      
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
      
      print('Successfully fetched ${pageProducts.length} products');
      
      // Return a map with all pagination-related data
      return {
        'products': pageProducts,
        'lastDocument': lastVisibleDocument,
        'hasMore': hasMore
      };
    } catch (e) {
      print('Error fetching paginated products: $e');
      print('Stack trace: ${StackTrace.current}');
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
      print('Error fetching product: $e');
      return null;
    }
  }

  // Check if the current user is a seller
  Future<Map<String, dynamic>> checkSellerStatus() async {
    try {
      User? currentUser = _auth.currentUser;
      print('🔍 CheckSellerStatus: Current user UID: ${currentUser?.uid}');
      
      if (currentUser == null) {
        print('❌ CheckSellerStatus: User is not logged in');
        return {
          'isSeller': false,
          'message': 'User is not logged in',
          'sellerId': null
        };
      }

      // First check if user exists in the users collection
      DocumentSnapshot userDoc = await _firestore
          .collection('User')
          .doc(currentUser.uid)
          .get();

      print('🔍 CheckSellerStatus: User doc exists: ${userDoc.exists}');
      
      if (!userDoc.exists) {
        print('❌ CheckSellerStatus: User profile not found');
        return {
          'isSeller': false,
          'message': 'User profile not found',
          'sellerId': null
        };
      }

      // Check the role field to see if the user is a seller
      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
      print('🔍 CheckSellerStatus: User role: ${userData['role']}');
      
      if (userData['role'] != 'seller') {
        print('❌ CheckSellerStatus: User role is not seller');
        return {
          'isSeller': false,
          'message': 'User is not registered as a seller',
          'sellerId': null
        };
      }

      print(currentUser.uid);

      // Check if there's an entry in the Seller collection
      DocumentSnapshot sellerDoc = await _firestore
          .collection('Seller')
          .doc(currentUser.uid)
          .get();

      print('🔍 CheckSellerStatus: Seller doc exists: ${sellerDoc.exists}');
      
      if (!sellerDoc.exists) {
        print('❌ CheckSellerStatus: Seller profile not setup completely');
        return {
          'isSeller': false,
          'message': 'Seller profile not setup completely',
          'sellerId': null
        };
      }

      Map<String, dynamic> sellerData = sellerDoc.data() as Map<String, dynamic>;
      print('🔍 CheckSellerStatus: Seller isActive: ${sellerData['isActive']}');
      print('🔍 CheckSellerStatus: Seller isActive type: ${sellerData['isActive'].runtimeType}');
      print('🔍 CheckSellerStatus: All seller fields: ${sellerData.keys.toList()}');
      
      if (sellerData['isActive'] != true) {
        print('❌ CheckSellerStatus: Seller account is not active');
        return {
          'isSeller': false,
          'message': 'Seller account is not active',
          'sellerId': null
        };
      }

      print('✅ CheckSellerStatus: User is verified seller');
      return {
        'isSeller': true,
        'message': 'User is a verified seller',
        'sellerId': currentUser.uid
      };
    } catch (e) {
      print('❌ CheckSellerStatus Error: $e');
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
      print('Error adding product: $e');
      return {
        'success': false,
        'message': 'Error: $e',
        'productId': null
      };
    }
  }
}
