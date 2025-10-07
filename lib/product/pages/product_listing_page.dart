import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product_model.dart';
import '../services/product_service.dart';
import '../services/user_service.dart';
import '../services/category_service.dart';
import '../services/click_tracking_service.dart';
import '../widgets/product_card.dart';
import '../../core/app_theme/app_colors.dart';
import '../../core/app_theme/app_text_styles.dart';
import 'package:dentpal/utils/app_logger.dart';
import 'product_detail_page.dart';
import 'package:flutter/services.dart';

// Custom cache manager with 24 hour TTL
class ProductImageCacheManager {
  static const key = 'productImageCache';
  static CacheManager instance = CacheManager(
    Config(
      key,
      stalePeriod: const Duration(days: 1),
      maxNrOfCacheObjects: 200,
      repo: JsonCacheInfoRepository(databaseName: key),
      fileService: HttpFileService(),
    ),
  );
}

class ProductListingPage extends StatefulWidget {
  const ProductListingPage({super.key, this.isStandalone = false});

  // Flag to indicate if this page is used standalone (not within bottom navigation)
  final bool isStandalone;

  @override
  _ProductListingPageState createState() => _ProductListingPageState();
}

class _ProductListingPageState extends State<ProductListingPage> with AutomaticKeepAliveClientMixin<ProductListingPage> {
  final ProductService _productService = ProductService();
  final UserService _userService = UserService();
  final CategoryService _categoryService = CategoryService();
  final ClickTrackingService _clickTrackingService = ClickTrackingService();
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String _selectedCategory = 'All';
  List<String> _categories = ['All'];
  String? _errorMessage;
  List<Product> _products = [];
  DateTime? _cacheTimestamp;
  DocumentSnapshot? _lastDocument;
  bool _hasMore = true;
  final int _pageSize = 15;
  final ScrollController _scrollController = ScrollController();
  
  bool _isSeller = false;
  String _userFirstName = 'User';
  
  // Mapping between category names and IDs for filtering
  Map<String, String> _categoryNameToId = {};
  Map<String, String> _categoryIdToName = {};
  
  // Subcategory state
  List<SubCategory> _subcategories = [];
  String? _selectedSubCategory;
  bool _isLoadingSubcategories = false;
  bool _isSubcategoriesExpanded = false;

  // Override to keep this page alive when navigating away
  @override
  bool get wantKeepAlive => true;

  // Static instance for the singleton pattern
  static _ProductListingPageState? _instance;
  
  @override
  void initState() {
    super.initState();
    
    // If we already have an instance, use its data
    if (_instance != null) {
      _products = _instance!._products;
      _cacheTimestamp = _instance!._cacheTimestamp;
      _categories = _instance!._categories;
      _selectedCategory = _instance!._selectedCategory;
      _isLoading = _instance!._isLoading;
      _lastDocument = _instance!._lastDocument;
      _hasMore = _instance!._hasMore;
      _errorMessage = _instance!._errorMessage;
      _isSeller = _instance!._isSeller;
      _userFirstName = _instance!._userFirstName;
      _categoryNameToId = _instance!._categoryNameToId;
      _categoryIdToName = _instance!._categoryIdToName;
      _subcategories = _instance!._subcategories;
      _selectedSubCategory = _instance!._selectedSubCategory;
      _isLoadingSubcategories = _instance!._isLoadingSubcategories;
      _isSubcategoriesExpanded = _instance!._isSubcategoriesExpanded;
      
      // Check if cache is expired (older than 12 hours)
      if (_isCacheExpired()) {
        _resetAndRefresh();
      }
      
      // Only check seller status if not already done
      if (!_isSeller) {
        _checkSellerStatus();
      }
      
      // Load user name if not already loaded
      if (_userFirstName == 'User') {
        _loadUserName();
      }
    } else {
      // First time initialization
      _loadFirstPage();
      _checkSellerStatus();
      _loadUserName();
    }
    
    // Add scroll listener for pagination
    _scrollController.addListener(_scrollListener);
    
    // Store this instance as the static instance
    _instance = this;
    
    // Clean up old click tracking data (run async without waiting)
    _clickTrackingService.cleanupOldClickData();
    
    // Add debug log to track initialization
    AppLogger.d("🔵 ProductListingPage initState called, products: ${_products.length}, timestamp: $_cacheTimestamp");
  }
  
