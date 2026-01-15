import 'package:dentpal/core/app_theme/index.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product_model.dart';
import '../services/product_service.dart';
import '../services/category_service.dart';
import '../widgets/product_card.dart';
import 'package:dentpal/utils/app_logger.dart';
import 'package:dentpal/utils/navigation_utils.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class StorePage extends StatefulWidget {
  final String sellerId;
  final Map<String, dynamic>? sellerData;

  const StorePage({super.key, required this.sellerId, this.sellerData});

  @override
  _StorePageState createState() => _StorePageState();
}

class _StorePageState extends State<StorePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ProductService _productService = ProductService();
  final CategoryService _categoryService = CategoryService();

  // Store data
  Map<String, dynamic> _storeData = {};
  bool _isLoading = true;

  // Products tab data
  List<Product> _allSellerProducts = [];
  List<Product> _filteredProducts = [];
  String _selectedFilter = 'Popular';
  bool _isLoadingProducts = false;

  // Categories tab data
  List<Category> _sellerCategories = [];
  List<SubCategory> _sellerSubCategories = [];
  bool _isLoadingCategories = false;
  String? _selectedCategoryId;
  String? _selectedSubCategoryId;
  List<Product> _categoryFilteredProducts = [];
  Map<String, List<SubCategory>> _subCategoriesByCategory = {};

  final List<String> _productFilters = [
    'Popular',
    'Latest',
    'Top Sales',
    'Price (Low to High)',
    'Price (High to Low)',
  ];

  @override
  void initState() {
    super.initState();
    // Check for initialTab in sellerData and set appropriate index
    int initialIndex = 0; // Default to 'Shop' tab
    if (widget.sellerData != null && widget.sellerData!['initialTab'] != null) {
      final String initialTab = widget.sellerData!['initialTab'] as String;
      if (initialTab == 'products') {
        initialIndex = 1; // Products tab
      } else if (initialTab == 'categories') {
        initialIndex = 2; // Categories tab
      }
    }
    
    _tabController = TabController(length: 3, vsync: this, initialIndex: initialIndex);
    _tabController.addListener(() {
      setState(() {}); // Rebuild when tab changes
    });
    _loadStoreData();
    
    // Update URL for deep linking support
    NavigationUtils.updatePageUrl('/store/${widget.sellerId}');
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadStoreData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      AppLogger.d(
        'StorePage: Starting to load store data for sellerId: ${widget.sellerId}',
      );

      // Load store/seller data
      // Check if sellerData contains actual store information (not just initialTab)
      if (widget.sellerData != null && widget.sellerData!.containsKey('shopName')) {
        _storeData = widget.sellerData!;
        AppLogger.d(
          'StorePage: Using provided seller data: ${_storeData['shopName']}',
        );
      } else {
        AppLogger.d('StorePage: Fetching seller data from Firestore...');
        _storeData = await _getSellerData(widget.sellerId);
        AppLogger.d(
          'StorePage: Fetched seller data: ${_storeData['shopName']}',
        );
      }

      // Load products when Products tab is initially selected
      AppLogger.d('StorePage: Loading seller products...');
      await _loadSellerProducts();
    } catch (e) {
      AppLogger.d('StorePage: Error loading store data: $e');
      AppLogger.d('StorePage: Stack trace: ${StackTrace.current}');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<Map<String, dynamic>> _getSellerData(String sellerId) async {
    try {
      final sellerDoc = await FirebaseFirestore.instance
          .collection('Seller')
          .doc(sellerId)
          .get();

      if (sellerDoc.exists) {
        final data = sellerDoc.data() as Map<String, dynamic>;

        // Safely read nested vendor > company fields
        final vendor = (data['vendor'] is Map)
            ? data['vendor'] as Map<String, dynamic>
            : const {};
        final company = (vendor['company'] is Map)
            ? vendor['company'] as Map<String, dynamic>
            : const {};

        // Store name from vendor.company.storeName, fallback to previous keys or default
        final String storeName =
            (company['storeName'] as String?) ??
            (data['storeName'] as String?) ??
            'DentPal Store';

        // Address: vendor.company.address.city and province concatenated
        String address = 'Store location not available';
        final addressMap = (company['address'] is Map)
            ? company['address'] as Map<String, dynamic>
            : const {};
        final String? city = addressMap['city'] as String?;
        final String? province = addressMap['province'] as String?;
        if ((city != null && city.isNotEmpty) ||
            (province != null && province.isNotEmpty)) {
          address = [
            city,
            province,
          ].whereType<String>().where((e) => e.isNotEmpty).join(', ');
        } else {
          // fallback to flat address if present
          address = (data['address'] as String?) ?? 'No address provided';
        }

        return {
          'shopName': storeName,
          'address': address,
          'contactEmail': data['contactEmail'] ?? '',
          'contactNumber': data['contactNumber'] ?? '',
          'isActive': data['isActive'] ?? true,
          'profileImageURL': data['profileImageURL'] ?? '',
        };
      }
    } catch (e) {
      AppLogger.d('Error fetching seller data: $e');
    }

    return {
      'shopName': 'DentPal Store',
      'address': 'Store location not available',
      'contactEmail': '',
      'contactNumber': '',
      'isActive': true,
      'profileImageURL': '',
    };
  }

  Future<void> _loadSellerProducts() async {
    setState(() {
      _isLoadingProducts = true;
    });

    try {
      AppLogger.d(
        'StorePage: Starting to load products for seller: ${widget.sellerId}',
      );
      _allSellerProducts = await _productService.getProductsBySeller(
        widget.sellerId,
      );
      AppLogger.d(
        'StorePage: Loaded ${_allSellerProducts.length} products for seller ${widget.sellerId}',
      );

      for (int i = 0; i < _allSellerProducts.length && i < 3; i++) {
        final product = _allSellerProducts[i];
        AppLogger.d('Product $i: ${product.name} (ID: ${product.productId})');
      }

      _applyProductFilter();
    } catch (e) {
      AppLogger.d('StorePage: Error loading seller products: $e');
      AppLogger.d('StorePage: Stack trace: ${StackTrace.current}');
    } finally {
      setState(() {
        _isLoadingProducts = false;
      });
    }
  }

  void _applyProductFilter() {
    List<Product> filtered = List.from(_allSellerProducts);

    switch (_selectedFilter) {
      case 'Popular':
        filtered.sort((a, b) => b.clickCounter.compareTo(a.clickCounter));
        break;
      case 'Latest':
        filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case 'Top Sales':
        filtered.sort((a, b) => b.clickCounter.compareTo(a.clickCounter));
        break;
      case 'Price (Low to High)':
        filtered.sort((a, b) {
          final priceA = a.lowestPrice ?? 0;
          final priceB = b.lowestPrice ?? 0;
          return priceA.compareTo(priceB);
        });
        break;
      case 'Price (High to Low)':
        filtered.sort((a, b) {
          final priceA = a.lowestPrice ?? 0;
          final priceB = b.lowestPrice ?? 0;
          return priceB.compareTo(priceA);
        });
        break;
    }

    setState(() {
      _filteredProducts = filtered;
    });
  }

  Future<void> _loadSellerCategories() async {
    setState(() {
      _isLoadingCategories = true;
    });

    try {
      AppLogger.d(
        'StorePage: Starting to load categories for seller: ${widget.sellerId}',
      );
      AppLogger.d(
        'StorePage: Total seller products: ${_allSellerProducts.length}',
      );

      // Get unique category IDs from seller's products
      final categoryIds = _allSellerProducts
          .map((product) => product.categoryId)
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      // Get unique subcategory IDs from seller's products
      final subCategoryIds = _allSellerProducts
          .map((product) => product.subCategoryId)
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      AppLogger.d(
        'StorePage: Found ${categoryIds.length} unique category IDs: $categoryIds',
      );
      AppLogger.d(
        'StorePage: Found ${subCategoryIds.length} unique subcategory IDs: $subCategoryIds',
      );

      // Load categories
      _sellerCategories = [];
      for (String categoryId in categoryIds) {
        try {
          final category = await _categoryService.getCategoryById(categoryId);
          if (category != null) {
            _sellerCategories.add(category);
            AppLogger.d('StorePage: Loaded category: ${category.categoryName}');
          } else {
            AppLogger.d('StorePage: Category not found for ID: $categoryId');
          }
        } catch (e) {
          AppLogger.d('StorePage: Error loading category $categoryId: $e');
        }
      }

      // Load subcategories and group them by category
      _sellerSubCategories = [];
      _subCategoriesByCategory = {};
      if (subCategoryIds.isNotEmpty) {
        try {
          _sellerSubCategories = await _categoryService.getSubCategoriesByIds(
            subCategoryIds,
          );
          AppLogger.d(
            'StorePage: Loaded ${_sellerSubCategories.length} subcategories',
          );
          
          // Group subcategories by their parent category
          for (var subCategory in _sellerSubCategories) {
            if (!_subCategoriesByCategory.containsKey(subCategory.categoryId)) {
              _subCategoriesByCategory[subCategory.categoryId] = [];
            }
            _subCategoriesByCategory[subCategory.categoryId]!.add(subCategory);
          }
        } catch (e) {
          AppLogger.d('StorePage: Error loading subcategories: $e');
        }
      }

      AppLogger.d(
        'StorePage: Final results - Categories: ${_sellerCategories.length}, Subcategories: ${_sellerSubCategories.length}',
      );
    } catch (e) {
      AppLogger.d('StorePage: Error loading seller categories: $e');
      AppLogger.d('StorePage: Stack trace: ${StackTrace.current}');
    } finally {
      setState(() {
        _isLoadingCategories = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const double kWebBreakpoint = 900; // [BREAKPOINT]
    const double kWebMaxWidth = 1100; // [MAX_WIDTH]

    return Scaffold(
      backgroundColor: AppColors.background,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final bool isWideWeb =
                    kIsWeb && constraints.maxWidth > kWebBreakpoint;

                final Widget pageContent = SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildAppBarHeader(),
                      _buildStoreInfo(),
                      _buildTabBar(),
                      _buildTabContent(),
                    ],
                  ),
                );

                if (isWideWeb) {
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: kWebMaxWidth),
                      child: pageContent,
                    ),
                  );
                }

                // Mobile and narrow web: full-width
                return pageContent;
              },
            ),
    );
  }

  Widget _buildAppBarHeader() {
    return Container(
      height: 250,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.8)],
        ),
      ),
      child: SafeArea(
        top: !kIsWeb, // remove top inset on web to avoid large top margin
        child: Column(
          children: [
            // Back button row
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.arrow_back,
                        color: AppColors.primary,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ],
              ),
            ),
            // Store info section
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildStoreIcon(),
                  const SizedBox(height: 16),
                  Text(
                    _storeData['shopName'] ?? 'Store Name',
                    style: AppTextStyles.headlineSmall.copyWith(
                      color: AppColors.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoreIcon() {
    final profileImageURL = _storeData['profileImageURL'] as String? ?? '';

    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.onPrimary, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: profileImageURL.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: profileImageURL,
                fit: BoxFit.cover,
                placeholder: (context, url) => const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.primary,
                    ),
                  ),
                ),
                errorWidget: (context, url, error) =>
                    const Icon(Icons.store, size: 40, color: AppColors.primary),
              )
            : const Icon(Icons.store, size: 40, color: AppColors.primary),
      ),
    );
  }

  Widget _buildStoreInfo() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow(
            Icons.location_on,
            'Address',
            _storeData['address'] ?? 'Not available',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.onSurface.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: AppColors.surface,
      child: TabBar(
        controller: _tabController,
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.onSurface.withValues(alpha: 0.6),
        indicatorColor: AppColors.primary,
        indicatorWeight: 3,
        onTap: (index) {
          if (index == 2 && _sellerCategories.isEmpty) {
            _loadSellerCategories();
          }
          setState(() {}); // Trigger rebuild to show selected tab content
        },
        tabs: const [
          Tab(text: 'Shop'),
          Tab(text: 'Products'),
          Tab(text: 'Categories'),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_tabController.index) {
      case 0:
        return _buildShopTabContent();
      case 1:
        return _buildProductsTabContent();
      case 2:
        return _buildCategoriesTabContent();
      default:
        return _buildShopTabContent();
    }
  }

  Widget _buildShopTabContent() {
    return Container(
      padding: const EdgeInsets.all(24),
      height: 400, // Fixed height for content
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.construction,
              size: 64,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Shop Coming Soon',
            style: AppTextStyles.titleLarge.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'This section is under development',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.onSurface.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildProductsTabContent() {
    return Column(
      children: [
        _buildProductFilters(),
        _isLoadingProducts
            ? SizedBox(
                height: 300,
                child: const Center(child: CircularProgressIndicator()),
              )
            : _filteredProducts.isEmpty
            ? _buildEmptyProductsState()
            : _buildProductGrid(),
      ],
    );
  }

  Widget _buildProductFilters() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _productFilters.map((filter) {
            final isSelected = filter == _selectedFilter;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedFilter = filter;
                });
                _applyProductFilter();
              },
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.onSurface.withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  filter,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: isSelected
                        ? AppColors.onPrimary
                        : AppColors.onSurface,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildProductGrid() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _getResponsiveCrossAxisCount(context),
          childAspectRatio: _getResponsiveAspectRatio(context),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: _filteredProducts.length,
        itemBuilder: (context, index) {
          final product = _filteredProducts[index];
          return ProductCard(
            product: product,
            onTap: () {
              // Navigate to product detail page with deep linking support
              NavigationUtils.navigateToProductDetail(
                context,
                product.productId,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyProductsState() {
    return SizedBox(
      height: 300,
      child: Center(
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
                Icons.inventory_2_outlined,
                size: 64,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Products Found',
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'This store doesn\'t have any products yet',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoriesTabContent() {
    if (_isLoadingCategories) {
      return SizedBox(
        height: 300,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_sellerCategories.isEmpty && _sellerSubCategories.isEmpty) {
      return _buildEmptyCategoriesState();
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Show categories if no category is selected
              if (_selectedCategoryId == null) ...[
                Text(
                  'Categories',
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                ..._sellerCategories.map(
                  (category) => _buildCategoryItem(category),
                ),
              ],
              // Show subcategories when category is selected
              if (_selectedCategoryId != null && _selectedSubCategoryId == null) ...[
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () {
                        setState(() {
                          _selectedCategoryId = null;
                        });
                      },
                    ),
                    Text(
                      'Subcategories',
                      style: AppTextStyles.titleMedium.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_subCategoriesByCategory[_selectedCategoryId]?.isNotEmpty == true) ...[
                  ..._subCategoriesByCategory[_selectedCategoryId]!.map(
                    (subCategory) => _buildSubCategoryItem(subCategory),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No subcategories found',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
        // Show products when subcategory is selected
        if (_selectedSubCategoryId != null && _categoryFilteredProducts.isNotEmpty) ...[
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    setState(() {
                      _selectedSubCategoryId = null;
                      _categoryFilteredProducts = [];
                    });
                  },
                ),
                Expanded(
                  child: Text(
                    'Products (${_categoryFilteredProducts.length})',
                    style: AppTextStyles.titleMedium.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildCategoryFilteredProductGrid(),
        ],
      ],
    );
  }

  Widget _buildCategoryItem(Category category) {
    final isSelected = _selectedCategoryId == category.categoryId;
    final productsInCategory = _allSellerProducts
        .where((product) => product.categoryId == category.categoryId)
        .length;
    final subCategoriesCount = _subCategoriesByCategory[category.categoryId]?.length ?? 0;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedCategoryId = category.categoryId;
          _selectedSubCategoryId = null;
          _categoryFilteredProducts = [];
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.15)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : AppColors.onSurface.withValues(alpha: 0.1),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.category,
                size: 20,
                color: isSelected ? AppColors.primary : AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.categoryName,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.onSurface,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$productsInCategory product${productsInCategory != 1 ? 's' : ''} • $subCategoriesCount subcategor${subCategoriesCount != 1 ? 'ies' : 'y'}',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.keyboard_arrow_right,
              color: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubCategoryItem(SubCategory subCategory) {
    final isSelected = _selectedSubCategoryId == subCategory.subCategoryId;
    final productsInSubCategory = _allSellerProducts
        .where((product) => product.subCategoryId == subCategory.subCategoryId)
        .length;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedSubCategoryId = subCategory.subCategoryId;
          _categoryFilteredProducts = _allSellerProducts
              .where((product) =>
                  product.subCategoryId == subCategory.subCategoryId)
              .toList();
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.secondary.withValues(alpha: 0.15)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppColors.secondary
                : AppColors.onSurface.withValues(alpha: 0.1),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.subdirectory_arrow_right,
                size: 20,
                color: isSelected ? AppColors.secondary : AppColors.secondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subCategory.subCategoryName,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.onSurface,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  if (productsInSubCategory > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      '$productsInSubCategory product${productsInSubCategory != 1 ? 's' : ''}',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.keyboard_arrow_right,
              color: AppColors.secondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCategoriesState() {
    return SizedBox(
      height: 300,
      child: Center(
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
                Icons.category_outlined,
                size: 64,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Categories Found',
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'This store doesn\'t have any categorized products yet',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryFilteredProductGrid() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _getResponsiveCrossAxisCount(context),
          childAspectRatio: _getResponsiveAspectRatio(context),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: _categoryFilteredProducts.length,
        itemBuilder: (context, index) {
          final product = _categoryFilteredProducts[index];
          return ProductCard(
            product: product,
            onTap: () {
              NavigationUtils.navigateToProductDetail(
                context,
                product.productId,
              );
            },
          );
        },
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
}
