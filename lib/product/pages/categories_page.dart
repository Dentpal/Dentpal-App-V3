import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/app_theme/app_text_styles.dart';
import '../../core/app_theme/ink_palette.dart';
import '../../core/widgets/app_network_image.dart';
import '../../core/widgets/skeleton.dart';
import '../../utils/app_logger.dart';
import '../../utils/currency_formatter.dart';
import '../models/product_model.dart';
import '../models/seller_display.dart';
import '../services/banned_seller_service.dart';
import '../services/category_service.dart';
import '../services/product_service.dart';
import '../services/user_service.dart';
import '../services/product_search_service.dart';
import '../../utils/navigation_utils.dart';
import 'product_detail_page.dart';
import '../../core/widgets/app_shell.dart';

/// What the browse page hands back to whoever pushed it.
///
/// Exactly one of the two is set. The listing page owns the filter state, so
/// this screen decides *what* to browse and lets the listing decide how to
/// show it.
class BrowseSelection {
  const BrowseSelection.category(this.categoryName) : brand = null;
  const BrowseSelection.brand(this.brand) : categoryName = null;

  final String? categoryName;
  final String? brand;
}

/// A category tile: artwork, name and how much is actually in it.
class _CategoryEntry {
  const _CategoryEntry({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.count,
  });

  final String id;
  final String name;
  final String? imageUrl;
  final int count;
}

/// A store tile: whatever the seller profile gives us, plus how much they list.
class _StoreEntry {
  const _StoreEntry({
    required this.sellerId,
    required this.count,
    required this.fallbackName,
    required this.fallbackImageUrl,
  });

  final String sellerId;
  final int count;

  /// Used until (or unless) the seller document loads.
  final String fallbackName;
  final String fallbackImageUrl;
}

class _BrandEntry {
  const _BrandEntry({
    required this.name,
    required this.imageUrl,
    required this.count,
  });

  final String name;
  final String imageUrl;
  final int count;
}

/// A browse selection made from a route the listing page did not push itself
/// — the mobile tab bar opens Browse from [HomePage], which has no handle on
/// the listing page living inside its tab stack. The listing page watches this
/// and applies whatever lands here.
final ValueNotifier<BrowseSelection?> pendingBrowseSelection =
    ValueNotifier<BrowseSelection?>(null);

/// Which slice of the catalogue the page is showing.
enum BrowseFilter { all, categories, brands, stores }

/// Browse: the catalogue's two axes — what a thing is for (category) and who
/// makes it (brand) — plus a search that replaces the taxonomy outright.
///
/// Replaces the slide-in category sheet the listing page used to show. A full
/// page can carry counts and brands, which a 400px drawer could not.
class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key, this.initialFilter = BrowseFilter.all});

  final BrowseFilter initialFilter;

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

/// Widest the browse content grows to; beyond this it centres instead of
/// stretching every tile.
const double _kMaxContentWidth = 1200;

class _CategoriesPageState extends State<CategoriesPage> {
  final CategoryService _categoryService = CategoryService();
  final ProductService _productService = ProductService();
  final UserService _userService = UserService();
  final ProductSearchService _searchService = ProductSearchService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  InkPalette get ink => InkPalette.of(context);

  late BrowseFilter _filter = widget.initialFilter;

  bool _isLoading = true;
  List<_CategoryEntry> _categories = [];
  List<_BrandEntry> _brands = [];
  List<_StoreEntry> _stores = [];

  /// Stores arrive in pages: each one costs a `Seller` document read, so only
  /// what is on screen is fetched.
  static const int _storePageSize = 6;
  int _visibleStores = _storePageSize;
  final Map<String, Map<String, dynamic>?> _sellerData = {};
  final Set<String> _sellerFetches = {};

