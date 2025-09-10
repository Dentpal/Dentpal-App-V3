import 'package:flutter/material.dart';
import '../models/cart_model.dart';
import '../services/cart_service.dart';

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
          SnackBar(content: Text('Error updating item: $e')),
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
      appBar: AppBar(
        title: const Text('My Cart'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _showClearCartConfirmation(),
          ),
        ],
      ),
      body: _buildCartBody(),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }
  
  Widget _buildCartBody() {
    // If we have cached data, use it immediately while loading fresh data
    if (_cachedCartItems != null) {
      if (_cachedCartItems!.isEmpty) {
        return _buildEmptyCart();
      }
      return _buildCartList(_cachedCartItems!);
    }
    
    // Otherwise, use FutureBuilder for initial load
    return FutureBuilder<List<CartItem>>(
      future: _cartItemsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting || _isLoading) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(
            child: Text('Error: ${snapshot.error}'),
          );
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return _buildEmptyCart();
        }
        
        final cartItems = snapshot.data!;
        return _buildCartList(cartItems);
      },
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.shopping_cart_outlined,
            size: 80,
            color: Colors.grey,
          ),
          const SizedBox(height: 16),
          const Text(
            'Your cart is empty',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Add items to your cart to continue shopping',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Continue Shopping'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCartList(List<CartItem> items) {
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
          return _buildCartItem(item);
        },
      ),
    );
  }
  
  Widget _buildCartItem(CartItem item) {
    return Dismissible(
      key: Key(item.cartItemId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(
          Icons.delete,
          color: Colors.white,
        ),
      ),
      onDismissed: (direction) {
        _removeItem(item);
      },
      child: Card(
        elevation: 2,
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product image
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 80,
                  height: 80,
                  child: item.productImage != null && item.productImage!.isNotEmpty
                      ? Image.network(
                          item.productImage!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.grey[200],
                              child: const Icon(Icons.image_not_supported),
                            );
                          },
                        )
                      : Container(
                          color: Colors.grey[200],
                          child: const Icon(Icons.image_not_supported),
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
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    if (item.productPrice != null)
                      Text(
                        '₱${item.productPrice!.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: Theme.of(context).primaryColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildQuantitySelector(item),
                        const Spacer(),
                        Text(
                          '₱${item.totalPrice.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
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
      ),
    );
  }
  
  Widget _buildQuantitySelector(CartItem item) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          // Decrease button
          InkWell(
            onTap: () {
              if (item.quantity > 1) {
                _updateItemQuantity(item, item.quantity - 1);
              } else {
                _showRemoveItemConfirmation(item);
              }
            },
            child: Container(
              padding: const EdgeInsets.all(4),
              child: const Icon(Icons.remove, size: 16),
            ),
          ),
          
          // Quantity display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              item.quantity.toString(),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          
          // Increase button
          InkWell(
            onTap: () {
              if (item.availableStock == null || item.quantity < item.availableStock!) {
                _updateItemQuantity(item, item.quantity + 1);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Maximum stock reached')),
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.all(4),
              child: const Icon(Icons.add, size: 16),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCheckoutSection(double totalPrice) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '₱${totalPrice.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  // TODO: Implement checkout functionality
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Checkout not implemented yet')),
                  );
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text(
                  'Checkout',
                  style: TextStyle(fontSize: 16),
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
        title: const Text('Remove Item'),
        content: const Text('Do you want to remove this item from your cart?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _removeItem(item);
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
  
  void _showClearCartConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Cart'),
        content: const Text('Are you sure you want to clear your cart?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
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
                    const SnackBar(content: Text('Cart cleared successfully')),
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
                    SnackBar(content: Text('Error clearing cart: $e')),
                  );
                }
              }
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}
