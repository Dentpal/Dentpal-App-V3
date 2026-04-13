import 'package:dentpal/core/app_theme/index.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../models/product_model.dart';
import '../services/product_service.dart';
import '../services/category_service.dart';
import 'package:dentpal/utils/app_logger.dart';
import 'package:dentpal/utils/navigation_utils.dart';
import 'package:dentpal/utils/currency_formatter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dentpal/core/widgets/web_footer.dart';

class StorePage extends StatefulWidget {
  final String sellerId;
  final Map<String, dynamic>? sellerData;

  const StorePage({super.key, required this.sellerId, this.sellerData});

  @override
  _StorePageState createState() => _StorePageState();
}

class _StorePageState extends State<StorePage> {
  final ProductService _productService = ProductService();
  final CategoryService _categoryService = CategoryService();

  // Store data
  Map<String, dynamic> _storeData = {};
  bool _isLoading = true;

  // Products (current page — filtered by selected category)
  List<Product> _products = [];
  bool _isLoadingProducts = false;

  // Product pagination
  DocumentSnapshot? _lastProductDoc;
  bool _hasMoreProducts = true;
  bool _isFetchingMore = false;
  final ScrollController _scrollController = ScrollController();

  // Sold counts from completed orders
  Map<String, int> _soldCounts = {};

  // Categories derived from this store's products
  // Map of categoryId -> display name
  Map<String, String> _categories = {};
  String? _selectedCategoryId; // null = All

  // Search (client-side on loaded products)
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Store rating
  double _storeRating = 0.0;

  // Version token for cache-busting
  late final String _imageVersionToken;

