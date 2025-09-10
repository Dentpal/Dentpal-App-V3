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
    print("🔵 ProductListingPage initState called, products: ${_products.length}, timestamp: $_cacheTimestamp");
  }
  
  @override
  void dispose() {
    // Remove scroll listener to prevent memory leaks
    _scrollController.removeListener(_scrollListener);
    
    // Don't clear the static instance on dispose, we want to keep it
    // Only clean up resources if needed
    print("🔴 ProductListingPage dispose called, keeping cached data");
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
      print('🔄 ProductListingPage: Loading first page of products...');
      
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
      
      print('✅ Loaded ${newProducts.length} products (first page)');
    } catch (e) {
      print('❌ Error loading first page: $e');
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
      print('🔄 ProductListingPage: Loading more products...');
      
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
      
      print('✅ Loaded ${newProducts.length} more products');
    } catch (e) {
      print('❌ Error loading more products: $e');
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
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Modern SliverAppBar with gradient
          SliverAppBar(
            expandedHeight: 80,
            floating: false,
            pinned: true,
            elevation: 0,
            backgroundColor: AppColors.surface,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
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
                          color: AppColors.onSurface.withOpacity(0.6),
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
                      AppColors.primary.withOpacity(0.05),
                      AppColors.secondary.withOpacity(0.02),
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
                      color: Colors.black.withOpacity(0.08),
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
                      color: AppColors.onSurface.withOpacity(0.1),
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
                
                // Modern Categories Section
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
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
                              color: AppColors.primary.withOpacity(0.1),
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
                                      color: isSelected ? AppColors.primary : AppColors.onSurface.withOpacity(0.2),
                                      width: 1.5,
                                    ),
                                    boxShadow: isSelected ? [
                                      BoxShadow(
                                        color: AppColors.primary.withOpacity(0.3),
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
                    ],
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Enhanced Image Banner Section
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  height: 180,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.2),
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
                          height: 180,
                          placeholder: (context, url) => Container(
                            height: 180,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [AppColors.primary.withOpacity(0.1), AppColors.secondary.withOpacity(0.1)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            height: 180,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [AppColors.primary.withOpacity(0.1), AppColors.secondary.withOpacity(0.1)],
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
                                Colors.black.withOpacity(0.3),
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
                                  color: Colors.black.withOpacity(0.2),
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
                
                const SizedBox(height: 24),
                
                // Products Section Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.secondary.withOpacity(0.1),
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
                          color: AppColors.primary.withOpacity(0.1),
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
      floatingActionButton: _isSeller ? Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: () {
            Navigator.pushNamed(context, '/add-product');
          },
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          icon: const Icon(Icons.add),
          label: const Text('Add Product'),
          elevation: 0,
          highlightElevation: 0,
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
              color: Colors.red.withOpacity(0.1),
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
                color: AppColors.onSurface.withOpacity(0.7),
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
                  color: AppColors.primary.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: () {
                print("🔄 Retry button pressed");
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
              color: AppColors.primary.withOpacity(0.1),
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
              color: AppColors.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 32),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: () {
                print("🔄 Empty state refresh button pressed");
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
    final filteredProducts = _products.where((product) {
      if (_selectedCategory == 'All') return true;
      return product.category == _selectedCategory;
    }).toList();

    if (filteredProducts.isEmpty) {
      return SliverToBoxAdapter(
        child: Container(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withOpacity(0.1),
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
                  color: AppColors.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.8, // Increased from 0.75 to give more height
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
          return _buildModernProductCard(product);
        },
        childCount: filteredProducts.length + (_isLoadingMore ? 1 : 0),
      ),
    );
  }

  // Build modern product card with enhanced styling
  Widget _buildModernProductCard(Product product) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Navigator.pushNamed(
                context,
                '/product/${product.productId}',
              );
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Product Image
                Expanded(
                  flex: 3,
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(20),
                            topRight: Radius.circular(20),
                          ),
                          child: CachedNetworkImage(
                            imageUrl: product.imageURL,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            placeholder: (context, url) => Container(
                              color: AppColors.background,
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: AppColors.background,
                              child: const Center(
                                child: Icon(
                                  Icons.image_not_supported,
                                  color: Colors.grey,
                                  size: 32,
                                ),
                              ),
                            ),
                            cacheManager: ProductImageCacheManager.instance,
                          ),
                        ),
                        // Favorite button
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.9),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.favorite_border,
                              size: 16,
                              color: AppColors.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Product Info
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            product.name,
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.onSurface,
                              fontSize: 13,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          product.category,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.secondary,
                            fontWeight: FontWeight.w500,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                product.lowestPrice != null 
                                  ? '₱${product.lowestPrice!.toStringAsFixed(2)}' 
                                  : 'Price varies',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  fontFamily: 'Roboto', // Use Roboto for peso sign support
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(
                                Icons.add_shopping_cart,
                                size: 14,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
