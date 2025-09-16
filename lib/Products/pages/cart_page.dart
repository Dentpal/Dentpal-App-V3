import 'package:flutter/material.dart';
import '../models/cart_model.dart';
import '../services/cart_service.dart';
import '../widgets/seller_group_widget.dart';
import '../../core/app_theme/app_colors.dart';
import '../../core/app_theme/app_text_styles.dart';

class CartPage extends StatefulWidget {
  const CartPage({Key? key, this.onBackPressed}) : super(key: key);

  // Callback for when back button is pressed
  final VoidCallback? onBackPressed;

  // Static method to mark the cart as needing refresh (only when items are actually added/removed)
  static void markCartAsStale() {
    _CartPageState._wasPopped = true;
    print("🛒 Cart has been marked as stale, will refresh when user returns");
  }

  // Static method to mark cart as stale specifically for item additions
  static void markCartAsStaleForItemAddition() {
    _CartPageState._wasPopped = true;
    print("🛒 Cart marked as stale due to item addition");
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

      print(
        "🔵 CartPage initState called, cached: ${_cachedSellerGroups != null}, items: ${_cachedSellerGroups?.length ?? 0}",
      );
      
      // Only load if we don't have any cached data
      if (_cachedSellerGroups == null) {
        _sellerGroupsFuture = _loadSellerGroups();
        print("🔵 No cached data, loading from API");
      }
    } else {
      // First time initialization
      _sellerGroupsFuture = _loadSellerGroups();
      print("🔵 CartPage initState called, first time initialization");
    }