  @override
  void initState() {
    super.initState();
    _imageVersionToken = DateTime.now().millisecondsSinceEpoch.toString();
    _scrollController.addListener(_onScroll);
    _loadStoreData();
    NavigationUtils.updatePageUrl('/store/${widget.sellerId}');
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isFetchingMore &&
        _hasMoreProducts &&
        _lastProductDoc != null) {
      _loadMoreProducts();
    }
  }

  Future<void> _loadStoreData() async {
    setState(() { _isLoading = true; });

    try {
      AppLogger.d('StorePage: Loading store data for sellerId: ${widget.sellerId}');

      // Check if sellerData contains actual store information (not just initialTab)
      if (widget.sellerData != null && widget.sellerData!.containsKey('shopName')) {
        _storeData = widget.sellerData!;
      } else {
        _storeData = await _getSellerData(widget.sellerId);
      }

      await _loadSellerProducts();
    } catch (e) {
      AppLogger.d('StorePage: Error loading store data: $e');
    } finally {
      setState(() { _isLoading = false; });
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

        final vendor = (data['vendor'] is Map)
            ? data['vendor'] as Map<String, dynamic>
            : const <String, dynamic>{};
        final company = (vendor['company'] is Map)
            ? vendor['company'] as Map<String, dynamic>
            : const <String, dynamic>{};

        // Cover image
        String coverImageURL = '';
        if (vendor['coverImage'] is Map && vendor['coverImage']['url'] is String) {
          coverImageURL = vendor['coverImage']['url'] as String;
        } else if (vendor['coverImage'] is String) {
          coverImageURL = vendor['coverImage'] as String;
        }

        // Profile image
        String profileImageURL = '';
        if (vendor['profileImage'] is Map && vendor['profileImage']['url'] is String) {
          profileImageURL = vendor['profileImage']['url'] as String;
        }

        // Store name
        final String storeName =
            (company['storeName'] as String?) ??
            (data['storeName'] as String?) ??
            'DentPal Store';

        // Address
        String address = 'Store location not available';
        final addressMap = (company['address'] is Map)
            ? company['address'] as Map<String, dynamic>
            : const <String, dynamic>{};
        final String? city = addressMap['city'] as String?;
        final String? province = addressMap['province'] as String?;
        if ((city != null && city.isNotEmpty) ||
            (province != null && province.isNotEmpty)) {
          address = [city, province]
              .whereType<String>()
              .where((e) => e.isNotEmpty)
              .join(', ');
        } else {
          address = (data['address'] as String?) ?? 'No address provided';
        }

        // Store rating
        final rating = data['rating'];
        if (rating is num) {
          _storeRating = rating.toDouble();
        }

        return {
          'shopName': storeName,
          'address': address,
          'contactEmail': data['contactEmail'] ?? '',
          'contactNumber': data['contactNumber'] ?? '',
          'isActive': data['isActive'] ?? true,
          'profileImageURL': profileImageURL.isNotEmpty ? profileImageURL : (data['profileImageURL'] ?? ''),
          'coverImageURL': coverImageURL,
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
      'coverImageURL': '',
    };
  }

  /// Initial load — fetches without category filter to populate category chips,
  /// then optionally re-fetches with category filter if one is pre-selected.
  Future<void> _loadSellerProducts() async {
    setState(() {
      _isLoadingProducts = true;
      _products = [];
      _lastProductDoc = null;
      _hasMoreProducts = true;
    });

    try {
      final result = await _productService.getProductsBySellerPaginated(
        sellerId: widget.sellerId,
        limit: 10,
        categoryId: _selectedCategoryId,
      );
      final loaded = result['products'] as List<Product>;
      _lastProductDoc = result['lastDocument'] as DocumentSnapshot?;
      _hasMoreProducts = result['hasMore'] as bool;

      // Derive categories from ALL this store's products (no category filter)
      // Only do this on first load (when no category is selected yet)
      if (_selectedCategoryId == null && _categories.isEmpty) {
        await _loadStoreCategories();
      }

      if (mounted) {
        setState(() {
          _products = loaded;
          _isLoadingProducts = false;
        });
      }

      AppLogger.d('StorePage: Loaded ${loaded.length} products (hasMore: $_hasMoreProducts)');

      // Fetch sold counts from completed orders
      _productService.getSoldCountsBySeller(widget.sellerId).then((counts) {
        if (mounted) setState(() { _soldCounts = counts; });
      });
    } catch (e) {
      AppLogger.d('StorePage: Error loading seller products: $e');
      if (mounted) setState(() { _isLoadingProducts = false; });
    }
  }

  /// Fetches all unique categoryIds for this store and resolves their names.
  Future<void> _loadStoreCategories() async {
    try {
      // Fetch all active products for this seller (just IDs + categoryId, limit high)
      final snapshot = await FirebaseFirestore.instance
          .collection('Product')
          .where('sellerId', isEqualTo: widget.sellerId)
          .where('isActive', isEqualTo: true)
          .get();

      final uniqueCategoryIds = snapshot.docs
          .map((d) => d.data()['categoryID'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      if (uniqueCategoryIds.isEmpty) return;

      // Resolve category names
      final Map<String, String> resolved = {};
      for (final catId in uniqueCategoryIds) {
        final cat = await _categoryService.getCategoryById(catId);
        if (cat != null) resolved[catId] = cat.categoryName;
      }

      if (mounted) setState(() { _categories = resolved; });
      AppLogger.d('StorePage: Derived ${resolved.length} categories from products');
    } catch (e) {
      AppLogger.d('StorePage: Error loading store categories: $e');
    }
  }

  Future<void> _loadMoreProducts() async {
    if (_isFetchingMore || !_hasMoreProducts || _lastProductDoc == null) return;

    setState(() { _isFetchingMore = true; });

    try {
      final result = await _productService.getProductsBySellerPaginated(
        sellerId: widget.sellerId,
        limit: 10,
        lastDocument: _lastProductDoc,
        categoryId: _selectedCategoryId,
      );
      final newProducts = result['products'] as List<Product>;
      _lastProductDoc = result['lastDocument'] as DocumentSnapshot?;
      _hasMoreProducts = result['hasMore'] as bool;

      if (mounted) {
        setState(() {
          _products.addAll(newProducts);
          _isFetchingMore = false;
        });
      }
      AppLogger.d('StorePage: Loaded ${newProducts.length} more products (total: ${_products.length})');
    } catch (e) {
      AppLogger.d('StorePage: Error loading more products: $e');
      if (mounted) setState(() { _isFetchingMore = false; });
    }
  }

  void _onCategorySelected(String? categoryId) {
    if (_selectedCategoryId == categoryId) return;
    setState(() { _selectedCategoryId = categoryId; });
    _loadSellerProducts(); // Reset pagination + refetch with new categoryId
  }

  void _onSearchChanged(String query) {
    setState(() { _searchQuery = query; });
  }

  /// Products to display — apply client-side search on top of loaded products
  List<Product> get _displayedProducts {
    if (_searchQuery.isEmpty) return _products;
    final q = _searchQuery.toLowerCase();
    return _products.where((p) =>
        p.name.toLowerCase().contains(q) ||
        p.description.toLowerCase().contains(q)).toList();
  }

  void _shareStore() {
    final shareUrl = NavigationUtils.getStoreShareUrl(widget.sellerId);
    final storeName = _storeData['shopName'] ?? 'DentPal Store';
    final shareText = '$storeName\n\nCheck out this store on DentPal: $shareUrl';

    if (!kIsWeb) {
      SharePlus.instance.share(ShareParams(text: shareText, subject: 'Check out this store on DentPal'));
      return;
    }

    // On web, copy to clipboard
    Clipboard.setData(ClipboardData(text: shareUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Store link copied to clipboard!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    const double kWebBreakpoint = 900;
    const double kWebMaxWidth = 1100;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final bool isWideWeb =
                    kIsWeb && constraints.maxWidth > kWebBreakpoint;

                final Widget pageContent = SingleChildScrollView(
                  controller: _scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildBannerSection(),
                      _buildStoreInfo(),
                      _buildVoucherSection(),
                      _buildSearchBar(),
                      if (_categories.isNotEmpty) _buildCategoriesSection(),
                      _buildProductsGrid(),
                      if (_isFetchingMore)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      const WebFooter(),
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

                return pageContent;
              },
            ),
    );
  }

  // ── Banner Section ──────────────────────────────────────────────────────

  Widget _buildBannerSection() {
    final coverImageURL = _storeData['coverImageURL'] as String? ?? '';
    final coverImageURLWithCache = coverImageURL.isNotEmpty
        ? (coverImageURL.contains('?')
            ? '$coverImageURL&v=$_imageVersionToken'
            : '$coverImageURL?v=$_imageVersionToken')
        : '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: AspectRatio(
          aspectRatio: 8 / 3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Cover image or fallback gradient
              if (coverImageURL.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: coverImageURLWithCache,
                  fit: BoxFit.cover,
                  cacheKey: coverImageURL,
                  placeholder: (context, url) => Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.8)],
                      ),
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
                  errorWidget: (context, url, error) => _buildBannerGradient(),
                )
              else
                _buildBannerGradient(),

              // Back button (top-left)
              Positioned(
                top: 12,
                left: 12,
                child: _buildCircleButton(
                  icon: Icons.arrow_back,
                  onPressed: () {
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    } else {
                      Navigator.pushReplacementNamed(context, '/');
                    }
                  },
                ),
              ),

              // Share button (top-right)
              Positioned(
                top: 12,
                right: 12,
                child: _buildCircleButton(
                  icon: Icons.share,
                  onPressed: _shareStore,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBannerGradient() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.8)],
        ),
      ),
    );
  }

  Widget _buildCircleButton({required IconData icon, required VoidCallback onPressed}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        icon: Icon(icon, color: AppColors.primary, size: 20),
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        padding: const EdgeInsets.all(8),
        onPressed: onPressed,
      ),
    );
  }

  // ── Store Info Section ──────────────────────────────────────────────────

  Widget _buildStoreInfo() {
    final profileImageURL = _storeData['profileImageURL'] as String? ?? '';
    final storeName = _storeData['shopName'] ?? 'Store Name';
    final address = _storeData['address'] ?? 'Not available';
    final profileImageURLWithCache = profileImageURL.isNotEmpty
        ? (profileImageURL.contains('?')
            ? '$profileImageURL&v=$_imageVersionToken'
            : '$profileImageURL?v=$_imageVersionToken')
        : '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Store Icon
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.2),
                width: 2,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: profileImageURL.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: profileImageURLWithCache,
                      fit: BoxFit.cover,
                      cacheKey: profileImageURL,
                      placeholder: (context, url) => const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      errorWidget: (context, url, error) =>
                          const Icon(Icons.store, size: 28, color: AppColors.primary),
                    )
                  : const Icon(Icons.store, size: 28, color: AppColors.primary),
            ),
          ),
          const SizedBox(width: 16),
          // Store Name, Location, and Rating
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  storeName,
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                // Location + Rating row
                Row(
                  children: [
                    const Icon(Icons.location_on, size: 14, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        address,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.onSurface.withValues(alpha: 0.7),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_storeRating > 0) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.star, size: 14, color: Colors.amber),
                      const SizedBox(width: 2),
                      Text(
                        _storeRating.toStringAsFixed(1),
                        style: AppTextStyles.bodySmall.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Voucher Section ─────────────────────────────────────────────────────

  Widget _buildVoucherSection() {
    final stream = FirebaseFirestore.instance
        .collection('vouchers')
        .where('sellerId', isEqualTo: widget.sellerId)
        .where('status', isEqualTo: 'active')
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final now = DateTime.now();
        final vouchers = snapshot.data!.docs
            .map((doc) => doc.data() as Map<String, dynamic>)
            .where((v) {
              final start = _parseDate(v['startDate']);
              final end = _parseDate(v['endDate']);
              if (start == null || end == null) return false;
              return !start.isAfter(now) && !end.isBefore(now);
            })
            .take(5)
            .toList();

        if (vouchers.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'Vouchers',
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              SizedBox(
                height: 88,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: vouchers.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) => _buildVoucherTicket(vouchers[index]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  Widget _buildVoucherTicket(Map<String, dynamic> voucher) {
    final code = (voucher['code'] as String?) ?? '';
    final name = (voucher['name'] as String?) ?? '';
    final minAmount = voucher['minimumOrderAmount'];
    final double? minSpend = (minAmount is num) ? minAmount.toDouble() : null;

    return ClipPath(
      clipper: _TicketClipper(),
      child: Container(
        width: 280,
        decoration: BoxDecoration(
          color: AppColors.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Left section — Code
            Container(
              width: 96,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.local_offer, size: 18, color: AppColors.primary),
                  const SizedBox(height: 4),
                  Text(
                    code,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                      letterSpacing: 0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            // Dashed divider
            SizedBox(
              width: 1,
              height: double.infinity,
              child: CustomPaint(
                painter: _DashedLinePainter(
                  color: AppColors.onSurface.withValues(alpha: 0.25),
                ),
              ),
            ),
            // Right section — Name + min spend
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (minSpend != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Min. Spend: ${CurrencyFormatter.formatWithPeso(minSpend)}',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.onSurface.withValues(alpha: 0.65),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Search Bar ──────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: 'Search products in this store...',
          hintStyle: AppTextStyles.bodySmall.copyWith(
            color: AppColors.onSurface.withValues(alpha: 0.5),
          ),
          prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.primary),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        style: AppTextStyles.bodyMedium,
      ),
    );
  }

  // ── Categories Section (derived from this store's products) ────────────

  Widget _buildCategoriesSection() {
    // Build ordered list: entries of [categoryId, categoryName]
    final entries = _categories.entries.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            'Categories',
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.onSurface,
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: entries.length + 1, // +1 for "All"
            itemBuilder: (context, index) {
              final isAll = index == 0;
              final catId = isAll ? null : entries[index - 1].key;
              final catName = isAll ? 'All' : entries[index - 1].value;
              final isSelected = _selectedCategoryId == catId;

              return GestureDetector(
                onTap: () => _onCategorySelected(catId),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                    catName,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: isSelected ? AppColors.onPrimary : AppColors.onSurface,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Products Grid ───────────────────────────────────────────────────────

  Widget _buildProductsGrid() {
    if (_isLoadingProducts) {
      return const SizedBox(
        height: 300,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_displayedProducts.isEmpty) {
      return _buildEmptyProductsState();
    }

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
        itemCount: _displayedProducts.length,
        itemBuilder: (context, index) {
          final product = _displayedProducts[index];
          return _buildStoreProductCard(product);
        },
      ),
    );
  }

  Widget _buildStoreProductCard(Product product) {
    final variationImage = (product.variations?.isNotEmpty == true)
        ? product.variations!.first.imageURL
        : null;
    final imageUrl = (variationImage != null && variationImage.isNotEmpty)
        ? variationImage
        : product.imageURL;

    final price = product.lowestPrice;
    final soldCount = _soldCounts[product.productId] ?? 0;
    final address = _storeData['address'] ?? '';

    return GestureDetector(
      onTap: () {
        NavigationUtils.navigateToProductDetail(context, product.productId);
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Image
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        placeholder: (context, url) => Container(
                          color: AppColors.primary.withValues(alpha: 0.05),
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: AppColors.primary.withValues(alpha: 0.05),
                          child: const Icon(Icons.image_not_supported, color: Colors.grey),
                        ),
                      )
                    : Container(
                        color: AppColors.primary.withValues(alpha: 0.05),
                        child: const Center(
                          child: Icon(Icons.image, color: Colors.grey, size: 40),
                        ),
                      ),
              ),
            ),
            // Product Info
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Line 1: Product Name
                  Text(
                    product.name,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Line 2: Price + Item Sold
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          price != null
                              ? CurrencyFormatter.formatWithPeso(price)
                              : 'Price varies',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (soldCount > 0)
                        Text(
                          '$soldCount sold',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.onSurface.withValues(alpha: 0.5),
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Line 3: ETA + Location
                  Row(
                    children: [
                      Text(
                        '1-3 days',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.onSurface.withValues(alpha: 0.5),
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          address,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.onSurface.withValues(alpha: 0.5),
                            fontSize: 10,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
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
              _searchQuery.isNotEmpty ? 'No products found.' : 'No Products Found',
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Try a different search term'
                  : 'This store doesn\'t have any products yet',
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

  // ── Responsive Helpers ──────────────────────────────────────────────────

  int _getResponsiveCrossAxisCount(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth >= 1200) return 6;
    if (screenWidth >= 900) return 5;
    if (screenWidth >= 600) return 4;
    if (screenWidth >= 480) return 3;
    return 2;
  }

  double _getResponsiveAspectRatio(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth >= 1200) return 0.70;
    if (screenWidth >= 900) return 0.65;
    if (screenWidth >= 600) return 0.68;
    return 0.65;
  }
}

/// Clips a rectangle into a ticket shape with small semicircle notches
/// cut out of the left and right edges at the vertical midpoint.
class _TicketClipper extends CustomClipper<Path> {
  static const double _radius = 14;
  static const double _notchRadius = 8;
  static const double _leftSectionWidth = 96;

  @override
  Path getClip(Size size) {
    final path = Path();
    final double notchCx = _leftSectionWidth;
    final double notchCy = size.height / 2;

    // Top-left rounded corner
    path.moveTo(0, _radius);
    path.quadraticBezierTo(0, 0, _radius, 0);
    // Top edge
    path.lineTo(size.width - _radius, 0);
    // Top-right rounded corner
    path.quadraticBezierTo(size.width, 0, size.width, _radius);
    // Right edge down to bottom-right corner
    path.lineTo(size.width, size.height - _radius);
    path.quadraticBezierTo(
        size.width, size.height, size.width - _radius, size.height);
    // Bottom edge
    path.lineTo(_radius, size.height);
    // Bottom-left rounded corner
    path.quadraticBezierTo(0, size.height, 0, size.height - _radius);
    // Left edge up, with notch at midpoint
    path.lineTo(0, notchCy + _notchRadius);
    path.arcToPoint(
      Offset(0, notchCy - _notchRadius),
      radius: const Radius.circular(_notchRadius),
      clockwise: true,
    );
    path.lineTo(0, _radius);
    path.close();

    // Cut out top and bottom notches at divider line
    final notchTop = Path()
      ..addOval(Rect.fromCircle(
        center: Offset(notchCx, 0),
        radius: _notchRadius,
      ));
    final notchBottom = Path()
      ..addOval(Rect.fromCircle(
        center: Offset(notchCx, size.height),
        radius: _notchRadius,
      ));

    return Path.combine(
      PathOperation.difference,
      Path.combine(PathOperation.difference, path, notchTop),
      notchBottom,
    );
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Paints a vertical dashed line filling the available height.
class _DashedLinePainter extends CustomPainter {
  final Color color;
  static const double _dashHeight = 4;
  static const double _dashSpace = 3;

  _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    double startY = 0;
    while (startY < size.height) {
      canvas.drawLine(
        Offset(0, startY),
        Offset(0, startY + _dashHeight),
        paint,
      );
      startY += _dashHeight + _dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}
