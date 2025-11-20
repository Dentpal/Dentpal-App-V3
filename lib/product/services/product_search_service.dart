import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dentpal/product/models/product_model.dart';
import 'package:dentpal/utils/app_logger.dart';

enum SortBy {
  relevance,
  priceAsc,
  priceDesc,
  nameAsc,
  nameDesc,
  newest,
  oldest,
  clickCount,
}

class SearchFilters {
  final List<String> categoryIds;
  final List<String> subCategoryIds;
  final double? minPrice;
  final double? maxPrice;
  final bool? hasWarranty;
  final SortBy sortBy;

  SearchFilters({
    this.categoryIds = const [],
    this.subCategoryIds = const [],
    this.minPrice,
    this.maxPrice,
    this.hasWarranty,
    this.sortBy = SortBy.relevance,
  });

  SearchFilters copyWith({
    List<String>? categoryIds,
    List<String>? subCategoryIds,
    double? minPrice,
    double? maxPrice,
    bool? hasWarranty,
    SortBy? sortBy,
  }) {
    return SearchFilters(
      categoryIds: categoryIds ?? this.categoryIds,
      subCategoryIds: subCategoryIds ?? this.subCategoryIds,
      minPrice: minPrice ?? this.minPrice,
      maxPrice: maxPrice ?? this.maxPrice,
      hasWarranty: hasWarranty ?? this.hasWarranty,
      sortBy: sortBy ?? this.sortBy,
    );
  }

  // Helper getters for backward compatibility
  String? get categoryId => categoryIds.isNotEmpty ? categoryIds.first : null;
  String? get subCategoryId => subCategoryIds.isNotEmpty ? subCategoryIds.first : null;
}

class SearchResult {
  final List<Product> products;
  final DocumentSnapshot? lastDocument;
  final bool hasMore;
  final String? error;
  final int totalCount;

  SearchResult({
    required this.products,
    this.lastDocument,
    required this.hasMore,
    this.error,
    this.totalCount = 0,
  });
}