    // Store this instance as the static instance
    _instance = this;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Only refresh if we actually need to (not on normal navigation)
    if (_shouldRefreshCart()) {
      print(
        "🔄 Cart needs refresh, refreshing data",
      );
      _refreshCart();
      _wasPopped = false;
    } else {
      print("🔵 Cart page shown via navigation, using cached data");
    }
  }

  // Method to refresh the cart data
  void _refreshCart() {
    print("🔄 Refreshing cart data");
    // Clear cache and reload
    _cachedSellerGroups = null;
    _cartSummary = null;
    _lastCacheTime = null;
    if (_instance != null) {
      _instance!._cachedSellerGroups = null;
      _instance!._cartSummary = null;
      _instance!._lastCacheTime = null;
    }
    setState(() {
      _sellerGroupsFuture = _loadSellerGroups();
    });
  }

  @override
  void dispose() {
    // Clear the static instance reference if this is the current instance
    if (_instance == this) {
      _instance = null;
      print("🔴 CartPage dispose called, cleared static instance reference");
    }
    print("🔴 CartPage dispose called");
    super.dispose();
  }

  Future<List<SellerGroup>> _loadSellerGroups() async {
    // Check if we have valid cached data
    if (_cachedSellerGroups != null && _lastCacheTime != null) {
      final cacheAge = DateTime.now().difference(_lastCacheTime!);
      if (cacheAge < _cacheDuration) {
        print("🟢 Using cached seller groups: ${_cachedSellerGroups!.length} (age: ${cacheAge.inSeconds}s)");
        _updateCartSummary();
        return _cachedSellerGroups!;
      } else {
        print(
          "🟡 Cache expired (${cacheAge.inMinutes} minutes old), refreshing",
        );
      }
    } else if (_cachedSellerGroups != null) {
      // Have cached data but no timestamp - still use it for better UX
      print("🟢 Using cached seller groups: ${_cachedSellerGroups!.length} (no timestamp)");
      _updateCartSummary();
      return _cachedSellerGroups!;
    }

    print("🟡 Loading seller groups from API");
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
      print('❌ Error loading seller groups: $e');
      return [];
    }
  }

  void _updateCartSummary() {
    if (_cachedSellerGroups != null) {
      _cartSummary = CartSummary(sellerGroups: _cachedSellerGroups!);
    }
  }

  // Helper method to save all current selection states to Firestore
  Future<void> _saveAllSelectionStates() async {
    if (_cachedSellerGroups == null) return;
    
    try {
      Map<String, bool> allSelections = {};
      for (var group in _cachedSellerGroups!) {
        for (var item in group.items) {
          allSelections[item.cartItemId] = item.isSelected;
        }
      }
      
      if (allSelections.isNotEmpty) {
        await _cartService.batchUpdateItemSelections(allSelections);
        print("✅ Saved all selection states to Firestore (${allSelections.length} items)");
      }
    } catch (e) {
      print("❌ Error saving selection states to Firestore: $e");
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
        print("🟡 Cache expired, should refresh");
        return true;
      }
    }
    
    // Only refresh if explicitly marked as stale
    if (_wasPopped) {
      print("🟡 Cart marked as stale, should refresh");
      return true;
    }
    
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
      print("⚠️ Cart page not mounted, skipping optimistic update");
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
      print("❌ Error adding to cart: $e");
      rethrow;
    }
  }

  void _onUpdateQuantity(CartItem item, int newQuantity) async {
    if (!mounted) return;

    try {
      print(
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
      print("❌ Error updating item: $e");
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
      print("🗑️ Removing cart item: ${item.cartItemId}");

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
      print("❌ Error removing item: $e");
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
        print("✅ Item selection saved to Firestore: ${item.cartItemId} = $isSelected");
      } catch (e) {
        print("❌ Error saving item selection to Firestore: $e");
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
        print("✅ Group selection saved to Firestore for seller: ${sellerGroup.sellerName}");
      } catch (e) {
        print("❌ Error saving group selection to Firestore: $e");
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

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // Modern SliverAppBar
          SliverAppBar(
            expandedHeight: 80,
            floating: false,
            pinned: true,
            elevation: 0,
            backgroundColor: AppColors.surface,
            leading: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
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

  Widget _buildCartContent() {
    // Prioritize cached data for immediate display
    if (_cachedSellerGroups != null) {
      print("🟢 Building cart content from cache (${_cachedSellerGroups!.length} seller groups)");
      if (_cachedSellerGroups!.isEmpty) {
        return _buildEmptyCart();
      }
      return _buildSellerGroupsList(_cachedSellerGroups!);
    }

    // Only use FutureBuilder if no cached data is available
    print("🟡 No cached data, using FutureBuilder");
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
    return SliverPadding(
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
    );
  }

  Widget _buildSellerGroupsListContent(List<SellerGroup> sellerGroups) {
    return RefreshIndicator(
      onRefresh: () async {
        print("🔄 Cart pull-to-refresh triggered");
        _refreshCart();
        await _sellerGroupsFuture;
      },
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
                color: AppColors.primary.withOpacity(0.1),
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
                color: AppColors.onSurface.withOpacity(0.7),
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
              color: AppColors.error.withOpacity(0.1),
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
                color: AppColors.onSurface.withOpacity(0.7),
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
              color: AppColors.primary.withOpacity(0.1),
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
              color: AppColors.onSurface.withOpacity(0.7),
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
            color: Colors.black.withOpacity(0.1),
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
                    color: AppColors.onSurface.withOpacity(0.6),
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
                                color: AppColors.success.withOpacity(0.1),
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
                        color: AppColors.info.withOpacity(0.1),
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

    // TODO: Navigate to checkout page with selected items
    print(
      "Proceeding to checkout with ${_cartSummary!.selectedItemsCount} items",
    );
    print("Total: ₱${_cartSummary!.grandTotal.toStringAsFixed(2)}");

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Checkout functionality coming soon! Total: ₱${_cartSummary!.grandTotal.toStringAsFixed(2)}',
        ),
        backgroundColor: AppColors.primary,
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
                color: AppColors.error.withOpacity(0.1),
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
            color: AppColors.onSurface.withOpacity(0.8),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.onSurface.withOpacity(0.6),
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
