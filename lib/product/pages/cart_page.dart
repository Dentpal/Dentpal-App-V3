import 'package:flutter/material.dart';
import 'package:dentpal/utils/app_logger.dart';
import '../models/cart_model.dart';
import '../services/cart_service.dart';
import '../widgets/seller_group_widget.dart';
import 'checkout_page.dart';
import '../../core/app_theme/app_colors.dart';
import '../../core/app_theme/app_text_styles.dart';
import 'package:flutter/services.dart';

class CartPage extends StatefulWidget {
  const CartPage({super.key, this.onBackPressed});

  // Callback for when back button is pressed
  final VoidCallback? onBackPressed;

  // Static method to mark the cart as needing refresh (only when items are actually added/removed)
  static void markCartAsStale() {
    _CartPageState._wasPopped = true;
    AppLogger.d("🛒 Cart has been marked as stale, will refresh when user returns");
  }

  // Static method to mark cart as stale specifically for item additions
  static void markCartAsStaleForItemAddition() {
    _CartPageState._wasPopped = true;
    AppLogger.d("🛒 Cart marked as stale due to item addition");
  }

  // Static method to optimistically add item to cart
  static Future<void> addItemOptimistically({
    required String productId,
    required int quantity,
    String? variationId,
    required CartService cartService,
  }) async {
    final instance = _CartPageState._instance;
    if (instance != null && instance.mounted) {
      await instance._addItemOptimisticallyInternal(
        productId: productId,
        quantity: quantity,
        variationId: variationId,
        cartService: cartService,
      );
    } else {
      // If no instance or instance is disposed, just add to cart normally and mark as stale
      await cartService.addToCart(
        productId: productId,
        quantity: quantity,
        variationId: variationId,
      );
      markCartAsStale();
    }
  }

  @override
  _CartPageState createState() => _CartPageState();
}

