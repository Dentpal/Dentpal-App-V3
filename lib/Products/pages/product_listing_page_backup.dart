import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product_model.dart';
import '../services/product_service.dart';
import '../services/user_service.dart';
import '../../core/app_theme/app_colors.dart';
import '../../core/app_theme/app_text_styles.dart';

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
  const ProductListingPage({Key? key}) : super(key: key);

  @override
  _ProductListingPageState createState() => _ProductListingPageState();
}

class _ProductListingPageState extends State<ProductListingPage> with AutomaticKeepAliveClientMixin<ProductListingPage> {
  final ProductService _productService = ProductService();
  final UserService _userService = UserService();
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
    
    // Add debug log to track initialization
    print("ProductListingPage initState called, products: ${_products.length}, timestamp: $_cacheTimestamp");
  }
  
  @override
  void dispose() {
    // Remove scroll listener to prevent memory leaks
    _scrollController.removeListener(_scrollListener);
    
    // Don't clear the static instance on dispose, we want to keep it
    // Only clean up resources if needed
    print("ProductListingPage dispose called, keeping cached data");
    super.dispose();
  }
  
  Future<void> _checkSellerStatus() async {
    final result = await _productService.checkSellerStatus();
    setState(() {
      _isSeller = result['isSeller'];
    });
  }
  
  Future<void> _loadUserName() async {
    final firstName = await _userService.getUserFirstName();
    setState(() {
      _userFirstName = firstName;
    });
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
    
    setState(() {
      _selectedCategory = category;
      // Reset pagination parameters for the new category
      _products = [];
      _lastDocument = null;
      _hasMore = true;
      _isLoading = false;
      _isLoadingMore = false;
    });
    
    // Load first page with the new category
    _loadFirstPage();
    
    // Update the static instance
    if (_instance != null) {
      _instance!._selectedCategory = category;
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
      print('ProductListingPage: Loading first page of products...');
      
      final result = await _productService.getProductsPaginated(
        limit: _pageSize,
        category: _selectedCategory == 'All' ? null : _selectedCategory,
      );
      
      final newProducts = result['products'] as List<Product>;
      final lastDoc = result['lastDocument'] as DocumentSnapshot?;
      final hasMore = result['hasMore'] as bool;
      
      // Extract all unique categories if this is the first load
      if (_categories.length <= 1) {
        Set<String> categorySet = {'All'};
        for (var product in newProducts) {
          if (product.category.isNotEmpty) {
            categorySet.add(product.category);
          }
        }
        _categories = categorySet.toList();
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
      
      print('Loaded ${newProducts.length} products (first page)');
    } catch (e) {
      print('Error loading first page: $e');
      print('Stack trace: ${StackTrace.current}');
      
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
      print('ProductListingPage: Loading more products...');
      
      final result = await _productService.getProductsPaginated(
        limit: _pageSize,
        lastDocument: _lastDocument,
        category: _selectedCategory == 'All' ? null : _selectedCategory,
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
      
      print('Loaded ${newProducts.length} more products');
    } catch (e) {
      print('Error loading more products: $e');
      print('Stack trace: ${StackTrace.current}');
      
      setState(() {
        _isLoadingMore = false;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Row(
          children: [
            Text(
              'Hi $_userFirstName',
              style: AppTextStyles.titleLarge.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.waving_hand,
              color: AppColors.accent,
              size: 20,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: AppColors.onSurface),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Search not implemented yet')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.shopping_cart, color: AppColors.onSurface),
            onPressed: () {
              Navigator.pushNamed(context, '/cart');
            },
          ),
        ],
      ),
      floatingActionButton: _isSeller ? FloatingActionButton(
        onPressed: () {
          Navigator.pushNamed(context, '/add-product');
        },
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: AppColors.onPrimary),
        tooltip: 'Add New Product',
      ) : null,
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          print("Pull-to-refresh triggered");
          
          // Reset the cache timestamp
          _cacheTimestamp = null;
          
          // Clear the image cache
          ProductImageCacheManager.instance.emptyCache();
          
          // Reset pagination and reload first page
          _resetAndRefresh();
          
          // Wait for the refresh to complete
          while (_isLoading) {
            await Future.delayed(const Duration(milliseconds: 100));
          }
        },
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            // Banner Section
            SliverToBoxAdapter(
              child: _buildBannerSection(),
            ),
            
            // Categories Section
            SliverToBoxAdapter(
              child: _buildCategoriesSection(),
            ),
            
            // Products Section Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                child: Row(
                  children: [
                    Text(
                      _selectedCategory == 'All' ? 'All Products' : _selectedCategory,
                      style: AppTextStyles.headlineSmall.copyWith(
                        color: AppColors.onBackground,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_products.length} items',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Products Grid
            _buildProductGrid(),
          ],
        ),
      ),
    );
  }
            child: Container(
              height: 50,
              margin: const EdgeInsets.only(top: 8.0),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                itemBuilder: (context, index) {
                  final category = _categories[index];
                  final isSelected = category == _selectedCategory;
                  
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: FilterChip(
                      label: Text(
                        category,
                        style: TextStyle(
                          fontSize: 14, // Slightly smaller font to avoid overflow
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      selected: isSelected,
                      onSelected: (selected) {
                        _onCategorySelected(category);
                      },
                      labelPadding: const EdgeInsets.symmetric(horizontal: 8.0),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  );
                },
              ),
            ),
          ),
          
          // Product grid
          Expanded(
            child: _isLoading && _products.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null && _products.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        const Text(
                          'Error loading products',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 14),
                            maxLines: 5, // Limit lines to prevent extreme overflow
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            print("Retry button pressed");
                            // Clear cache on retry
                            _cacheTimestamp = null;
                            
                            // Clear image cache
                            ProductImageCacheManager.instance.emptyCache();
                            
                            // Reset and reload
                            _resetAndRefresh();
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : _products.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.search_off, size: 48, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text(
                            'No products found',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          const Text('There are no products to display at this time.'),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              print("Empty state refresh button pressed");
                              // Clear cache on refresh
                              _cacheTimestamp = null;
                              
                              // Clear image cache
                              ProductImageCacheManager.instance.emptyCache();
                              
                              // Reset and reload
                              _resetAndRefresh();
                            },
                            child: const Text('Refresh'),
                          ),
                        ],
                      ),
    );
  }
  
  // Banner section widget
  Widget _buildBannerSection() {
    return Container(
      margin: const EdgeInsets.all(16),
      height: 160,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: 60,
            bottom: -30,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Dental Products',
                  style: AppTextStyles.headlineMedium.copyWith(
                    color: AppColors.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Quality dental supplies for\nprofessionals and students',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.onPrimary.withOpacity(0.9),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Free Delivery Available',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.onPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  // Categories section widget
  Widget _buildCategoriesSection() {
    return Container(
      height: 60,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemBuilder: (context, index) {
          final category = _categories[index];
          final isSelected = category == _selectedCategory;
          
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilterChip(
              label: Text(
                category,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? AppColors.onPrimary : AppColors.onSurfaceVariant,
                ),
              ),
              selected: isSelected,
              onSelected: (selected) {
                _onCategorySelected(category);
              },
              backgroundColor: isSelected ? AppColors.primary : AppColors.surface,
              selectedColor: AppColors.primary,
              checkmarkColor: AppColors.onPrimary,
              side: BorderSide(
                color: isSelected ? AppColors.primary : AppColors.grey300,
                width: 1,
              ),
              elevation: isSelected ? 2 : 0,
              shadowColor: AppColors.primary.withOpacity(0.3),
            ),
          );
        },
      ),
    );
  }
  
  // Build the product grid with support for pagination
  Widget _buildProductGrid() {
    final filteredProducts = _products.where((product) {
      if (_selectedCategory == 'All') return true;
      return product.category == _selectedCategory;
    }).toList();
    
    if (filteredProducts.isEmpty) {
      return Center(
        child: Text('No products found in $_selectedCategory category'),
      );
    }
    
    return RefreshIndicator(
      onRefresh: () async {
        print("Pull-to-refresh triggered");
        // Clear the cache timestamp
        _cacheTimestamp = null;
        
        // Clear image cache
        await ProductImageCacheManager.instance.emptyCache();
        
        // Reset and reload first page
        _resetAndRefresh();
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Calculate proper child aspect ratio and columns based on available width
          final width = constraints.maxWidth;
          
          // Determine number of columns based on screen width
          int crossAxisCount = 2; // Default for phones
          if (width > 600) {
            crossAxisCount = 3; // Tablets
          }
          if (width > 900) {
            crossAxisCount = 4; // Large tablets/desktops
          }
          
          final itemWidth = (width - (16 * (crossAxisCount + 1))) / crossAxisCount;
          final itemHeight = 200.0;
          final aspectRatio = itemWidth / itemHeight;
          
          return Column(
            children: [
              Expanded(
                child: GridView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    childAspectRatio: aspectRatio,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 20,
                    mainAxisExtent: 200,
                  ),
                  itemCount: filteredProducts.length,
                  itemBuilder: (context, index) {
                    final product = filteredProducts[index];
                    return _buildProductCard(product);
                  },
                ),
              ),
              
              // Loading indicator at the bottom when loading more products
              if (_isLoadingMore)
                Container(
                  height: 60,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
  
  Widget _buildProductCard(Product product) {
    // Get price from first variation or null if no variations
    double? price;
    String? imageUrl = product.imageURL;
    
    if (product.variations != null && product.variations!.isNotEmpty) {
      price = product.variations![0].price;
      if (product.variations![0].imageURL != null && 
          product.variations![0].imageURL!.isNotEmpty) {
        imageUrl = product.variations![0].imageURL;
      }
    }
    
    return GestureDetector(
      onTap: () {
        // Use named routes to maintain consistency
        Navigator.pushNamed(
          context, 
          '/product/${product.productId}'
        );
      },
      child: SizedBox(
        height: 200, // Fixed height for entire card
        child: Card(
          elevation: 3,
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product Image
              SizedBox(
                height: 120,
                width: double.infinity,
                child: imageUrl != null && imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        cacheManager: ProductImageCacheManager.instance,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Center(
                          child: CircularProgressIndicator(),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.grey[200],
                          child: const Center(child: Icon(Icons.image_not_supported)),
                        ),
                      )
                    : Container(
                        color: Colors.grey[200],
                        child: const Center(child: Icon(Icons.image_not_supported)),
                      ),
              ),
              
              // Product Details
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Product Name
                      Text(
                        product.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    
                      // Price at the bottom
                      if (price != null)
                        Text(
                          '₱${price.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: Theme.of(context).primaryColor,
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                        )
                      else
                        Text(
                          'Price unavailable',
                          style: TextStyle(color: Colors.grey[600], fontSize: 14),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