  @override
  void dispose() {
    // Remove scroll listener to prevent memory leaks
    _scrollController.removeListener(_scrollListener);
    
    // Don't clear the static instance on dispose, we want to keep it
    // Only clean up resources if needed
    AppLogger.d("🔴 ProductListingPage dispose called, keeping cached data");
    super.dispose();
  }
  
  Future<void> _checkSellerStatus() async {
    try {
      AppLogger.d('🔄 ProductListingPage: Checking seller status...');
      final result = await _productService.checkSellerStatus();
      AppLogger.d('🔍 ProductListingPage: Seller status result: $result');
      
      if (mounted) {
        setState(() {
          _isSeller = result['isSeller'] ?? false;
        });
        AppLogger.d('🔍 ProductListingPage: Updated _isSeller to: $_isSeller');
      }
    } catch (e) {
      AppLogger.d('❌ ProductListingPage: Error checking seller status: $e');
      if (mounted) {
        setState(() {
          _isSeller = false;
        });
      }
    }
  }
  
  Future<void> _loadUserName() async {
    final firstName = await _userService.getUserFirstName();
    if (mounted) {
      setState(() {
        _userFirstName = firstName;
      });
    }
  }
  

  
  bool _isCacheExpired() {
    if (_cacheTimestamp == null) return true;
    
    final now = DateTime.now();
    final difference = now.difference(_cacheTimestamp!);
    return difference.inHours >= 12; // Cache expires after 12 hours
  }
  
  // Reset all pagination parameters and refresh the data
  void _resetAndRefresh() {
    setState(() {
      _products = [];
      _lastDocument = null;
      _hasMore = true;
      _errorMessage = null;
      _cacheTimestamp = null;
    });
    
    _loadFirstPage();
  }
  
  // Scroll listener for detecting when user reaches bottom
  void _scrollListener() {
    if (_scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 200 &&
        !_isLoading && 
        !_isLoadingMore && 
        _hasMore) {
      _loadNextPage();
    }
  }
  
  // Handle category selection
  void _onCategorySelected(String category) {
    if (_selectedCategory == category) return;
    
    // Track category click if it's not 'All'
    if (category != 'All') {
      final categoryId = _categoryNameToId[category];
      if (categoryId != null) {
        _clickTrackingService.trackCategoryClick(categoryId);
      }
    }
    
    setState(() {
      _selectedCategory = category;
      // Reset subcategory selection when switching categories
      _selectedSubCategory = null;
      _subcategories = [];
      _isSubcategoriesExpanded = false;
      // Reset pagination parameters for the new category
      _products = [];
      _lastDocument = null;
      _hasMore = true;
      _isLoading = false;
      _isLoadingMore = false;
    });
    
    // Load subcategories for the selected category if it's not 'All'
    if (category != 'All') {
      _loadSubcategories(category);
    }
    
    // Load first page with the new category
    _loadFirstPage();
    
    // Update the static instance
    if (_instance != null) {
      _instance!._selectedCategory = category;
      _instance!._selectedSubCategory = null;
      _instance!._subcategories = [];
      _instance!._isSubcategoriesExpanded = false;
    }
  }

  // Load subcategories for a given category
  Future<void> _loadSubcategories(String categoryName) async {
    final categoryId = _categoryNameToId[categoryName];
    if (categoryId == null) return;
    
    setState(() {
      _isLoadingSubcategories = true;
    });
    
    try {
      final subcategories = await _categoryService.getSubCategories(categoryId);
      if (mounted) {
        setState(() {
          _subcategories = subcategories;
          _isLoadingSubcategories = false;
          // Auto-expand if subcategories are found
          _isSubcategoriesExpanded = subcategories.isNotEmpty;
        });
        
        // Update the static instance
        if (_instance != null) {
          _instance!._subcategories = subcategories;
          _instance!._isLoadingSubcategories = false;
          _instance!._isSubcategoriesExpanded = subcategories.isNotEmpty;
        }
      }
    } catch (e) {
      AppLogger.d('❌ Error loading subcategories: $e');
      if (mounted) {
        setState(() {
          _subcategories = [];
          _isLoadingSubcategories = false;
          _isSubcategoriesExpanded = false;
        });
      }
    }
  }