  String _query = '';
  Timer? _debounce;
  bool _isSearching = false;
  List<Product> _results = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Hands a pick to whoever is showing the results.
  ///
  /// This page lives in two places. As one of the shell's tabs it cannot pop —
  /// there is no route of its own to pop — so it asks the shell to switch to
  /// Home and apply the filter. As a pushed route (the listing page opens it
  /// with a preset filter) it pops the selection back to its caller as before.
  ///
  /// A pushed route is a sibling of the shell under the same Navigator, not a
  /// descendant of it, so [AppShell.of] returning null is exactly the "I was
  /// pushed" signal — no flag has to be threaded through the constructor.
  void _select(BrowseSelection selection) {
    final shell = AppShell.of(context);
    if (shell != null) {
      shell.applyBrowseSelection(selection);
      return;
    }
    Navigator.of(context).pop(selection);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// One pass over the active catalogue gives both taxonomies and their
  /// counts; the category documents supply names and artwork.
  Future<void> _load() async {
    try {
      // Shares the cached catalogue read with the listing page rather than
      // running its own unbounded `.get()` on every visit to this tab.
      final productsFuture = _productService.getActiveCatalogue();
      final categoriesFuture = _categoryService.getCategories();

      final productDocs = await productsFuture;
      final allCategories = await categoriesFuture;

      final categoryCounts = <String, int>{};
      final brandCounts = <String, int>{};
      final brandDisplay = <String, String>{};
      final brandImages = <String, String>{};
      final storeCounts = <String, int>{};
      final storeFallbackName = <String, String>{};
      final storeFallbackImage = <String, String>{};

      for (final doc in productDocs) {
        final data = doc.data();
        if (data['isDraft'] == true || data['isArchived'] == true) continue;
        final sellerId = (data['sellerId'] as String?) ?? '';
        if (sellerId.isEmpty) continue;
        if (BannedSellerService.instance.isBanned(sellerId)) continue;

        storeCounts[sellerId] = (storeCounts[sellerId] ?? 0) + 1;
        storeFallbackName[sellerId] ??=
            ((data['brand'] as String?)?.trim().isNotEmpty == true
            ? (data['brand'] as String).trim()
            : 'Dental Trader');
        if ((storeFallbackImage[sellerId] ?? '').isEmpty) {
          storeFallbackImage[sellerId] = (data['imageURL'] as String?) ?? '';
        }

        final categoryId = (data['categoryID'] as String?) ?? '';
        if (categoryId.isNotEmpty) {
          categoryCounts[categoryId] = (categoryCounts[categoryId] ?? 0) + 1;
        }

        final rawBrand = (data['brand'] as String?)?.trim() ?? '';
        if (rawBrand.isNotEmpty) {
          final key = rawBrand.toLowerCase();
          brandCounts[key] = (brandCounts[key] ?? 0) + 1;
          brandDisplay[key] ??= rawBrand;
          if ((brandImages[key] ?? '').isEmpty) {
            brandImages[key] =
                (data['brandImage'] as String?) ??
                (data['brandimage'] as String?) ??
                '';
          }
        }
      }

      // Empty categories would just be dead ends.
      final categories = <_CategoryEntry>[
        for (final category in allCategories)
          if ((categoryCounts[category.categoryId] ?? 0) > 0)
            _CategoryEntry(
              id: category.categoryId,
              name: category.categoryName,
              imageUrl: category.categoryImageUrl,
              count: categoryCounts[category.categoryId]!,
            ),
      ]..sort((a, b) => b.count.compareTo(a.count));

      final brands =
          <_BrandEntry>[
            for (final entry in brandCounts.entries)
              _BrandEntry(
                name: brandDisplay[entry.key]!,
                imageUrl: brandImages[entry.key] ?? '',
                count: entry.value,
              ),
          ]..sort((a, b) {
            final byCount = b.count.compareTo(a.count);
            return byCount != 0
                ? byCount
                : a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });

      // Busiest storefronts first — the page shows only five at a time.
      final stores = <_StoreEntry>[
        for (final entry in storeCounts.entries)
          _StoreEntry(
            sellerId: entry.key,
            count: entry.value,
            fallbackName: storeFallbackName[entry.key] ?? 'Dental Trader',
            fallbackImageUrl: storeFallbackImage[entry.key] ?? '',
          ),
      ]..sort((a, b) => b.count.compareTo(a.count));

      if (!mounted) return;
      setState(() {
        _categories = categories;
        _brands = brands;
        _stores = stores;
        _isLoading = false;
      });
      _fetchSellersForVisibleStores();
    } catch (e) {
      AppLogger.d('Error loading browse page: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Loads `Seller` documents for the stores currently revealed. Called on
  /// first paint and again each time the list is extended, so a buyer who
  /// never opens the Stores tab never pays for these reads.
  Future<void> _fetchSellersForVisibleStores() async {
    final pending = _stores
        .take(_visibleStores)
        .map((store) => store.sellerId)
        .where(
          (id) => !_sellerData.containsKey(id) && !_sellerFetches.contains(id),
        )
        .toList();
    if (pending.isEmpty) return;

    _sellerFetches.addAll(pending);
    await Future.wait(
      pending.map((id) async {
        try {
          _sellerData[id] = await _userService.getSellerData(id);
        } catch (e) {
          AppLogger.d('Error loading seller $id: $e');
          _sellerData[id] = null;
        } finally {
          _sellerFetches.remove(id);
        }
      }),
    );
    if (mounted) setState(() {});
  }

  void _showMoreStores() {
    setState(() {
      _visibleStores = math.min(
        _visibleStores + _storePageSize,
        _stores.length,
      );
    });
    _fetchSellersForVisibleStores();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    setState(() => _query = value);
    if (value.trim().isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
      });
      return;
    }
    setState(() => _isSearching = true);
    _debounce = Timer(const Duration(milliseconds: 400), _runSearch);
  }

  Future<void> _runSearch() async {
    final query = _query.trim();
    if (query.isEmpty) return;
    final result = await _searchService.searchProducts(
      searchQuery: query,
      filters: SearchFilters(),
    );
    if (!mounted || query != _query.trim()) return;
    setState(() {
      _results = result.products;
      _isSearching = false;
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() {
      _query = '';
      _results = [];
      _isSearching = false;
    });
    _searchFocusNode.unfocus();
  }

  /// Category artwork is portrait 3:4, so the tiles stay narrow and numerous
  /// rather than growing into billboards.
  int _categoryColumns(double contentWidth) {
    if (contentWidth >= 1000) return 5;
    if (contentWidth >= 700) return 4;
    return 3;
  }

  /// Brand cards are horizontal rows — a logo beside two lines of text — so
  /// they want few, wide columns.
  int _brandColumns(double contentWidth) {
    if (contentWidth >= 1000) return 3;
    if (contentWidth >= 640) return 2;
    return 1;
  }

  /// Height reserved for the name + count block under a category tile. Sized
  /// with a few pixels of slack: the artwork below takes a fixed ratio, so a
  /// label that outgrew its allowance would overflow the cell rather than
  /// shrink it.
  static const double _categoryLabelHeight = 64;

  /// Category artwork's own ratio, matched exactly so the image is never
  /// cropped or stretched — the same 1086x1448 source the listing page uses.
  static const double _categoryArtRatio = 1086 / 1448;

  /// Brand cards read as list rows, so they get a fixed comfortable height at
  /// every breakpoint instead of a ratio that stretches with the column width.
  static const double _brandCardHeight = 96;

  /// Store cards pair 8:3 cover art with a name/location/categories block.
  static const double _storeCoverRatio = 8 / 3;

  /// Height that block needs, with slack — the cover below takes a fixed
  /// ratio, so an overlong label would overflow the cell rather than shrink it.
  static const double _storeLabelHeight = 104;

  /// Two abreast once there is room; a single wide card per row looks stranded
  /// on a large screen.
  int _storeColumns(double contentWidth) => contentWidth >= 760 ? 2 : 1;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final horizontalPadding = width >= 900 ? 32.0 : 16.0;
    final searching = _query.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: ink.bg,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(horizontalPadding),
                Expanded(
                  child: searching
                      ? _buildResults(horizontalPadding)
                      : _buildTaxonomy(horizontalPadding, width),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(double horizontalPadding) {
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 12, horizontalPadding, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // A pushed route needs its own way back. As a shell tab there is
              // no route to pop, so the arrow would be a dead control — the
              // rail and the bottom bar are the way out of this tab.
              if (Navigator.of(context).canPop()) ...[
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icon(Icons.arrow_back, color: ink.text),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                'Browse',
                style: AppTextStyles.titleLarge.copyWith(
                  color: ink.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 30,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildSearchField(),
          const SizedBox(height: 14),
          _buildFilterPills(),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ink.border),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 20, color: ink.text.withValues(alpha: 0.5)),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: _onQueryChanged,
              textInputAction: TextInputAction.search,
              style: AppTextStyles.bodyMedium.copyWith(color: ink.text),
              cursorColor: ink.emerald,
              // The global inputDecorationTheme fills and outlines fields; this
              // one draws its own shell, so all of that is switched off.
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                fillColor: Colors.transparent,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: 'Search products, brands…',
                hintStyle: AppTextStyles.bodyMedium.copyWith(
                  color: ink.text.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
          if (_query.isNotEmpty)
            GestureDetector(
              onTap: _clearSearch,
              child: Icon(
                Icons.close,
                size: 18,
                color: ink.text.withValues(alpha: 0.5),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterPills() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in BrowseFilter.values) ...[
            _buildPill(filter),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildPill(BrowseFilter filter) {
    const labels = {
      BrowseFilter.all: 'All',
      BrowseFilter.categories: 'Categories',
      BrowseFilter.brands: 'Brands',
      BrowseFilter.stores: 'Stores',
    };
    final isActive = _filter == filter;

    return GestureDetector(
      onTap: () => setState(() => _filter = filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: isActive ? ink.emerald : ink.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: isActive ? ink.emerald : ink.border),
        ),
        child: Text(
          labels[filter]!,
          style: AppTextStyles.bodyMedium.copyWith(
            color: isActive ? ink.onEmerald : ink.text.withValues(alpha: 0.8),
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13.5,
          ),
        ),
      ),
    );
  }

  // ── Taxonomy ─────────────────────────────────────────────────────────────

  Widget _buildTaxonomy(double horizontalPadding, double width) {
    if (_isLoading) {
      return _buildTaxonomySkeleton(horizontalPadding, width);
    }

    final showCategories =
        _filter == BrowseFilter.all || _filter == BrowseFilter.categories;
    final showBrands =
        _filter == BrowseFilter.all || _filter == BrowseFilter.brands;
    final showStores =
        _filter == BrowseFilter.all || _filter == BrowseFilter.stores;

    // Grids are sized from the width they actually get, so the tile ratio can
    // be derived rather than guessed.
    final contentWidth =
        math.min(width, _kMaxContentWidth) - horizontalPadding * 2;
    final categoryColumns = _categoryColumns(contentWidth);
    final brandColumns = _brandColumns(contentWidth);
    final categoryCellWidth =
        (contentWidth - 12 * (categoryColumns - 1)) / categoryColumns;
    final brandCellWidth =
        (contentWidth - 12 * (brandColumns - 1)) / brandColumns;
    final storeColumns = _storeColumns(contentWidth);
    final storeCellWidth =
        (contentWidth - 12 * (storeColumns - 1)) / storeColumns;

    if (_categories.isEmpty && _brands.isEmpty && _stores.isEmpty) {
      return _buildEmpty(
        icon: Icons.category_outlined,
        title: 'Nothing to browse yet',
        detail: 'Categories appear here once products are listed.',
      );
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        16,
        horizontalPadding,
        32,
      ),
      children: [
        if (showCategories && _categories.isNotEmpty) ...[
          // The heading only earns its place when both groups are shown.
          if (_filter == BrowseFilter.all) _buildGroupHeading('Categories'),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: _categories.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: categoryColumns,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              // Artwork at its native ratio, plus room for the label.
              childAspectRatio:
                  categoryCellWidth /
                  (categoryCellWidth / _categoryArtRatio +
                      _categoryLabelHeight),
            ),
            itemBuilder: (context, index) =>
                _buildCategoryCard(_categories[index]),
          ),
        ],
        if (showCategories && showBrands && _categories.isNotEmpty)
          const SizedBox(height: 28),
        if (showBrands && _brands.isNotEmpty) ...[
          if (_filter == BrowseFilter.all) _buildGroupHeading('Brands'),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: _brands.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: brandColumns,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: brandCellWidth / _brandCardHeight,
            ),
            itemBuilder: (context, index) => _buildBrandCard(_brands[index]),
          ),
        ],
        if (showStores && showBrands && _brands.isNotEmpty)
          const SizedBox(height: 28),
        if (showStores && _stores.isNotEmpty) ...[
          if (_filter == BrowseFilter.all) _buildGroupHeading('Stores'),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: math.min(_visibleStores, _stores.length),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: storeColumns,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio:
                  storeCellWidth /
                  (storeCellWidth / _storeCoverRatio + _storeLabelHeight),
            ),
            itemBuilder: (context, index) => _buildStoreCard(_stores[index]),
          ),
          if (_visibleStores < _stores.length)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Center(
                child: TextButton.icon(
                  onPressed: _showMoreStores,
                  icon: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: ink.emerald,
                  ),
                  label: Text(
                    'Show more stores',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: ink.emerald,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  /// Placeholder for the browse taxonomy.
  ///
  /// Deliberately built from the same column counts and tile ratios as
  /// [_buildTaxonomy], so the real categories, brands and stores land exactly
  /// where their placeholders were instead of the page reflowing under the
  /// reader. A centred spinner told you to wait; this tells you what is coming.
  Widget _buildTaxonomySkeleton(double horizontalPadding, double width) {
    final showCategories =
        _filter == BrowseFilter.all || _filter == BrowseFilter.categories;
    final showBrands =
        _filter == BrowseFilter.all || _filter == BrowseFilter.brands;
    final showStores =
        _filter == BrowseFilter.all || _filter == BrowseFilter.stores;

    final contentWidth =
        math.min(width, _kMaxContentWidth) - horizontalPadding * 2;

    final categoryColumns = _categoryColumns(contentWidth);
    final categoryCellWidth =
        (contentWidth - 12 * (categoryColumns - 1)) / categoryColumns;
    final brandColumns = _brandColumns(contentWidth);
    final brandCellWidth =
        (contentWidth - 12 * (brandColumns - 1)) / brandColumns;
    final storeColumns = _storeColumns(contentWidth);
    final storeCellWidth =
        (contentWidth - 12 * (storeColumns - 1)) / storeColumns;

    return SkeletonShimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          16,
          horizontalPadding,
          32,
        ),
        children: [
          if (showCategories) ...[
            if (_filter == BrowseFilter.all) _buildHeadingSkeleton(),
            _buildGridSkeleton(
              columns: categoryColumns,
              // Two rows is enough to read as "a grid" without filling the
              // screen with placeholders.
              count: categoryColumns * 2,
              aspectRatio:
                  categoryCellWidth /
                  (categoryCellWidth / _categoryArtRatio +
                      _categoryLabelHeight),
              radius: 16,
            ),
          ],
          if (showCategories && showBrands) const SizedBox(height: 28),
          if (showBrands) ...[
            if (_filter == BrowseFilter.all) _buildHeadingSkeleton(),
            _buildGridSkeleton(
              columns: brandColumns,
              count: brandColumns * 2,
              aspectRatio: brandCellWidth / _brandCardHeight,
              radius: 14,
            ),
          ],
          if (showStores && showBrands) const SizedBox(height: 28),
          if (showStores) ...[
            if (_filter == BrowseFilter.all) _buildHeadingSkeleton(),
            _buildGridSkeleton(
              columns: storeColumns,
              count: storeColumns * 2,
              aspectRatio:
                  storeCellWidth /
                  (storeCellWidth / _storeCoverRatio + _storeLabelHeight),
              radius: 16,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeadingSkeleton() => const Padding(
    padding: EdgeInsets.only(bottom: 12),
    child: SkeletonLine(width: 120, height: 17),
  );

  Widget _buildGridSkeleton({
    required int columns,
    required int count,
    required double aspectRatio,
    required double radius,
  }) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: count,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: aspectRatio,
      ),
      itemBuilder: (context, index) => SkeletonBox(radius: radius),
    );
  }

  /// Placeholder rows for a search still in flight, shaped like
  /// [_buildResultRow]: thumbnail, brand line, name line, price.
  Widget _buildResultsSkeleton(double horizontalPadding) {
    return SkeletonShimmer(
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          12,
          horizontalPadding,
          32,
        ),
        itemCount: 6,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) => Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: ink.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ink.border),
          ),
          child: const Row(
            children: [
              SkeletonBox(width: 50, height: 50, radius: 10),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SkeletonLine(width: 54, height: 9),
                    SizedBox(height: 7),
                    SkeletonLine(widthFactor: 0.75, height: 12),
                    SizedBox(height: 8),
                    SkeletonLine(width: 78, height: 13),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A storefront, in the same shape the listing page uses: cover art, name,
  /// where it ships from, and what it carries.
  Widget _buildStoreCard(_StoreEntry store) {
    final raw = _sellerData[store.sellerId];
    final loading =
        !_sellerData.containsKey(store.sellerId) &&
        _sellerFetches.contains(store.sellerId);
    final display = SellerDisplay.fromSellerData(
      raw,
      fallbackName: store.fallbackName,
      fallbackCategories: 'Dental Products',
      fallbackImageUrl: store.fallbackImageUrl,
    );

    return GestureDetector(
      onTap: () => NavigationUtils.navigateToStore(
        context,
        store.sellerId,
        sellerData: raw,
      ),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: ink.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ink.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 8 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (display.coverImageUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: display.coverImageUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: 1080,
                      placeholder: (context, url) =>
                          Container(color: ink.surfaceHigh),
                      errorWidget: (context, url, error) => Container(
                        color: ink.surfaceHigh,
                        child: Icon(
                          Icons.store_rounded,
                          color: ink.emerald,
                          size: 32,
                        ),
                      ),
                    )
                  else
                    Container(
                      color: ink.surfaceHigh,
                      child: Icon(
                        Icons.store_rounded,
                        color: ink.emerald,
                        size: 32,
                      ),
                    ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${store.count} ${store.count == 1 ? 'item' : 'items'}',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loading ? 'Loading store…' : display.storeName,
                    style: AppTextStyles.titleMedium.copyWith(
                      color: ink.text,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 14,
                        color: ink.text.withValues(alpha: 0.55),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          display.province,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: ink.text.withValues(alpha: 0.6),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    display.categories,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: ink.text.withValues(alpha: 0.5),
                      fontSize: 11.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupHeading(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: AppTextStyles.titleMedium.copyWith(
          color: ink.text,
          fontWeight: FontWeight.w800,
          fontSize: 18,
        ),
      ),
    );
  }

  /// Category artwork carries its own name, so the card shows the graphic
  /// full-bleed — as the listing page does — with the count laid over it.
  Widget _buildCategoryCard(_CategoryEntry category) {
    return GestureDetector(
      onTap: () => _select(BrowseSelection.category(category.name)),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: ink.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ink.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: _categoryArtRatio,
              child: (category.imageUrl ?? '').isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: category.imageUrl!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      memCacheWidth: 480,
                      placeholder: (context, url) =>
                          Container(color: ink.surfaceHigh),
                      errorWidget: (context, url, error) => Container(
                        color: ink.surfaceHigh,
                        child: Icon(Icons.category, color: ink.emerald),
                      ),
                    )
                  : Container(
                      color: ink.surfaceHigh,
                      child: Center(
                        child: Icon(
                          Icons.category,
                          color: ink.emerald,
                          size: 28,
                        ),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    category.name,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: ink.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${category.count} ${category.count == 1 ? 'product' : 'products'}',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: ink.text.withValues(alpha: 0.5),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrandCard(_BrandEntry brand) {
    return GestureDetector(
      onTap: () => _select(BrowseSelection.brand(brand.name)),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ink.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ink.border),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(gradient: ink.productBackdrop),
                child: brand.imageUrl.isNotEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(6),
                        child: AppNetworkImage(
                          url: brand.imageUrl,
                          width: 64,
                          height: 64,
                          fit: BoxFit.contain,
                          backgroundColor: Colors.transparent,
                        ),
                      )
                    : Icon(
                        Icons.verified_rounded,
                        color: ink.emerald,
                        size: 28,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    brand.name,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: ink.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${brand.count} ${brand.count == 1 ? 'product' : 'products'}',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: ink.text.withValues(alpha: 0.55),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Search ───────────────────────────────────────────────────────────────

  /// Results replace the taxonomy outright: someone hunting one SKU should
  /// never have to scroll past the whole catalogue to reach it.
  Widget _buildResults(double horizontalPadding) {
    if (_isSearching) {
      return _buildResultsSkeleton(horizontalPadding);
    }

    if (_results.isEmpty) {
      return _buildEmpty(
        icon: Icons.search_off,
        title: 'Nothing matched',
        detail: 'Try a brand name, or a shorter search term.',
      );
    }

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        12,
        horizontalPadding,
        32,
      ),
      itemCount: _results.length + 1,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              '${_results.length} ${_results.length == 1 ? 'result' : 'results'} for "${_query.trim()}"',
              style: AppTextStyles.bodySmall.copyWith(
                color: ink.text.withValues(alpha: 0.6),
              ),
            ),
          );
        }
        return _buildResultRow(_results[index - 1]);
      },
    );
  }

  Widget _buildResultRow(Product product) {
    final variation = product.variations?.isNotEmpty == true
        ? product.variations!.first
        : null;
    final imageUrl =
        variation?.thumbnailURL ??
        product.thumbnailURL ??
        variation?.imageURL ??
        product.imageURL;
    final price = product.lowestPrice;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ProductDetailPage(productId: product.productId),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: ink.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ink.border),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(gradient: ink.productBackdrop),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: AppNetworkImage(
                    url: imageUrl,
                    width: 50,
                    height: 50,
                    fit: BoxFit.contain,
                    backgroundColor: Colors.transparent,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if ((product.brand ?? '').isNotEmpty)
                    Text(
                      product.brand!.toUpperCase(),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: ink.text.withValues(alpha: 0.45),
                        fontWeight: FontWeight.w700,
                        fontSize: 9.5,
                        letterSpacing: 0.7,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  Text(
                    product.name,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: ink.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (price != null)
              Text(
                CurrencyFormatter.formatWithPeso(price),
                style: AppTextStyles.bodyMedium.copyWith(
                  color: ink.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty({
    required IconData icon,
    required String title,
    required String detail,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: ink.text.withValues(alpha: 0.3)),
            const SizedBox(height: 14),
            Text(
              title,
              style: AppTextStyles.titleMedium.copyWith(
                color: ink.text,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: ink.text.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
