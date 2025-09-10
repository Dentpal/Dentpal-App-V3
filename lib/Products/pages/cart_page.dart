import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/cart_model.dart';
import '../services/cart_service.dart';
import '../../core/app_theme/app_colors.dart';
import '../../core/app_theme/app_text_styles.dart';

class CartPage extends StatefulWidget {
  const CartPage({Key? key}) : super(key: key);

  // Static method to mark the cart as needing refresh
  static void markCartAsStale() {
    _CartPageState._wasPopped = true;
    print("🛒 Cart has been marked as stale, will refresh when user returns");
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

class _CartPageState extends State<CartPage> with AutomaticKeepAliveClientMixin<CartPage> {
  // Static instance for singleton pattern
  static _CartPageState? _instance;
  
  // Flag to indicate the cart needs a refresh
  static bool _wasPopped = false;
  
  final CartService _cartService = CartService();
  Future<List<CartItem>>? _cartItemsFuture;
  List<CartItem>? _cachedCartItems;
  bool _isLoading = false;
  
  // Override to keep this page alive when navigating away
  @override
  bool get wantKeepAlive => true;
  
  @override
  void initState() {
    super.initState();
    
    // If we already have an instance, use its data
    if (_instance != null) {
      _cartItemsFuture = _instance!._cartItemsFuture;
      _cachedCartItems = _instance!._cachedCartItems;
      _isLoading = _instance!._isLoading;
      
      print("🔵 CartPage initState called, cached: ${_cachedCartItems != null}");
    } else {
      // First time initialization
      _cartItemsFuture = _loadCartItems();
      print("🔵 CartPage initState called, first time initialization");
    }
    
    // Store this instance as the static instance
    _instance = this;
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Check if we should refresh the cart (when returning from product detail or another page)
    if (_wasPopped) {
      print("🔄 Cart page is being shown again after navigation, refreshing data");
      _refreshCart();
      _wasPopped = false;
    }
  }
  
  // Method to refresh the cart data
  void _refreshCart() {
    print("🔄 Refreshing cart data");
    // Don't clear cache completely, just trigger a background sync to update data
    if (_cachedCartItems != null && _cachedCartItems!.isNotEmpty) {
      _syncAllCartItemsInBackground();
    } else {
      // If no cache, do a full reload
      _cachedCartItems = null;
      if (_instance != null) {
        _instance!._cachedCartItems = null;
      }
      setState(() {
        _cartItemsFuture = _loadCartItems();
      });
    }
  }
  
  // Background sync for all cart items
  Future<void> _syncAllCartItemsInBackground() async {
    if (!mounted) {
      print("⚠️ Cart page not mounted, skipping background sync for all items");
      return;
    }
    
    try {
      print("🔄 Background syncing all cart items");
      final freshCartItems = await _cartService.getCartItems();
      
      if (_cachedCartItems != null && mounted) {
        setState(() {
          _cachedCartItems = freshCartItems;
        });
        print("🔄 Background sync completed for all items");
      }
    } catch (e) {
      print("⚠️ Background sync failed for all items: $e");
    }
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

  Future<List<CartItem>> _loadCartItems() async {
    // If we have cached cart items, return them immediately
    if (_cachedCartItems != null) {
      print("🟢 Using cached cart items: ${_cachedCartItems!.length}");
      return _cachedCartItems!;
    }
    
    print("🟡 No cached cart items, loading from API");
    setState(() {
      _isLoading = true;
    });
    
    try {
      final cartItems = await _cartService.getCartItems();
      
      // Cache the cart items for future use
      _cachedCartItems = cartItems;
      
      setState(() {
        _isLoading = false;
      });
      return cartItems;
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      print('❌ Error loading cart items: $e');
      return [];
    }
  }
  
  Future<void> _updateItemQuantity(CartItem item, int newQuantity) async {
    if (!mounted) {
      print("⚠️ Cart page not mounted, skipping quantity update");
      return;
    }
    
    // Allow decreasing quantity even if current quantity exceeds stock
    // Only prevent increasing if it would exceed available stock
    if (item.availableStock != null && 
        newQuantity > item.quantity && // Only check if we're increasing
        newQuantity > item.availableStock!) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.warning, color: AppColors.onPrimary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Cannot exceed available stock (${item.availableStock!})',
                  style: const TextStyle(color: AppColors.onPrimary),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }
    
    try {
      print("🛒 Updating cart item quantity: ${item.cartItemId} to $newQuantity");
      
      // Optimistic update: Update cached data immediately
      if (_cachedCartItems != null && mounted) {
        final itemIndex = _cachedCartItems!.indexWhere((cartItem) => cartItem.cartItemId == item.cartItemId);
        if (itemIndex != -1) {
          setState(() {
            _cachedCartItems![itemIndex].quantity = newQuantity;
          });
          print("🟢 Optimistically updated item quantity in cache");
        }
      }
      
      // Background update: Sync with server
      await _cartService.updateCartItemQuantity(item.cartItemId, newQuantity);
      
      // Background sync: Fetch fresh data for this specific item and update cache
      if (mounted) {
        _syncCartItemInBackground(item.cartItemId);
      }
      
    } catch (e) {
      print("❌ Error updating item: $e");
      
      // Revert optimistic update on error
      if (_cachedCartItems != null && mounted) {
        final itemIndex = _cachedCartItems!.indexWhere((cartItem) => cartItem.cartItemId == item.cartItemId);
        if (itemIndex != -1) {
          setState(() {
            _cachedCartItems![itemIndex].quantity = item.quantity; // Revert to original
          });
          print("⏪ Reverted optimistic update due to error");
        }
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: AppColors.onPrimary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Error updating item: $e',
                    style: const TextStyle(color: AppColors.onPrimary),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
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
      // Just add to cart normally if page is not mounted
      await cartService.addToCart(
        productId: productId,
        quantity: quantity,
        variationId: variationId,
      );
      return;
    }
    
    if (_cachedCartItems != null) {
      // Check if item already exists in cache
      final existingItemIndex = _cachedCartItems!.indexWhere(
        (item) => item.productId == productId && item.variationId == variationId,
      );
      
      if (existingItemIndex != -1) {
        // Update existing item quantity optimistically
        if (mounted) {
          setState(() {
            _cachedCartItems![existingItemIndex].quantity += quantity;
          });
          print("🟢 Optimistically updated existing item quantity in cart cache");
        }
      } else {
        // Create a temporary cart item for immediate display
        final tempCartItem = CartItem(
          cartItemId: 'temp_${DateTime.now().millisecondsSinceEpoch}',
          productId: productId,
          quantity: quantity,
          variationId: variationId,
          addedAt: DateTime.now(),
          productName: 'Loading...', // Will be updated by background sync
        );
        
        if (mounted) {
          setState(() {
            _cachedCartItems!.insert(0, tempCartItem); // Add at beginning
          });
          print("🟢 Optimistically added new item to cart cache");
        }
      }
    }
    
    try {
      // Background sync with server
      final cartItemId = await cartService.addToCart(
        productId: productId,
        quantity: quantity,
        variationId: variationId,
      );
      
      // Background sync: Update cache with server data
      if (cartItemId != null && mounted) {
        _syncCartItemInBackground(cartItemId);
      }
    } catch (e) {
      print("❌ Error adding to cart: $e");
      
      // Revert optimistic update on error
      if (_cachedCartItems != null && mounted) {
        final existingItemIndex = _cachedCartItems!.indexWhere(
          (item) => item.productId == productId && item.variationId == variationId,
        );
        
        if (existingItemIndex != -1) {
          final item = _cachedCartItems![existingItemIndex];
          if (item.cartItemId.startsWith('temp_')) {
            // Remove temporary item
            setState(() {
              _cachedCartItems!.removeAt(existingItemIndex);
            });
          } else {
            // Revert quantity change
            setState(() {
              _cachedCartItems![existingItemIndex].quantity -= quantity;
            });
          }
          print("⏪ Reverted optimistic cart addition due to error");
        }
      }
      rethrow;
    }
  }
  
  // Background sync method to update a specific cart item
  Future<void> _syncCartItemInBackground(String cartItemId) async {
    if (!mounted) {
      print("⚠️ Cart page not mounted, skipping background sync for item: $cartItemId");
      return;
    }
    
    try {
      final updatedItem = await _cartService.getCartItem(cartItemId);
      if (updatedItem != null && _cachedCartItems != null && mounted) {
        final itemIndex = _cachedCartItems!.indexWhere((item) => item.cartItemId == cartItemId);
        
        if (itemIndex != -1) {
          setState(() {
            _cachedCartItems![itemIndex] = updatedItem;
          });
          print("🔄 Background sync completed for item: $cartItemId");
        } else {
          // Check if this is replacing a temporary item
          final tempItemIndex = _cachedCartItems!.indexWhere((item) => 
            item.cartItemId.startsWith('temp_') && 
            item.productId == updatedItem.productId && 
            item.variationId == updatedItem.variationId
          );
          
          if (tempItemIndex != -1 && mounted) {
            setState(() {
              _cachedCartItems![tempItemIndex] = updatedItem;
            });
            print("🔄 Background sync replaced temporary item: $cartItemId");
          } else if (mounted) {
            // Add new item that wasn't in cache
            setState(() {
              _cachedCartItems!.insert(0, updatedItem);
            });
            print("🔄 Background sync added new item: $cartItemId");
          }
        }
      }
    } catch (e) {
      print("⚠️ Background sync failed for item $cartItemId: $e");
    }
  }
  
  Future<void> _removeItem(CartItem item) async {
    if (!mounted) {
      print("⚠️ Cart page not mounted, skipping item removal");
      return;
    }
    
    CartItem? removedItem;
    int? removedIndex;
    
    try {
      print("🗑️ Removing cart item: ${item.cartItemId}");
      
      // Optimistic update: Remove from cached data immediately
      if (_cachedCartItems != null && mounted) {
        final itemIndex = _cachedCartItems!.indexWhere((cartItem) => cartItem.cartItemId == item.cartItemId);
        if (itemIndex != -1) {
          setState(() {
            removedItem = _cachedCartItems![itemIndex];
            removedIndex = itemIndex;
            _cachedCartItems!.removeAt(itemIndex);
          });
          print("🟢 Optimistically removed item from cache");
        }
      }
      
      // Background update: Sync with server
      await _cartService.removeCartItem(item.cartItemId);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item removed from cart')),
        );
      }
    } catch (e) {
      print("❌ Error removing item: $e");
      
      // Revert optimistic update on error
      if (_cachedCartItems != null && removedItem != null && removedIndex != null && mounted) {
        setState(() {
          _cachedCartItems!.insert(removedIndex!, removedItem!);
        });
        print("⏪ Reverted optimistic removal due to error");
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error removing item: $e')),
        );
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
          // Modern SliverAppBar with gradient
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
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.shopping_cart,
                    color: AppColors.primary,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'My Cart',
                        style: AppTextStyles.titleMedium.copyWith(
                          fontSize: 16,
                        ),
                      ),
                      if (_cachedCartItems != null)
                        Text(
                          '${_cachedCartItems!.length} items',
                          style: AppTextStyles.bodySmall.copyWith(
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primary.withOpacity(0.05),
                      AppColors.secondary.withOpacity(0.02),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              if (_cachedCartItems != null && _cachedCartItems!.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    iconSize: 20,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    icon: const Icon(Icons.delete_outline, color: AppColors.error),
                    onPressed: () => _showClearCartConfirmation(),
                  ),
                ),
              const SizedBox(width: 8),
            ],
          ),
          
          // Cart content
          SliverToBoxAdapter(
            child: const SizedBox(height: 8),
          ),
          
          _buildCartContent(),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }
  
