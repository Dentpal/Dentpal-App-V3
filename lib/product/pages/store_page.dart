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
import '../widgets/voucher_terms_sheet.dart';

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
  // Map of categoryId -> image URL (parallel to _categories)
  final Map<String, String?> _categoryImages = {};
  String? _selectedCategoryId; // null = All

  // Search (client-side on loaded products)
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Price sort + range (client-side on loaded products)
  String _selectedPriceSort = 'All';
  double? _minPrice;
  double? _maxPrice;


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


        return {
          'shopName': storeName,
          'address': address,
          'contactEmail': data['contactEmail'] ?? '',
          'contactNumber': data['contactNumber'] ?? '',
          'isActive': data['isActive'] ?? true,
          'profileImageURL': profileImageURL.isNotEmpty ? profileImageURL : (data['profileImageURL'] ?? ''),
          'coverImageURL': coverImageURL,
          'Rating': data['Rating'] ?? '',
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
      'Rating': '',
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

      // Resolve category names + images
      final Map<String, String> resolved = {};
      final Map<String, String?> resolvedImages = {};
      for (final catId in uniqueCategoryIds) {
        final cat = await _categoryService.getCategoryById(catId);
        if (cat != null) {
          resolved[catId] = cat.categoryName;
          resolvedImages[catId] = cat.categoryImageUrl;
        }
      }

      if (mounted) setState(() {
        _categories = resolved;
        _categoryImages
          ..clear()
          ..addAll(resolvedImages);
      });
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

  /// Products to display — apply client-side search + price sort on top of loaded products
  List<Product> get _displayedProducts {
    List<Product> list;
    if (_searchQuery.isEmpty) {
      list = List<Product>.from(_products);
    } else {
      final q = _searchQuery.toLowerCase();
      list = _products.where((p) =>
          p.name.toLowerCase().contains(q) ||
          p.description.toLowerCase().contains(q)).toList();
    }

    if (_minPrice != null || _maxPrice != null) {
      list = list.where((p) {
        final price = p.lowestPrice ?? 0.0;
        if (_minPrice != null && price < _minPrice!) return false;
        if (_maxPrice != null && price > _maxPrice!) return false;
        return true;
      }).toList();
    }

    if (_selectedPriceSort == 'Low to High') {
      list.sort((a, b) => (a.lowestPrice ?? 0.0).compareTo(b.lowestPrice ?? 0.0));
    } else if (_selectedPriceSort == 'High to Low') {
      list.sort((a, b) => (b.lowestPrice ?? 0.0).compareTo(a.lowestPrice ?? 0.0));
    }

    return list;
  }

  int get _activeFilterCount {
    int count = 0;
    if (_selectedPriceSort != 'All') count++;
    if (_minPrice != null || _maxPrice != null) count++;
    return count;
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
                      _buildBannerAndStoreHeader(),
                      _buildVoucherSection(),
                      _buildSearchBar(),
                      if (_categories.isNotEmpty) _buildCategoriesSection(),
                      if (kIsWeb) const SizedBox(height: 24),
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

  // ── Banner + Store Header (combined) ────────────────────────────────────

  Widget _buildBannerAndStoreHeader() {
    final coverImageURL = _storeData['coverImageURL'] as String? ?? '';
    final profileImageURL = _storeData['profileImageURL'] as String? ?? '';
    final storeName = _storeData['shopName'] ?? 'Store Name';

    final coverImageURLWithCache = coverImageURL.isNotEmpty
        ? (coverImageURL.contains('?')
            ? '$coverImageURL&v=$_imageVersionToken'
            : '$coverImageURL?v=$_imageVersionToken')
        : '';
    final profileImageURLWithCache = profileImageURL.isNotEmpty
        ? (profileImageURL.contains('?')
            ? '$profileImageURL&v=$_imageVersionToken'
            : '$profileImageURL?v=$_imageVersionToken')
        : '';

    const double iconDiameter = 80.0;
    const double iconRadius = iconDiameter / 2;

    return Column(
      children: [
        // Banner with overlapping store icon
        Stack(
          clipBehavior: Clip.none,
          children: [
            // Banner
            Container(
              margin: const EdgeInsets.only(left: 16, right: 16, top: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: AspectRatio(
                  aspectRatio: 8 / 3,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
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
                      // Back button
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
                      // Share button
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
            ),
            // Store icon overlapping bottom center of banner
            Positioned(
              bottom: -iconRadius,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: iconDiameter,
                  height: iconDiameter,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: profileImageURL.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: profileImageURLWithCache,
                            fit: BoxFit.cover,
                            cacheKey: profileImageURL,
                            placeholder: (context, url) => const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            errorWidget: (context, url, error) =>
                                const Icon(Icons.store, size: 36, color: AppColors.primary),
                          )
                        : const Icon(Icons.store, size: 36, color: AppColors.primary),
                  ),
                ),
              ),
            ),
          ],
        ),
        // Space for the overlapping icon
        const SizedBox(height: iconRadius + 10),
        // Store name
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            storeName,
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.onSurface,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Rating + Location row
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Left: Rating
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star, size: 15, color: Colors.amber),
                    const SizedBox(width: 3),
                    Text(
                      () {
                        final raw = (_storeData['Rating'] as String? ?? '').trim();
                        return raw.isEmpty ? '0.0' : raw;
                      }(),
                      style: AppTextStyles.bodySmall.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            // Vertical divider
            Container(
              height: 30,
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: 14),
              color: AppColors.onSurface.withValues(alpha: 0.18),
            ),
            // Right: Location
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.location_on, size: 13, color: AppColors.primary),
                const SizedBox(width: 3),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    (_storeData['address'] as String? ?? '').isNotEmpty
                        ? _storeData['address'] as String
                        : 'Location unavailable',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.onSurface.withValues(alpha: 0.7),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
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

  // ── Voucher Section ─────────────────────────────────────────────────────

  Widget _buildVoucherSection() {
    final stream = FirebaseFirestore.instance
        .collection('Vouchers')
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
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                child: Text(
                  'Vouchers',
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              SizedBox(
                height: 64,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: vouchers.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => showVoucherTermsSheet(context, vouchers[index]),
                    child: _buildVoucherTicket(vouchers[index]),
                  ),
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
            // Left section — Min. Spend (green)
            Container(
              width: 110,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Min. Spend',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.primary.withValues(alpha: 0.8),
                      fontSize: 10,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    minSpend != null
                        ? CurrencyFormatter.formatWithPeso(minSpend)
                        : 'No min.',
                    style: AppTextStyles.bodySmall.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
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
            // Right section — Code (white)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(Icons.local_offer, size: 14, color: AppColors.primary),
                    const SizedBox(height: 3),
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
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Categories',
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              _buildFilterIconButton(),
            ],
          ),
        ),
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: entries.length + 1, // +1 for "All"
            itemBuilder: (context, index) {
              final isAll = index == 0;
              final catId = isAll ? null : entries[index - 1].key;
              final catName = isAll ? 'All' : entries[index - 1].value;
              final imageUrl = isAll ? null : _categoryImages[catId];
              final isSelected = _selectedCategoryId == catId;

              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: GestureDetector(
                  onTap: () => _onCategorySelected(catId),
                  child: IntrinsicWidth(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 80),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primary : AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.onSurface.withValues(alpha: 0.12),
                            width: 1.5,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: AppColors.primary.withValues(alpha: 0.25),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ]
                              : [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.04),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: imageUrl != null && imageUrl.isNotEmpty
                                      ? Colors.transparent
                                      : isSelected
                                          ? Colors.white.withValues(alpha: 0.2)
                                          : AppColors.primary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: imageUrl != null && imageUrl.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: imageUrl,
                                        fit: BoxFit.cover,
                                        placeholder: (context, url) => Center(
                                          child: Icon(
                                            Icons.category,
                                            color: isSelected
                                                ? Colors.white.withValues(alpha: 0.7)
                                                : AppColors.primary.withValues(alpha: 0.5),
                                            size: 20,
                                          ),
                                        ),
                                        errorWidget: (context, url, error) => Center(
                                          child: Icon(
                                            Icons.category,
                                            color: isSelected
                                                ? Colors.white.withValues(alpha: 0.7)
                                                : AppColors.primary.withValues(alpha: 0.5),
                                            size: 20,
                                          ),
                                        ),
                                      )
                                    : Center(
                                        child: Icon(
                                          isAll ? Icons.grid_view_rounded : Icons.category,
                                          color: isSelected
                                              ? Colors.white.withValues(alpha: 0.9)
                                              : AppColors.primary.withValues(alpha: 0.7),
                                          size: 22,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(
                                catName.length > 17
                                    ? '${catName.substring(0, 17)}...'
                                    : catName,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: isSelected ? AppColors.onPrimary : AppColors.onSurface,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 10,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
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

  // ── Filter Icon + Bottom Sheet ──────────────────────────────────────────

  Widget _buildFilterIconButton() {
    final count = _activeFilterCount;
    final isActive = count > 0;

    return GestureDetector(
      onTap: _showFiltersSheet,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: isActive ? AppColors.primary : AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isActive
                    ? AppColors.primary
                    : AppColors.onSurface.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 16,
                  color: isActive
                      ? AppColors.onPrimary
                      : AppColors.onSurface.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 6),
                Text(
                  'Filter',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: isActive ? AppColors.onPrimary : AppColors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (isActive)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.all(3),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    '$count',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.primary,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showFiltersSheet() {
    String draftSort = _selectedPriceSort;
    final minController = TextEditingController(
      text: _minPrice != null ? _minPrice!.toStringAsFixed(0) : '',
    );
    final maxController = TextEditingController(
      text: _maxPrice != null ? _maxPrice!.toStringAsFixed(0) : '',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            Widget sortOption(String label) {
              final selected = draftSort == label;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setSheetState(() => draftSort = label),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primary.withValues(alpha: 0.08)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? AppColors.primary
                          : AppColors.onSurface.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 20,
                        color: selected
                            ? AppColors.primary
                            : AppColors.onSurface.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        label,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: selected ? AppColors.primary : AppColors.onSurface,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          margin: const EdgeInsets.only(top: 12),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.onSurface.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.tune_rounded,
                                color: AppColors.primary,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Filters',
                                style: AppTextStyles.titleLarge.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.onSurface,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(sheetContext),
                              icon: const Icon(Icons.close),
                              iconSize: 20,
                              color: AppColors.onSurface,
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                        child: Text(
                          'SORT BY PRICE',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.onSurface.withValues(alpha: 0.6),
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          children: [
                            sortOption('All'),
                            const SizedBox(height: 8),
                            sortOption('Low to High'),
                            const SizedBox(height: 8),
                            sortOption('High to Low'),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                        child: Text(
                          'PRICE RANGE',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.onSurface.withValues(alpha: 0.6),
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildPriceField(
                                controller: minController,
                                hint: 'Min',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '—',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.onSurface.withValues(alpha: 0.5),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildPriceField(
                                controller: maxController,
                                hint: 'Max',
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  setSheetState(() {
                                    draftSort = 'All';
                                    minController.clear();
                                    maxController.clear();
                                  });
                                },
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  side: BorderSide(
                                    color: AppColors.onSurface.withValues(alpha: 0.25),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  'Reset',
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: AppColors.onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {
                                  final minVal = double.tryParse(minController.text.trim());
                                  final maxVal = double.tryParse(maxController.text.trim());
                                  setState(() {
                                    _selectedPriceSort = draftSort;
                                    _minPrice = minVal;
                                    _maxPrice = maxVal;
                                  });
                                  Navigator.pop(sheetContext);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: AppColors.onPrimary,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                                child: Text(
                                  'Apply',
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: AppColors.onPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPriceField({
    required TextEditingController controller,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: AppTextStyles.bodyMedium,
      decoration: InputDecoration(
        prefixText: '₱ ',
        prefixStyle: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.onSurface.withValues(alpha: 0.6),
        ),
        hintText: hint,
        hintStyle: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.onSurface.withValues(alpha: 0.4),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: AppColors.onSurface.withValues(alpha: 0.2),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: AppColors.onSurface.withValues(alpha: 0.2),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
      ),
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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