class _CartPageState extends State<CartPage>
    with AutomaticKeepAliveClientMixin<CartPage> {
  // Static instance for singleton pattern
  static _CartPageState? _instance;

  // Flag to indicate the cart needs a refresh
  static bool _wasPopped = false;

  final CartService _cartService = CartService();
  Future<List<SellerGroup>>? _sellerGroupsFuture;
  List<SellerGroup>? _cachedSellerGroups;
  CartSummary? _cartSummary;
  bool _isLoading = false;

  // Track the last cache timestamp to determine if we should refresh
  DateTime? _lastCacheTime;

  // Cache duration - refresh after 5 minutes
  static const Duration _cacheDuration = Duration(minutes: 5);

  // Override to keep this page alive when navigating away
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    // If we already have an instance, use its data
    if (_instance != null) {
      _sellerGroupsFuture = _instance!._sellerGroupsFuture;
      _cachedSellerGroups = _instance!._cachedSellerGroups;
      _cartSummary = _instance!._cartSummary;
      _isLoading = _instance!._isLoading;
      _lastCacheTime = _instance!._lastCacheTime;

      AppLogger.d(
        "🔵 CartPage initState called, cached: ${_cachedSellerGroups != null}, items: ${_cachedSellerGroups?.length ?? 0}",
      );
      
      // Only load if we don't have any cached data
      if (_cachedSellerGroups == null) {
        _sellerGroupsFuture = _loadSellerGroups();
        AppLogger.d("🔵 No cached data, loading from API");
      }
    } else {
      // First time initialization
      _sellerGroupsFuture = _loadSellerGroups();
      AppLogger.d("🔵 CartPage initState called, first time initialization");
    }

    // Store this instance as the static instance
    _instance = this;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Only refresh if we actually need to (not on normal navigation)
    if (_shouldRefreshCart()) {
      AppLogger.d(
        "🔄 Cart needs refresh, refreshing data",
      );
      _refreshCart();
      _wasPopped = false;
    } else {
      AppLogger.d("🔵 Cart page shown via navigation, using cached data");
    }
  }

  // Method to refresh the cart data
  void _refreshCart() {
    AppLogger.d("🔄 Refreshing cart data");
    // Clear cache and reload
    _cachedSellerGroups = null;
    _cartSummary = null;
    _lastCacheTime = null;
    if (_instance != null) {
      _instance!._cachedSellerGroups = null;
      _instance!._cartSummary = null;
      _instance!._lastCacheTime = null;
    }
    // Check if widget is still mounted before calling setState
    if (mounted) {
      setState(() {
        _sellerGroupsFuture = _loadSellerGroups();
      });
    }
  }

  @override
  void dispose() {
    // Clear the static instance reference if this is the current instance
    if (_instance == this) {
      _instance = null;
      AppLogger.d("🔴 CartPage dispose called, cleared static instance reference");
    }
    AppLogger.d("🔴 CartPage dispose called");
    super.dispose();
  }

  Future<List<SellerGroup>> _loadSellerGroups() async {
    // Check if we have valid cached data
    if (_cachedSellerGroups != null && _lastCacheTime != null) {
      final cacheAge = DateTime.now().difference(_lastCacheTime!);
      if (cacheAge < _cacheDuration) {
        AppLogger.d("🟢 Using cached seller groups: ${_cachedSellerGroups!.length} (age: ${cacheAge.inSeconds}s)");
        _updateCartSummary();
        return _cachedSellerGroups!;
      } else {
        AppLogger.d(
          "🟡 Cache expired (${cacheAge.inMinutes} minutes old), refreshing",
        );
      }
    } else if (_cachedSellerGroups != null) {
      // Have cached data but no timestamp - still use it for better UX
      AppLogger.d("🟢 Using cached seller groups: ${_cachedSellerGroups!.length} (no timestamp)");
      _updateCartSummary();
      return _cachedSellerGroups!;
    }

    AppLogger.d("🟡 Loading seller groups from API");
    setState(() {
      _isLoading = true;
    });

    try {
      final sellerGroups = await _cartService.getCartItemsGroupedBySeller();

      // Cache the seller groups with current timestamp
      _cachedSellerGroups = sellerGroups;
      _lastCacheTime = DateTime.now();
      _updateCartSummary();

      setState(() {
        _isLoading = false;
      });
      return sellerGroups;
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      AppLogger.d('❌ Error loading seller groups: $e');
      return [];
    }
  }

  void _updateCartSummary() {
    if (_cachedSellerGroups != null) {
      _cartSummary = CartSummary(sellerGroups: _cachedSellerGroups!);
    }
  }

  // Check if we need to refresh the cart based on actual data changes
  bool _shouldRefreshCart() {
    // Always refresh if no cached data
    if (_cachedSellerGroups == null) return true;
    
    // Check cache age
    if (_lastCacheTime != null) {
      final cacheAge = DateTime.now().difference(_lastCacheTime!);
      if (cacheAge >= _cacheDuration) {
        AppLogger.d("🟡 Cache expired, should refresh");
        return true;
      }
    }
    
    // Only refresh if explicitly marked as stale
    if (_wasPopped) {
      AppLogger.d("🟡 Cart marked as stale, should refresh");
      return true;
    }
    
    return false;
  }

  // Cache-first refresh with change detection
  Future<void> _handleRefresh() async {
    AppLogger.d("🔄 Cart refresh started - cache-first approach");
    
    try {
      // Store current cached data for comparison
      final currentSellerGroups = _cachedSellerGroups;
      
      // Fetch new data from API
      final newSellerGroups = await _cartService.getCartItemsGroupedBySeller();
      
      // Compare with cached data
      if (currentSellerGroups != null && _hasSellerGroupsDataChanged(currentSellerGroups, newSellerGroups)) {
        AppLogger.d("🔄 Cart data has changed, updating UI and cache");
        
        // Update cache and UI
        _cachedSellerGroups = newSellerGroups;
        _lastCacheTime = DateTime.now();
        _updateCartSummary();
        
        if (mounted) {
          setState(() {
            // UI will rebuild with new data
          });
        }
      } else {
        AppLogger.d("✅ Cart data unchanged, keeping existing cache");
      }
      
      // Reset the stale flag since we've refreshed
      _wasPopped = false;
      
    } catch (e) {
      AppLogger.d("❌ Error during cart refresh: $e");
      rethrow;
    }
  }

  // Helper method to compare seller groups data
  bool _hasSellerGroupsDataChanged(List<SellerGroup> oldData, List<SellerGroup> newData) {
    if (oldData.length != newData.length) {
      AppLogger.d("🔍 Seller groups count changed: ${oldData.length} -> ${newData.length}");
      return true;
    }
    
    // Create maps for easier comparison
    final oldMap = <String, SellerGroup>{};
    final newMap = <String, SellerGroup>{};
    
    for (var group in oldData) {
      oldMap[group.sellerId] = group;
    }
    
    for (var group in newData) {
      newMap[group.sellerId] = group;
    }
    
    // Check if seller IDs are the same
    if (oldMap.keys.toSet().difference(newMap.keys.toSet()).isNotEmpty ||
        newMap.keys.toSet().difference(oldMap.keys.toSet()).isNotEmpty) {
      AppLogger.d("🔍 Seller groups composition changed");
      return true;
    }
    
    // Compare each seller group's items
    for (var sellerId in oldMap.keys) {
      final oldGroup = oldMap[sellerId]!;
      final newGroup = newMap[sellerId]!;
      
      if (oldGroup.items.length != newGroup.items.length) {
        AppLogger.d("🔍 Items count changed for seller $sellerId: ${oldGroup.items.length} -> ${newGroup.items.length}");
        return true;
      }
      
      // Create maps for cart items comparison
      final oldItemsMap = <String, CartItem>{};
      final newItemsMap = <String, CartItem>{};
      
      for (var item in oldGroup.items) {
        oldItemsMap[item.cartItemId] = item;
      }
      
      for (var item in newGroup.items) {
        newItemsMap[item.cartItemId] = item;
      }
      
      // Check if cart item IDs are the same
      if (oldItemsMap.keys.toSet().difference(newItemsMap.keys.toSet()).isNotEmpty ||
          newItemsMap.keys.toSet().difference(oldItemsMap.keys.toSet()).isNotEmpty) {
        AppLogger.d("🔍 Cart items composition changed for seller $sellerId");
        return true;
      }
      
      // Compare individual cart items
      for (var cartItemId in oldItemsMap.keys) {
        final oldItem = oldItemsMap[cartItemId]!;
        final newItem = newItemsMap[cartItemId]!;
        
        if (oldItem.quantity != newItem.quantity ||
            oldItem.isSelected != newItem.isSelected ||
            oldItem.productPrice != newItem.productPrice ||
            oldItem.productName != newItem.productName ||
            oldItem.availableStock != newItem.availableStock) {
          AppLogger.d("🔍 Cart item details changed for item $cartItemId");
          return true;
        }
      }
    }
    
    AppLogger.d("✅ No changes detected in seller groups data");
    return false;
  }

  // Instance method to handle optimistic cart additions
  Future<void> _addItemOptimisticallyInternal({
    required String productId,
    required int quantity,
    String? variationId,
    required CartService cartService,
  }) async {
    if (!mounted) {
      AppLogger.d("⚠️ Cart page not mounted, skipping optimistic update");
      await cartService.addToCart(
        productId: productId,
        quantity: quantity,
        variationId: variationId,
      );
      return;
    }

    try {
      // Background sync with server
      await cartService.addToCart(
        productId: productId,
        quantity: quantity,
        variationId: variationId,
      );

      // Refresh the cart after adding
      if (mounted) {
        _refreshCart();
      }
    } catch (e) {
      AppLogger.d("❌ Error adding to cart: $e");
      rethrow;
    }
  }

  void _onUpdateQuantity(CartItem item, int newQuantity) async {
    if (!mounted) return;

    try {
      AppLogger.d(
        "🛒 Updating cart item quantity: ${item.cartItemId} to $newQuantity",
      );

      // Update the server
      await _cartService.updateCartItemQuantity(item.cartItemId, newQuantity);

      // Update local cache
      if (_cachedSellerGroups != null) {
        for (var group in _cachedSellerGroups!) {
          final itemIndex = group.items.indexWhere(
            (cartItem) => cartItem.cartItemId == item.cartItemId,
          );
          if (itemIndex != -1) {
            setState(() {
              group.items[itemIndex].quantity = newQuantity;
              _updateCartSummary();
            });
            break;
          }
        }
      }
    } catch (e) {
      AppLogger.d("❌ Error updating item: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating item: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _onRemoveItem(CartItem item) async {
    if (!mounted) return;

    try {
      AppLogger.d("🗑️ Removing cart item: ${item.cartItemId}");

      // Remove from server
      await _cartService.removeCartItem(item.cartItemId);

      // Update local cache
      if (_cachedSellerGroups != null) {
        setState(() {
          for (var group in _cachedSellerGroups!) {
            group.items.removeWhere(
              (cartItem) => cartItem.cartItemId == item.cartItemId,
            );
          }
          // Remove empty seller groups
          _cachedSellerGroups!.removeWhere((group) => group.items.isEmpty);
          _updateCartSummary();
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Item removed from cart')));
      }
    } catch (e) {
      AppLogger.d("❌ Error removing item: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error removing item: $e')));
      }
    }
  }

  void _onToggleItemSelection(CartItem item, bool isSelected) async {
    if (_cachedSellerGroups != null) {
      // Update local state immediately for responsive UI
      setState(() {
        for (var group in _cachedSellerGroups!) {
          final itemIndex = group.items.indexWhere(
            (cartItem) => cartItem.cartItemId == item.cartItemId,
          );
          if (itemIndex != -1) {
            group.items[itemIndex].isSelected = isSelected;
            group.updateGroupSelection();
            break;
          }
        }
        _updateCartSummary();
      });

      // Save to Firestore in background
      try {
        await _cartService.updateItemSelection(item.cartItemId, isSelected);
        AppLogger.d("✅ Item selection saved to Firestore: ${item.cartItemId} = $isSelected");
      } catch (e) {
        AppLogger.d("❌ Error saving item selection to Firestore: $e");
        // Optionally revert the local state if Firestore update fails
        if (mounted) {
          setState(() {
            for (var group in _cachedSellerGroups!) {
              final itemIndex = group.items.indexWhere(
                (cartItem) => cartItem.cartItemId == item.cartItemId,
              );
              if (itemIndex != -1) {
                group.items[itemIndex].isSelected = !isSelected; // Revert
                group.updateGroupSelection();
                break;
              }
            }
            _updateCartSummary();
          });
        }
      }
    }
  }

  void _onToggleGroupSelection(SellerGroup sellerGroup) async {
    if (_cachedSellerGroups != null) {
      // Store original states in case we need to revert
      final originalStates = sellerGroup.items.map((item) => item.isSelected).toList();
      
      // Update local state immediately for responsive UI
      setState(() {
        sellerGroup.toggleAllItems();
        _updateCartSummary();
      });

      // Save all item selection states to Firestore using batch update
      try {
        Map<String, bool> itemSelections = {};
        for (var item in sellerGroup.items) {
          itemSelections[item.cartItemId] = item.isSelected;
        }
        
        await _cartService.batchUpdateItemSelections(itemSelections);
        AppLogger.d("✅ Group selection saved to Firestore for seller: ${sellerGroup.sellerName}");
      } catch (e) {
        AppLogger.d("❌ Error saving group selection to Firestore: $e");
        // Revert to original states if Firestore update fails
        if (mounted) {
          setState(() {
            for (int i = 0; i < sellerGroup.items.length; i++) {
              sellerGroup.items[i].isSelected = originalStates[i];
            }
            sellerGroup.updateGroupSelection();
            _updateCartSummary();
          });
        }
      }
    }
  }

  Future<bool> _showExitConfirmation() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
    ) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    final screenWidth = MediaQuery.of(context).size.width;
    final isWebView = screenWidth > 1024;

    Widget scaffold = isWebView ? _buildWebScaffold() : _buildScaffold();

    // Only wrap with PopScope if not used within home page navigation
    if (widget.onBackPressed != null) {
      return scaffold;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        
        final shouldExit = await _showExitConfirmation();
        if (shouldExit && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: scaffold,
    );
  }

  Widget _buildScaffold() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // Modern SliverAppBar
          SliverAppBar(
            expandedHeight: 60,
            floating: false,
            pinned: true,
            elevation: 0,
            backgroundColor: AppColors.surface,
            // Hide leading icon when used within home page navigation
            leading: widget.onBackPressed != null ? null : Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
                onPressed: () {
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  } else {
                    // Fallback: try to navigate to the first route
                    Navigator.of(
                      context,
                    ).pushNamedAndRemoveUntil('/', (route) => false);
                  }
                },
                icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
              ),
            ),
            title: Row(
              children: [
                Icon(Icons.shopping_cart, color: AppColors.primary, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Shopping Cart',
                  style: AppTextStyles.titleLarge.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            actions: [
              if (_cartSummary?.hasSelectedItems == true)
                IconButton(
                  onPressed: _showClearCartConfirmation,
                  icon: const Icon(
                    Icons.delete_outline,
                    color: AppColors.error,
                  ),
                  tooltip: 'Clear Cart',
                ),
              const SizedBox(width: 8),
            ],
          ),

          // Cart content
          SliverToBoxAdapter(child: const SizedBox(height: 8)),

          _buildCartContent(),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildWebScaffold() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // Web Header
          Container(
            height: 80,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Back button (only show if not used within home page navigation)
                if (widget.onBackPressed == null)
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.onSurface.withValues(alpha: 0.1)),
                    ),
                    child: IconButton(
                      onPressed: () {
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        } else {
                          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
                        }
                      },
                      icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
                    ),
                  ),
                if (widget.onBackPressed == null) const SizedBox(width: 16),
                
                // Title
                Row(
                  children: [
                    Icon(Icons.shopping_cart, color: AppColors.primary, size: 28),
                    const SizedBox(width: 12),
                    Text(
                      'Shopping Cart',
                      style: AppTextStyles.headlineSmall.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ],
                ),
                
                const Spacer(),
                
                // Cart summary info
                if (_cartSummary?.hasSelectedItems == true) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shopping_bag, color: AppColors.primary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '${_cartSummary!.selectedItemsCount} item${_cartSummary!.selectedItemsCount != 1 ? 's' : ''}',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
                
                // Clear cart button
                if (_cartSummary?.hasSelectedItems == true)
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
                    ),
                    child: IconButton(
                      onPressed: _showClearCartConfirmation,
                      icon: const Icon(Icons.delete_outline, color: AppColors.error),
                      tooltip: 'Clear Cart',
                    ),
                  ),
              ],
            ),
          ),

          // Web Content Area
          Expanded(
            child: _buildWebContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildWebContent() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Main cart content area
        Expanded(
          flex: 2,
          child: Container(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cart items header
                if (_cachedSellerGroups != null && _cachedSellerGroups!.isNotEmpty) ...[
                  Row(
                    children: [
                      Text(
                        'Cart Items',
                        style: AppTextStyles.titleLarge.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_cachedSellerGroups!.fold(0, (total, group) => total + group.items.length)}',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Spacer(),
                      // Select all toggle
                      Row(
                        children: [
                          Text(
                            'Select All',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.onSurface,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Switch.adaptive(
                            value: _cachedSellerGroups?.every((group) => group.allItemsSelected) == true,
                            onChanged: _toggleSelectAllWeb,
                            activeThumbColor: AppColors.primary,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],

                // Cart items list
                Expanded(
                  child: _buildWebCartItems(),
                ),
              ],
            ),
          ),
        ),

        // Sidebar with cart summary and actions
        Container(
          width: 400,
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(
              left: BorderSide(
                color: AppColors.onSurface.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
          ),
          child: _buildWebCartSummary(),
        ),
      ],
    );
  }

  void _toggleSelectAllWeb(bool? value) async {
    if (_cachedSellerGroups == null) return;

    try {
      setState(() {
        for (var group in _cachedSellerGroups!) {
          group.toggleAllItems();
        }
        _updateCartSummary();
      });

      // Save all changes to Firestore
      Map<String, bool> itemSelections = {};
      for (var group in _cachedSellerGroups!) {
        for (var item in group.items) {
          itemSelections[item.cartItemId] = item.isSelected;
        }
      }
      
      await _cartService.batchUpdateItemSelections(itemSelections);
      AppLogger.d("✅ All items selection saved to Firestore");
    } catch (e) {
      AppLogger.d("❌ Error saving all items selection: $e");
      // Optionally show error message to user
    }
  }

  Widget _buildWebCartItems() {
    if (_cachedSellerGroups == null || _cachedSellerGroups!.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shopping_cart_outlined,
              size: 80,
              color: AppColors.onSurface,
            ),
            SizedBox(height: 16),
            Text(
              'Your cart is empty',
              style: AppTextStyles.titleMedium,
            ),
            SizedBox(height: 8),
            Text(
              'Add some products to get started',
              style: AppTextStyles.bodyMedium,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _cachedSellerGroups!.length,
      itemBuilder: (context, index) {
        final sellerGroup = _cachedSellerGroups![index];
        return Container(
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: SellerGroupWidget(
            sellerGroup: sellerGroup,
            onUpdateQuantity: _onUpdateQuantity,
            onRemoveItem: _onRemoveItem,
            onToggleItemSelection: _onToggleItemSelection,
            onToggleGroupSelection: _onToggleGroupSelection,
          ),
        );
      },
    );
  }

  Widget _buildWebCartSummary() {
    return Column(
      children: [
        // Summary header
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.background,
            border: Border(
              bottom: BorderSide(
                color: AppColors.onSurface.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.receipt_long, color: AppColors.primary, size: 24),
              const SizedBox(width: 12),
              Text(
                'Order Summary',
                style: AppTextStyles.titleLarge.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
        ),

        // Summary content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_cartSummary?.hasSelectedItems == true) ...[
                  // Selected items count
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Selected Items',
                        style: AppTextStyles.bodyLarge.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '${_cartSummary!.selectedItemsCount}',
                        style: AppTextStyles.bodyLarge.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Subtotal
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Subtotal', style: AppTextStyles.bodyMedium),
                      Text(
                        '₱${_cartSummary!.selectedItemsTotal.toStringAsFixed(2)}',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Shipping
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Shipping', style: AppTextStyles.bodyMedium),
                      Text(
                        '₱${_cartSummary!.totalShippingCost.toStringAsFixed(2)}',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Divider
                  Divider(
                    color: AppColors.onSurface.withValues(alpha: 0.2),
                    thickness: 1,
                  ),
                  const SizedBox(height: 16),

                  // Total
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total',
                        style: AppTextStyles.titleMedium.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '₱${_cartSummary!.grandTotal.toStringAsFixed(2)}',
                        style: AppTextStyles.titleMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Checkout button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _proceedToCheckout,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onPrimary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.shopping_bag),
                          const SizedBox(width: 8),
                          Text(
                            'Checkout',
                            style: AppTextStyles.buttonLarge.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  // Empty state
                  Column(
                    children: [
                      const SizedBox(height: 40),
                      Icon(
                        Icons.shopping_cart_outlined,
                        size: 64,
                        color: AppColors.onSurface.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No items selected',
                        style: AppTextStyles.bodyLarge.copyWith(
                          color: AppColors.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Select items to see summary',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }  Widget _buildCartContent() {
    // Prioritize cached data for immediate display
    if (_cachedSellerGroups != null) {
      AppLogger.d("🟢 Building cart content from cache (${_cachedSellerGroups!.length} seller groups)");
      if (_cachedSellerGroups!.isEmpty) {
        return _buildEmptyCart();
      }
      return _buildSellerGroupsList(_cachedSellerGroups!);
    }

    // Only use FutureBuilder if no cached data is available
    AppLogger.d("🟡 No cached data, using FutureBuilder");
    return SliverFillRemaining(
      child: FutureBuilder<List<SellerGroup>>(
        future: _sellerGroupsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting ||
              _isLoading) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          } else if (snapshot.hasError) {
            return _buildErrorState(snapshot.error.toString());
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return _buildEmptyCartContent();
          }

          final sellerGroups = snapshot.data!;
          return _buildSellerGroupsListContent(sellerGroups);
        },
      ),
    );
  }

  Widget _buildSellerGroupsList(List<SellerGroup> sellerGroups) {
    return SliverFillRemaining(
      child: RefreshIndicator(
        onRefresh: _handleRefresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final sellerGroup = sellerGroups[index];
                  return SellerGroupWidget(
                    sellerGroup: sellerGroup,
                    onUpdateQuantity: _onUpdateQuantity,
                    onRemoveItem: _onRemoveItem,
                    onToggleItemSelection: _onToggleItemSelection,
                    onToggleGroupSelection: _onToggleGroupSelection,
                  );
                }, childCount: sellerGroups.length),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSellerGroupsListContent(List<SellerGroup> sellerGroups) {
    return RefreshIndicator(
      onRefresh: _handleRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sellerGroups.length,
        itemBuilder: (context, index) {
          final sellerGroup = sellerGroups[index];
          return SellerGroupWidget(
            sellerGroup: sellerGroup,
            onUpdateQuantity: _onUpdateQuantity,
            onRemoveItem: _onRemoveItem,
            onToggleItemSelection: _onToggleItemSelection,
            onToggleGroupSelection: _onToggleGroupSelection,
          );
        },
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    if (_cartSummary != null && _cartSummary!.hasSelectedItems) {
      return _buildCheckoutSection();
    }
    return const SizedBox.shrink();
  }

  Widget _buildEmptyCart() {
    return SliverFillRemaining(
      child: Container(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: .1),
              ),
              child: const Icon(
                Icons.shopping_cart_outlined,
                size: 64,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Your cart is empty',
              style: AppTextStyles.titleLarge.copyWith(
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Add items to your cart to continue shopping',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.onSurface.withValues(alpha: .7),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                  // Use the callback if provided, otherwise try to pop
                  if (widget.onBackPressed != null) {
                    widget.onBackPressed!();
                  } else if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  } else {
                    // Fallback: try to navigate to the first route
                    Navigator.of(
                      context,
                    ).pushNamedAndRemoveUntil('/', (route) => false);
                  }
                },
              icon: const Icon(Icons.shopping_bag),
              label: const Text('Continue Shopping'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.error.withValues(alpha: .1),
            ),
            child: const Icon(
              Icons.error_outline,
              size: 64,
              color: AppColors.error,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Something went wrong',
            style: AppTextStyles.titleLarge.copyWith(
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              error,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.7),
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _refreshCart,
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCartContent() {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: 0.1),
            ),
            child: const Icon(
              Icons.shopping_cart_outlined,
              size: 64,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Your cart is empty',
            style: AppTextStyles.titleLarge.copyWith(
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Add items to your cart to continue shopping',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () {
                  // Use the callback if provided, otherwise try to pop
                  if (widget.onBackPressed != null) {
                    widget.onBackPressed!();
                  } else if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  } else {
                    // Fallback: try to navigate to the first route
                    Navigator.of(
                      context,
                    ).pushNamedAndRemoveUntil('/', (route) => false);
                  }
                },
            icon: const Icon(Icons.shopping_bag),
            label: const Text('Continue Shopping'),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckoutSection() {
    final summary = _cartSummary!;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Order summary header
            Row(
              children: [
                Icon(Icons.receipt_long, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Order Summary',
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${summary.selectedItemsCount} item${summary.selectedItemsCount != 1 ? 's' : ''}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Total breakdown
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.grey50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Subtotal', style: AppTextStyles.bodyMedium),
                      Text(
                        '₱${summary.selectedItemsTotal.toStringAsFixed(2)}',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Roboto', // Use Roboto for peso sign
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text('Shipping', style: AppTextStyles.bodyMedium),
                          if (summary.totalShippingCost == 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'FREE',
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: AppColors.success,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        summary.totalShippingCost == 0
                            ? 'Free'
                            : '₱${summary.totalShippingCost.toStringAsFixed(2)}',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: summary.totalShippingCost == 0
                              ? AppColors.success
                              : AppColors.onSurface,
                          fontFamily: summary.totalShippingCost == 0
                              ? null
                              : 'Roboto', // Use Roboto for peso sign
                        ),
                      ),
                    ],
                  ),

                  if (summary.sellersWithSelectedItems.length > 1) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.info.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: AppColors.info,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Items from ${summary.sellersWithSelectedItems.length} different sellers will ship separately',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.info,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),
                  const Divider(height: 1, color: AppColors.grey300),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total',
                        style: AppTextStyles.titleMedium.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '₱${summary.grandTotal.toStringAsFixed(2)}',
                        style: AppTextStyles.titleLarge.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Roboto', // Use Roboto for peso sign
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Checkout button
            ElevatedButton(
              onPressed: _proceedToCheckout,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.payment),
                  const SizedBox(width: 8),
                  Text('Proceed to Checkout', style: AppTextStyles.buttonLarge),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _proceedToCheckout() {
    if (_cartSummary == null || !_cartSummary!.hasSelectedItems) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select items to checkout'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    // Get selected cart items
    final selectedItems = <CartItem>[];
    if (_cachedSellerGroups != null) {
      for (final group in _cachedSellerGroups!) {
        for (final item in group.items) {
          if (item.isSelected) {
            selectedItems.add(item);
          }
        }
      }
    }

    if (selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No items selected for checkout'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    // Navigate to checkout page
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CheckoutPage(
          cartItems: selectedItems,
          cartSummary: _cartSummary!,
          onOrderComplete: () {
            // Refresh cart after successful order
            _refreshCart();
          },
        ),
      ),
    );
  }

  void _showClearCartConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.warning_outlined,
                color: AppColors.error,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Clear Cart',
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to clear your entire cart? This action cannot be undone.',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.onSurface.withValues(alpha: 0.8),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.onSurface.withValues(alpha: 0.6),
            ),
            child: Text('Cancel', style: AppTextStyles.buttonMedium),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _cartService.clearCart();
                _refreshCart();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cart cleared successfully')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error clearing cart: $e')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.onPrimary,
              elevation: 0,
            ),
            child: Text('Clear', style: AppTextStyles.buttonMedium),
          ),
        ],
      ),
    );
  }
}
