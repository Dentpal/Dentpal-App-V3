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
    String? category,
  }) async {
    try {
      print('Fetching paginated products from Firestore...');
      
      // Start building the query
      Query query = _firestore
          .collection('Product')
          .orderBy('createdAt', descending: true);
      
      // Add category filter if specified
      if (category != null && category != 'All') {
        query = query.where('category', isEqualTo: category);
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
            category: product.category,
            sellerId: product.sellerId,
            createdAt: product.createdAt,
            updatedAt: product.updatedAt,
            isActive: product.isActive,
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
          category: product.category, // change to categoryID we will separate this
          sellerId: product.sellerId,
          createdAt: product.createdAt,
          updatedAt: product.updatedAt,
          isActive: product.isActive,
          variations: variations,
          //add clickAmt
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
      if (currentUser == null) {
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

      if (!userDoc.exists) {
        return {
          'isSeller': false,
          'message': 'User profile not found',
          'sellerId': null
        };
      }

      // Check the role field to see if the user is a seller
      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
      if (userData['role'] != 'seller') {
        return {
          'isSeller': false,
          'message': 'User is not registered as a seller',
          'sellerId': null
        };
      }

      // Check if there's an entry in the Seller collection
      DocumentSnapshot sellerDoc = await _firestore
          .collection('Seller')
          .doc(currentUser.uid)
          .get();

      if (!sellerDoc.exists) {
        return {
          'isSeller': false,
          'message': 'Seller profile not setup completely',
          'sellerId': null
        };
      }

      Map<String, dynamic> sellerData = sellerDoc.data() as Map<String, dynamic>;
      if (sellerData['isActive'] != true) {
        return {
          'isSeller': false,
          'message': 'Seller account is not active',
          'sellerId': null
        };
      }

      return {
        'isSeller': true,
        'message': 'User is a verified seller',
        'sellerId': currentUser.uid
      };
    } catch (e) {
      print('Error checking seller status: $e');
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
        'category': productForm.category,
        'sellerId': sellerId,
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
        'isActive': true,
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