  Widget _buildCartContent() {
    // If we have cached data, use it immediately while loading fresh data
    if (_cachedCartItems != null) {
      if (_cachedCartItems!.isEmpty) {
        return _buildEmptyCart();
      }
      return _buildCartList(_cachedCartItems!);
    }
    
    // Otherwise, use FutureBuilder for initial load
    return SliverFillRemaining(
      child: FutureBuilder<List<CartItem>>(
        future: _cartItemsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting || _isLoading) {
            return const Center(child: CircularProgressIndicator(
              color: AppColors.primary,
            ));
          } else if (snapshot.hasError) {
            return _buildErrorState(snapshot.error.toString());
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return _buildEmptyCartContent();
          }
          
          final cartItems = snapshot.data!;
          return _buildCartListContent(cartItems);
        },
      ),
    );
  }
  
  Widget _buildBottomNavigationBar() {
    // Calculate total from cached data if available
    if (_cachedCartItems != null && _cachedCartItems!.isNotEmpty) {
      final totalPrice = _cachedCartItems!.fold(
        0.0, 
        (total, item) => total + (item.totalPrice),
      );
      return _buildCheckoutSection(totalPrice);
    }
    
    // Otherwise use FutureBuilder
    return FutureBuilder<List<CartItem>>(
      future: _cartItemsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }
        
        final cartItems = snapshot.data!;
        final totalPrice = cartItems.fold(
          0.0, 
          (total, item) => total + (item.totalPrice),
        );
        
        return _buildCheckoutSection(totalPrice);
      },
    );
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
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
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
                fontWeight: FontWeight.bold,
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
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.shopping_bag),
                label: const Text('Continue Shopping'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
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
              color: AppColors.error.withOpacity(0.1),
              shape: BoxShape.circle,
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
              fontWeight: FontWeight.bold,
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
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: () {
                _cachedCartItems = null;
                if (_instance != null) {
                  _instance!._cachedCartItems = null;
                }
                setState(() {
                  _cartItemsFuture = _loadCartItems();
                });
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
            ),
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
              color: AppColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
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
              fontWeight: FontWeight.bold,
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
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.shopping_bag),
              label: const Text('Continue Shopping'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartListContent(List<CartItem> items) {
    return RefreshIndicator(
      onRefresh: () async {
        print("🔄 Cart pull-to-refresh triggered");
        // Full refresh: Clear cache and reload from server
        _cachedCartItems = null;
        if (_instance != null) {
          _instance!._cachedCartItems = null;
        }
        setState(() {
          _cartItemsFuture = _loadCartItems();
        });
        await _cartItemsFuture; // Wait for the future to complete
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return _buildModernCartItem(item);
        },
      ),
    );
  }
  
  Widget _buildCartList(List<CartItem> items) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final item = items[index];
            return _buildModernCartItem(item);
          },
          childCount: items.length,
        ),
      ),
    );
  }
  
  Widget _buildModernCartItem(CartItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Dismissible(
          key: Key(item.cartItemId),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: AppColors.error,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.delete,
              color: AppColors.onPrimary,
              size: 24,
            ),
          ),
          onDismissed: (direction) {
            _removeItem(item);
          },
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                // Navigate to product detail
                Navigator.pushNamed(
                  context,
                  '/product/${item.productId}',
                );
              },
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Product image
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: item.productImage != null && item.productImage!.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: item.productImage!,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Container(
                                      color: AppColors.grey100,
                                      child: const Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                    errorWidget: (context, url, error) => Container(
                                      color: AppColors.grey100,
                                      child: const Icon(
                                        Icons.image_not_supported,
                                        color: AppColors.grey400,
                                        size: 32,
                                      ),
                                    ),
                                  )
                                : Container(
                                    color: AppColors.grey100,
                                    child: const Icon(
                                      Icons.image_not_supported,
                                      color: AppColors.grey400,
                                      size: 32,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        
                        // Product details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.productName ?? 'Unknown Product',
                                style: AppTextStyles.titleMedium.copyWith(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              
                              // Price and stock info
                              Row(
                                children: [
                                  if (item.productPrice != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '₱${item.productPrice!.toStringAsFixed(2)}',
                                        style: AppTextStyles.bodyMedium.copyWith(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w600,
                                          fontFamily: 'Roboto', // Use Roboto for peso sign support
                                        ),
                                      ),
                                    ),
                                  const SizedBox(width: 8),
                                  if (item.availableStock != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: item.availableStock! > 10 
                                            ? AppColors.success.withOpacity(0.1)
                                            : AppColors.warning.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${item.availableStock!} in stock',
                                        style: AppTextStyles.bodySmall.copyWith(
                                          color: item.availableStock! > 10 
                                              ? AppColors.success
                                              : AppColors.warning,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              
                              const SizedBox(height: 12),
                              
                              // Quantity controls and total
                              Row(
                                children: [
                                  _buildModernQuantitySelector(item),
                                  const Spacer(),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        'Total',
                                        style: AppTextStyles.bodySmall.copyWith(
                                          color: AppColors.onSurface.withOpacity(0.7),
                                        ),
                                      ),
                                      Text(
                                        '₱${item.totalPrice.toStringAsFixed(2)}',
                                        style: AppTextStyles.titleMedium.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primary,
                                          fontFamily: 'Roboto', // Use Roboto for peso sign support
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    
                    // Stock warning if quantity exceeds available stock - full width
                    if (item.availableStock != null && item.quantity > item.availableStock!)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.error.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.error.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: AppColors.error.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(
                                Icons.warning,
                                size: 16,
                                color: AppColors.error,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Quantity exceeds available stock',
                                    style: AppTextStyles.bodyMedium.copyWith(
                                      color: AppColors.error,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Please reduce quantity to ${item.availableStock} or less',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: AppColors.error.withOpacity(0.8),
                                    ),
                                  ),
                                ],
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
        ),
      ),
    );
  }
  
  Widget _buildModernQuantitySelector(CartItem item) {
    final bool canDecrease = item.quantity > 1;
    final bool canIncrease = item.availableStock == null || item.quantity < item.availableStock!;
    final bool exceedsStock = item.availableStock != null && item.quantity > item.availableStock!;
    
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: exceedsStock ? AppColors.error : AppColors.grey300,
          width: exceedsStock ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
        color: AppColors.surface,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Decrease button - Always allow decrease when quantity > 1, even if exceeds stock
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: canDecrease ? () {
                if (item.quantity > 1) {
                  _updateItemQuantity(item, item.quantity - 1);
                } else {
                  _showRemoveItemConfirmation(item);
                }
              } : null,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
              child: Container(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  item.quantity > 1 ? Icons.remove : Icons.delete_outline,
                  size: 18,
                  color: canDecrease 
                      ? (item.quantity > 1 ? AppColors.onSurface : AppColors.error)
                      : AppColors.grey400,
                ),
              ),
            ),
          ),
          
          // Quantity display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: exceedsStock 
                  ? AppColors.error.withOpacity(0.1)
                  : AppColors.background,
              border: Border.symmetric(
                vertical: BorderSide(
                  color: exceedsStock ? AppColors.error : AppColors.grey300,
                  width: exceedsStock ? 1 : 0.5,
                ),
              ),
            ),
            child: Text(
              item.quantity.toString(),
              style: AppTextStyles.titleMedium.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: exceedsStock ? AppColors.error : AppColors.onSurface,
              ),
            ),
          ),
          
          // Increase button - Only allow increase if stock limit isn't exceeded
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: canIncrease ? () {
                _updateItemQuantity(item, item.quantity + 1);
              } : () {
                // Show feedback when max stock reached
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.warning, color: AppColors.onPrimary),
                        const SizedBox(width: 8),
                        Text(
                          'Maximum stock (${item.availableStock}) reached',
                          style: const TextStyle(color: AppColors.onPrimary),
                        ),
                      ],
                    ),
                    backgroundColor: AppColors.warning,
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.all(16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
              },
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
              child: Container(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.add,
                  size: 18,
                  color: canIncrease ? AppColors.primary : AppColors.grey400,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCheckoutSection(double totalPrice) {
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
            // Total summary card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.primary.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Amount',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.onSurface.withOpacity(0.7),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '₱${totalPrice.toStringAsFixed(2)}',
                        style: AppTextStyles.headlineSmall.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.receipt_long,
                      color: AppColors.primary,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Checkout button
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: () {
                  // Check if any items exceed stock
                  if (_cachedCartItems != null) {
                    final hasStockIssues = _cachedCartItems!.any((item) => 
                      item.availableStock != null && item.quantity > item.availableStock!
                    );
                    
                    if (hasStockIssues) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Row(
                            children: [
                              const Icon(Icons.warning, color: AppColors.onPrimary),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Please adjust quantities that exceed available stock',
                                  style: TextStyle(color: AppColors.onPrimary),
                                ),
                              ),
                            ],
                          ),
                          backgroundColor: AppColors.error,
                          behavior: SnackBarBehavior.floating,
                          margin: const EdgeInsets.all(16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      );
                      return;
                    }
                  }
                  
                  // TODO: Implement checkout functionality
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.info, color: AppColors.onPrimary),
                          const SizedBox(width: 8),
                          const Text(
                            'Checkout feature coming soon!',
                            style: TextStyle(color: AppColors.onPrimary),
                          ),
                        ],
                      ),
                      backgroundColor: AppColors.info,
                      behavior: SnackBarBehavior.floating,
                      margin: const EdgeInsets.all(16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.payment, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Proceed to Checkout',
                      style: AppTextStyles.titleMedium.copyWith(
                        color: AppColors.onPrimary,
                        fontWeight: FontWeight.w600,
                      ),
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
  
  void _showRemoveItemConfirmation(CartItem item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.delete_outline,
                color: AppColors.error,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Remove Item',
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Do you want to remove "${item.productName ?? 'this item'}" from your cart?',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.onSurface.withOpacity(0.8),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Cancel',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.onSurface.withOpacity(0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _removeItem(item);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: Text(
              'Remove',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.onPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  void _showClearCartConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.clear_all,
                color: AppColors.warning,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Clear Cart',
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.bold,
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Cancel',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.onSurface.withOpacity(0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              
              if (!mounted) {
                print("⚠️ Cart page not mounted, skipping cart clear");
                return;
              }
              
              // Store original cart for potential rollback
              List<CartItem>? originalCart;
              if (_cachedCartItems != null) {
                originalCart = List<CartItem>.from(_cachedCartItems!);
              }
              
              try {
                print("🧹 Clearing the entire cart");
                
                // Optimistic update: Clear cached data immediately
                if (_cachedCartItems != null && mounted) {
                  setState(() {
                    _cachedCartItems!.clear();
                  });
                  print("🟢 Optimistically cleared cart cache");
                }
                
                // Background update: Sync with server
                await _cartService.clearCart();
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.check_circle, color: AppColors.onPrimary),
                          const SizedBox(width: 8),
                          const Text(
                            'Cart cleared successfully',
                            style: TextStyle(color: AppColors.onPrimary),
                          ),
                        ],
                      ),
                      backgroundColor: AppColors.success,
                      behavior: SnackBarBehavior.floating,
                      margin: const EdgeInsets.all(16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );
                }
              } catch (e) {
                print("❌ Error clearing cart: $e");
                
                // Revert optimistic update on error
                if (originalCart != null && _cachedCartItems != null && mounted) {
                  setState(() {
                    _cachedCartItems!.clear();
                    _cachedCartItems!.addAll(originalCart!);
                  });
                  print("⏪ Reverted optimistic cart clear due to error");
                }
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.error, color: AppColors.onPrimary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Error clearing cart: $e',
                              style: const TextStyle(color: AppColors.onPrimary),
                            ),
                          ),
                        ],
                      ),
                      backgroundColor: AppColors.error,
                      behavior: SnackBarBehavior.floating,
                      margin: const EdgeInsets.all(16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: AppColors.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: Text(
              'Clear All',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.onPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
