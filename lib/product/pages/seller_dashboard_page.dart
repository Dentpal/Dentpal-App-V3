import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/product_model.dart';
import '../services/user_service.dart';
import '../widgets/product_card.dart';
import '../../core/app_theme/app_colors.dart';
import '../../core/app_theme/app_text_styles.dart';
import 'package:dentpal/utils/app_logger.dart';
import 'package:flutter/services.dart';
import '../../profile/pages/profile_page.dart';

// Custom cache manager with web compatibility
class ProductImageCacheManager {
  static const key = 'productImageCache';

  static CacheManager get instance {
    if (kIsWeb) {
      // For web, use a simplified cache manager without persistent storage
      return DefaultCacheManager();
    } else {
      // For mobile platforms, use the full cache manager with persistence
      return DefaultCacheManager();
    }
  }
}

class SellerDashboardPage extends StatefulWidget {
  const SellerDashboardPage({super.key, this.isStandalone = false});

  // Flag to indicate if this page is used standalone (not within bottom navigation)
  final bool isStandalone;

  @override
  _SellerDashboardPageState createState() => _SellerDashboardPageState();
}

class _SellerDashboardPageState extends State<SellerDashboardPage>
    with AutomaticKeepAliveClientMixin<SellerDashboardPage>, TickerProviderStateMixin {
  final UserService _userService = UserService();
  
  // Seller listings data
  List<Product> _allProducts = [];
  final List<Product> _activeProducts = [];
  final List<Product> _inactiveProducts = [];
  final List<Product> _outOfStockProducts = [];
  final List<Product> _draftProducts = [];
  final List<Product> _archivedProducts = [];
  
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _errorMessage;
  String _userFirstName = 'Seller';

  // Pagination state
  DocumentSnapshot? _lastDocument;
  bool _hasMore = true;
  final int _pageSize = 20; // Load 20 products at a time
  final ScrollController _scrollController = ScrollController();

  // Tab controller for product categories within My Listings only
  late TabController _productTabController;
  
  // Current page state - true for My Listings, false for Profile
  bool _showingMyListings = true;

  // Override to keep this page alive when navigating away
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    
    // Initialize tab controller for product categories only
    _productTabController = TabController(length: 5, vsync: this); // Product categories
    
    // Add scroll listener for pagination
    _scrollController.addListener(_scrollListener);
    
    // Load data
    _loadUserName();
    _loadSellerProducts();

    // Add debug log to track initialization
    AppLogger.d("SellerDashboardPage initState called");
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    _productTabController.dispose();
    
    AppLogger.d("SellerDashboardPage dispose called");
    super.dispose();
  }

  Future<void> _loadUserName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // User not authenticated, set generic name
      if (mounted) {
        setState(() {
          _userFirstName = 'Seller';
        });
      }
      return;
    }

    final firstName = await _userService.getUserFirstName();
    if (mounted) {
      setState(() {
        _userFirstName = firstName;
      });
    }
  }

  Future<void> _loadSellerProducts() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      // Reset pagination state
      _allProducts.clear();
      _lastDocument = null;
      _hasMore = true;
    });
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not logged in');
      }
      
      AppLogger.d('Loading first page of products for seller: ${user.uid}');
      
      // Load first page with pagination
      await _loadSellerProductsPage(user.uid, isFirstPage: true);
      
    } catch (e) {
      AppLogger.d('Error loading seller products: $e');
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadSellerProductsPage(String sellerId, {bool isFirstPage = false}) async {
    try {
      AppLogger.d('Loading ${isFirstPage ? 'first' : 'next'} page of seller products');
      
      Query query = FirebaseFirestore.instance
          .collection('Product')
          .where('sellerId', isEqualTo: sellerId)
          .orderBy('createdAt', descending: true) // Uses composite index
          .limit(_pageSize);
      
      // Add pagination cursor if not first page
      if (!isFirstPage && _lastDocument != null) {
        query = query.startAfterDocument(_lastDocument!);
      }
      
      QuerySnapshot querySnapshot = await query.get();
      
      AppLogger.d('Query completed, processing ${querySnapshot.docs.length} documents');
      
      List<Product> pageProducts = [];
      
      // Process products from this page
      for (var doc in querySnapshot.docs) {
        try {
          Product product = Product.fromFirestore(doc);
          
          // Get variations for this product
          QuerySnapshot variationsSnapshot = await FirebaseFirestore.instance
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
              isActive: product.isActive,
              isDraft: product.isDraft,
              isArchived: product.isArchived,
              createdAt: product.createdAt,
              updatedAt: product.updatedAt,
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
        } catch (e) {
          AppLogger.d('Error processing product document: $e');
        }
      }
      
      if (mounted) {
        setState(() {
          if (isFirstPage) {
            _allProducts = pageProducts;
          } else {
            _allProducts.addAll(pageProducts);
          }
          
          // Update pagination state
          _lastDocument = querySnapshot.docs.isNotEmpty ? querySnapshot.docs.last : null;
          _hasMore = querySnapshot.docs.length == _pageSize;
          
          if (isFirstPage) {
            _isLoading = false;
          } else {
            _isLoadingMore = false;
          }
          
          // Categorize all products
          _categorizeProducts(_allProducts);
        });
      }
      
      AppLogger.d('Successfully loaded ${pageProducts.length} products (page total: ${_allProducts.length})');
      
    } catch (e) {
      AppLogger.d('Error loading seller products page: $e');
      if (mounted) {
        setState(() {
          if (isFirstPage) {
            _isLoading = false;
          } else {
            _isLoadingMore = false;
          }
          _errorMessage = e.toString();
        });
      }
      rethrow;
    }
  }

  // Scroll listener for detecting when user reaches bottom
  void _scrollListener() {
    if (!mounted) return;
    
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoading &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMoreProducts();
    }
  }

  Future<void> _loadMoreProducts() async {
    if (_isLoadingMore || !_hasMore || _lastDocument == null || !mounted) return;
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    if (mounted) {
      setState(() {
        _isLoadingMore = true;
      });
    }
    
    try {
      await _loadSellerProductsPage(user.uid, isFirstPage: false);
    } catch (e) {
      AppLogger.d('Error loading more products: $e');
    }
  }

  
  void _categorizeProducts(List<Product> products) {
    _activeProducts.clear();
    _inactiveProducts.clear();
    _outOfStockProducts.clear();
    _draftProducts.clear();
    _archivedProducts.clear();
    
    for (Product product in products) {
      if (product.isArchived == true) {
        _archivedProducts.add(product);
      } else if (product.isDraft) {
        _draftProducts.add(product);
      } else if (!product.isActive) {
        _inactiveProducts.add(product);
      } else if (_isProductOutOfStock(product)) {
        _outOfStockProducts.add(product);
      } else {
        _activeProducts.add(product);
      }
    }
    
    AppLogger.d('Products categorized - Active: ${_activeProducts.length}, Inactive: ${_inactiveProducts.length}, Out of Stock: ${_outOfStockProducts.length}, Drafts: ${_draftProducts.length}, Archived: ${_archivedProducts.length}');
  }
  
  bool _isProductOutOfStock(Product product) {
    if (product.variations == null || product.variations!.isEmpty) return true;
    
    // Check if all variations have 0 stock
    return product.variations!.every((variation) => variation.stock <= 0);
  }

  Future<void> _handleRefresh() async {
    await _loadSellerProducts();
  }




  Future<bool> _showExitConfirmation() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
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
        ) ??
        false;
  }

  void _navigateToAddProduct() {
    Navigator.pushNamed(context, '/add-product').then((_) {
      // Refresh the list when returning from add product
      _handleRefresh();
    });
  }

  void _navigateToEditProduct(Product product) {
    Navigator.pushNamed(
      context,
      '/edit-product',
      arguments: {'productId': product.productId},
    ).then((_) {
      // Refresh the list when returning from edit product
      _handleRefresh();
    });
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
        
        // If we're on Profile page and standalone, go back to My Listings first
        if (!_showingMyListings && mounted) {
          setState(() {
            _showingMyListings = true;
          });
          return;
        }
        
        // If we're on My Listings or not standalone, show exit confirmation
        final shouldExit = await _showExitConfirmation();
        if (shouldExit && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: _buildScaffold(),
    );
  }

  Widget _buildScaffold() {
    final isWideScreen = MediaQuery.of(context).size.width >= 900;
    
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // Header similar to product listing page (for wide screens)
          if (isWideScreen)
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                child: Row(
                  children: [
                    // LEFT: Welcome section
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.store,
                            color: AppColors.primary,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Seller Dashboard',
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
                      ],
                    ),
                    
                    // CENTER: Spacer
                    const Expanded(child: SizedBox()),
                    
                    // RIGHT: Navigation buttons
                    Row(
                      children: [
                        // My Listings button
                        GestureDetector(
                          onTap: () {
                            if (mounted) {
                              setState(() {
                                _showingMyListings = true;
                              });
                            }
                          },
                          child: Row(
                            children: [
                              Icon(
                                Icons.inventory,
                                size: 22,
                                color: _showingMyListings 
                                    ? AppColors.primary 
                                    : AppColors.onSurface.withOpacity(0.7),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'My Listings',
                                style: AppTextStyles.titleMedium.copyWith(
                                  color: _showingMyListings 
                                      ? AppColors.primary 
                                      : AppColors.onSurface.withOpacity(0.7),
                                  fontWeight: _showingMyListings 
                                      ? FontWeight.bold 
                                      : FontWeight.normal,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 24),
                        // Profile button
                        GestureDetector(
                          onTap: () {
                            if (mounted) {
                              setState(() {
                                _showingMyListings = false;
                              });
                            }
                          },
                          child: Row(
                            children: [
                              Icon(
                                Icons.person_outline,
                                size: 22,
                                color: !_showingMyListings 
                                    ? AppColors.primary 
                                    : AppColors.onSurface.withOpacity(0.7),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Profile',
                                style: AppTextStyles.titleMedium.copyWith(
                                  color: !_showingMyListings 
                                      ? AppColors.primary 
                                      : AppColors.onSurface.withOpacity(0.7),
                                  fontWeight: !_showingMyListings 
                                      ? FontWeight.bold 
                                      : FontWeight.normal,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          
          // SliverAppBar for mobile/tablet only
          if (!isWideScreen)
            SliverAppBar(
              expandedHeight: 60,
              floating: false,
              pinned: true,
              elevation: 0,
              backgroundColor: AppColors.surface,
              automaticallyImplyLeading: widget.isStandalone,
              leading: widget.isStandalone 
                  ? IconButton(
                      icon: Icon(
                        Icons.arrow_back,
                        color: AppColors.onSurface,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    )
                  : null,
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.store,
                      color: AppColors.primary,
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
                          'Seller Dashboard',
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
            ),
          
          // Navigation tabs section for mobile only
          if (!isWideScreen)
            SliverToBoxAdapter(
              child: Container(
                color: AppColors.surface,
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (mounted) {
                            setState(() {
                              _showingMyListings = true;
                            });
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: _showingMyListings 
                                    ? AppColors.primary 
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                          child: Text(
                            'My Listings',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.titleSmall.copyWith(
                              color: _showingMyListings 
                                  ? AppColors.primary 
                                  : AppColors.onSurface.withValues(alpha: 0.6),
                              fontWeight: _showingMyListings 
                                  ? FontWeight.w600 
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (mounted) {
                            setState(() {
                              _showingMyListings = false;
                            });
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: !_showingMyListings 
                                    ? AppColors.primary 
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                          child: Text(
                            'Profile',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.titleSmall.copyWith(
                              color: !_showingMyListings 
                                  ? AppColors.primary 
                                  : AppColors.onSurface.withValues(alpha: 0.6),
                              fontWeight: !_showingMyListings 
                                  ? FontWeight.w600 
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          
          // Page content
          SliverFillRemaining(
            child: _showingMyListings ? _buildListingsPage() : const ProfilePage(),
          ),
        ],
      ),
      floatingActionButton: _showingMyListings
          ? FloatingActionButton(
              onPressed: _navigateToAddProduct,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 4,
              shape: const CircleBorder(),
              child: const Icon(Icons.add, size: 28),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildListingsPage() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_errorMessage != null) {
      return _buildErrorState();
    }
    
    if (_allProducts.isEmpty) {
      return _buildEmptyState();
    }
    
    return RefreshIndicator(
      onRefresh: _handleRefresh,
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      child: Column(
        children: [
          // Product categories tabs
          Container(
            color: AppColors.surface,
            child: TabBar(
              controller: _productTabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.onSurface.withValues(alpha: 0.6),
              indicatorColor: AppColors.primary,
              isScrollable: true,
              tabs: [
                Tab(text: 'Active (${_activeProducts.length})'),
                Tab(text: 'Inactive (${_inactiveProducts.length})'),
                Tab(text: 'Out of Stock (${_outOfStockProducts.length})'),
                Tab(text: 'Drafts (${_draftProducts.length})'),
                Tab(text: 'Archived (${_archivedProducts.length})'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _productTabController,
              children: [
                _buildProductList(_activeProducts, 'active'),
                _buildProductList(_inactiveProducts, 'inactive'),
                _buildProductList(_outOfStockProducts, 'out of stock'),
                _buildProductList(_draftProducts, 'drafts'),
                _buildProductList(_archivedProducts, 'archived'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductList(List<Product> products, String category) {
    if (products.isEmpty) {
      return _buildEmptyTabState(category);
    }
    
    return Column(
      children: [
        Expanded(
          child: GridView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _getResponsiveCrossAxisCount(context),
              childAspectRatio: 0.75,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: products.length + (_isLoadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              // Show loading indicator at the end
              if (index >= products.length) {
                return Container(
                  padding: const EdgeInsets.all(32),
                  child: const Center(child: CircularProgressIndicator()),
                );
              }
              
              final product = products[index];
              return GestureDetector(
                onTap: () => _navigateToEditProduct(product),
                child: ProductCard(
                  product: product,
                  onTap: () => _navigateToEditProduct(product),
                ),
              );
            },
          ),
        ),
        // Loading indicator at the bottom when loading more
        if (_isLoadingMore)
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 12),
                Text(
                  'Loading more products...',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyTabState(String category) {
    String message;
    IconData icon;
    
    switch (category) {
      case 'active':
        message = 'No active products\nAdd a new product to get started';
        icon = Icons.add_business;
        break;
      case 'inactive':
        message = 'No inactive products\nAll your products are currently active';
        icon = Icons.visibility_off;
        break;
      case 'out of stock':
        message = 'No out of stock products\nAll your products are in stock';
        icon = Icons.inventory_2;
        break;
      case 'drafts':
        message = 'No draft products\nSave products as drafts to work on them later';
        icon = Icons.drafts;
        break;
      case 'archived':
        message = 'No archived products\nArchive products you want to keep but not display';
        icon = Icons.archive;
        break;
      default:
        message = 'No products found';
        icon = Icons.search_off;
    }
    
    return Center(
      child: Container(
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
              child: Icon(
                icon,
                size: 48,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyLarge.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.7),
              ),
            ),
            if (category == 'active') ...[
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _navigateToAddProduct,
                icon: const Icon(Icons.add),
                label: const Text('Add Your First Product'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ],
        ),
      ),
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
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(50),
            ),
            child: Icon(
              Icons.error_outline,
              size: 64,
              color: AppColors.error,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Failed to load products',
            style: AppTextStyles.headlineSmall.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.onBackground,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage ?? 'An error occurred while loading your products',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyLarge.copyWith(
              color: AppColors.onBackground.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _handleRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
              borderRadius: BorderRadius.circular(50),
            ),
            child: Icon(
              Icons.inventory_2_outlined,
              size: 64,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No products yet',
            style: AppTextStyles.headlineSmall.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.onBackground,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Start by adding your first product to your store',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyLarge.copyWith(
              color: AppColors.onBackground.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _navigateToAddProduct,
            icon: const Icon(Icons.add),
            label: const Text('Add Your First Product'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
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
}
