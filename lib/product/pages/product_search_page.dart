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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchHeader(),
            if (_showFilters) _buildFiltersSection(),
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
              IconButton(
                icon: Icon(
                  _showFilters ? Icons.filter_list_off : Icons.filter_list,
                  color: _showFilters ? AppColors.primary : AppColors.grey500,
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
