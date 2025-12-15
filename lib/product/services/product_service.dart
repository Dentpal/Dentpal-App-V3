import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/product_model.dart';
import '../models/product_form_model.dart';
import 'package:dentpal/utils/app_logger.dart';

class ProductService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Helper method to get variations for a single product
  Future<List<ProductVariation>> _getProductVariations(String productId) async {
    try {
      QuerySnapshot variationsSnapshot = await _firestore
          .collection('Product')
          .doc(productId)
          .collection('Variation')
          .get();
      
      return variationsSnapshot.docs
          .map((doc) => ProductVariation.fromFirestore(doc))
          .toList();
    } catch (e) {
      //AppLogger.d('Error fetching variations for product $productId: $e');
      return [];
    }
  }

  // Get all products (legacy method - kept for backward compatibility)
  Future<List<Product>> getProducts() async {
    try {
      //AppLogger.d('Fetching all products from Firestore...');
      
      // Get the first page of products with a large limit
      final result = await getProductsPaginated(limit: 100);
      return result['products'] as List<Product>;
    } catch (e) {
      //AppLogger.d('Error fetching all products: $e');
      //AppLogger.d('Stack trace: ${StackTrace.current}');
      return [];
    }
  }

  // Get paginated products with optional last document for pagination
  Future<Map<String, dynamic>> getProductsPaginated({
    int limit = 15,
    DocumentSnapshot? lastDocument,
    String? categoryId,
    String? subCategoryId,
    bool includeInactive = false,
    bool includeDrafts = false,
    bool includeArchived = false,
  }) async {
    try {
      //AppLogger.d('Fetching paginated products from Firestore...');
      
      // Start building the query - Use fewer WHERE clauses to avoid complex indexes
      Query query = _firestore.collection('Product');
      
      // Only add essential filters to minimize index requirements
      // Filter for active products only (this is the most important filter)
      if (!includeInactive) {
        query = query.where('isActive', isEqualTo: true);
      }
      
      // Add category filter if specified (single additional WHERE clause)
      if (categoryId != null && categoryId != 'All' && categoryId.isNotEmpty) {
        query = query.where('categoryID', isEqualTo: categoryId);
      }
      
      // Order by creation date (most recent first)
      query = query.orderBy('createdAt', descending: true);
      
      // Add pagination parameters
      query = query.limit(limit);
      
      // If we have a last document, start after it
      if (lastDocument != null) {
        query = query.startAfterDocument(lastDocument);
      }
      
      // Execute the query
      QuerySnapshot querySnapshot = await query.get();
      
      //AppLogger.d('Fetched page with ${querySnapshot.docs.length} products');
      
      // Check if we've reached the end of the data
      bool hasMore = querySnapshot.docs.length == limit;
      
      // Get the last document for next pagination call
      DocumentSnapshot? lastVisibleDocument = 
          querySnapshot.docs.isNotEmpty ? querySnapshot.docs.last : null;

      List<Product> pageProducts = [];
      
      // Convert documents to products first
      List<Product> initialProducts = querySnapshot.docs
          .map((doc) => Product.fromFirestore(doc))
          .toList();
      
      // Apply client-side filtering for draft and archived status to avoid complex indexes
      List<Product> filteredProducts = initialProducts.where((product) {
        // Filter drafts on client side
        if (!includeDrafts && product.isDraft) return false;
        
        // Filter archived on client side  
        if (!includeArchived && product.isArchived) return false;
        
        // Filter subcategory on client side if specified
        if (subCategoryId != null && subCategoryId.isNotEmpty) {
          if (product.subCategoryId != subCategoryId) return false;
        }
        
        return true;
      }).toList();
      
      if (filteredProducts.isEmpty) {
        //AppLogger.d('No products found after client-side filtering');
        return {
          'products': pageProducts,
          'lastDocument': lastVisibleDocument,
          'hasMore': hasMore
        };
      }
      
      // Batch fetch all variations in parallel to avoid N+1 queries
      //AppLogger.d('Fetching variations for ${filteredProducts.length} products in parallel...');
      
      List<Future<List<ProductVariation>>> variationFutures = filteredProducts
          .map((product) => _getProductVariations(product.productId))
          .toList();
      
      List<List<ProductVariation>> allVariations = await Future.wait(variationFutures);
      
      // Combine products with their variations
      for (int i = 0; i < filteredProducts.length; i++) {
        Product product = filteredProducts[i];
        List<ProductVariation> variations = allVariations[i];
        
        if (variations.isNotEmpty) {
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
            isDraft: product.isDraft,
            isArchived: product.isArchived,
            clickCounter: product.clickCounter,
            variations: variations,
            hasWarranty: product.hasWarranty,
            warrantyType: product.warrantyType,
            warrantyPeriod: product.warrantyPeriod,
            warrantyPeriodUnit: product.warrantyPeriodUnit,
            warrantyPolicy: product.warrantyPolicy,
            allowInquiry: product.allowInquiry,
          );
        }
        
        pageProducts.add(product);
      }
      
      //AppLogger.d('Successfully fetched ${pageProducts.length} products');
      
      // Return a map with all pagination-related data
      return {
        'products': pageProducts,
        'lastDocument': lastVisibleDocument,
        'hasMore': hasMore
      };
    } catch (e) {
      //AppLogger.d('Error fetching paginated products: $e');
      //AppLogger.d('Stack trace: ${StackTrace.current}');
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
          isDraft: product.isDraft,
          isArchived: product.isArchived,
          clickCounter: product.clickCounter,
          variations: variations,
          hasWarranty: product.hasWarranty,
          warrantyType: product.warrantyType,
          warrantyPeriod: product.warrantyPeriod,
          warrantyPeriodUnit: product.warrantyPeriodUnit,
          warrantyPolicy: product.warrantyPolicy,
          allowInquiry: product.allowInquiry,
        );
      }
      
      return product;
    } catch (e) {
      //AppLogger.d('Error fetching product: $e');
      return null;
    }
  }

  // Check if the current user is a seller
  Future<Map<String, dynamic>> checkSellerStatus() async {
    try {
      User? currentUser = _auth.currentUser;
      final userUID = currentUser?.uid;
      
      if (currentUser == null || userUID == null) {
        return {
          'isSeller': false,
          'message': 'User is not logged in',
          'sellerId': null
        };
      }

      // Check if user exists in the users collection
      DocumentSnapshot userDoc = await _firestore
          .collection('User')
          .doc(userUID)
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

      // Check if there's an entry in the Seller collection - use server fetch to bypass cache
      DocumentSnapshot sellerDoc = await _firestore
          .collection('Seller')
          .doc(userUID)
          .get(const GetOptions(source: Source.server));
      
      if (!sellerDoc.exists) {
        return {
          'isSeller': false,
          'message': 'Seller profile not setup completely',
          'sellerId': null
        };
      }

      Map<String, dynamic> sellerData = sellerDoc.data() as Map<String, dynamic>;
      
      // Verify UIDs match between User and Seller collections
      if (userDoc.id != sellerDoc.id) {
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
      
      if (!isActive) {
        return {
          'isSeller': false,
          'message': 'Seller account is not active',
          'sellerId': null
        };
      }

      return {
        'isSeller': true,
        'message': 'User is a verified seller',
        'sellerId': userUID
      };
    } catch (e) {
      return {
        'isSeller': false,
        'message': 'Error checking seller status: $e',
        'sellerId': null
      };
    }
  }

  // Add a new product to Firestore
  Future<Map<String, dynamic>> addProduct(
      ProductFormModel productForm, List<VariationFormModel> variations, {bool isDraft = false}) async {
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
        'isActive': !isDraft, // If it's a draft, set isActive to false
        'isDraft': isDraft,
        'isArchived': false, // New products are not archived by default
        'clickCounter': 0,
        'hasWarranty': productForm.hasWarranty,
        'warrantyType': productForm.warrantyType,
        'warrantyPeriod': productForm.warrantyPeriod,
        'warrantyPolicy': productForm.warrantyPolicy,
        'allowInquiry': productForm.allowInquiry,
      });
      
      // Add variations as a sub-collection
      for (var variationForm in variations) {
        DocumentReference variationRef = productRef.collection('Variation').doc();
        
        await variationRef.set({
          'productId': productRef.id,
          'name': variationForm.name,
          'imageURL': variationForm.imageURL,
          'price': variationForm.price, // Price already includes VAT
          'stock': variationForm.stock,
          'sku': variationForm.sku,
          'weight': variationForm.weight,
          'dimensions': variationForm.dimensions,
          'isFragile': variationForm.isFragile,
        });
      }
      
      return {
        'success': true,
        'message': 'Product added successfully',
        'productId': productRef.id
      };
    } catch (e) {
      //AppLogger.d('Error adding product: $e');
      return {
        'success': false,
        'message': 'Error: $e',
        'productId': null
      };
    }
  }

  // Update an existing product in Firestore
  Future<Map<String, dynamic>> updateProduct(
      String productId, ProductFormModel productForm, List<VariationFormModel> variations, {bool? isDraft}) async {
    try {
      // First check if the user is a seller
      Map<String, dynamic> sellerStatus = await checkSellerStatus();
      
      if (!sellerStatus['isSeller']) {
        return {
          'success': false,
          'message': sellerStatus['message'],
        };
      }
      
      // Check if the product exists and belongs to the current user
      DocumentSnapshot productDoc = await _firestore.collection('Product').doc(productId).get();
      
      if (!productDoc.exists) {
        return {
          'success': false,
          'message': 'Product not found',
        };
      }
      
      Map<String, dynamic> productData = productDoc.data() as Map<String, dynamic>;
      String productSellerId = productData['sellerId'] ?? '';
      String currentUserSellerId = sellerStatus['sellerId'];
      
      if (productSellerId != currentUserSellerId) {
        return {
          'success': false,
          'message': 'You can only edit your own products',
        };
      }
      
      // Update the product document
      DocumentReference productRef = _firestore.collection('Product').doc(productId);
      DateTime now = DateTime.now();
      
      Map<String, dynamic> updateData = {
        'name': productForm.name,
        'description': productForm.description,
        'imageURL': productForm.imageURL,
        'categoryID': productForm.categoryId,
        'subCategoryID': productForm.subCategoryId,
        'updatedAt': Timestamp.fromDate(now),
        'hasWarranty': productForm.hasWarranty,
        'warrantyType': productForm.warrantyType,
        'warrantyPeriod': productForm.warrantyPeriod,
        'warrantyPolicy': productForm.warrantyPolicy,
        'allowInquiry': productForm.allowInquiry,
      };
      
      // Add isDraft field if it's provided
      if (isDraft != null) {
        updateData['isDraft'] = isDraft;
        updateData['isActive'] = !isDraft; // If it's a draft, set isActive to false
      }
      
      await productRef.update(updateData);
      
      // Handle variations update
      // First, get existing variations
      QuerySnapshot existingVariations = await productRef.collection('Variation').get();
      
      // Create a map of existing variations for easier lookup
      Map<String, DocumentSnapshot> existingVariationsMap = {};
      for (var doc in existingVariations.docs) {
        existingVariationsMap[doc.id] = doc;
      }
      
      // Track which variations we're keeping
      Set<String> variationsToKeep = {};
      
      // Update or create variations
      for (int index = 0; index < variations.length; index++) {
        var variationForm = variations[index];
        
        // Check if this is an existing variation (by checking if we can find a match)
        String? existingVariationId;
        
        // For existing variations, try to match by index first, then by properties
        if (index < existingVariations.docs.length) {
          existingVariationId = existingVariations.docs[index].id;
        }
        
        if (existingVariationId != null && existingVariationsMap.containsKey(existingVariationId)) {
          // Update existing variation
          await productRef.collection('Variation').doc(existingVariationId).update({
            'name': variationForm.name,
            'imageURL': variationForm.imageURL,
            'price': variationForm.price, // Price already includes VAT
            'stock': variationForm.stock,
            'sku': variationForm.sku,
            'weight': variationForm.weight,
            'dimensions': variationForm.dimensions,
            'isFragile': variationForm.isFragile,
          });
          variationsToKeep.add(existingVariationId);
        } else {
          // Create new variation
          DocumentReference variationRef = productRef.collection('Variation').doc();
          await variationRef.set({
            'productId': productId,
            'name': variationForm.name,
            'imageURL': variationForm.imageURL,
            'price': variationForm.price, // Price already includes VAT
            'stock': variationForm.stock,
            'sku': variationForm.sku,
            'weight': variationForm.weight,
            'dimensions': variationForm.dimensions,
            'isFragile': variationForm.isFragile,
          });
          variationsToKeep.add(variationRef.id);
        }
      }
      
      // Delete variations that are no longer needed
      for (var doc in existingVariations.docs) {
        if (!variationsToKeep.contains(doc.id)) {
          await doc.reference.delete();
        }
      }
      
      return {
        'success': true,
        'message': 'Product updated successfully',
      };
    } catch (e) {
      //AppLogger.d('Error updating product: $e');
      return {
        'success': false,
        'message': 'Error: $e',
      };
    }
  }

  // Get all products for a specific seller
  Future<List<Product>> getProductsBySeller(String sellerId) async {
    try {
      //AppLogger.d('ProductService: Fetching products for seller: $sellerId');
      
      // Use simple query to avoid index requirements
      QuerySnapshot querySnapshot = await _firestore
          .collection('Product')
          .where('sellerId', isEqualTo: sellerId)
          .get();
      
      //AppLogger.d('ProductService: Simple query successful with ${querySnapshot.docs.length} documents');
      
      //AppLogger.d('ProductService: Query returned ${querySnapshot.docs.length} documents');
      
      List<Product> products = [];
      for (var doc in querySnapshot.docs) {
        try {
          //AppLogger.d('ProductService: Processing document ${doc.id}');
          Product product = Product.fromFirestore(doc);
          
          // Filter by isActive manually since we're using simple query
          if (!product.isActive) {
            //AppLogger.d('ProductService: Skipping inactive product ${product.name}');
            continue;
          }
          
          // Get variations for each product
          QuerySnapshot variationsSnapshot = await _firestore
              .collection('Product')
              .doc(product.productId)
              .collection('Variation')
              .get();
          
          //AppLogger.d('ProductService: Found ${variationsSnapshot.docs.length} variations for ${product.name}');
          
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
              isDraft: product.isDraft,
              isArchived: product.isArchived,
              clickCounter: product.clickCounter,
              variations: variations,
              hasWarranty: product.hasWarranty,
              warrantyType: product.warrantyType,
              warrantyPeriod: product.warrantyPeriod,
              warrantyPeriodUnit: product.warrantyPeriodUnit,
              warrantyPolicy: product.warrantyPolicy,
              allowInquiry: product.allowInquiry,
            );
          }
          
          products.add(product);
          //AppLogger.d('ProductService: Added product ${product.name} to results');
        } catch (productError) {
          //AppLogger.d('ProductService: Error processing product document ${doc.id}: $productError');
        }
      }
      
      //AppLogger.d('ProductService: Final result - Fetched ${products.length} active products for seller $sellerId');
      return products;
    } catch (e) {
      //AppLogger.d('ProductService: Error fetching products for seller $sellerId: $e');
      //AppLogger.d('ProductService: Stack trace: ${StackTrace.current}');
      return [];
    }
  }
}
