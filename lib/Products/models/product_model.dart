import 'package:cloud_firestore/cloud_firestore.dart';

class Product {
  final String productId;
  final String name;
  final String description;
  final String imageURL;
  final String category;
  final String sellerId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive;
  final List<ProductVariation>? variations;

  Product({
    required this.productId,
    required this.name,
    required this.description,
    required this.imageURL,
    required this.category,
    required this.sellerId,
    required this.createdAt,
    required this.updatedAt,
    required this.isActive,
    this.variations,
  });

  factory Product.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    // Add more defensive coding for timestamp fields
    DateTime createdAt = DateTime.now();
    DateTime updatedAt = DateTime.now();
    
    try {
      if (data['createdAt'] != null) {
        if (data['createdAt'] is Timestamp) {
          createdAt = (data['createdAt'] as Timestamp).toDate();
        } else if (data['createdAt'] is DateTime) {
          createdAt = data['createdAt'] as DateTime;
        }
      }
      
      if (data['updatedAt'] != null) {
        if (data['updatedAt'] is Timestamp) {
          updatedAt = (data['updatedAt'] as Timestamp).toDate();
        } else if (data['updatedAt'] is DateTime) {
          updatedAt = data['updatedAt'] as DateTime;
        }
      }
    } catch (e) {
      print('❌ Error parsing timestamps for product ${doc.id}: $e');
    }
    
    return Product(
      productId: doc.id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      imageURL: data['imageURL'] ?? '',
      category: data['category'] ?? '',
      sellerId: data['sellerId'] ?? '',
      createdAt: createdAt,
      updatedAt: updatedAt,
      isActive: data['isActive'] ?? true,
      variations: null, // Variations will be fetched separately
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'imageURL': imageURL,
      'category': category,
      'sellerId': sellerId,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'isActive': isActive,
    };
  }

  // Return the lowest price from all variations or null if no variations
  double? get lowestPrice {
    if (variations == null || variations!.isEmpty) return null;
    return variations!.map((v) => v.price).reduce((a, b) => a < b ? a : b);
  }
}

class ProductVariation {
  final String variationId;
  final String productId;
  final String? imageURL;
  final double price;
  final int stock;
  final String sku;
  final double? weight;
  final Map<String, dynamic>? dimensions;

  ProductVariation({
    required this.variationId,
    required this.productId,
    this.imageURL,
    required this.price,
    required this.stock,
    required this.sku,
    this.weight,
    this.dimensions,
  });

  factory ProductVariation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    // Handle numeric fields more defensively
    double price = 0;
    int stock = 0;
    double? weight;
    
    try {
      if (data['price'] != null) {
        if (data['price'] is double) {
          price = data['price'];
        } else if (data['price'] is int) {
          price = (data['price'] as int).toDouble();
        } else if (data['price'] is String) {
          price = double.tryParse(data['price']) ?? 0;
        }
      }
      
      if (data['stock'] != null) {
        if (data['stock'] is int) {
          stock = data['stock'];
        } else if (data['stock'] is double) {
          stock = (data['stock'] as double).toInt();
        } else if (data['stock'] is String) {
          stock = int.tryParse(data['stock']) ?? 0;
        }
      }
      
      if (data['weight'] != null) {
        if (data['weight'] is double) {
          weight = data['weight'];
        } else if (data['weight'] is int) {
          weight = (data['weight'] as int).toDouble();
        } else if (data['weight'] is String) {
          weight = double.tryParse(data['weight']);
        }
      }
    } catch (e) {
      print('❌ Error parsing numeric fields for variation ${doc.id}: $e');
    }
    
    return ProductVariation(
      variationId: doc.id,
      productId: data['productId'] ?? '',
      imageURL: data['imageURL'],
      price: price,
      stock: stock,
      sku: data['SKU'] ?? '',
      weight: weight,
      dimensions: data['dimensions'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'imageURL': imageURL,
      'price': price,
      'stock': stock,
      'SKU': sku,
      'weight': weight,
      'dimensions': dimensions,
    };
  }
}
