import 'package:flutter/material.dart';
import 'package:dentpal/utils/app_logger.dart';
import 'package:dentpal/utils/navigation_utils.dart';
import 'package:dentpal/core/services/sub_account_service.dart';
import '../models/cart_model.dart';
import '../services/cart_service.dart';
import '../widgets/seller_group_widget.dart';
import '../widgets/voucher_picker_sheet.dart';
import '../widgets/loading_skeletons.dart';
import 'checkout_page.dart';
import '../../core/app_theme/app_text_styles.dart';
import '../../core/app_theme/ink_palette.dart';
import '../../core/app_theme/theme_utils.dart';
import '../../core/widgets/app_shell.dart';
import 'package:dentpal/utils/currency_formatter.dart';

class CartPage extends StatefulWidget {
  const CartPage({super.key, this.onBackPressed});

  // Callback for when back button is pressed
  final VoidCallback? onBackPressed;

  // Static method to mark the cart as needing refresh (only when items are actually added/removed)
  static void markCartAsStale() {
    _CartPageState._wasPopped = true;
    AppLogger.d(" Cart has been marked as stale, will refresh when user returns");
  }

  // Static method to mark cart as stale specifically for item additions
  static void markCartAsStaleForItemAddition() {
    _CartPageState._wasPopped = true;
    AppLogger.d(" Cart marked as stale due to item addition");
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
  final Map<String, Map<String, dynamic>?> _selectedDiscountVouchers = {};
  final Map<String, Map<String, dynamic>?> _selectedShippingVouchers = {};

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

    // This used to copy cached groups off the previous [_instance], because
    // switching tabs destroyed and recreated the page. That never actually
    // worked — dispose() nulls _instance before the next initState runs, so the
    // copy always found null and the cart refetched on every single visit.
    // As a tab of AppShell the state now survives, so this runs once.
    _sellerGroupsFuture = _loadSellerGroups();
    AppLogger.d('CartPage initState: loading seller groups');

    // Still published so other pages can add to this live cart optimistically.
    _instance = this;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Only refresh if we actually need to (not on normal navigation)
    if (_shouldRefreshCart()) {
      AppLogger.d(
        "Cart needs refresh, refreshing data",
      );
      _refreshCart();
      _wasPopped = false;
    } else {
      AppLogger.d("Cart page shown via navigation, using cached data");
    }
  }

