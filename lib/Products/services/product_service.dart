import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product_model.dart';

class ProductService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get all active products
  Future<List<Product>> getProducts() async {
    try {
      print('🔍 Fetching products from Firestore...');
      
      // First, let's get all products without filters to debug
      QuerySnapshot allProducts = await _firestore
          .collection('Product')
          .get();
      
      print('📊 Total products in Firestore: ${allProducts.docs.length}');
      
      if (allProducts.docs.isEmpty) {
        print('❌ No products found in the database at all.');
        return [];
      }
      
      // Let's temporarily remove the isActive filter to see if that's the issue
      QuerySnapshot querySnapshot = await _firestore
          .collection('Product')
          .orderBy('createdAt', descending: true)
          .get();
      
      print('🔢 Products after filtering (isActive=true): ${querySnapshot.docs.length}');
      
      if (querySnapshot.docs.isEmpty) {
        print('⚠️ No active products found. Checking if isActive field exists...');
        
        // Check one product to see its structure
        if (allProducts.docs.isNotEmpty) {
          print('📄 Example product data: ${allProducts.docs[0].data()}');
        }
      }

      List<Product> products = [];
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
        
        products.add(product);
      }
      
      print('✅ Successfully fetched ${products.length} products');
      return products;
    } catch (e) {
      print('❌ Error fetching products: $e');
      print('Stack trace: ${StackTrace.current}');
      return [];
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
          category: product.category,
          sellerId: product.sellerId,
          createdAt: product.createdAt,
          updatedAt: product.updatedAt,
          isActive: product.isActive,
          variations: variations,
        );
      }
      
      return product;
    } catch (e) {
      print('Error fetching product: $e');
      return null;
    }
  }
}