class ProductSearchService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const int _defaultPageSize = 15;

  /// Performs a comprehensive search for products
  /// Supports text search, category filtering, price filtering, and sorting
  Future<SearchResult> searchProducts({
    String? searchQuery,
    SearchFilters? filters,
    DocumentSnapshot? lastDocument,
    int limit = _defaultPageSize,
  }) async {
    try {
      AppLogger.d('ProductSearchService: Starting search with query: "$searchQuery"');
      AppLogger.d('ProductSearchService: Filters - categories: ${filters?.categoryIds}, subCategories: ${filters?.subCategoryIds}');
      
      // If we have a search query, use text-based search
      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        return _performTextSearch(
          searchQuery: searchQuery.trim(),
          filters: filters,
          lastDocument: lastDocument,
          limit: limit,
        );
      }
      
      // Otherwise, perform filtered browsing
      return _performFilteredBrowse(
        filters: filters,
        lastDocument: lastDocument,
        limit: limit,
      );
    } catch (e) {
      AppLogger.e('❌ ProductSearchService: Error in searchProducts', e);
      return SearchResult(
        products: [],
        hasMore: false,
        error: e.toString(),
      );
    }
  }

  /// Performs text-based search using Firestore's limitations workaround
  /// Since Firestore doesn't have full-text search, we use multiple queries
  Future<SearchResult> _performTextSearch({
    required String searchQuery,
    SearchFilters? filters,
    DocumentSnapshot? lastDocument,
    int limit = _defaultPageSize,
  }) async {
    try {
      AppLogger.d('ProductSearchService: Performing text search for: "$searchQuery"');
      
      // Convert search query to lowercase for case-insensitive search
      String lowerQuery = searchQuery.toLowerCase();
      
      // Create search terms for better matching
      List<String> searchTerms = lowerQuery.split(' ').where((term) => term.isNotEmpty).toList();
      AppLogger.d('ProductSearchService: Search terms: $searchTerms');
      
      // Use the simplest possible query to avoid any index requirements
      Query baseQuery = _firestore
          .collection('Product');
      
      // No where clauses, no orderBy - just get documents and filter everything client-side
      AppLogger.d('ProductSearchService: Using simplest query (no filters, no ordering)');
      
      // Apply pagination if we have a lastDocument
      if (lastDocument != null) {
        baseQuery = baseQuery.startAfterDocument(lastDocument);
        AppLogger.d('ProductSearchService: Pagination applied with lastDocument');
      }
      
      // Fetch more documents than needed for client-side filtering
      int fetchLimit = limit * 10; // Fetch 10x to account for filtering
      baseQuery = baseQuery.limit(fetchLimit);
      
      AppLogger.d('ProductSearchService: Executing simple query with limit: $fetchLimit');
      
      QuerySnapshot querySnapshot = await baseQuery.get();
      AppLogger.d('ProductSearchService: Fetched ${querySnapshot.docs.length} documents for filtering');
      
      // Debug: Log first few products to see what we're getting
      if (querySnapshot.docs.isNotEmpty) {
        for (int i = 0; i < querySnapshot.docs.length && i < 3; i++) {
          var doc = querySnapshot.docs[i];
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
          AppLogger.d('ProductSearchService: Sample product ${i + 1}: name="${data['name']}", description="${data['description']}"');
        }
      }
      
      // Filter results client-side for all conditions
      List<DocumentSnapshot> matchingDocs = querySnapshot.docs.where((doc) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        
        // Check basic product status first
        bool isActive = data['isActive'] ?? false;
        bool isDraft = data['isDraft'] ?? false;
        bool isArchived = data['isArchived'] ?? false;
        if (!isActive || isDraft || isArchived) {
          AppLogger.d('ProductSearchService: Filtering out inactive/draft/archived product: ${data['name']}');
          return false;
        }
        
        // Apply text search filter
        String name = (data['name'] ?? '').toString().toLowerCase();
        String description = (data['description'] ?? '').toString().toLowerCase();
        
        AppLogger.d('ProductSearchService: Checking product: "$name" against terms: $searchTerms');
        
        bool textMatches = searchTerms.any((term) => 
          name.contains(term) || description.contains(term)
        );
        
        if (!textMatches) {
          AppLogger.d('ProductSearchService: No text match for: "$name"');
          return false;
        }
        
        // Apply category filter if specified
        if (filters?.categoryIds.isNotEmpty == true) {
          String productCategoryId = data['categoryID'] ?? '';
          if (!filters!.categoryIds.contains(productCategoryId)) {
            AppLogger.d('ProductSearchService: Category filter mismatch for: "$name"');
            return false;
          }
        }
        
        // Apply subcategory filter if specified
        if (filters?.subCategoryIds.isNotEmpty == true) {
          String productSubCategoryId = data['subCategoryID'] ?? '';
          if (!filters!.subCategoryIds.contains(productSubCategoryId)) {
            AppLogger.d('ProductSearchService: Subcategory filter mismatch for: "$name"');
            return false;
          }
        }
        
        // Apply warranty filter if specified
        if (filters?.hasWarranty != null) {
          bool productHasWarranty = data['hasWarranty'] ?? false;
          if (productHasWarranty != filters!.hasWarranty) {
            AppLogger.d('ProductSearchService: Warranty filter mismatch for: "$name"');
            return false;
          }
        }
        
        AppLogger.d('ProductSearchService: All filters passed for product: "$name"');
        return true;
      }).toList();
      
      // Take only the requested limit
      List<DocumentSnapshot> limitedDocs = matchingDocs.take(limit).toList();
      
      AppLogger.d('ProductSearchService: Found ${limitedDocs.length} matching products after client-side filtering');
      
      // Convert to Product objects with variations
      List<Product> products = [];
      for (var doc in limitedDocs) {
        try {
          Product product = await _buildProductWithVariations(doc);
          
          // Apply price filtering if specified (client-side)
          if (_matchesPriceFilter(product, filters)) {
            products.add(product);
            AppLogger.d('ProductSearchService: Added product: ${product.name}');
          } else {
            AppLogger.d('ProductSearchService: Product ${product.name} filtered out by price');
          }
        } catch (e) {
          AppLogger.w('⚠️ ProductSearchService: Error building product ${doc.id}: $e');
        }
      }
      
      // Apply client-side sorting
      if (filters?.sortBy != null) {
        products = sortProducts(products, filters!.sortBy);
        AppLogger.d('ProductSearchService: Applied client-side sorting: ${filters.sortBy}');
      }
      
      // Determine if there are more results
      bool hasMore = matchingDocs.length > limit;
      DocumentSnapshot? lastDoc = limitedDocs.isNotEmpty ? limitedDocs.last : null;
      
      AppLogger.d('ProductSearchService: Returning ${products.length} products, hasMore: $hasMore');
      
      return SearchResult(
        products: products,
        lastDocument: lastDoc,
        hasMore: hasMore,
        totalCount: products.length,
      );
    } catch (e) {
      AppLogger.e('❌ ProductSearchService: Error in text search', e);
      return SearchResult(
        products: [],
        hasMore: false,
        error: e.toString(),
      );
    }
  }

  /// Performs filtered browsing without text search
  Future<SearchResult> _performFilteredBrowse({
    SearchFilters? filters,
    DocumentSnapshot? lastDocument,
    int limit = _defaultPageSize,
  }) async {
    try {
      AppLogger.d('ProductSearchService: Performing filtered browse');
      
      // Use the simplest possible query to avoid any index requirements
      Query query = _firestore
          .collection('Product');
      
      // No where clauses, no orderBy - just get documents and filter everything client-side
      AppLogger.d('ProductSearchService: Using simplest query (no filters, no ordering)');
      
      // Apply pagination if we have a lastDocument
      if (lastDocument != null) {
        query = query.startAfterDocument(lastDocument);
      }
      
      // Fetch more documents for client-side filtering
      query = query.limit(limit * 10);
      
      QuerySnapshot querySnapshot = await query.get();
      AppLogger.d('ProductSearchService: Fetched ${querySnapshot.docs.length} documents');
      
      // Filter results client-side
      List<DocumentSnapshot> filteredDocs = querySnapshot.docs.where((doc) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        
        // Check basic product status
        bool isActive = data['isActive'] ?? false;
        bool isDraft = data['isDraft'] ?? false;
        bool isArchived = data['isArchived'] ?? false;
        if (!isActive || isDraft || isArchived) return false;
        
        // Apply category filter
        if (filters?.categoryIds.isNotEmpty == true) {
          String productCategoryId = data['categoryID'] ?? '';
          if (!filters!.categoryIds.contains(productCategoryId)) return false;
        }
        
        // Apply subcategory filter
        if (filters?.subCategoryIds.isNotEmpty == true) {
          String productSubCategoryId = data['subCategoryID'] ?? '';
          if (!filters!.subCategoryIds.contains(productSubCategoryId)) return false;
        }
        
        // Apply warranty filter
        if (filters?.hasWarranty != null) {
          bool productHasWarranty = data['hasWarranty'] ?? false;
          if (productHasWarranty != filters!.hasWarranty) return false;
        }
        
        return true;
      }).toList();
      
      // Take only the requested limit
      List<DocumentSnapshot> limitedDocs = filteredDocs.take(limit).toList();
      
      // Convert to Product objects with variations
      List<Product> products = [];
      for (var doc in limitedDocs) {
        try {
          Product product = await _buildProductWithVariations(doc);
          
          // Apply price filtering if specified (client-side)
          if (_matchesPriceFilter(product, filters)) {
            products.add(product);
          }
        } catch (e) {
          AppLogger.w('⚠️ ProductSearchService: Error building product ${doc.id}: $e');
        }
      }
      
      // Apply client-side sorting
      if (filters?.sortBy != null) {
        products = sortProducts(products, filters!.sortBy);
        AppLogger.d('ProductSearchService: Applied client-side sorting: ${filters.sortBy}');
      }
      
      bool hasMore = filteredDocs.length > limit;
      DocumentSnapshot? lastDoc = limitedDocs.isNotEmpty ? limitedDocs.last : null;
      
      AppLogger.d('ProductSearchService: Returning ${products.length} products, hasMore: $hasMore');
      
      return SearchResult(
        products: products,
        lastDocument: lastDoc,
        hasMore: hasMore,
        totalCount: products.length,
      );
    } catch (e) {
      AppLogger.e('❌ ProductSearchService: Error in filtered browse', e);
      return SearchResult(
        products: [],
        hasMore: false,
        error: e.toString(),
      );
    }
  }

  /// Builds a Product object with its variations
  Future<Product> _buildProductWithVariations(DocumentSnapshot doc) async {
    Product product = Product.fromFirestore(doc);
    
    // Get variations for the product
    QuerySnapshot variationsSnapshot = await _firestore
        .collection('Product')
        .doc(product.productId)
        .collection('Variation')
        .get();
    
    if (variationsSnapshot.docs.isNotEmpty) {
      List<ProductVariation> variations = variationsSnapshot.docs
          .map((doc) => ProductVariation.fromFirestore(doc))
          .toList();
      
      // Create a new Product instance with variations
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
  }

  /// Checks if a product matches the price filter
  bool _matchesPriceFilter(Product product, SearchFilters? filters) {
    if (filters?.minPrice == null && filters?.maxPrice == null) {
      return true;
    }
    
    double? productPrice = product.lowestPrice;
    if (productPrice == null) return true; // No price filtering for products without variations
    
    if (filters?.minPrice != null && productPrice < filters!.minPrice!) {
      return false;
    }
    
    if (filters?.maxPrice != null && productPrice > filters!.maxPrice!) {
      return false;
    }
    
    return true;
  }

  /// Gets search suggestions based on partial input
  Future<List<String>> getSearchSuggestions(String partialQuery) async {
    try {
      if (partialQuery.trim().isEmpty) return [];
      
      String lowerQuery = partialQuery.toLowerCase();
      
      // Simple suggestion system - in production, you might want to maintain
      // a separate collection for search terms or use a dedicated search service
      QuerySnapshot querySnapshot = await _firestore
          .collection('Product')
          .where('isActive', isEqualTo: true)
          .limit(50) // Limit for performance
          .get();
      
      Set<String> suggestions = {};
      
      for (var doc in querySnapshot.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        String name = (data['name'] ?? '').toString();
        
        if (name.toLowerCase().contains(lowerQuery)) {
          suggestions.add(name);
        }
      }
      
      return suggestions.take(10).toList(); // Return top 10 suggestions
    } catch (e) {
      AppLogger.e('❌ ProductSearchService: Error getting suggestions', e);
      return [];
    }
  }

  /// Sorts products client-side for all sorting options
  List<Product> sortProducts(List<Product> products, SortBy sortBy) {
    switch (sortBy) {
      case SortBy.priceAsc:
        products.sort((a, b) {
          double? priceA = a.lowestPrice ?? double.infinity;
          double? priceB = b.lowestPrice ?? double.infinity;
          return priceA.compareTo(priceB);
        });
        break;
      case SortBy.priceDesc:
        products.sort((a, b) {
          double? priceA = a.lowestPrice ?? double.infinity;
          double? priceB = b.lowestPrice ?? double.infinity;
          return priceB.compareTo(priceA);
        });
        break;
      case SortBy.nameAsc:
        products.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case SortBy.nameDesc:
        products.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
      case SortBy.newest:
        products.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case SortBy.oldest:
        products.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case SortBy.clickCount:
        products.sort((a, b) => b.clickCounter.compareTo(a.clickCounter));
        break;
      case SortBy.relevance:
        // For relevance, keep the order as is (already sorted by createdAt desc from Firestore)
        break;
    }
    
    return products;
  }

  /// Sorts products client-side for price-based sorting
  List<Product> sortProductsByPrice(List<Product> products, bool ascending) {
    products.sort((a, b) {
      double? priceA = a.lowestPrice ?? double.infinity;
      double? priceB = b.lowestPrice ?? double.infinity;
      
      if (ascending) {
        return priceA.compareTo(priceB);
      } else {
        return priceB.compareTo(priceA);
      }
    });
    
    return products;
  }
}
