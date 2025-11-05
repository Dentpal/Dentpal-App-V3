import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dentpal/utils/app_logger.dart';

class Product {
  final String productId;
  final String name;
  final String description;
  final String imageURL;
  final String categoryId;
  final String subCategoryId;
  final String sellerId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive;
  final bool isDraft;
  final bool isArchived;
  final int clickCounter;
  final List<ProductVariation>? variations;
  final bool hasWarranty;
  final String? warrantyType;
  final String? warrantyPeriod;
  final String? warrantyPeriodUnit;
  final String? warrantyPolicy;

  Product({
    required this.productId,
    required this.name,
    required this.description,
    required this.imageURL,
    required this.categoryId,
    required this.subCategoryId,
    required this.sellerId,
    required this.createdAt,
    required this.updatedAt,
    required this.isActive,
    required this.isDraft,
    required this.isArchived,
    required this.clickCounter,
    this.variations,
    required this.hasWarranty,
    this.warrantyType,
    this.warrantyPeriod,
    this.warrantyPeriodUnit,
    this.warrantyPolicy,
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
      AppLogger.d('Error parsing timestamps for product ${doc.id}: $e');
    }
    
    // Handle nullable string fields defensively
    String? warrantyType;
    String? warrantyPeriod;
    String? warrantyPeriodUnit;
    String? warrantyPolicy;
    
    try {
      // Convert non-null values to strings safely
      warrantyType = data['warrantyType']?.toString();
      warrantyPeriod = data['warrantyPeriod']?.toString();
      warrantyPeriodUnit = data['warrantyPeriodUnit']?.toString();
      warrantyPolicy = data['warrantyPolicy']?.toString();
    } catch (e) {
      AppLogger.d('Error parsing warranty fields for product ${doc.id}: $e');
    }
    
    return Product(
      productId: doc.id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      imageURL: data['imageURL'] ?? '',
      categoryId: data['categoryID'] ?? '',
      subCategoryId: data['subCategoryID'] ?? '',
      sellerId: data['sellerId'] ?? '',
      createdAt: createdAt,
      updatedAt: updatedAt,
      isActive: data['isActive'] ?? true,
      isDraft: data['isDraft'] ?? false,
      isArchived: data['isArchived'] ?? false,
      clickCounter: data['clickCounter'] ?? 0,
      variations: null, // Variations will be fetched separately
      hasWarranty: data['hasWarranty'] ?? false,
      warrantyType: warrantyType,
      warrantyPeriod: warrantyPeriod,
      warrantyPeriodUnit: warrantyPeriodUnit,
      warrantyPolicy: warrantyPolicy,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'imageURL': imageURL,
      'categoryID': categoryId,
      'subCategoryID': subCategoryId,
      'sellerId': sellerId,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'isActive': isActive,
      'isDraft': isDraft,
      'isArchived': isArchived,
      'clickCounter': clickCounter,
      'hasWarranty': hasWarranty,
      'warrantyType': warrantyType,
      'warrantyPeriod': warrantyPeriod,
      'warrantyPeriodUnit': warrantyPeriodUnit,
      'warrantyPolicy': warrantyPolicy,
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
  final String name;
  final String? imageURL;
  final double price;
  final int stock;
  final String sku;
  final double? weight;
  final Map<String, dynamic>? dimensions;

  ProductVariation({
    required this.variationId,
    required this.productId,
    required this.name,
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
      AppLogger.d('Error parsing numeric fields for variation ${doc.id}: $e');
    }
    
    return ProductVariation(
      variationId: doc.id,
      productId: data['productId'] ?? '',
      name: data['name'] ?? '',
      imageURL: data['imageURL'],
      price: price,
      stock: stock,
      sku: data['sku'] ?? data['SKU'] ?? '',
      weight: weight,
      dimensions: data['dimensions'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'name': name,
      'imageURL': imageURL,
      'price': price,
      'stock': stock,
      'sku': sku,
      'weight': weight,
      'dimensions': dimensions,
    };
  }
}

class Category {
  final String categoryId;
  final String categoryName;
  final int clickCounter;

  Category({
    required this.categoryId,
    required this.categoryName,
    required this.clickCounter,
  });

  factory Category.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    return Category(
      categoryId: doc.id,
      categoryName: data['categoryName'] ?? '',
      clickCounter: data['clickCounter'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'categoryName': categoryName,
      'clickCounter': clickCounter,
    };
  }
}

class SubCategory {
  final String subCategoryId;
  final String subCategoryName;
  final String categoryId;

  SubCategory({
    required this.subCategoryId,
    required this.subCategoryName,
    required this.categoryId,
  });

  factory SubCategory.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    return SubCategory(
      subCategoryId: doc.id,
      subCategoryName: data['subCategoryName'] ?? '',
      categoryId: data['categoryId'] ?? '',  // Changed from 'categoryID' to 'categoryId'
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'subCategoryName': subCategoryName,
      'categoryId': categoryId,  // Changed from 'categoryID' to 'categoryId'
    };
  }
}
