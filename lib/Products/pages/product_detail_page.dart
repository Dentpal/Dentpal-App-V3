import 'package:dentpal/core/app_theme/index.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product_model.dart';
import '../services/product_service.dart';
import '../services/cart_service.dart';
import '../services/category_service.dart';
import '../widgets/loading_overlay.dart';
import '../utils/cart_feedback.dart';
import 'cart_page.dart';
import 'edit_product_page.dart';
import 'package:dentpal/utils/app_logger.dart';


class ProductDetailPage extends StatefulWidget {
  final String productId;

  const ProductDetailPage({super.key, required this.productId});

  @override
  _ProductDetailPageState createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  void _showFullImagePopup(String imageUrl) {
  final TransformationController _transformationController =
      TransformationController();

  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(), // dismiss when tapping outside
        child: Stack(
          children: [
            Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 600, maxHeight: 600),
                child: GestureDetector(
                  onTap: () {}, // absorb taps on the image
                  onDoubleTap: () {
                    // Reset zoom and pan on double tap
                    _transformationController.value = Matrix4.identity();
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: InteractiveViewer(
                      transformationController: _transformationController,
                      minScale: 1.0,
                      maxScale: 4.0,
                      panEnabled: true,
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.contain,
                        placeholder: (context, url) =>
                            const Center(child: CircularProgressIndicator()),
                        errorWidget: (context, url, error) => const Icon(
                          Icons.broken_image,
                          color: AppColors.error,
                          size: 48,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Icon(Icons.close, color: Colors.white, size: 28),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}



  final ProductService _productService = ProductService();
  final CartService _cartService = CartService();
  final CategoryService _categoryService = CategoryService();
  
  late Future<Product?> _productFuture;
  int _quantity = 1;
  ProductVariation? _selectedVariation;
  bool _isAddingToCart = false;
  DateTime? _lastAddToCartTime;
  
  // Cache for category names to avoid repeated Firestore calls
  final Map<String, String> _categoryNames = {};
  
  // Cache for seller data to avoid repeated Firestore calls
  final Map<String, Map<String, dynamic>> _sellerData = {};
  
  // Cache management
  Product? _cachedProduct;
  DateTime? _cacheTimestamp;
  
  // Check if current user is the seller of this product
  bool _isCurrentUserSeller(Product product) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return false;
    return currentUser.uid == product.sellerId;
  }
  
  @override
  void initState() {
    super.initState();
    _productFuture = _loadProduct();
  }
  
  Future<Product?> _loadProduct() async {
    try {
      AppLogger.d('📄 ProductDetailPage: Loading product ${widget.productId}...');
      final product = await _productService.getProductById(widget.productId);
      
      if (product != null) {
        // Cache the product data
        _cachedProduct = product;
        _cacheTimestamp = DateTime.now();
        
        // Select the first variation by default if available
        if (product.variations != null && 
            product.variations!.isNotEmpty) {
          _selectedVariation = product.variations![0];
        }
        
        AppLogger.d('✅ ProductDetailPage: Loaded product ${product.name}');
      }
      
      return product;
    } catch (e) {
      AppLogger.d('❌ Error loading product: $e');
      return null;
    }
  }
  
  // Fetch category name by ID and cache it
  Future<String> _getCategoryName(String categoryId) async {
    if (_categoryNames.containsKey(categoryId)) {
      return _categoryNames[categoryId]!;
    }
    
    try {
      final category = await _categoryService.getCategoryById(categoryId);
      final categoryName = category?.categoryName ?? 'Unknown Category';
      _categoryNames[categoryId] = categoryName;
      return categoryName;
    } catch (e) {
      AppLogger.d('❌ Error fetching category name for $categoryId: $e');
      _categoryNames[categoryId] = 'Unknown Category';
      return 'Unknown Category';
    }
  }

  // Fetch seller data by ID and cache it
  Future<Map<String, dynamic>> _getSellerData(String sellerId) async {
    if (_sellerData.containsKey(sellerId)) {
      return _sellerData[sellerId]!;
    }
    
    try {
      final sellerDoc = await FirebaseFirestore.instance
          .collection('Seller')
          .doc(sellerId)
          .get();
      
      if (sellerDoc.exists) {
        final data = sellerDoc.data() as Map<String, dynamic>;
        final sellerInfo = {
          'shopName': data['shopName'] ?? 'DentPal Store',
          'address': data['address'] ?? 'No address provided',
          'contactEmail': data['contactEmail'] ?? '',
          'contactNumber': data['contactNumber'] ?? '',
          'isActive': data['isActive'] ?? true,
        };
        _sellerData[sellerId] = sellerInfo;
        return sellerInfo;
      } else {
        // Default data if seller not found
        final defaultData = {
          'shopName': 'DentPal Store',
          'address': 'Store location not available',
          'contactEmail': '',
          'contactNumber': '',
          'isActive': true,
        };
        _sellerData[sellerId] = defaultData;
        return defaultData;
      }
    } catch (e) {
      AppLogger.d('❌ Error fetching seller data for $sellerId: $e');
      final defaultData = {
        'shopName': 'DentPal Store',
        'address': 'Store location not available',
        'contactEmail': '',
        'contactNumber': '',
        'isActive': true,
      };
      _sellerData[sellerId] = defaultData;
      return defaultData;
    }
  }

  // Check if cache is expired (older than 10 minutes for product details)
  bool _isCacheExpired() {
    if (_cacheTimestamp == null) return true;
    
    final now = DateTime.now();
    final difference = now.difference(_cacheTimestamp!);
    return difference.inMinutes >= 10;
  }

  // Helper method to compare products for change detection
  bool _hasProductChanged(Product? oldProduct, Product? newProduct) {
    if (oldProduct == null && newProduct == null) return false;
    if (oldProduct == null || newProduct == null) return true;
    
    // Compare basic product properties
    if (oldProduct.productId != newProduct.productId ||
        oldProduct.name != newProduct.name ||
        oldProduct.description != newProduct.description ||
        oldProduct.imageURL != newProduct.imageURL ||
        oldProduct.categoryId != newProduct.categoryId ||
        oldProduct.lowestPrice != newProduct.lowestPrice) {
      AppLogger.d('🔍 Product data changed: Basic properties differ');
      return true;
    }
    
    // Compare variations
    if (oldProduct.variations?.length != newProduct.variations?.length) {
      AppLogger.d('🔍 Product data changed: Variation count differs');
      return true;
    }
    
    if (oldProduct.variations != null && newProduct.variations != null) {
      for (int i = 0; i < oldProduct.variations!.length; i++) {
        final oldVar = oldProduct.variations![i];
        final newVar = newProduct.variations![i];
        
        if (oldVar.variationId != newVar.variationId ||
            oldVar.name != newVar.name ||
            oldVar.price != newVar.price ||
            oldVar.stock != newVar.stock ||
            oldVar.imageURL != newVar.imageURL) {
          AppLogger.d('🔍 Product data changed: Variation ${oldVar.name} has differences');
          return true;
        }
      }
    }
    
    return false;
  }

  // Handle pull-to-refresh with cache-first approach and change detection
  Future<void> _handleRefresh() async {
    AppLogger.d('🔄 ProductDetailPage: Pull-to-refresh triggered (cache-first approach)');
    
    try {
      // Keep current data as backup
      final currentProduct = _cachedProduct;
      final currentTimestamp = _cacheTimestamp;
      
      AppLogger.d('📋 Current cache: ${currentProduct?.name ?? 'No cached product'}');
      
      // Fetch fresh data from Firebase
      AppLogger.d('🌐 Fetching fresh product data from Firebase...');
      final freshProduct = await _productService.getProductById(widget.productId);
      
      // Compare data for changes
      final hasChanges = _hasProductChanged(currentProduct, freshProduct);
      
      if (hasChanges || currentTimestamp == null || _isCacheExpired()) {
        AppLogger.d('🔄 Changes detected or cache expired - updating data');
        
        // Update with fresh data
        setState(() {
          _cachedProduct = freshProduct;
          _cacheTimestamp = DateTime.now();
          _productFuture = Future.value(freshProduct);
          
          // Re-select variation if it still exists, otherwise select first available
          if (freshProduct?.variations != null && freshProduct!.variations!.isNotEmpty) {
            final currentVariationId = _selectedVariation?.variationId;
            final foundVariation = freshProduct.variations!
                .where((v) => v.variationId == currentVariationId)
                .firstOrNull;
            
            if (foundVariation != null) {
              _selectedVariation = foundVariation;
              // Adjust quantity if it exceeds new stock
              if (_quantity > foundVariation.stock) {
                _quantity = foundVariation.stock > 0 ? 1 : 0;
              }
            } else {
              // Current variation no longer exists, select first one
              _selectedVariation = freshProduct.variations![0];
              if (_quantity > _selectedVariation!.stock) {
                _quantity = _selectedVariation!.stock > 0 ? 1 : 0;
              }
            }
          }
        });
        
        AppLogger.d('✅ Product data updated: ${freshProduct?.name ?? 'Product removed'}');
      } else {
        // No changes detected, just refresh timestamp
        setState(() {
          _cacheTimestamp = DateTime.now();
        });
        
        AppLogger.d('ℹ️ No changes detected - cache timestamp refreshed');
      }
      
    } catch (e) {
      AppLogger.d('❌ Refresh error: $e');
      AppLogger.d('Stack trace: ${StackTrace.current}');
      
      // Show error but keep existing data
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to refresh: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
    
    AppLogger.d('✅ ProductDetailPage: Pull-to-refresh completed');
  }

  void _addToCart(Product product) async {
    // Prevent multiple simultaneous requests
    if (_isAddingToCart) return;
    
    // Additional safety check for stock availability
    if (_selectedVariation != null && _quantity > _selectedVariation!.stock) {
      CartFeedback.showError(
        context, 
        'Cannot add more items than available stock (${_selectedVariation!.stock})'
      );
      setState(() {
        _quantity = _selectedVariation!.stock > 0 ? _selectedVariation!.stock : 1;
      });
      return;
    }

    // Debounce: Prevent rapid button taps (minimum 1 second between requests)
    final now = DateTime.now();
    if (_lastAddToCartTime != null && 
        now.difference(_lastAddToCartTime!).inSeconds < 1) {
      CartFeedback.showInfo(context, 'Please wait before adding another item');
      return;
    }
    
    _lastAddToCartTime = now;
    
    setState(() {
      _isAddingToCart = true;
    });
    
    try {
      await CartPage.addItemOptimistically(
        productId: product.productId,
        quantity: _quantity,
        variationId: _selectedVariation?.variationId,
        cartService: _cartService,
      );
      
      if (mounted) {
        CartFeedback.showSuccess(
          context, 
          'Added $_quantity ${product.name} to cart'
        );
      }
    } catch (e) {
      if (mounted) {
        CartFeedback.showError(
          context, 
          'Failed to add item to cart: ${e.toString()}'
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAddingToCart = false;
        });
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: FutureBuilder<Product?>(
        future: _productFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return _buildErrorState();
          } else if (!snapshot.hasData || snapshot.data == null) {
            return _buildNotFoundState();
          }
          
          final product = snapshot.data!;
          return _buildModernProductDetail(product);
        },
      ),
    );
  }

  Widget _buildErrorState() {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
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
            Text(
              'Unable to load product details',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _productFuture = _loadProduct();
                });
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
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotFoundState() {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
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
              'Product Not Found',
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'The product you\'re looking for doesn\'t exist',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Go Back'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernProductDetail(Product product) {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _handleRefresh,
          color: AppColors.primary,
          backgroundColor: AppColors.surface,
          displacement: 40,
          strokeWidth: 2.5,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
            // Modern SliverAppBar with product image
            SliverAppBar(
              expandedHeight: 400,
              floating: false,
              pinned: true,
              elevation: 0,
              backgroundColor: AppColors.surface,
              leading: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .9),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              actions: [
                Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .9),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Edit button - only show if current user is the seller
                      if (_isCurrentUserSeller(product)) ...[
                        IconButton(
                          icon: const Icon(Icons.edit, color: AppColors.primary),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => EditProductPage(product: product),
                              ),
                            ).then((_) {
                              // Refresh product data after edit
                              _handleRefresh();
                            });
                          },
                        ),
                        Container(
                          width: 1,
                          height: 24,
                          color: AppColors.onSurface.withValues(alpha: .1),
                        ),
                      ],
                      IconButton(
                        icon: const Icon(Icons.shopping_cart, color: AppColors.onSurface),
                        onPressed: () => Navigator.pushNamed(context, '/cart'),
                      ),
                    ],
                  ),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Hero(
                  tag: 'product-${product.productId}',
                  child: _buildProductImageSection(product),
                ),
              ),
            ),
            
            // Product Information
            SliverToBoxAdapter(
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Column(
                  children: [
                    _buildProductInfo(product),
                    _buildVariationsSection(product),
                    _buildQuantityAndStock(),
                    _buildDescriptionSection(product),
                    _buildReviewsSection(),
                    const SizedBox(height: 80), // Bottom padding for fixed button
                  ],
                ),
              ),
            ),
          ],
        ), // End CustomScrollView
        ), // End RefreshIndicator
        
        // Fixed Add to Cart Button
        _buildFixedAddToCartButton(product),
        
        // Loading overlay
        LoadingOverlay(
          message: 'Adding to cart...',
          isVisible: _isAddingToCart,
        ),
      ],
    );
  }

  Widget _buildProductImageSection(Product product) {
  final imageUrl = _selectedVariation?.imageURL ?? product.imageURL;
  // Track swipe direction for animation
  Offset _swipeOffset = const Offset(0.2, 0);

  return GestureDetector(
    onHorizontalDragEnd: (details) {
      if (product.variations == null || product.variations!.isEmpty) return;
      final currentIndex = product.variations!
          .indexWhere((v) => v.variationId == _selectedVariation?.variationId);

      if (details.primaryVelocity != null) {
        // Swipe right (velocity > 0): previous variation
        if (details.primaryVelocity! > 0) {
          if (currentIndex > 0) {
            setState(() {
              _swipeOffset = const Offset(-0.2, 0); // slide in from left
              _selectedVariation = product.variations![currentIndex - 1];
              if (_quantity > _selectedVariation!.stock) {
                _quantity = _selectedVariation!.stock > 0 ? 1 : 0;
              }
            });
          }
        }
        // Swipe left (velocity < 0): next variation
        else if (details.primaryVelocity! < 0) {
          if (currentIndex < product.variations!.length - 1) {
            setState(() {
              _swipeOffset = const Offset(0.2, 0); // slide in from right
              _selectedVariation = product.variations![currentIndex + 1];
              if (_quantity > _selectedVariation!.stock) {
                _quantity = _selectedVariation!.stock > 0 ? 1 : 0;
              }
            });
          }
        }
      }
    },
    onTap: () {
      if (imageUrl.isNotEmpty) {
        _showFullImagePopup(imageUrl);
      }
    },
    child: Container(
      width: double.infinity,
      height: 400,
      decoration: BoxDecoration(
        color: Colors.white,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white,
            Colors.grey.shade50,
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) {
                final offsetAnimation = Tween<Offset>(
                  begin: _swipeOffset,
                  end: Offset.zero,
                ).animate(animation);

                return SlideTransition(
                  position: offsetAnimation,
                  child: FadeTransition(opacity: animation, child: child),
                );
              },
              child: Container(
                key: ValueKey(imageUrl), // important for detecting image change
                width: double.infinity,
                height: double.infinity,
                child: imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover, // fill container
                        filterQuality: FilterQuality.high,
                        fadeInDuration: const Duration(milliseconds: 300),
                        fadeOutDuration: const Duration(milliseconds: 100),
                        placeholder: (context, url) => Container(
                          color: Colors.white,
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.white,
                          child: const Center(
                            child: Icon(Icons.image_not_supported,
                                size: 64, color: Colors.grey),
                          ),
                        ),
                        memCacheWidth: 1920,
                        memCacheHeight: 1080,
                      )
                    : Container(
                        color: Colors.white,
                        child: const Center(
                          child: Icon(Icons.image_not_supported,
                              size: 64, color: Colors.grey),
                        ),
                      ),
              ),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.1),
                  ],
                ),
              ),
            ),
          ),
          if (product.variations != null && product.variations!.length > 1)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: product.variations!.asMap().entries.map((entry) {
                  final isSelected =
                      _selectedVariation?.variationId == entry.value.variationId;

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: isSelected ? 28 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary
                          : Colors.white.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(isSelected ? 6 : 50),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    ),
  );
}


  Widget _buildProductInfo(Product product) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product name and favorite
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _selectedVariation != null && _selectedVariation!.name.isNotEmpty
                        ? RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: product.name,
                                  style: AppTextStyles.headlineSmall.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.onSurface,
                                  ),
                                ),
                                TextSpan(
                                  text: ' - ',
                                  style: AppTextStyles.headlineSmall.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.onSurface,
                                  ),
                                ),
                                TextSpan(
                                  text: _selectedVariation!.name,
                                  style: AppTextStyles.headlineSmall.copyWith(
                                    color: AppColors.grey400,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Text(
                            product.name,
                            style: AppTextStyles.headlineSmall.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.onSurface,
                            ),
                          ),
                    const SizedBox(height: 8),
                    FutureBuilder<String>(
                      future: _getCategoryName(product.categoryId),
                      builder: (context, snapshot) {
                        final categoryName = snapshot.data ?? 'Loading...';
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.onSurfaceVariant.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            categoryName,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.grey500,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Shop name section
          if (_selectedVariation != null)
            FutureBuilder<Map<String, dynamic>>(
              future: _getSellerData(product.sellerId),
              builder: (context, sellerSnapshot) {
                final sellerData = sellerSnapshot.data ?? {
                  'shopName': 'DentPal Store',
                  'address': 'Loading...',
                  'isActive': true,
                };
                
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.store,
                          color: AppColors.onPrimary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sellerData['shopName'] ?? 'Store name not available',
                              style: AppTextStyles.titleLarge.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              sellerData['address'] ?? 'Address not available',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.onSurface.withValues(alpha: 0.7),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: (sellerData['isActive'] == true ? Colors.green : Colors.orange).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          sellerData['isActive'] == true ? 'Verified' : 'Inactive',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: sellerData['isActive'] == true ? Colors.green : Colors.orange,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildVariationsSection(Product product) {
    if (product.variations == null || product.variations!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.tune,
                  color: AppColors.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Variations',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 60,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: product.variations!.length,
              itemBuilder: (context, index) {
                final variation = product.variations![index];
                final isSelected = _selectedVariation?.variationId == variation.variationId;
                
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedVariation = variation;
                      // Reset quantity if it exceeds the new variation's stock
                      if (_quantity > variation.stock) {
                        _quantity = variation.stock > 0 ? 1 : 0;
                      }
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 60,
                    height: 60,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primary.withValues(alpha: 0.1) : AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? AppColors.primary : AppColors.onSurface.withValues(alpha: 0.2),
                        width: isSelected ? 2 : 1,
                      ),
                      boxShadow: isSelected ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.2),
                          blurRadius: 6,
                          offset: const Offset(0, 1),
                        ),
                      ] : [],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: variation.imageURL != null && variation.imageURL!.isNotEmpty
                          ? AspectRatio(
                              aspectRatio: 1.0, // Force square aspect ratio
                              child: CachedNetworkImage(
                                imageUrl: variation.imageURL!,
                                fit: BoxFit.cover, // Crop to fill square
                                filterQuality: FilterQuality.high,
                                fadeInDuration: const Duration(milliseconds: 200),
                                placeholder: (context, url) => Container(
                                  color: AppColors.background,
                                  child: const Center(
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  ),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  color: AppColors.background,
                                  child: const Center(
                                    child: Icon(
                                      Icons.image_not_supported,
                                      size: 20,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                                // Cache at 1080p resolution for high quality thumbnails
                                memCacheWidth: 1920,
                                memCacheHeight: 1080,
                              ),
                            )
                          : Container(
                              color: AppColors.background,
                              child: const Center(
                                child: Icon(
                                  Icons.image_not_supported,
                                  size: 20,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildQuantityAndStock() {
    if (_selectedVariation == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(24, 4, 24, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.onSurface.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
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
                  Icons.shopping_bag,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Quantity',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                '${_selectedVariation!.stock} available',
                style: AppTextStyles.bodySmall.copyWith(
                  color: _quantity >= _selectedVariation!.stock 
                      ? Colors.orange 
                      : AppColors.onSurface.withValues(alpha: 0.7),
                  fontWeight: _quantity >= _selectedVariation!.stock 
                      ? FontWeight.w600 
                      : FontWeight.normal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // Quantity selector
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove, color: AppColors.primary),
                      onPressed: _quantity > 1
                          ? () {
                              setState(() {
                                _quantity--;
                              });
                            }
                          : null,
                      iconSize: 20,
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        _quantity.toString(),
                        style: AppTextStyles.titleMedium.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, color: AppColors.primary),
                      onPressed: _quantity < _selectedVariation!.stock
                          ? () {
                              setState(() {
                                _quantity++;
                              });
                            }
                          : null,
                      iconSize: 20,
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Price and Total section
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Unit Price',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  Text(
                    '₱${_selectedVariation!.price.toStringAsFixed(2)}',
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                      fontFamily: 'Roboto', // Use Roboto for peso sign support
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Total',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  Text(
                    '₱${(_selectedVariation!.price * _quantity).toStringAsFixed(2)}',
                    style: AppTextStyles.titleMedium.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                      fontFamily: 'Roboto', // Use Roboto for peso sign support
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionSection(Product product) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 4, 24, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.onSurface.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.description,
                  color: AppColors.secondary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Description',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            product.description,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.onSurface.withValues(alpha: 0.8),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewsSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 4, 24, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.onSurface.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.star,
                  color: Colors.amber,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Reviews',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  // TODO: Navigate to reviews page
                },
                child: Text(
                  'See All',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Rating summary
          Row(
            children: [
              Text(
                '4.5',
                style: AppTextStyles.headlineSmall.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: List.generate(5, (index) {
                      return Icon(
                        index < 4 ? Icons.star : Icons.star_half,
                        color: Colors.amber,
                        size: 16,
                      );
                    }),
                  ),
                  Text(
                    '24 reviews',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Sample reviews
          _buildModernReviewItem(
            name: 'John Doe',
            rating: 5,
            date: '2 weeks ago',
            comment: 'Great product! Really satisfied with the quality.',
          ),
          const SizedBox(height: 16),
          _buildModernReviewItem(
            name: 'Jane Smith',
            rating: 4,
            date: '1 month ago',
            comment: 'Good product but shipping took longer than expected.',
          ),
        ],
      ),
    );
  }

  Widget _buildModernReviewItem({
    required String name,
    required int rating,
    required String date,
    required String comment,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    name[0].toUpperCase(),
                    style: AppTextStyles.titleSmall.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                    ),
                    Row(
                      children: [
                        Row(
                          children: List.generate(5, (index) {
                            return Icon(
                              index < rating ? Icons.star : Icons.star_border,
                              color: Colors.amber,
                              size: 14,
                            );
                          }),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          date,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            comment,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.onSurface.withValues(alpha: 0.8),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFixedAddToCartButton(Product product) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: LoadingButton(
            text: _selectedVariation != null && _selectedVariation!.stock > 0
                ? 'Add to Cart • ₱${(_selectedVariation!.price * _quantity).toStringAsFixed(2)}'
                : 'Out of Stock',
            loadingText: 'Adding to cart...',
            isLoading: _isAddingToCart,
            onPressed: _selectedVariation != null && _selectedVariation!.stock > 0
                ? () => _addToCart(product)
                : null,
            padding: const EdgeInsets.symmetric(vertical: 14),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              fontFamily: 'Roboto', // Use Roboto for peso sign support
            ),
          ),
        ),
      ),
    );
  }
}