  // Handle subcategory selection
  void _onSubCategorySelected(String subCategoryId, String subCategoryName) {
    if (_selectedSubCategory == subCategoryId) return;
    
    // Track subcategory click (need categoryId)
    final categoryId = _categoryNameToId[_selectedCategory];
    if (categoryId != null) {
      _clickTrackingService.trackSubCategoryClick(categoryId, subCategoryId);
    }
    
    setState(() {
      _selectedSubCategory = subCategoryId;
      // Reset pagination parameters for the new subcategory
      _products = [];
      _lastDocument = null;
      _hasMore = true;
      _isLoading = false;
      _isLoadingMore = false;
    });
    
    // Load first page with the new subcategory
    _loadFirstPage();
    
    // Update the static instance
    if (_instance != null) {
      _instance!._selectedSubCategory = subCategoryId;
    }
  }
  
  // Load the first page of products
  Future<void> _loadFirstPage() async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      AppLogger.d('🔄 ProductListingPage: Loading first page of products...');
      AppLogger.d('🔍 DEBUG: Selected category "$_selectedCategory" maps to ID: ${_categoryNameToId[_selectedCategory]}');
      
      // Load all products first, then filter on client side to avoid Firestore index issues
      final result = await _productService.getProductsPaginated(
        limit: _pageSize,
        categoryId: null, // Always load all products to avoid index issues
      );
      
      final newProducts = result['products'] as List<Product>;
      final lastDoc = result['lastDocument'] as DocumentSnapshot?;
      final hasMore = result['hasMore'] as bool;
      
      // Extract all unique categories if this is the first load
      if (_categories.length <= 1) {
        try {
          // Fetch all categories from CategoryService
          final allCategories = await _categoryService.getCategories();
          
          AppLogger.d('🔍 DEBUG: Fetched ${allCategories.length} categories from service');
          
          // Build categories list starting with 'All'
          Set<String> categorySet = {'All'};
          
          // Clear existing mappings
          _categoryNameToId.clear();
          _categoryIdToName.clear();
          
          // Add all category names from the service and build mappings
          for (var category in allCategories) {
            AppLogger.d('🔍 DEBUG: Category - Name: ${category.categoryName}, ID: ${category.categoryId}');
            categorySet.add(category.categoryName);
            _categoryNameToId[category.categoryName] = category.categoryId;
            _categoryIdToName[category.categoryId] = category.categoryName;
          }
          
          _categories = categorySet.toList();
          AppLogger.d('🔍 DEBUG: Final categories list: $_categories');
          AppLogger.d('🔍 DEBUG: Category name to ID mapping: $_categoryNameToId');
          
          // Update static instance
          if (_instance != null) {
            _instance!._categories = _categories;
            _instance!._categoryNameToId = _categoryNameToId;
            _instance!._categoryIdToName = _categoryIdToName;
          }
        } catch (e) {
          AppLogger.d('❌ Error loading categories: $e');
          // Fallback to just 'All' if category loading fails
          _categories = ['All'];
        }
      }
      
      setState(() {
        _products = newProducts;
        _lastDocument = lastDoc;
        _hasMore = hasMore;
        _isLoading = false;
        _cacheTimestamp = DateTime.now();
        
        // Update static instance
        if (_instance != null) {
          _instance!._products = _products;
          _instance!._lastDocument = _lastDocument;
          _instance!._hasMore = _hasMore;
          _instance!._cacheTimestamp = _cacheTimestamp;
        }
      });
      
