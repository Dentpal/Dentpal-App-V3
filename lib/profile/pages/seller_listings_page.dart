import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // Added for web detection
import '../../core/app_theme/app_colors.dart';
import '../../core/app_theme/app_text_styles.dart';
import '../../product/models/product_model.dart';
import '../../product/widgets/product_card.dart';
import 'package:dentpal/utils/app_logger.dart';

class SellerListingsPage extends StatefulWidget {
  const SellerListingsPage({super.key});

  @override
  State<SellerListingsPage> createState() => _SellerListingsPageState();
}

class _SellerListingsPageState extends State<SellerListingsPage>
    with TickerProviderStateMixin {
  List<Product> _allProducts = [];
  final List<Product> _activeProducts = [];
  final List<Product> _inactiveProducts = [];
  final List<Product> _outOfStockProducts = [];
  final List<Product> _draftProducts = [];
  final List<Product> _archivedProducts = [];

  bool _isLoading = true;
  String? _errorMessage;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this); // Updated to 5 tabs
    _loadSellerProducts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSellerProducts() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not logged in');
      }

      AppLogger.d('Loading products for seller: ${user.uid}');

      // Get all products by this seller (including inactive ones)
      final allProducts = await _getAllProductsBySeller(user.uid);

      AppLogger.d('Loaded ${allProducts.length} products for seller');

      // Categorize products
      _categorizeProducts(allProducts);

      if (mounted) {
        setState(() {
          _allProducts = allProducts;
          _isLoading = false;
        });
      }
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

  Future<List<Product>> _getAllProductsBySeller(String sellerId) async {
    try {
      // Get ALL products by seller (not just active ones)
      // Remove orderBy to avoid index requirement
      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection('Product')
          .where('sellerId', isEqualTo: sellerId)
          .get();

      List<Product> products = [];
      for (var doc in querySnapshot.docs) {
        try {
          Product product = Product.fromFirestore(doc);

          // Get variations for each product
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

          products.add(product);
        } catch (e) {
          AppLogger.d('Error processing product document: $e');
        }
      }

      // Sort products by createdAt on the client side (newest first)
      products.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return products;
    } catch (e) {
      AppLogger.d('Error fetching seller products: $e');
      rethrow;
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

    AppLogger.d(
      'Products categorized - Active: ${_activeProducts.length}, Inactive: ${_inactiveProducts.length}, Out of Stock: ${_outOfStockProducts.length}, Drafts: ${_draftProducts.length}, Archived: ${_archivedProducts.length}',
    );
  }

  bool _isProductOutOfStock(Product product) {
    if (product.variations == null || product.variations!.isEmpty) return true;

    // Check if all variations have 0 stock
    return product.variations!.every((variation) => variation.stock <= 0);
  }

  Future<void> _handleRefresh() async {
    await _loadSellerProducts();
  }

  void _navigateToAddProduct() {
    Navigator.pushNamed(context, '/add-product').then((_) {
      // Refresh the list when returning from add product
      _loadSellerProducts();
    });
  }

  void _navigateToEditProduct(Product product) {
    Navigator.pushNamed(
      context,
      '/edit-product',
      arguments: {'productId': product.productId},
    ).then((_) {
      // Refresh the list when returning from edit product
      _loadSellerProducts();
    });
  }

  void _showProductOptions(Product product) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.onSurface.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              product.name,
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            _buildBottomSheetOption(
              icon: Icons.edit,
              title: 'Edit Product',
              onTap: () {
                Navigator.pop(context);
                _navigateToEditProduct(product);
              },
            ),
            const SizedBox(height: 12),
            // Show different options based on product status
            if (product.isDraft) ...[
              _buildBottomSheetOption(
                icon: Icons.publish,
                title: 'Publish Product',
                onTap: () {
                  Navigator.pop(context);
                  _publishDraft(product);
                },
              ),
            ] else if (product.isArchived) ...[
              _buildBottomSheetOption(
                icon: Icons.unarchive,
                title: 'Unarchive Product',
                onTap: () {
                  Navigator.pop(context);
                  _unarchiveProduct(product);
                },
              ),
            ] else ...[
              _buildBottomSheetOption(
                icon: product.isActive
                    ? Icons.visibility_off
                    : Icons.visibility,
                title: product.isActive ? 'Deactivate' : 'Activate',
                onTap: () {
                  Navigator.pop(context);
                  _toggleProductStatus(product);
                },
              ),
              const SizedBox(height: 12),
              _buildBottomSheetOption(
                icon: Icons.archive,
                title: 'Archive Product',
                onTap: () {
                  Navigator.pop(context);
                  _archiveProduct(product);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSheetOption({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          child: Row(
            children: [
              Icon(
                icon,
                color: isDestructive ? AppColors.error : AppColors.primary,
                size: 24,
              ),
              const SizedBox(width: 16),
              Text(
                title,
                style: AppTextStyles.bodyLarge.copyWith(
                  color: isDestructive ? AppColors.error : AppColors.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleProductStatus(Product product) async {
    try {
      final newStatus = !product.isActive;

      await FirebaseFirestore.instance
          .collection('Product')
          .doc(product.productId)
          .update({
            'isActive': newStatus,
            'updatedAt': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newStatus
                  ? 'Product activated successfully'
                  : 'Product deactivated successfully',
            ),
            backgroundColor: AppColors.success,
          ),
        );

        // Refresh the list
        _loadSellerProducts();
      }
    } catch (e) {
      AppLogger.d('Error toggling product status: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating product status: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _publishDraft(Product product) async {
    try {
      await FirebaseFirestore.instance
          .collection('Product')
          .doc(product.productId)
          .update({
            'isDraft': false,
            'isActive': true,
            'updatedAt': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Draft "${product.name}" published successfully'),
            backgroundColor: AppColors.success,
          ),
        );

        // Refresh the list
        _loadSellerProducts();
      }
    } catch (e) {
      AppLogger.d('Error publishing draft: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error publishing draft: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _archiveProduct(Product product) async {
    try {
      await FirebaseFirestore.instance
          .collection('Product')
          .doc(product.productId)
          .update({
            'isArchived': true,
            'isActive': false,
            'updatedAt': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Product "${product.name}" archived successfully'),
            backgroundColor: AppColors.success,
          ),
        );

        // Refresh the list
        _loadSellerProducts();
      }
    } catch (e) {
      AppLogger.d('Error archiving product: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error archiving product: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _unarchiveProduct(Product product) async {
    try {
      await FirebaseFirestore.instance
          .collection('Product')
          .doc(product.productId)
          .update({
            'isArchived': false,
            'isActive': true,
            'updatedAt': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Product "${product.name}" unarchived successfully'),
            backgroundColor: AppColors.success,
          ),
        );

        // Refresh the list
        _loadSellerProducts();
      }
    } catch (e) {
      AppLogger.d('Error unarchiving product: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error unarchiving product: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Row(
          children: [
            Icon(Icons.store, color: AppColors.primary, size: 24),
            const SizedBox(width: 8),
            Text(
              'My Listings',
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        bottom: _isLoading
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(kToolbarHeight),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWideWeb =
                        kIsWeb &&
                        MediaQuery.of(context).size.width > 800; // BREAKPOINT
                    final tabs = TabBar(
                      controller: _tabController,
                      labelColor: AppColors.primary,
                      unselectedLabelColor: AppColors.onSurface.withValues(
                        alpha: 0.6,
                      ),
                      indicatorColor: AppColors.primary,
                      isScrollable: true,
                      tabs: [
                        Tab(text: 'Active (${_activeProducts.length})'),
                        Tab(text: 'Inactive (${_inactiveProducts.length})'),
                        Tab(
                          text: 'Out of Stock (${_outOfStockProducts.length})',
                        ),
                        Tab(text: 'Drafts (${_draftProducts.length})'),
                        Tab(text: 'Archived (${_archivedProducts.length})'),
                      ],
                    );
                    if (isWideWeb) {
                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: 1000,
                          ), // MAX_WIDTH match body
                          child: tabs,
                        ),
                      );
                    }
                    return tabs; // mobile & narrow web full width
                  },
                ),
              ),
      ),
      // Responsive wrapper added
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWideWeb = kIsWeb && constraints.maxWidth > 800; // BREAKPOINT
          final content = _buildBody();
          if (isWideWeb) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000), // MAX_WIDTH
                child: Material(color: Colors.transparent, child: content),
              ),
            );
          }
          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(width: constraints.maxWidth, child: content),
          );
        },
      ),
      floatingActionButton: Container(
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
          onPressed: _navigateToAddProduct,
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          elevation: 0,
          highlightElevation: 0,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildBody() {
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
      child: TabBarView(
        controller: _tabController,
        children: [
          _buildProductList(_activeProducts, 'active'),
          _buildProductList(_inactiveProducts, 'inactive'),
          _buildProductList(_outOfStockProducts, 'out of stock'),
          _buildProductList(_draftProducts, 'drafts'),
          _buildProductList(_archivedProducts, 'archived'),
        ],
      ),
    );
  }

  Widget _buildProductList(List<Product> products, String category) {
    if (products.isEmpty) {
      return _buildEmptyTabState(category);
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _getResponsiveCrossAxisCount(context),
        childAspectRatio: 0.75,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
        return GestureDetector(
          onTap: () => _showProductOptions(product),
          child: ProductCard(
            product: product,
            onTap: () => _showProductOptions(product),
          ),
        );
      },
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
        message =
            'No inactive products\nAll your products are currently active';
        icon = Icons.visibility_off;
        break;
      case 'out of stock':
        message = 'No out of stock products\nAll your products are in stock';
        icon = Icons.inventory_2;
        break;
      case 'drafts':
        message =
            'No draft products\nSave products as drafts to work on them later';
        icon = Icons.drafts;
        break;
      case 'archived':
        message =
            'No archived products\nArchive products you want to keep but not display';
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
              child: Icon(icon, size: 64, color: AppColors.primary),
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
                label: const Text('Add Product'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Container(
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
              'Failed to load products',
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'An error occurred',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _loadSellerProducts,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                elevation: 0,
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

  Widget _buildEmptyState() {
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
              child: const Icon(
                Icons.store,
                size: 64,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No products yet',
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Start selling by adding your first product',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.7),
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
                elevation: 0,
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

  int _getResponsiveCrossAxisCount(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    if (screenWidth >= 1200) {
      return 6;
    } else if (screenWidth >= 900) {
      return 5;
    } else if (screenWidth >= 600) {
      return 4;
    } else if (screenWidth >= 480) {
      return 3;
    } else {
      return 2;
    }
  }
}