  // Method to refresh the cart data
  void _refreshCart() {
    AppLogger.d("Refreshing cart data");
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
      AppLogger.d("CartPage dispose called, cleared static instance reference");
    }
    AppLogger.d("CartPage dispose called");
    super.dispose();
  }

  Future<List<SellerGroup>> _loadSellerGroups() async {
    final stopwatch = Stopwatch()..start();
    
    // Check if we have valid cached data
    if (_cachedSellerGroups != null && _lastCacheTime != null) {
      final cacheAge = DateTime.now().difference(_lastCacheTime!);
      if (cacheAge < _cacheDuration) {
        AppLogger.d("Using cached seller groups: ${_cachedSellerGroups!.length} (age: ${cacheAge.inSeconds}s)");
        _updateCartSummary();
        return _cachedSellerGroups!;
      } else {
        AppLogger.d(
          "Cache expired (${cacheAge.inMinutes} minutes old), refreshing",
        );
      }
    } else if (_cachedSellerGroups != null) {
      // Have cached data but no timestamp - still use it for better UX
      AppLogger.d("Using cached seller groups: ${_cachedSellerGroups!.length} (no timestamp)");
      _updateCartSummary();
      return _cachedSellerGroups!;
    }

    AppLogger.d("Loading seller groups from API (optimized version)");
    setState(() {
      _isLoading = true;
    });

    try {
      final sellerGroups = await _cartService.getCartItemsGroupedBySeller();
      
      stopwatch.stop();
      AppLogger.d("Cart loaded in ${stopwatch.elapsedMilliseconds}ms");

      // Cache the seller groups with current timestamp
      _cachedSellerGroups = sellerGroups;
      _lastCacheTime = DateTime.now();
      _updateCartSummary();

      setState(() {
        _isLoading = false;
      });
      return sellerGroups;
    } catch (e) {
      stopwatch.stop();
      AppLogger.d("Cart loading failed after ${stopwatch.elapsedMilliseconds}ms: $e");
      
      setState(() {
        _isLoading = false;
      });
      AppLogger.d('Error loading seller groups: $e');
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
        AppLogger.d("Cache expired, should refresh");
        return true;
      }
    }
    
    // Only refresh if explicitly marked as stale
    if (_wasPopped) {
      AppLogger.d("Cart marked as stale, should refresh");
      return true;
    }
    
    return false;
  }

  // Cache-first refresh with change detection
  Future<void> _handleRefresh() async {
    AppLogger.d("Cart refresh started - cache-first approach");
    
    try {
      // Store current cached data for comparison
      final currentSellerGroups = _cachedSellerGroups;
      
      // Fetch new data from API
      final newSellerGroups = await _cartService.getCartItemsGroupedBySeller();
      
      // Compare with cached data
      if (currentSellerGroups != null && _hasSellerGroupsDataChanged(currentSellerGroups, newSellerGroups)) {
        AppLogger.d("Cart data has changed, updating UI and cache");
        
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
        AppLogger.d("Cart data unchanged, keeping existing cache");
      }
      
      // Reset the stale flag since we've refreshed
      _wasPopped = false;
      
    } catch (e) {
      AppLogger.d("Error during cart refresh: $e");
      rethrow;
    }
  }

  // Helper method to compare seller groups data
  bool _hasSellerGroupsDataChanged(List<SellerGroup> oldData, List<SellerGroup> newData) {
    if (oldData.length != newData.length) {
      AppLogger.d("Seller groups count changed: ${oldData.length} -> ${newData.length}");
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
      AppLogger.d("Seller groups composition changed");
      return true;
    }
    
    // Compare each seller group's items
    for (var sellerId in oldMap.keys) {
      final oldGroup = oldMap[sellerId]!;
      final newGroup = newMap[sellerId]!;
      
      if (oldGroup.items.length != newGroup.items.length) {
        AppLogger.d("Items count changed for seller $sellerId: ${oldGroup.items.length} -> ${newGroup.items.length}");
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
        AppLogger.d("Cart items composition changed for seller $sellerId");
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
          AppLogger.d("Cart item details changed for item $cartItemId");
          return true;
        }
      }
    }
    
    AppLogger.d("No changes detected in seller groups data");
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
      AppLogger.d("Cart page not mounted, skipping optimistic update");
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
      AppLogger.d("Error adding to cart: $e");
      rethrow;
    }
  }

  void _onUpdateQuantity(CartItem item, int newQuantity) async {
    if (!mounted) return;

    try {
      AppLogger.d(
        "Updating cart item quantity: ${item.cartItemId} to $newQuantity",
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
      AppLogger.d("Error updating item: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating item: $e'),
            backgroundColor: _danger,
          ),
        );
      }
    }
  }

  void _onRemoveItem(CartItem item) async {
    if (!mounted) return;

    try {
      AppLogger.d("Removing cart item: ${item.cartItemId}");

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
      AppLogger.d("Error removing item: $e");
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
        AppLogger.d("Item selection saved to Firestore: ${item.cartItemId} = $isSelected");
      } catch (e) {
        AppLogger.d("Error saving item selection to Firestore: $e");
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
        AppLogger.d("Group selection saved to Firestore for seller: ${sellerGroup.sellerName}");
      } catch (e) {
        AppLogger.d("Error saving group selection to Firestore: $e");
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


  // ── Layout ───────────────────────────────────────────────────────────────

  /// Widest the two-column layout grows to before it centres.
  static const double _kMaxContentWidth = 1100;

  /// The money column, per the reference design.
  static const double _kSummaryWidth = 360;

  InkPalette get ink => InkPalette.of(context);

  /// Destructive red. [InkPalette] reserves amber for urgency, so danger needs
  /// its own tone that still reads in both themes.
  Color get _danger =>
      ink.isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);

  Color get _warning => ink.amber;

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    // Back handling is not this page's business either way: as a tab the shell
    // owns it (back returns to Home), and as a pushed route the Navigator does.
    final isWide = context.isWideLayout;

    return Scaffold(
      backgroundColor: ink.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildBody(isWide)),
          ],
        ),
      ),
      // On a phone the total and the action that commits to it ride above the
      // tab bar. On desktop they live inside the summary column instead, so the
      // number and the button never separate.
      bottomNavigationBar: isWide ? null : _buildMobileCheckoutBar(),
    );
  }

  /// "Cart (3)" — the count belongs in the title, as in the reference, so the
  /// header states the size of the order rather than just naming the screen.
  Widget _buildHeader() {
    final count = _cartSummary?.selectedItemsCount ?? 0;
    final hasItems = (_cachedSellerGroups?.isNotEmpty ?? false);
    final canPop = Navigator.of(context).canPop();

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      decoration: BoxDecoration(
        color: ink.bg,
        border: Border(bottom: BorderSide(color: ink.border)),
      ),
      child: Row(
        children: [
          if (canPop)
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back),
              color: ink.text,
              tooltip: 'Back',
            )
          else
            const SizedBox(width: 8),
          Expanded(
            child: Text(
              count > 0 ? 'Cart ($count)' : 'Cart',
              textAlign: TextAlign.center,
              style: AppTextStyles.titleLarge.copyWith(
                color: ink.text,
                fontWeight: FontWeight.w800,
                fontSize: 19,
              ),
            ),
          ),
          if (hasItems)
            IconButton(
              onPressed: _showClearCartConfirmation,
              icon: const Icon(Icons.delete_outline, size: 21),
              color: ink.text.withValues(alpha: 0.55),
              tooltip: 'Clear cart',
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildBody(bool isWide) {
    // Prioritise cached data for immediate display.
    if (_cachedSellerGroups != null) {
      if (_cachedSellerGroups!.isEmpty) return _buildEmptyCart();
      return _buildContent(_cachedSellerGroups!, isWide);
    }

    return FutureBuilder<List<SellerGroup>>(
      future: _sellerGroupsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting || _isLoading) {
          return const CartSkeleton();
        }
        if (snapshot.hasError) {
          return _buildErrorState(snapshot.error.toString());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return _buildEmptyCart();
        }
        return _buildContent(snapshot.data!, isWide);
      },
    );
  }

  /// Two columns on desktop — what you are buying on the left, what it costs on
  /// the right. A purchasing decision on a long cart is made against a running
  /// total, so the summary stays put while the items scroll. One column on a
  /// phone, with the summary at the end of the list.
  Widget _buildContent(List<SellerGroup> sellerGroups, bool isWide) {
    final list = RefreshIndicator(
      onRefresh: _handleRefresh,
      color: ink.emerald,
      backgroundColor: ink.surface,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 14, isWide ? 8 : 16, 24),
        children: [
          _buildShippingNotice(),
          const SizedBox(height: 14),
          for (final group in sellerGroups) _buildSellerGroup(group),
          if (!isWide) ...[
            const SizedBox(height: 2),
            _buildSummaryCard(includeButton: false),
          ],
        ],
      ),
    );

    if (!isWide) return list;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: list),
            SizedBox(
              width: _kSummaryWidth,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(8, 14, 16, 24),
                child: _buildSummaryCard(includeButton: true),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSellerGroup(SellerGroup sellerGroup) {
    return SellerGroupWidget(
      sellerGroup: sellerGroup,
      onUpdateQuantity: _onUpdateQuantity,
      onRemoveItem: _onRemoveItem,
      onToggleItemSelection: _onToggleItemSelection,
      onToggleGroupSelection: _onToggleGroupSelection,
      onSellerNameTap: () {
        NavigationUtils.navigateToStore(
          context,
          sellerGroup.sellerId,
          sellerData: {'initialTab': 'products'},
        );
      },
      selectedDiscountVoucher: _selectedDiscountVouchers[sellerGroup.sellerId],
      onDiscountVoucherSelected: (voucher) {
        setState(() {
          _selectedDiscountVouchers[sellerGroup.sellerId] = voucher;
        });
      },
      selectedShippingVoucher: _selectedShippingVouchers[sellerGroup.sellerId],
      onShippingVoucherSelected: (voucher) {
        setState(() {
          _selectedShippingVouchers[sellerGroup.sellerId] = voucher;
        });
      },
    );
  }

  /// Shipping, stated rather than sold.
  ///
  /// The reference names a flat fee and a free-shipping threshold. Ours cannot:
  /// shipping is quoted per seller at checkout (couriers price it by weight and
  /// destination), and each seller sets their own free-delivery threshold —
  /// which is why the bar for that lives on the seller card. Saying so plainly
  /// beats implying a number this screen does not know.
  Widget _buildShippingNotice() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: ink.emerald.withValues(alpha: ink.isDark ? 0.12 : 0.09),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink.emerald.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(Icons.local_shipping_outlined, size: 18, color: ink.emerald),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Shipping is quoted at checkout for each seller. '
              'Sellers running a free-delivery offer show your progress below.',
              style: AppTextStyles.bodySmall.copyWith(
                color: ink.isDark
                    ? ink.emerald
                    : ink.emerald.withValues(alpha: 0.95),
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Summary ──────────────────────────────────────────────────────────────

  Widget _buildSummaryCard({required bool includeButton}) {
    final summary = _cartSummary;
    if (summary == null || !summary.hasSelectedItems) {
      return _buildNothingSelectedCard();
    }

    final totalDiscount = _calculateTotalCartDiscount();
    final shippingVoucherLabels = _selectedShippingVoucherLabels();
    final total = summary.selectedItemsTotal - totalDiscount;
    final sellerCount = summary.sellersWithSelectedItems.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _summaryRow(
            'Subtotal (${summary.selectedItemsCount} item'
            '${summary.selectedItemsCount != 1 ? 's' : ''})',
            CurrencyFormatter.formatWithPeso(summary.selectedItemsTotal),
          ),
          if (totalDiscount > 0) ...[
            const SizedBox(height: 10),
            _summaryRow(
              'Shop vouchers',
              '-${CurrencyFormatter.formatWithPeso(totalDiscount)}',
              good: true,
            ),
          ],
          const SizedBox(height: 10),
          _summaryRow(
            'Shipping',
            shippingVoucherLabels.isNotEmpty ? 'Voucher applied' : 'At checkout',
            good: shippingVoucherLabels.isNotEmpty,
            muted: shippingVoucherLabels.isEmpty,
          ),

          const SizedBox(height: 14),
          Divider(height: 1, thickness: 1, color: ink.border),
          const SizedBox(height: 14),

          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'Total',
                style: AppTextStyles.titleMedium.copyWith(
                  color: ink.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              Text(
                CurrencyFormatter.formatWithPeso(total),
                style: AppTextStyles.headlineSmall.copyWith(
                  color: ink.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 25,
                ),
              ),
            ],
          ),

          // Savings sit BELOW the total, not in the deduction column: the
          // subtotal above is the list price, and the discount has already been
          // taken off the figure shown — repeating it as a deduction line would
          // imply a second reduction that never happens.
          if (totalDiscount > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.sell_outlined, size: 14, color: ink.emerald),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'You saved '
                    '${CurrencyFormatter.formatWithPeso(totalDiscount)} '
                    'with shop vouchers',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: ink.emerald,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ],

          if (shippingVoucherLabels.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.local_shipping_outlined,
                  size: 14,
                  color: ink.emerald,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    shippingVoucherLabels.join(', '),
                    style: AppTextStyles.bodySmall.copyWith(
                      color: ink.emerald,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ],

          if (sellerCount > 1) ...[
            const SizedBox(height: 12),
            _buildNotice(
              icon: Icons.info_outline,
              tone: ink.text.withValues(alpha: 0.7),
              text:
                  'Items from $sellerCount sellers ship separately, '
                  'each with its own delivery date.',
            ),
          ],

          ..._buildBlockingNotices(),

          if (includeButton) ...[
            const SizedBox(height: 16),
            _buildCheckoutButton(),
          ],
        ],
      ),
    );
  }

  /// Warnings that stop checkout. Shown in both layouts, so a buyer never meets
  /// a disabled button without being told why.
  List<Widget> _buildBlockingNotices() {
    final summary = _cartSummary;
    if (summary == null) return const [];

    return [
      if (summary.hasInsufficientStock) ...[
        const SizedBox(height: 12),
        _buildNotice(
          icon: Icons.warning_amber_rounded,
          tone: _danger,
          text: 'Some selected items exceed available stock. '
              'Please adjust quantities.',
        ),
      ],
      if (summary.hasUnavailableItems) ...[
        const SizedBox(height: 12),
        _buildNotice(
          icon: Icons.warning_amber_rounded,
          tone: _danger,
          text: 'Some selected items are no longer available. '
              'Please remove them to continue.',
        ),
      ],
      if (_isSubAccountWithoutCheckout()) ...[
        const SizedBox(height: 12),
        _buildNotice(
          icon: Icons.info_outline,
          tone: _warning,
          text: 'Sub accounts cannot start a checkout. Please ask the main '
              'account holder to complete the purchase.',
        ),
      ],
    ];
  }

  Widget _summaryRow(
    String label,
    String value, {
    bool good = false,
    bool muted = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          label,
          style: AppTextStyles.bodyMedium.copyWith(
            color: ink.text.withValues(alpha: 0.65),
            fontSize: 13.5,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: AppTextStyles.bodyMedium.copyWith(
            color: good
                ? ink.emerald
                : ink.text.withValues(alpha: muted ? 0.55 : 1),
            fontWeight: muted ? FontWeight.w500 : FontWeight.w700,
            fontSize: 13.5,
          ),
        ),
      ],
    );
  }

  Widget _buildNothingSelectedCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink.border),
      ),
      child: Column(
        children: [
          Icon(
            Icons.check_box_outlined,
            size: 30,
            color: ink.text.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 10),
          Text(
            'Nothing selected',
            style: AppTextStyles.bodyMedium.copyWith(
              color: ink.text.withValues(alpha: 0.75),
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tick the items you want to order to see your total.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(
              color: ink.text.withValues(alpha: 0.5),
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── Checkout ─────────────────────────────────────────────────────────────

  bool get _checkoutBlocked {
    final summary = _cartSummary;
    if (summary == null) return true;
    return summary.hasUnavailableItems ||
        summary.hasInsufficientStock ||
        _isSubAccountWithoutCheckout();
  }

  String get _checkoutLabel {
    final summary = _cartSummary;
    if (summary == null) return 'Proceed to checkout';
    if (summary.hasUnavailableItems) return 'Unavailable items';
    if (summary.hasInsufficientStock) return 'Insufficient stock';
    if (_isSubAccountWithoutCheckout()) return 'Checkout not allowed';
    return 'Proceed to checkout';
  }

  Widget _buildCheckoutButton() {
    final blocked = _checkoutBlocked;

    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: blocked ? null : _proceedToCheckout,
        style: ElevatedButton.styleFrom(
          backgroundColor: ink.emerald,
          foregroundColor: ink.onEmerald,
          disabledBackgroundColor: ink.surfaceHigh,
          disabledForegroundColor: ink.text.withValues(alpha: 0.38),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                _checkoutLabel,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.buttonLarge.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            if (!blocked) ...[
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward, size: 18),
            ],
          ],
        ),
      ),
    );
  }

  /// The phone's committed action: total on the left, button on the right,
  /// floating above the tab bar.
  Widget? _buildMobileCheckoutBar() {
    final summary = _cartSummary;
    if (summary == null || !summary.hasSelectedItems) return null;

    final total = summary.selectedItemsTotal - _calculateTotalCartDiscount();

    return Container(
      decoration: BoxDecoration(
        color: ink.surface,
        border: Border(top: BorderSide(color: ink.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Total',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: ink.text.withValues(alpha: 0.55),
                      fontSize: 11.5,
                    ),
                  ),
                  Text(
                    CurrencyFormatter.formatWithPeso(total),
                    style: AppTextStyles.titleLarge.copyWith(
                      color: ink.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 19,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(child: _buildCheckoutButton()),
            ],
          ),
        ),
      ),
    );
  }

  // ── Empty / error ────────────────────────────────────────────────────────

  Widget _buildEmptyCart() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: ink.surfaceHigh,
                shape: BoxShape.circle,
                border: Border.all(color: ink.border),
              ),
              child: Icon(
                Icons.shopping_cart_outlined,
                size: 42,
                color: ink.text.withValues(alpha: 0.35),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'Your cart is empty',
              style: AppTextStyles.headlineSmall.copyWith(
                color: ink.text,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Have a look by category, or search for what you need.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: ink.text.withValues(alpha: 0.6),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 26),
            SizedBox(
              width: 260,
              height: 50,
              child: ElevatedButton(
                onPressed: _browseProducts,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ink.emerald,
                  foregroundColor: ink.onEmerald,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  'Browse products',
                  style: AppTextStyles.buttonLarge.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Sends an empty cart somewhere useful: the Categories tab when we are
  /// inside the shell, otherwise back to whatever pushed this page.
  void _browseProducts() {
    final shell = AppShell.of(context);
    if (shell != null) {
      shell.selectTab(ShellTab.categories);
      return;
    }
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: _danger),
            const SizedBox(height: 16),
            Text(
              'Could not load your cart',
              style: AppTextStyles.titleMedium.copyWith(
                color: ink.text,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(
                color: ink.text.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: _refreshCart,
              style: OutlinedButton.styleFrom(
                foregroundColor: ink.emerald,
                side: BorderSide(color: ink.emerald),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
              ),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotice({
    required IconData icon,
    required Color tone,
    required String text,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: tone.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: tone, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodySmall.copyWith(
                color: tone,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }


  /// Compute the total voucher discount across all selected sellers.
  double _calculateTotalCartDiscount() {
    if (_cachedSellerGroups == null) return 0.0;
    double total = 0.0;
    for (final group in _cachedSellerGroups!) {
      final voucher = _selectedDiscountVouchers[group.sellerId];
      if (voucher == null) continue;

      final sellerSubtotal = group.selectedItemsTotal;
      final discountType = voucher['discountType'] as String? ?? '';
      final discountValue = (voucher['discountValue'] as num? ?? 0).toDouble();
      final minimumOrderAmount = (voucher['minimumOrderAmount'] as num? ?? 0).toDouble();
      final maximumSpend = (voucher['maximumSpend'] as num?)?.toDouble();

      if (sellerSubtotal < minimumOrderAmount) continue;

      if (discountType == 'percentage') {
        double discount = sellerSubtotal * (discountValue / 100.0);
        if (maximumSpend != null && discount > maximumSpend) discount = maximumSpend;
        total += discount.clamp(0.0, sellerSubtotal);
      } else if (discountType == 'fixed') {
        total += discountValue.clamp(0.0, sellerSubtotal);
      }
    }
    return total;
  }

  String _shippingVoucherSummaryLabel(Map<String, dynamic> voucher) {
    final modes = parseShippingCoverage(voucher['shippingOption']);
    if (modes.contains('standard') && modes.contains('express')) {
      return 'Free Standard/Express Shipping';
    }
    if (modes.contains('express')) {
      return 'Free Express Shipping';
    }
    return 'Free Standard Shipping';
  }

  List<String> _selectedShippingVoucherLabels() {
    if (_cachedSellerGroups == null) return const [];
    final labels = <String>[];
    for (final group in _cachedSellerGroups!) {
      if (!group.hasSelectedItems) continue;
      final voucher = _selectedShippingVouchers[group.sellerId];
      if (voucher == null) continue;
      labels.add(_shippingVoucherSummaryLabel(voucher));
    }
    return labels;
  }

  /// Returns true if the current user is a sub account without checkout permission.
  bool _isSubAccountWithoutCheckout() {
    return SubAccountSessionManager.isSubAccount &&
        !SubAccountSessionManager.canCheckout;
  }

  void _proceedToCheckout() {
    // Check if the user is a sub account without checkout permission
    if (SubAccountSessionManager.isSubAccount &&
        !SubAccountSessionManager.canCheckout) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Sub accounts are not allowed to initiate checkout. Please ask the main account holder to complete the purchase.',
          ),
          backgroundColor: _warning,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    if (_cartSummary == null || !_cartSummary!.hasSelectedItems) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select items to checkout'),
          backgroundColor: _warning,
        ),
      );
      return;
    }

    // Check for unavailable items (inactive or out of stock)
    if (_cartSummary!.hasUnavailableItems) {
      final unavailableItems = _cartSummary!.unavailableSelectedItems;
      final itemNames = unavailableItems
          .take(3)
          .map((item) => item.productName ?? 'Unknown')
          .join(', ');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot checkout: ${unavailableItems.length} item(s) are no longer available${unavailableItems.length <= 3 ? ' ($itemNames)' : ''}. Please remove them from your cart.',
          ),
          backgroundColor: _danger,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    // Check for insufficient stock
    if (_cartSummary!.hasInsufficientStock) {
      final insufficientItems = _cartSummary!.itemsWithInsufficientStock;
      final itemNames = insufficientItems
          .take(3)
          .map((item) => item.productName ?? 'Unknown')
          .join(', ');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot checkout: ${insufficientItems.length} item(s) exceed available stock${insufficientItems.length <= 3 ? ' ($itemNames)' : ''}',
          ),
          backgroundColor: _danger,
          duration: const Duration(seconds: 4),
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
            if (item.sellerId == null || item.sellerId!.isEmpty) {
              item.sellerId = group.sellerId;
            }
            selectedItems.add(item);
          }
        }
      }
    }

    if (selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No items selected for checkout'),
          backgroundColor: _warning,
        ),
      );
      return;
    }

    // Filter vouchers to only include sellers with selected items
    final selectedSellerIds = (_cachedSellerGroups ?? const <SellerGroup>[])
        .where((group) => group.hasSelectedItems)
        .map((group) => group.sellerId)
        .toSet();
    final relevantDiscountVouchers = Map<String, Map<String, dynamic>?>.fromEntries(
      _selectedDiscountVouchers.entries.where(
        (e) => selectedSellerIds.contains(e.key),
      ),
    );
    final relevantShippingVouchers = Map<String, Map<String, dynamic>?>.fromEntries(
      _selectedShippingVouchers.entries.where(
        (e) => selectedSellerIds.contains(e.key),
      ),
    );

    // Navigate to checkout page
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CheckoutPage(
          cartItems: selectedItems,
          cartSummary: _cartSummary!,
          selectedDiscountVouchers: relevantDiscountVouchers,
          selectedShippingVouchers: relevantShippingVouchers,
          onVouchersChanged: (discountVouchers, shippingVouchers) {
            setState(() {
              _selectedDiscountVouchers
                ..clear()
                ..addAll(discountVouchers);
              _selectedShippingVouchers
                ..clear()
                ..addAll(shippingVouchers);
            });
          },
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
        backgroundColor: ink.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _danger.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.warning_outlined, color: _danger, size: 22),
            ),
            const SizedBox(width: 12),
            Text(
              'Clear cart',
              style: AppTextStyles.titleMedium.copyWith(
                color: ink.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Text(
          'Remove everything from your cart? This cannot be undone.',
          style: AppTextStyles.bodyMedium.copyWith(
            color: ink.text.withValues(alpha: 0.8),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: ink.text.withValues(alpha: 0.6),
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
              backgroundColor: _danger,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text('Clear', style: AppTextStyles.buttonMedium),
          ),
        ],
      ),
    );
  }
}