      AppLogger.d('✅ Loaded ${newProducts.length} products (first page)');
    } catch (e) {
      AppLogger.d('❌ Error loading first page: $e');
      AppLogger.d('Stack trace: ${StackTrace.current}');
      
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }
  
  // Load the next page of products
  Future<void> _loadNextPage() async {
    if (_isLoadingMore || !_hasMore || _lastDocument == null) return;
    
    setState(() {
      _isLoadingMore = true;
    });
    
    try {
      AppLogger.d('🔄 ProductListingPage: Loading more products...');
      
      // Load all products first, then filter on client side to avoid Firestore index issues
      final result = await _productService.getProductsPaginated(
        limit: _pageSize,
        lastDocument: _lastDocument,
        categoryId: null, // Always load all products to avoid index issues
      );
      
      final newProducts = result['products'] as List<Product>;
      final lastDoc = result['lastDocument'] as DocumentSnapshot?;
      final hasMore = result['hasMore'] as bool;
      
      setState(() {
        _products.addAll(newProducts);
        _lastDocument = lastDoc;
        _hasMore = hasMore;
        _isLoadingMore = false;
        
        // Update static instance
        if (_instance != null) {
          _instance!._products = _products;
          _instance!._lastDocument = _lastDocument;
          _instance!._hasMore = _hasMore;
        }
      });
      
      AppLogger.d('✅ Loaded ${newProducts.length} more products');
    } catch (e) {
      AppLogger.d('❌ Error loading more products: $e');
      AppLogger.d('Stack trace: ${StackTrace.current}');
      
      setState(() {
        _isLoadingMore = false;
      });
    }
  }
  
  // Helper method to compare product lists for change detection
  bool _hasDataChanged(List<Product> oldProducts, List<Product> newProducts) {
    if (oldProducts.length != newProducts.length) {
      AppLogger.d('🔍 Data changed: Product count differs (${oldProducts.length} vs ${newProducts.length})');
      return true;
    }
    
    for (int i = 0; i < oldProducts.length; i++) {
      final oldProduct = oldProducts[i];
      final newProduct = newProducts[i];
      
      if (oldProduct.productId != newProduct.productId ||
          oldProduct.name != newProduct.name ||
          oldProduct.lowestPrice != newProduct.lowestPrice ||
          oldProduct.imageURL != newProduct.imageURL ||
          oldProduct.categoryId != newProduct.categoryId) {
        AppLogger.d('🔍 Data changed: Product ${oldProduct.name} has differences');
        return true;
      }
    }
    
    return false;
  }
  
  // Helper method to compare category data for changes
  bool _hasCategoryDataChanged(Map<String, String> oldMapping, Map<String, String> newMapping) {
    if (oldMapping.length != newMapping.length) {
      AppLogger.d('🔍 Categories changed: Count differs (${oldMapping.length} vs ${newMapping.length})');
      return true;
    }
    
    for (final entry in oldMapping.entries) {
      if (newMapping[entry.key] != entry.value) {
        AppLogger.d('🔍 Categories changed: ${entry.key} mapping differs');
        return true;
      }
    }
    
    return false;
  }

  // Handle pull-to-refresh with cache-first approach and change detection
  Future<void> _handleRefresh() async {
    AppLogger.d('🔄 ProductListingPage: Pull-to-refresh triggered (cache-first approach)');
    
    try {
      // Keep current data as backup
      final currentProducts = List<Product>.from(_products);
      final currentCategories = Map<String, String>.from(_categoryNameToId);
      final currentTimestamp = _cacheTimestamp;
      
      AppLogger.d('📋 Current cache: ${currentProducts.length} products, ${currentCategories.length} categories');
      
      // Fetch fresh data from Firebase
      AppLogger.d('🌐 Fetching fresh data from Firebase...');
      final result = await _productService.getProductsPaginated(
        limit: _pageSize,
        categoryId: null,
      );
      
      final freshProducts = result['products'] as List<Product>;
      
      // Fetch fresh categories
      Map<String, String> freshCategoryMapping = {};
      Map<String, String> freshCategoryIdToName = {};
      List<String> freshCategoriesList = ['All'];
      
      try {
        final allCategories = await _categoryService.getCategories();
        for (var category in allCategories) {
          freshCategoriesList.add(category.categoryName);
          freshCategoryMapping[category.categoryName] = category.categoryId;
          freshCategoryIdToName[category.categoryId] = category.categoryName;
        }
        AppLogger.d('📂 Fetched ${allCategories.length} fresh categories');
      } catch (e) {
        AppLogger.d('❌ Error fetching fresh categories: $e');
        // Keep existing categories on error
        freshCategoryMapping = currentCategories;
        freshCategoriesList = _categories;
      }
      
      // Compare data for changes
      final hasProductChanges = _hasDataChanged(currentProducts, freshProducts);
      final hasCategoryChanges = _hasCategoryDataChanged(currentCategories, freshCategoryMapping);
      final hasAnyChanges = hasProductChanges || hasCategoryChanges;
      
      if (hasAnyChanges || currentTimestamp == null || _isCacheExpired()) {
        AppLogger.d('🔄 Changes detected or cache expired - updating data');
        
        // Update with fresh data
        setState(() {
          _products = freshProducts;
          _lastDocument = result['lastDocument'] as DocumentSnapshot?;
          _hasMore = result['hasMore'] as bool;
          _categories = freshCategoriesList;
          _categoryNameToId = freshCategoryMapping;
          _categoryIdToName = freshCategoryIdToName;
          _cacheTimestamp = DateTime.now();
          _errorMessage = null;
        });
        
        // Update static instance
        if (_instance != null) {
          _instance!._products = _products;
          _instance!._lastDocument = _lastDocument;
          _instance!._hasMore = _hasMore;
          _instance!._categories = _categories;
          _instance!._categoryNameToId = _categoryNameToId;
          _instance!._categoryIdToName = _categoryIdToName;
          _instance!._cacheTimestamp = _cacheTimestamp;
        }
        
        // Clear image cache only if there are actual changes
        if (hasProductChanges) {
          AppLogger.d('🗑️ Clearing image cache due to product changes');
          await ProductImageCacheManager.instance.emptyCache();
        }
        
        AppLogger.d('✅ Data updated: ${freshProducts.length} products, ${freshCategoriesList.length - 1} categories');
      } else {
        // No changes detected, just refresh timestamp
        setState(() {
          _cacheTimestamp = DateTime.now();
        });
        
        // Update static instance timestamp
        if (_instance != null) {
          _instance!._cacheTimestamp = _cacheTimestamp;
        }
        
        AppLogger.d('ℹ️ No changes detected - cache timestamp refreshed');
      }
      
    } catch (e) {
      AppLogger.d('❌ Refresh error: $e');
      AppLogger.d('Stack trace: ${StackTrace.current}');
      
      // Keep existing data on error, but show error state if we have no data
      if (_products.isEmpty) {
        setState(() {
          _errorMessage = 'Failed to refresh data: ${e.toString()}';
        });
      }
    }
    
    AppLogger.d('✅ ProductListingPage: Pull-to-refresh completed');
  }

  Future<bool> _showExitConfirmation() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.exit_to_app,
                color: AppColors.warning,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Exit App',
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to exit the app?',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.onSurface.withValues(alpha: 0.8),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.onSurface.withValues(alpha: 0.6),
            ),
            child: Text('Cancel', style: AppTextStyles.buttonMedium),
          ),
          ElevatedButton(
            onPressed: () {
              SystemNavigator.pop(); // Sends to background or closes app
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: AppColors.onPrimary,
              elevation: 0,
            ),
            child: Text('Exit', style: AppTextStyles.buttonMedium),
          ),
        ],
      ),
    ) ?? false;
  }
  
  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
    // Only wrap with PopScope if used standalone (not within home page navigation)
    if (!widget.isStandalone) {
      return _buildScaffold();
    }
    
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        
        final shouldExit = await _showExitConfirmation();
        if (shouldExit && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: _buildScaffold(),
    );
  }

  Widget _buildScaffold() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        displacement: 40,
        strokeWidth: 2.5,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
          // Modern SliverAppBar with gradient
          SliverAppBar(
            expandedHeight: 60,
            floating: false,
            pinned: true,
            elevation: 0,
            backgroundColor: AppColors.surface,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.waving_hand,
                    color: AppColors.accent,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Welcome back!',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.onSurface.withValues(alpha: 0.6),
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        'Hi $_userFirstName',
                        style: AppTextStyles.titleMedium.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primary.withValues(alpha: 0.05),
                      AppColors.secondary.withValues(alpha: 0.02),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              Container(
                margin: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      iconSize: 20,
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      icon: const Icon(Icons.search, color: AppColors.onSurface),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Search not implemented yet')),
                        );
                      },
                    ),
                    Container(
                      width: 1,
                      height: 20,
                      color: AppColors.onSurface.withValues(alpha: 0.1),
                    ),
                    IconButton(
                      iconSize: 20,
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      icon: const Icon(Icons.shopping_cart, color: AppColors.onSurface),
                      onPressed: () {
                        Navigator.pushNamed(context, '/cart');
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
          
          // Content sections
          SliverToBoxAdapter(
            child: Column(
              children: [
                const SizedBox(height: 8),
                
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  height: MediaQuery.of(context).size.width > 800 ? 300 : 180,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      children: [
                        CachedNetworkImage(
                          imageUrl: 'https://placehold.co/600x400',
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: MediaQuery.of(context).size.width > 800 ? 300 : 180,
                          placeholder: (context, url) => Container(
                            height: MediaQuery.of(context).size.width > 800 ? 300 : 180,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [AppColors.primary.withValues(alpha: 0.1), AppColors.secondary.withValues(alpha: 0.1)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            height: MediaQuery.of(context).size.width > 800 ? 300 : 180,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [AppColors.primary.withValues(alpha: 0.1), AppColors.secondary.withValues(alpha: 0.1)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.image_not_supported,
                                    color: Colors.grey,
                                    size: 40,
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Banner image unavailable',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          cacheManager: ProductImageCacheManager.instance,
                        ),
                        // Gradient overlay for better text readability
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.3),
                              ],
                            ),
                          ),
                        ),
                        // Badge overlay
                        Positioned(
                          top: 16,
                          right: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              'Featured',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                // Modern Categories Section
                
                const SizedBox(height: 20),
                
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.category,
                              color: AppColors.primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Categories',
                            style: AppTextStyles.titleMedium.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.onSurface,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 40,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _categories.length,
                          itemBuilder: (context, index) {
                            final category = _categories[index];
                            final isSelected = category == _selectedCategory;
                            
                            return Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: GestureDetector(
                                onTap: () => _onCategorySelected(category),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isSelected ? AppColors.primary : AppColors.surface,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: isSelected ? AppColors.primary : AppColors.onSurface.withValues(alpha: 0.2),
                                      width: 1.5,
                                    ),
                                    boxShadow: isSelected ? [
                                      BoxShadow(
                                        color: AppColors.primary.withValues(alpha: 0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ] : [],
                                  ),
                                  child: Center(
                                    child: Text(
                                      category,
                                      style: AppTextStyles.bodyMedium.copyWith(
                                        color: isSelected ? AppColors.onPrimary : AppColors.onSurface,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                        fontSize: 13,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      
                      // Subcategories section (expandable)
                      if (_selectedCategory != 'All' && _subcategories.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _isSubcategoriesExpanded = !_isSubcategoriesExpanded;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.secondary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.secondary.withValues(alpha: 0.2),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: AppColors.secondary.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(
                                    Icons.subdirectory_arrow_right,
                                    color: AppColors.secondary,
                                    size: 14,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Subcategories (${_subcategories.length})',
                                    style: AppTextStyles.bodyMedium.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.secondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                if (_selectedSubCategory != null) ...[
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedSubCategory = null;
                                      });
                                      _loadFirstPage();
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.error.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'Clear',
                                        style: AppTextStyles.bodySmall.copyWith(
                                          color: AppColors.error,
                                          fontWeight: FontWeight.w500,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                AnimatedRotation(
                                  turns: _isSubcategoriesExpanded ? 0.25 : 0,
                                  duration: const Duration(milliseconds: 200),
                                  child: Icon(
                                    Icons.keyboard_arrow_right,
                                    color: AppColors.secondary,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        
                        // Expandable subcategories content
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          height: _isSubcategoriesExpanded ? null : 0,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 200),
                            opacity: _isSubcategoriesExpanded ? 1.0 : 0.0,
                            child: Container(
                              margin: const EdgeInsets.only(top: 12),
                              child: _isLoadingSubcategories
                                  ? const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(16.0),
                                        child: SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        ),
                                      ),
                                    )
                                  : Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: _subcategories.map((subcategory) {
                                        final isSelected = _selectedSubCategory == subcategory.subCategoryId;
                                        
                                        return GestureDetector(
                                          onTap: () => _onSubCategorySelected(
                                            subcategory.subCategoryId,
                                            subcategory.subCategoryName,
                                          ),
                                          child: AnimatedContainer(
                                            duration: const Duration(milliseconds: 200),
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: isSelected 
                                                  ? AppColors.secondary 
                                                  : Colors.white,
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(
                                                color: isSelected 
                                                    ? AppColors.secondary 
                                                    : AppColors.onSurface.withValues(alpha: 0.2),
                                                width: 1,
                                              ),
                                              boxShadow: isSelected ? [
                                                BoxShadow(
                                                  color: AppColors.secondary.withValues(alpha: 0.2),
                                                  blurRadius: 4,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ] : [],
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  subcategory.subCategoryName,
                                                  style: AppTextStyles.bodySmall.copyWith(
                                                    color: isSelected 
                                                        ? AppColors.onSecondary 
                                                        : AppColors.onSurface,
                                                    fontWeight: isSelected 
                                                        ? FontWeight.bold 
                                                        : FontWeight.w500,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                FutureBuilder<int>(
                                                  future: _getSubCategoryClickCount(subcategory.subCategoryId),
                                                  builder: (context, snapshot) {
                                                    final clickCount = snapshot.data ?? 0;
                                                    if (clickCount == 0) return const SizedBox.shrink();
                                                    
                                                    return Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                      decoration: BoxDecoration(
                                                        color: isSelected 
                                                            ? AppColors.onSecondary.withValues(alpha: 0.2)
                                                            : AppColors.primary.withValues(alpha: 0.1),
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Text(
                                                        '$clickCount',
                                                        style: AppTextStyles.bodySmall.copyWith(
                                                          color: isSelected 
                                                              ? AppColors.onSecondary 
                                                              : AppColors.primary,
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 9,
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                
                // Enhanced Image Banner Section
                
                const SizedBox(height: 24),
                
                // Products Section Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.secondary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.grid_view_rounded,
                          color: AppColors.secondary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Products',
                          style: AppTextStyles.titleLarge.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.onSurface,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '${_products.length} items',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
              ],
            ),
          ),
          
          // Products Grid
          _isLoading && _products.isEmpty
            ? const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            : _errorMessage != null && _products.isEmpty
              ? SliverFillRemaining(
                  child: _buildErrorState(),
                )
              : _products.isEmpty
                ? SliverFillRemaining(
                    child: _buildEmptyState(),
                  )
                : SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: _buildModernProductGrid(),
                  ),
          ],
        ),
      ),
      floatingActionButton: _isSeller ? Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: FloatingActionButton(
          onPressed: () {
            AppLogger.d('🔍 ProductListingPage: FAB pressed - navigating to add-product');
            Navigator.pushNamed(context, '/add-product');
          },
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          elevation: 0,
          highlightElevation: 0,
          child: const Icon(Icons.add),
        ),
      ) : null,
    );
  }

  // Build error state with modern design
  Widget _buildErrorState() {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Oops! Something went wrong',
            style: AppTextStyles.titleLarge.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              _errorMessage ?? 'Unable to load products at this time',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.7),
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 32),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: () {
                AppLogger.d("🔄 Retry button pressed");
                _cacheTimestamp = null;
                ProductImageCacheManager.instance.emptyCache();
                _resetAndRefresh();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Build empty state with modern design
  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.search_off,
              size: 64,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No products found',
            style: AppTextStyles.titleLarge.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'There are no products to display at this time.\nTry refreshing or check back later.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 32),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: () {
                AppLogger.d("🔄 Empty state refresh button pressed");
                _cacheTimestamp = null;
                ProductImageCacheManager.instance.emptyCache();
                _resetAndRefresh();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Build modern product grid with enhanced design
  Widget _buildModernProductGrid() {
    AppLogger.d('🔍 DEBUG: _buildModernProductGrid called');
    AppLogger.d('🔍 Selected category: $_selectedCategory');
    AppLogger.d('🔍 Category name to ID mapping: $_categoryNameToId');
    AppLogger.d('🔍 Total products: ${_products.length}');
    
    final filteredProducts = _products.where((product) {
      // Exclude draft products from product listing page
      if (product.isDraft == true) return false;
      
      // Exclude inactive products from product listing page
      if (product.isActive == false) return false;
      
      // Exclude archived products from product listing page
      if (product.isArchived == true) return false;
      
      if (_selectedCategory == 'All') return true;
      
      // If a subcategory is selected, filter by subcategory
      if (_selectedSubCategory != null) {
        return product.subCategoryId == _selectedSubCategory;
      }
      
      // Otherwise, filter by category
      final selectedCategoryId = _categoryNameToId[_selectedCategory];
      return product.categoryId == selectedCategoryId;
    }).toList();
    
    AppLogger.d('🔍 Displaying ${filteredProducts.length} products for category: $_selectedCategory');

    if (filteredProducts.isEmpty) {
      return SliverToBoxAdapter(
        child: Container(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.category,
                  size: 48,
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'No products in $_selectedCategory',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Try selecting a different category',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _getResponsiveCrossAxisCount(context),
        childAspectRatio: _getResponsiveAspectRatio(context),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index >= filteredProducts.length) {
            // Show loading indicator if we're loading more
            if (_isLoadingMore) {
              return Container(
                padding: const EdgeInsets.all(32),
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              );
            }
            return null;
          }

          final product = filteredProducts[index];
          return ProductCard(
            product: product,
            onTap: () {
              // Track product click
              _clickTrackingService.trackProductClick(product.productId);
              
              // Navigate to product detail page
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProductDetailPage(productId: product.productId),
                ),
              );
            },
          );
        },
        childCount: filteredProducts.length + (_isLoadingMore ? 1 : 0),
      ),
    );
  }

  // Helper method to get responsive cross axis count based on screen width
  int _getResponsiveCrossAxisCount(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    
    if (screenWidth >= 1200) {
      return 6; // Large desktop screens
    } else if (screenWidth >= 900) {
      return 5; // Desktop screens
    } else if (screenWidth >= 600) {
      return 4; // Tablet screens
    } else if (screenWidth >= 480) {
      return 3; // Large mobile screens
    } else {
      return 2; // Small mobile screens
    }
  }

  // Helper method to get responsive aspect ratio based on screen width
  double _getResponsiveAspectRatio(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    
    if (screenWidth >= 1200) {
      return 0.85; // Slightly taller cards for large desktop
    } else if (screenWidth >= 900) {
      return 0.8; // Desktop screens
    } else if (screenWidth >= 600) {
      return 0.78; // Tablet screens
    } else {
      return 0.75; // Mobile screens (same as original)
    }
  }

  // Get subcategory click count from Firestore
  Future<int> _getSubCategoryClickCount(String subCategoryId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('SubCategoryClicks')
          .doc(subCategoryId)
          .get();
      
      if (doc.exists) {
        return doc.data()?['clickCounter'] ?? 0;
      }
      return 0;
    } catch (e) {
      AppLogger.d('❌ Error getting subcategory click count: $e');
      return 0;
    }
  }
}
