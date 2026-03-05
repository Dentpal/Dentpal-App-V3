import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dentpal/core/app_theme/index.dart';
import 'package:dentpal/product/models/product_model.dart';
import 'package:dentpal/product/services/product_search_service.dart';
import 'package:dentpal/product/services/category_service.dart';
import 'package:dentpal/product/widgets/product_card.dart';
import 'package:dentpal/product/pages/product_detail_page.dart';
import 'package:dentpal/utils/app_logger.dart';

class ProductSearchPage extends StatefulWidget {
  final String? initialQuery;
  final String? initialCategoryId;

  const ProductSearchPage({
    super.key,
    this.initialQuery,
    this.initialCategoryId,
  });

  @override
  State<ProductSearchPage> createState() => _ProductSearchPageState();
}

class _ProductSearchPageState extends State<ProductSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ProductSearchService _searchService = ProductSearchService();
  final CategoryService _categoryService = CategoryService();
  final ScrollController _scrollController = ScrollController();

  List<Product> _searchResults = [];
  List<Category> _categories = [];
  Map<String, List<SubCategory>> _subcategoriesByCategory = {};
  List<String> _searchSuggestions = [];
  
  SearchFilters _currentFilters = SearchFilters();
  SearchResult? _lastSearchResult;
  Timer? _debounceTimer;
  
  bool _isSearching = false;
  bool _isLoadingMore = false;
  bool _isLoadingCategories = false;
  bool _showFilters = false;
  bool _showSuggestions = false;
  String _searchQuery = '';

  // Price range filter controllers
  final TextEditingController _minPriceController = TextEditingController();
  final TextEditingController _maxPriceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _setupInitialState();
    _loadCategories();
    _setupScrollListener();
  }

  void _setupInitialState() {
    if (widget.initialQuery != null) {
      _searchController.text = widget.initialQuery!;
      _searchQuery = widget.initialQuery!;
    }
    
    if (widget.initialCategoryId != null) {
      _currentFilters = _currentFilters.copyWith(
        categoryIds: [widget.initialCategoryId!],
      );
    }
    
    // Perform initial search if we have a query or category filter
    if (_searchQuery.isNotEmpty || widget.initialCategoryId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _performSearch();
      });
    }
  }

  void _setupScrollListener() {
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= 
          _scrollController.position.maxScrollExtent - 200) {
        _loadMoreResults();
      }
    });
  }

  Future<void> _loadCategories() async {
    setState(() => _isLoadingCategories = true);
    
    try {
      final categories = await _categoryService.getCategories();
      setState(() {
        _categories = categories;
        _isLoadingCategories = false;
      });
    } catch (e) {
      AppLogger.e('Error loading categories', e);
      setState(() => _isLoadingCategories = false);
    }
  }

  Future<void> _loadSubcategories(String categoryId) async {
    // Skip if subcategories already loaded for this category
    if (_subcategoriesByCategory.containsKey(categoryId)) return;
    
    try {
      final subcategories = await _categoryService.getSubCategories(categoryId);
      if (mounted) {
        setState(() {
          _subcategoriesByCategory[categoryId] = subcategories;
        });
      }
    } catch (e) {
      AppLogger.e('Error loading subcategories', e);
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      _showSuggestions = query.isNotEmpty;
    });

    // Cancel previous debounce timer
    _debounceTimer?.cancel();

    // Load suggestions
    if (query.isNotEmpty) {
      _loadSearchSuggestions(query);
    }

    // Set up new debounce timer for search
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        _performSearch();
      }
    });
  }

  Future<void> _loadSearchSuggestions(String query) async {
    try {
      final suggestions = await _searchService.getSearchSuggestions(query);
      if (mounted) {
        setState(() {
          _searchSuggestions = suggestions;
        });
      }
    } catch (e) {
      AppLogger.e('Error loading search suggestions', e);
    }
  }

  Future<void> _performSearch({bool isLoadMore = false}) async {
    if (_isSearching && !isLoadMore) return;

    setState(() {
      if (isLoadMore) {
        _isLoadingMore = true;
      } else {
        _isSearching = true;
        _showSuggestions = false;
      }
    });

    try {
      AppLogger.d('ProductSearchPage: Performing search with query: "$_searchQuery"');
      
      final result = await _searchService.searchProducts(
        searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
        filters: _currentFilters,
        lastDocument: isLoadMore ? _lastSearchResult?.lastDocument : null,
      );

      if (mounted) {
        setState(() {
          if (isLoadMore) {
            _searchResults.addAll(result.products);
            _isLoadingMore = false;
          } else {
            _searchResults = result.products;
            _isSearching = false;
          }
          _lastSearchResult = result;
        });
      }
    } catch (e) {
      AppLogger.e('Error performing search', e);
      if (mounted) {
        setState(() {
          _isSearching = false;
          _isLoadingMore = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Search failed: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _loadMoreResults() async {
    if (_isLoadingMore || _lastSearchResult?.hasMore != true) return;
    await _performSearch(isLoadMore: true);
  }

  void _onFilterChanged() {
    // Parse price filters
    double? minPrice;
    double? maxPrice;
    
    if (_minPriceController.text.isNotEmpty) {
      minPrice = double.tryParse(_minPriceController.text);
    }
    
    if (_maxPriceController.text.isNotEmpty) {
      maxPrice = double.tryParse(_maxPriceController.text);
    }

    _currentFilters = _currentFilters.copyWith(
      minPrice: minPrice,
      maxPrice: maxPrice,
    );

    _performSearch();
  }

  void _clearFilters() {
    setState(() {
      _currentFilters = SearchFilters();
      _minPriceController.clear();
      _maxPriceController.clear();
      _subcategoriesByCategory.clear();
    });
    _performSearch();
  }

  void _onSuggestionTap(String suggestion) {
    _searchController.text = suggestion;
    _searchQuery = suggestion;
    _showSuggestions = false;
    _performSearch();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    _minPriceController.dispose();
    _maxPriceController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _showCategoryFilterSidebar() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    if (!isMobile) return; // sidebar only on mobile

    // Pre-load subcategories for all categories
    for (final category in _categories) {
      _loadSubcategories(category.categoryId);
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Categories',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return _SearchCategorySidebarSheet(
          categories: _categories,
          subcategoriesByCategory: _subcategoriesByCategory,
          selectedCategoryIds: List.from(_currentFilters.categoryIds),
          selectedSubCategoryIds: List.from(_currentFilters.subCategoryIds),
          onLoadSubcategories: _loadSubcategories,
          onApplySelection: (newCategoryIds, newSubCategoryIds) {
            if (!mounted) return;
            setState(() {
              _currentFilters = _currentFilters.copyWith(
                categoryIds: newCategoryIds,
                subCategoryIds: newSubCategoryIds,
              );
              _subcategoriesByCategory.removeWhere(
                (key, _) => !newCategoryIds.contains(key),
              );
            });
            _performSearch();
          },
        );
      },
      transitionBuilder: (ctx, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchHeader(),
            // On mobile: always show price + sort; category uses sidebar
            if (isMobile) _buildMobilePriceSortBar(),
            // On web/tablet: collapsible full filter panel (no category on mobile)
            if (!isMobile && _showFilters) _buildFiltersSection(),
            if (_showSuggestions && _searchSuggestions.isNotEmpty)
              _buildSuggestionsSection(),
            Expanded(
              child: _buildSearchResults(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchHeader() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final hasCategoryFilter = _currentFilters.categoryIds.isNotEmpty ||
        _currentFilters.subCategoryIds.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Container(
                  height: 48,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: AppColors.grey100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search products...',
                      hintStyle: AppTextStyles.inputHint,
                      prefixIcon: const Icon(
                        Icons.search,
                        color: AppColors.grey500,
                        size: 20,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    style: AppTextStyles.inputText,
                  ),
                ),
              ),
              // On mobile: category sidebar icon; on web/tablet: full filter toggle
              if (isMobile)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.menu,
                        color: hasCategoryFilter
                            ? AppColors.primary
                            : AppColors.grey500,
                      ),
                      onPressed: _showCategoryFilterSidebar,
                    ),
                    if (hasCategoryFilter)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                )
              else
                IconButton(
                  icon: Icon(
                    _showFilters ? Icons.filter_list_off : Icons.filter_list,
                    color:
                        _showFilters ? AppColors.primary : AppColors.grey500,
                  ),
                  onPressed: () {
                    setState(() {
                      _showFilters = !_showFilters;
                    });
                  },
                ),
            ],
          ),
          if (_hasActiveFilters()) ...[
            const SizedBox(height: 12),
            _buildActiveFiltersChips(),
          ],
        ],
      ),
    );
  }

  Widget _buildSuggestionsSection() {
    return Container(
      color: AppColors.surface,
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _searchSuggestions.length,
        itemBuilder: (context, index) {
          final suggestion = _searchSuggestions[index];
          return ListTile(
            leading: const Icon(Icons.search, color: AppColors.grey500),
            title: Text(
              suggestion,
              style: AppTextStyles.bodyMedium,
            ),
            onTap: () => _onSuggestionTap(suggestion),
          );
        },
      ),
    );
  }

  Widget _buildMobilePriceSortBar() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Price range title
          Text(
            'Price Range',
            style: AppTextStyles.labelLarge.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          // Price range row
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _minPriceController,
                  decoration: InputDecoration(
                    hintText: 'Min price',
                    hintStyle: AppTextStyles.inputHint,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    prefixText: '₱',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  style: AppTextStyles.bodySmall,
                  onChanged: (_) => _onFilterChanged(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '–',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _maxPriceController,
                  decoration: InputDecoration(
                    hintText: 'Max price',
                    hintStyle: AppTextStyles.inputHint,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    prefixText: '₱',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  style: AppTextStyles.bodySmall,
                  onChanged: (_) => _onFilterChanged(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Sort by title
          Text(
            'Sort By',
            style: AppTextStyles.labelLarge.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          // Sort chips row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildSortChip('Relevance', SortBy.relevance),
                const SizedBox(width: 6),
                _buildSortChip('Price ↑', SortBy.priceAsc),
                const SizedBox(width: 6),
                _buildSortChip('Price ↓', SortBy.priceDesc),
                const SizedBox(width: 6),
                _buildSortChip('A–Z', SortBy.nameAsc),
                const SizedBox(width: 6),
                _buildSortChip('Newest', SortBy.newest),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortChip(String label, SortBy sortBy) {
    final isSelected = _currentFilters.sortBy == sortBy;
    return GestureDetector(
      onTap: () => _changeSortBy(sortBy),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.grey100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.grey300,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: isSelected ? AppColors.onPrimary : AppColors.onSurface,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildFiltersSection() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Filters',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _clearFilters,
                child: Text(
                  'Clear All',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Category Filter
          _buildCategoryFilter(),
          
          const SizedBox(height: 16),
          
          // Price Range Filter
          _buildPriceRangeFilter(),
          
          const SizedBox(height: 16),
          
          // Sort Options
          _buildSortOptions(),
        ],
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Category',
          style: AppTextStyles.labelLarge.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        if (_isLoadingCategories)
          const Center(child: CircularProgressIndicator())
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildFilterChip(
                'All',
                _currentFilters.categoryIds.isEmpty,
                () {
                  setState(() {
                    _currentFilters = _currentFilters.copyWith(
                      categoryIds: [],
                      subCategoryIds: [],
                    );
                    _subcategoriesByCategory.clear();
                  });
                  _performSearch();
                },
              ),
              ..._categories.map((category) {
                final isSelected = _currentFilters.categoryIds.contains(category.categoryId);
                return _buildFilterChip(
                  category.categoryName,
                  isSelected,
                  () {
                    setState(() {
                      List<String> newCategoryIds = List.from(_currentFilters.categoryIds);
                      if (isSelected) {
                        // Remove category
                        newCategoryIds.remove(category.categoryId);
                      } else {
                        // Add category
                        newCategoryIds.add(category.categoryId);
                      }
                      _currentFilters = _currentFilters.copyWith(
                        categoryIds: newCategoryIds,
                        subCategoryIds: [], // Clear subcategories when changing categories
                      );
                      // Don't clear the entire map, just remove subcategories for unselected categories
                      _subcategoriesByCategory.removeWhere((key, value) => !newCategoryIds.contains(key));
                    });
                    
                    // Load subcategories for all selected categories
                    if (_currentFilters.categoryIds.isNotEmpty) {
                      for (String categoryId in _currentFilters.categoryIds) {
                        _loadSubcategories(categoryId);
                      }
                    }
                    
                    _performSearch();
                  },
                );
              }),
            ],
          ),
        
        // Subcategories grouped by category
        if (_subcategoriesByCategory.isNotEmpty) ...[
          const SizedBox(height: 12),
          ..._buildGroupedSubcategories(),
        ],
      ],
    );
  }

  List<Widget> _buildGroupedSubcategories() {
    List<Widget> widgets = [];
    
    // Iterate through selected categories that have subcategories
    for (String categoryId in _currentFilters.categoryIds) {
      if (_subcategoriesByCategory.containsKey(categoryId)) {
        final category = _categories.firstWhere(
          (c) => c.categoryId == categoryId,
          orElse: () => Category(categoryId: '', categoryName: 'Unknown', clickCounter: 0),
        );
        
        final subcategories = _subcategoriesByCategory[categoryId]!;
        
        if (subcategories.isNotEmpty) {
          // Add category header
          widgets.add(
            Text(
              '${category.categoryName} Subcategories',
              style: AppTextStyles.labelMedium.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          );
          
          widgets.add(const SizedBox(height: 8));
          
          // Add subcategory chips for this category
          widgets.add(
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: subcategories.map((subcategory) {
                final isSelected = _currentFilters.subCategoryIds.contains(subcategory.subCategoryId);
                return _buildFilterChip(
                  subcategory.subCategoryName,
                  isSelected,
                  () {
                    setState(() {
                      List<String> newSubCategoryIds = List.from(_currentFilters.subCategoryIds);
                      if (isSelected) {
                        // Remove subcategory
                        newSubCategoryIds.remove(subcategory.subCategoryId);
                      } else {
                        // Add subcategory
                        newSubCategoryIds.add(subcategory.subCategoryId);
                      }
                      _currentFilters = _currentFilters.copyWith(
                        subCategoryIds: newSubCategoryIds,
                      );
                    });
                    _performSearch();
                  },
                );
              }).toList(),
            ),
          );
          
          // Add spacing between category groups
          widgets.add(const SizedBox(height: 16));
        }
      }
    }
    
    return widgets;
  }

  Widget _buildPriceRangeFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Price Range',
          style: AppTextStyles.labelLarge.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width > 600 
                      ? MediaQuery.of(context).size.width * 0.25 
                      : double.infinity,
                ),
                child: TextField(
                  controller: _minPriceController,
                  decoration: InputDecoration(
                    hintText: 'Min price',
                    hintStyle: AppTextStyles.inputHint,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    prefixText: '₱',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _onFilterChanged(),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width > 600 
                      ? MediaQuery.of(context).size.width * 0.25 
                      : double.infinity,
                ),
                child: TextField(
                  controller: _maxPriceController,
                  decoration: InputDecoration(
                    hintText: 'Max price',
                    hintStyle: AppTextStyles.inputHint,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    prefixText: '₱',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _onFilterChanged(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSortOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sort By',
          style: AppTextStyles.labelLarge.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildFilterChip(
              'Relevance',
              _currentFilters.sortBy == SortBy.relevance,
              () => _changeSortBy(SortBy.relevance),
            ),
            _buildFilterChip(
              'Price: Low to High',
              _currentFilters.sortBy == SortBy.priceAsc,
              () => _changeSortBy(SortBy.priceAsc),
            ),
            _buildFilterChip(
              'Price: High to Low',
              _currentFilters.sortBy == SortBy.priceDesc,
              () => _changeSortBy(SortBy.priceDesc),
            ),
            _buildFilterChip(
              'Name A-Z',
              _currentFilters.sortBy == SortBy.nameAsc,
              () => _changeSortBy(SortBy.nameAsc),
            ),
            _buildFilterChip(
              'Newest',
              _currentFilters.sortBy == SortBy.newest,
              () => _changeSortBy(SortBy.newest),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.grey100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.grey300,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: isSelected ? AppColors.onPrimary : AppColors.onSurface,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildActiveFiltersChips() {
    List<Widget> chips = [];

    // Add category chips
    if (_currentFilters.categoryIds.isNotEmpty) {
      for (String categoryId in _currentFilters.categoryIds) {
        final category = _categories.firstWhere(
          (c) => c.categoryId == categoryId,
          orElse: () => Category(categoryId: '', categoryName: 'Unknown', clickCounter: 0),
        );
        chips.add(_buildActiveFilterChip('Category: ${category.categoryName}', () {
          AppLogger.d('Removing category filter: ${category.categoryName}');
          setState(() {
            List<String> newCategoryIds = List.from(_currentFilters.categoryIds);
            newCategoryIds.remove(categoryId);
            _currentFilters = _currentFilters.copyWith(categoryIds: newCategoryIds);
            
            // If removing all categories, also clear subcategories
            if (newCategoryIds.isEmpty) {
              _currentFilters = _currentFilters.copyWith(subCategoryIds: []);
              _subcategoriesByCategory.clear();
            }
          });
          AppLogger.d('Category filter cleared, performing search');
          _performSearch();
        }));
      }
    }

    // Add subcategory chips
    if (_currentFilters.subCategoryIds.isNotEmpty) {
      for (String subCategoryId in _currentFilters.subCategoryIds) {
        // Find the subcategory across all category maps
        SubCategory? foundSubcategory;
        for (var subcategoryList in _subcategoriesByCategory.values) {
          try {
            foundSubcategory = subcategoryList.firstWhere(
              (s) => s.subCategoryId == subCategoryId,
            );
            break;
          } catch (e) {
            // Continue searching in other lists
          }
        }
        
        if (foundSubcategory != null) {
          chips.add(_buildActiveFilterChip('Subcategory: ${foundSubcategory.subCategoryName}', () {
            setState(() {
              List<String> newSubCategoryIds = List.from(_currentFilters.subCategoryIds);
              newSubCategoryIds.remove(subCategoryId);
              _currentFilters = _currentFilters.copyWith(subCategoryIds: newSubCategoryIds);
            });
            _performSearch();
          }));
        }
      }
    }

    if (_currentFilters.minPrice != null || _currentFilters.maxPrice != null) {
      String priceText = 'Price: ';
      if (_currentFilters.minPrice != null && _currentFilters.maxPrice != null) {
        priceText += '₱${_currentFilters.minPrice} - ₱${_currentFilters.maxPrice}';
      } else if (_currentFilters.minPrice != null) {
        priceText += '₱${_currentFilters.minPrice}+';
      } else {
        priceText += 'Up to ₱${_currentFilters.maxPrice}';
      }
      chips.add(_buildActiveFilterChip(priceText, () {
        AppLogger.d('Removing price filter');
        setState(() {
          _currentFilters = _currentFilters.copyWith(
            minPrice: null,
            maxPrice: null,
          );
          _minPriceController.clear();
          _maxPriceController.clear();
        });
        AppLogger.d('Price filter cleared, performing search');
        _performSearch();
      }));
    }

    return SizedBox(
      height: chips.isNotEmpty ? 40 : 0,
      child: chips.isNotEmpty 
          ? ListView(
              scrollDirection: Axis.horizontal,
              children: chips,
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildActiveFilterChip(String label, VoidCallback onRemove) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                AppLogger.d('Removing filter: $label');
                onRemove();
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.close,
                  size: 16,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_isSearching && _searchResults.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_searchResults.isEmpty && !_isSearching) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: () => _performSearch(),
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16, top: 8),
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
                        'Search Results',
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
                        '${_searchResults.length} items',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _getResponsiveCrossAxisCount(context),
                childAspectRatio: _getResponsiveAspectRatio(context),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index >= _searchResults.length) {
                    // Show loading indicator if we're loading more
                    if (_isLoadingMore) {
                      return Container(
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    return null;
                  }
                  
                  final product = _searchResults[index];
                  return ProductCard(
                    product: product,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => ProductDetailPage(productId: product.productId),
                        ),
                      );
                    },
                  );
                },
                childCount: _searchResults.length + (_isLoadingMore ? 1 : 0),
              ),
            ),
          ),
          if (_isLoadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          const SliverToBoxAdapter(
            child: SizedBox(height: 100), // Bottom padding for better UX
          ),
        ],
      ),
    );
  }

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
            child: Icon(
              _searchQuery.isEmpty ? Icons.search : Icons.search_off,
              size: 64,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _searchQuery.isEmpty ? 'Start searching for products' : 'No products found',
            style: AppTextStyles.titleLarge.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              _searchQuery.isEmpty 
                  ? 'Enter a search term or apply filters to find products.\nUse the filter button to browse by category.'
                  : 'Try adjusting your search terms or filters.\nCheck spelling or use different keywords.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          const SizedBox(height: 32),
          if (_searchQuery.isNotEmpty)
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
                  _searchController.clear();
                  _onSearchChanged('');
                },
                icon: const Icon(Icons.clear),
                label: const Text('Clear Search'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _hasActiveFilters() {
    return _currentFilters.categoryIds.isNotEmpty ||
           _currentFilters.subCategoryIds.isNotEmpty ||
           _currentFilters.minPrice != null ||
           _currentFilters.maxPrice != null ||
           _currentFilters.sortBy != SortBy.relevance;
  }

  void _changeSortBy(SortBy sortBy) {
    setState(() {
      _currentFilters = _currentFilters.copyWith(sortBy: sortBy);
    });
    _performSearch();
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
      return 0.80; // Slightly taller cards for large desktop
    } else if (screenWidth >= 900) {
      return 0.75; // Desktop screens (increased height for 2-line product names)
    } else if (screenWidth >= 600) {
      return 0.78; // Tablet screens
    } else {
      return 0.75; // Mobile screens (same as original)
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mobile category sidebar sheet for the search page
// ─────────────────────────────────────────────────────────────────────────────

class _SearchCategorySidebarSheet extends StatefulWidget {
  final List<Category> categories;
  final Map<String, List<SubCategory>> subcategoriesByCategory;
  final List<String> selectedCategoryIds;
  final List<String> selectedSubCategoryIds;
  final Future<void> Function(String categoryId) onLoadSubcategories;
  final void Function(
    List<String> selectedCategoryIds,
    List<String> selectedSubCategoryIds,
  ) onApplySelection;

  const _SearchCategorySidebarSheet({
    required this.categories,
    required this.subcategoriesByCategory,
    required this.selectedCategoryIds,
    required this.selectedSubCategoryIds,
    required this.onLoadSubcategories,
    required this.onApplySelection,
  });

  @override
  State<_SearchCategorySidebarSheet> createState() =>
      _SearchCategorySidebarSheetState();
}

class _SearchCategorySidebarSheetState
    extends State<_SearchCategorySidebarSheet> {
  // null means "All" is highlighted
  Category? _highlightedCategory;
  late Map<String, List<SubCategory>> _localSubcategories;
  bool _loadingSubcategories = false;
  late List<String> _localSelectedCategoryIds;
  late List<String> _localSelectedSubCategoryIds;

  @override
  void initState() {
    super.initState();
    _localSubcategories = Map.from(widget.subcategoriesByCategory);
    _localSelectedCategoryIds = List.from(widget.selectedCategoryIds);
    _localSelectedSubCategoryIds = List.from(widget.selectedSubCategoryIds);

    // Highlight the first selected category, or "All" if none selected
    if (_localSelectedCategoryIds.isNotEmpty) {
      try {
        _highlightedCategory = widget.categories.firstWhere(
          (c) => c.categoryId == _localSelectedCategoryIds.first,
        );
      } catch (_) {
        _highlightedCategory = null;
      }
    }

    if (_highlightedCategory != null) {
      _ensureSubcategoriesLoaded(_highlightedCategory!);
    }
  }

  Future<void> _ensureSubcategoriesLoaded(Category category) async {
    if (_localSubcategories.containsKey(category.categoryId)) return;
    if (mounted) setState(() => _loadingSubcategories = true);
    await widget.onLoadSubcategories(category.categoryId);
    if (mounted) {
      setState(() {
        final updated = widget.subcategoriesByCategory[category.categoryId];
        if (updated != null) {
          _localSubcategories[category.categoryId] = updated;
        }
        _loadingSubcategories = false;
      });
    }
  }

  List<SubCategory> get _currentSubcategories {
    if (_highlightedCategory == null) return [];
    return _localSubcategories[_highlightedCategory!.categoryId] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final sidebarWidth = (screenWidth * 0.88).clamp(0.0, 400.0);

    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: sidebarWidth,
          height: double.infinity,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              bottomLeft: Radius.circular(20),
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // ── Header ──────────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.category_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Shop by Category',
                        style: AppTextStyles.titleMedium.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Body: left rail + right subcategory grid ─────────────
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left rail
                      Container(
                        width: 110,
                        color: const Color(0xFFF5F5F5),
                        child: ListView(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          children: [
                            // "All" option
                            _buildRailItem(
                              label: 'All',
                              imageUrl: null,
                              isHighlighted: _highlightedCategory == null,
                              isSelected: _localSelectedCategoryIds.isEmpty,
                              onTap: () {
                                setState(() => _highlightedCategory = null);
                              },
                            ),
                            ...widget.categories.map((category) {
                              final isHighlighted =
                                  _highlightedCategory?.categoryId ==
                                      category.categoryId;
                              final isSelected = _localSelectedCategoryIds
                                  .contains(category.categoryId);
                              return _buildRailItem(
                                label: category.categoryName,
                                imageUrl: category.categoryImageUrl,
                                isHighlighted: isHighlighted,
                                isSelected: isSelected,
                                onTap: () {
                                  setState(() {
                                    _highlightedCategory = category;
                                    _loadingSubcategories = false;
                                  });
                                  _ensureSubcategoriesLoaded(category);
                                },
                              );
                            }),
                          ],
                        ),
                      ),

                      // Vertical divider
                      Container(width: 1, color: const Color(0xFFE0E0E0)),

                      // Right panel
                      Expanded(
                        child: _highlightedCategory == null
                            ? _buildAllCategoriesGrid()
                            : _buildSubcategoryGrid(),
                      ),
                    ],
                  ),
                ),

                // ── Footer ───────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      top: BorderSide(
                        color: Colors.grey.withValues(alpha: 0.15),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () {
                            setState(() {
                              _localSelectedCategoryIds.clear();
                              _localSelectedSubCategoryIds.clear();
                            });
                          },
                          style: TextButton.styleFrom(
                            backgroundColor:
                                AppColors.primary.withValues(alpha: 0.08),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          child: Text(
                            'Show All',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            widget.onApplySelection(
                              _localSelectedCategoryIds,
                              _localSelectedSubCategoryIds,
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          child: Text(
                            'Apply',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
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
      ),
    );
  }

  Widget _buildRailItem({
    required String label,
    required String? imageUrl,
    required bool isHighlighted,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        color: isHighlighted ? Colors.white : Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: isHighlighted
                    ? AppColors.primary.withValues(alpha: 0.1)
                    : AppColors.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: isHighlighted
                    ? Border.all(color: AppColors.primary, width: 1.5)
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: imageUrl != null && imageUrl.isNotEmpty
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) => Icon(
                          Icons.category,
                          color: AppColors.primary.withValues(alpha: 0.5),
                          size: 22,
                        ),
                      )
                    : Center(
                        child: Icon(
                          label == 'All'
                              ? Icons.grid_view_rounded
                              : Icons.category,
                          color: isHighlighted
                              ? AppColors.primary
                              : AppColors.primary.withValues(alpha: 0.5),
                          size: 24,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                fontSize: 10,
                fontWeight:
                    isHighlighted || isSelected ? FontWeight.bold : FontWeight.w500,
                color:
                    isHighlighted ? AppColors.primary : AppColors.onSurface,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (isSelected)
              Container(
                margin: const EdgeInsets.only(top: 3),
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAllCategoriesGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.95,
      ),
      itemCount: widget.categories.length,
      itemBuilder: (context, index) {
        final category = widget.categories[index];
        final isSelected =
            _localSelectedCategoryIds.contains(category.categoryId);
        final imageUrl = category.categoryImageUrl;

        return GestureDetector(
          onTap: () {
            setState(() {
              if (isSelected) {
                _localSelectedCategoryIds.remove(category.categoryId);
                // Remove subcategories belonging to this category
                if (_localSubcategories.containsKey(category.categoryId)) {
                  final subIds = _localSubcategories[category.categoryId]!
                      .map((s) => s.subCategoryId)
                      .toList();
                  _localSelectedSubCategoryIds
                      .removeWhere((id) => subIds.contains(id));
                }
              } else {
                _localSelectedCategoryIds.add(category.categoryId);
              }
              _highlightedCategory = category;
            });
            _ensureSubcategoriesLoaded(category);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.08)
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? AppColors.primary
                    : Colors.grey.withValues(alpha: 0.2),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: imageUrl != null && imageUrl.isNotEmpty
                        ? Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (c, e, s) => Icon(
                              Icons.category,
                              color: AppColors.primary.withValues(alpha: 0.5),
                              size: 24,
                            ),
                          )
                        : Icon(
                            Icons.category,
                            color: AppColors.primary.withValues(alpha: 0.5),
                            size: 24,
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    category.categoryName,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontSize: 11,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w500,
                      color:
                          isSelected ? AppColors.primary : AppColors.onSurface,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSubcategoryGrid() {
    if (_loadingSubcategories) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.primary,
        ),
      );
    }

    final subs = _currentSubcategories;
    final cat = _highlightedCategory!;
    final isCatSelected =
        _localSelectedCategoryIds.contains(cat.categoryId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category header – tap toggles this category's selection
        GestureDetector(
          onTap: () {
            setState(() {
              if (isCatSelected) {
                _localSelectedCategoryIds.remove(cat.categoryId);
                // Deselect subcategories of this category
                if (_localSubcategories.containsKey(cat.categoryId)) {
                  final subIds = _localSubcategories[cat.categoryId]!
                      .map((s) => s.subCategoryId)
                      .toList();
                  _localSelectedSubCategoryIds
                      .removeWhere((id) => subIds.contains(id));
                }
              } else {
                _localSelectedCategoryIds.add(cat.categoryId);
              }
            });
          },
          child: Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            color: isCatSelected
                ? AppColors.primary.withValues(alpha: 0.08)
                : AppColors.primary.withValues(alpha: 0.05),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    cat.categoryName,
                    style: AppTextStyles.titleSmall.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                if (isCatSelected)
                  const Icon(
                    Icons.check_circle,
                    color: AppColors.primary,
                    size: 16,
                  )
                else
                  Text(
                    'Select all ›',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (subs.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                'No subcategories',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
          )
        else
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(10),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.1,
              ),
              itemCount: subs.length,
              itemBuilder: (context, index) {
                final sub = subs[index];
                final isSelected = _localSelectedSubCategoryIds
                    .contains(sub.subCategoryId);

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _localSelectedSubCategoryIds
                            .remove(sub.subCategoryId);
                      } else {
                        // Auto-select parent category
                        if (!_localSelectedCategoryIds
                            .contains(cat.categoryId)) {
                          _localSelectedCategoryIds.add(cat.categoryId);
                        }
                        _localSelectedSubCategoryIds.add(sub.subCategoryId);
                      }
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.08)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : Colors.grey.withValues(alpha: 0.2),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary.withValues(alpha: 0.12)
                                : AppColors.primary.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.label_outline_rounded,
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.primary.withValues(alpha: 0.5),
                            size: 22,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            sub.subCategoryName,
                            style: AppTextStyles.bodySmall.copyWith(
                              fontSize: 10,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.onSurface,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
