import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import '../../core/app_theme/app_colors.dart';
import '../../core/app_theme/app_text_styles.dart';
import '../../product/models/order_model.dart' as order_model;
import '../../product/pages/paymongo_webview_page.dart';
import '../../product/pages/cart_page.dart';
import '../../product/services/cart_service.dart';
import '../../utils/app_logger.dart';
import '../services/order_service.dart';
import 'order_details_page.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> with TickerProviderStateMixin {
  List<order_model.Order> orders = [];
  List<order_model.Order> filteredOrders = [];
  bool isLoading = true;
  String? error;
  order_model.OrderStatus? selectedFilter;
  TabController? _tabController;
  final TextEditingController _searchController = TextEditingController();
  String searchQuery = '';

  // Add stream subscription for real-time updates
  late Stream<List<order_model.Order>> _ordersStream;

  final List<order_model.OrderStatus> filterOptions = [
    order_model.OrderStatus.pending,
    order_model.OrderStatus.confirmed,
    order_model.OrderStatus.to_ship,
    order_model.OrderStatus.shipping,
    order_model.OrderStatus.delivered,
    order_model.OrderStatus.cancelled,
    order_model.OrderStatus.expired,
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: filterOptions.length + 1,
      vsync: this,
    );
    _initializeOrdersStream();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _initializeOrdersStream() {
    try {
      setState(() {
        isLoading = true;
        error = null;
      });

      _ordersStream = OrderService.getUserOrdersStream();

      _ordersStream.listen(
        (fetchedOrders) {
          if (mounted) {
            setState(() {
              orders = fetchedOrders;
              _applyFilter();
              isLoading = false;
            });
          }
        },
        onError: (e) {
          if (mounted) {
            setState(() {
              error = 'Failed to fetch orders: $e';
              isLoading = false;
            });
          }
        },
      );
    } catch (e) {
      setState(() {
        error = 'Failed to initialize orders stream: $e';
        isLoading = false;
      });
    }
  }

  void _applyFilter() {
    List<order_model.Order> result = orders;

    // Apply status filter
    if (selectedFilter != null) {
      if (selectedFilter == order_model.OrderStatus.to_ship) {
        // Include to_pack, to_arrangement, to_handover in processing filter
        result = result
            .where((order) => order.status == order_model.OrderStatus.to_ship)
            .toList();
      } else {
        result = result
            .where((order) => order.status == selectedFilter)
            .toList();
      }
    }

    // Apply search filter
    if (searchQuery.isNotEmpty) {
      result = result.where((order) {
        final orderIdMatch = order.orderId.toLowerCase().contains(
          searchQuery.toLowerCase(),
        );
        final itemsMatch = order.items.any(
          (item) => item.productName.toLowerCase().contains(
            searchQuery.toLowerCase(),
          ),
        );
        return orderIdMatch || itemsMatch;
      }).toList();
    }

    filteredOrders = result;
  }

  void _onFilterChanged(order_model.OrderStatus? status) {
    setState(() {
      selectedFilter = status;
      _applyFilter();
    });
  }

  void _onSearchChanged(String query) {
    setState(() {
      searchQuery = query;
      _applyFilter();
    });
  }

  Future<void> _refreshOrders() async {
    // With streams, we can just reinitialize the stream to get fresh data
    _initializeOrdersStream();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        toolbarHeight: 60,
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Icon(Icons.shopping_bag, color: AppColors.primary, size: 24),
            const SizedBox(width: 8),
            Text(
              'My Orders',
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWideWeb = kIsWeb && constraints.maxWidth > 800; // breakpoint

          final pageContent = Column(
            children: [
              // Search bar
              Container(
                color: AppColors.surface,
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        hintText: 'Search orders...',
                        hintStyle: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.onSurface.withValues(alpha: 0.5),
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          color: AppColors.onSurface.withValues(alpha: 0.5),
                        ),
                        suffixIcon: searchQuery.isNotEmpty
                            ? IconButton(
                                icon: Icon(
                                  Icons.clear,
                                  color: AppColors.onSurface.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                                onPressed: () {
                                  _searchController.clear();
                                  _onSearchChanged('');
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppColors.onSurface.withValues(alpha: 0.2),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppColors.primary,
                            width: 2,
                          ),
                        ),
                        filled: true,
                        fillColor: AppColors.background,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Filter tabs
              Container(
                color: AppColors.surface,
                child: TabBar(
                  controller: _tabController,
                  isScrollable: !isWideWeb, // wide web: fixed tabs
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.onSurface.withValues(
                    alpha: 0.6,
                  ),
                  indicatorColor: AppColors.primary,
                  labelStyle: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: AppTextStyles.bodyMedium,
                  labelPadding: const EdgeInsets.symmetric(
                    horizontal: 5,
                  ), // added to give more space when fixed
                  tabs: [
                    Tab(text: 'All (${orders.length})'),
                    ...filterOptions.map((status) {
                      final count = orders
                          .where((order) => order.status == status)
                          .length;
                      // Shorten labels for wide web to avoid clipping
                      final baseLabel = _formatStatus(status);
                      final shortLabel = isWideWeb
                          ? _shortenStatus(baseLabel)
                          : baseLabel;
                      return Tab(text: '$shortLabel ($count)');
                    }),
                  ],
                  onTap: (index) {
                    if (index == 0) {
                      _onFilterChanged(null);
                    } else {
                      _onFilterChanged(filterOptions[index - 1]);
                    }
                  },
                ),
              ),
              // Orders content
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refreshOrders,
                  color: AppColors.primary,
                  child: _buildBody(),
                ),
              ),
            ],
          );

          if (isWideWeb) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 840,
                ), // increased width to prevent tab text truncation
                child: Material(color: Colors.transparent, child: pageContent),
              ),
            );
          }

          // Mobile & narrow web: full-width fit
          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(width: constraints.maxWidth, child: pageContent),
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              'Error',
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                error!,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.onSurface.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _initializeOrdersStream,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (filteredOrders.isEmpty && orders.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.filter_list_off,
              size: 64,
              color: AppColors.onSurface.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'No Orders Found',
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No orders match the selected filter',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.5),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shopping_bag_outlined,
              size: 64,
              color: AppColors.onSurface.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'No Orders Yet',
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your orders will appear here once you make a purchase',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.5),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredOrders.length,
      itemBuilder: (context, index) {
        final order = filteredOrders[index];
        return _buildOrderCard(order);
      },
    );
  }

  Widget _buildOrderCard(order_model.Order order) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Order Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Order #${order.orderId.substring(0, 8).toUpperCase()}',
                        style: AppTextStyles.titleMedium.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatDate(order.createdAt),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusChip(order.status),
              ],
            ),

            const SizedBox(height: 16),

            // Order Items Preview
            Text(
              'Items (${order.items.length})',
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),

            // Show first few items
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: order.items.length > 3 ? 3 : order.items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = order.items[index];
                return _buildOrderItemPreview(item);
              },
            ),

            if (order.items.length > 3)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '+ ${order.items.length - 3} more items',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Order Summary
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
                  '₱${order.summary.total.toStringAsFixed(2)}',
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    fontFamily: 'Roboto',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Action Buttons
            Row(
              mainAxisAlignment: kIsWeb
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              children: [
                if (kIsWeb) ...[
                  // Web layout - buttons take only necessary space
                  OutlinedButton(
                    onPressed: () => _viewOrderDetails(order),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppColors.primary),
                      foregroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('View Details'),
                  ),
                  const SizedBox(width: 12),
                  if (_canCancelOrder(order))
                    ElevatedButton(
                      onPressed: () => _cancelOrder(order),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: AppColors.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancel Order'),
                    )
                  else if (_canResumePayment(order))
                    ElevatedButton(
                      onPressed: () => _resumePayment(order),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.warning,
                        foregroundColor: AppColors.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Resume Payment'),
                    )
                  else if (_canReorder(order.status))
                    ElevatedButton(
                      onPressed: () => _reorderItems(order),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Reorder'),
                    ),
                ] else ...[
                  // Mobile layout - buttons expanded
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _viewOrderDetails(order),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.primary),
                        foregroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('View Details'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (_canCancelOrder(order))
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _cancelOrder(order),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.error,
                          foregroundColor: AppColors.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Cancel Order'),
                      ),
                    )
                  else if (_canResumePayment(order))
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _resumePayment(order),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.warning,
                          foregroundColor: AppColors.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Resume Payment'),
                      ),
                    )
                  else if (_canReorder(order.status))
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _reorderItems(order),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Reorder'),
                      ),
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderItemPreview(order_model.OrderItem item) {
    return Row(
      children: [
        // Product Image
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: AppColors.grey200,
            borderRadius: BorderRadius.circular(8),
          ),
          child: item.productImage.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    item.productImage,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(
                        Icons.inventory_2_outlined,
                        color: AppColors.grey500,
                        size: 24,
                      );
                    },
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.primary,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                )
              : Icon(
                  Icons.inventory_2_outlined,
                  color: AppColors.grey500,
                  size: 24,
                ),
        ),
        const SizedBox(width: 12),

        // Product Info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.productName,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    'Qty: ${item.quantity}',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  if (item.variationName != null) ...[
                    Text(
                      ' • ',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    Text(
                      item.variationName!,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),

        // Item Price
        Text(
          '₱${item.price.toStringAsFixed(2)}',
          style: AppTextStyles.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
            fontFamily: 'Roboto',
          ),
        ),
      ],
    );
  }

  Widget _buildStatusChip(order_model.OrderStatus status) {
    Color backgroundColor;
    Color textColor;
    IconData icon;

    switch (status) {
      case order_model.OrderStatus.pending:
        backgroundColor = AppColors.grey500.withValues(alpha: 0.1);
        textColor = AppColors.grey500;
        icon = Icons.pending;
        break;
      case order_model.OrderStatus.confirmed:
        backgroundColor = AppColors.success.withValues(alpha: 0.1);
        textColor = AppColors.success;
        icon = Icons.check_circle_outline;
        break;
      case order_model.OrderStatus.to_ship:
        backgroundColor = AppColors.info.withValues(alpha: 0.1);
        textColor = AppColors.info;
        icon = Icons.autorenew;
        break;
      case order_model.OrderStatus.shipping:
        backgroundColor = AppColors.primary.withValues(alpha: 0.1);
        textColor = AppColors.primary;
        icon = Icons.local_shipping;
        break;
      case order_model.OrderStatus.delivered:
        backgroundColor = AppColors.success.withValues(alpha: 0.1);
        textColor = AppColors.success;
        icon = Icons.check_circle;
        break;
      case order_model.OrderStatus.cancelled:
        backgroundColor = AppColors.error.withValues(alpha: 0.1);
        textColor = AppColors.error;
        icon = Icons.cancel;
        break;
      case order_model.OrderStatus.refunded:
        backgroundColor = AppColors.grey400.withValues(alpha: 0.1);
        textColor = AppColors.grey600;
        icon = Icons.refresh;
        break;
      case order_model.OrderStatus.payment_failed:
        backgroundColor = AppColors.error.withValues(alpha: 0.1);
        textColor = AppColors.error;
        icon = Icons.error;
        break;
      case order_model.OrderStatus.expired:
        backgroundColor = AppColors.warning.withValues(alpha: 0.1);
        textColor = AppColors.warning;
        icon = Icons.access_time;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: textColor),
          const SizedBox(width: 4),
          Text(
            _formatStatus(status),
            style: AppTextStyles.bodySmall.copyWith(
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatStatus(order_model.OrderStatus status) {
    switch (status) {
      case order_model.OrderStatus.pending:
        return 'Pending Payment';
      case order_model.OrderStatus.confirmed:
        return 'Confirmed Payment';
      case order_model.OrderStatus.to_ship:
        return 'Processing';
      case order_model.OrderStatus.shipping:
        return 'Shipping';
      case order_model.OrderStatus.delivered:
        return 'Completed';
      case order_model.OrderStatus.cancelled:
        return 'Cancelled';
      case order_model.OrderStatus.refunded:
        return 'Refunded';
      case order_model.OrderStatus.payment_failed:
        return 'Payment Failed';
      case order_model.OrderStatus.expired:
        return 'Expired Payment';
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  bool _canReorder(order_model.OrderStatus status) {
    return status == order_model.OrderStatus.delivered ||
        status == order_model.OrderStatus.expired;
  }

  bool _canCancelOrder(order_model.Order order) {
    // Can cancel if order is pending, confirmed, or to_ship (not yet shipping)
    return order.status == order_model.OrderStatus.pending ||
        order.status == order_model.OrderStatus.confirmed ||
        order.status == order_model.OrderStatus.to_ship;
  }

  bool _canResumePayment(order_model.Order order) {
    // Can only resume payment if:
    // 1. Order status is pending
    // 2. Order is not expired
    // 3. Order has a checkout URL
    return order.status == order_model.OrderStatus.pending &&
        order.paymongo.checkoutUrl != null &&
        order.paymongo.checkoutUrl!.isNotEmpty;
  }

  void _viewOrderDetails(order_model.Order order) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => OrderDetailsPage(order: order)),
    );
  }

  void _reorderItems(order_model.Order order) async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    bool success = false;

    try {
      final cartService = CartService();

      // Get all current cart items to deselect them
      final currentCartItems = await cartService.getCartItems();

      // Deselect all current cart items
      if (currentCartItems.isNotEmpty) {
        final Map<String, bool> itemSelections = {};
        for (var item in currentCartItems) {
          itemSelections[item.cartItemId] = false;
        }
        await cartService.batchUpdateItemSelections(itemSelections);
      }

      // Add each order item to the cart
      for (var orderItem in order.items) {
        await cartService.addToCart(
          productId: orderItem.productId,
          quantity: orderItem.quantity,
          variationId: orderItem.variationId,
        );
      }

      // Mark cart as stale to trigger refresh
      CartPage.markCartAsStale();
      
      success = true;
    } catch (e) {
      AppLogger.d('Error reordering items: $e');
      success = false;
    } finally {
      // Always dismiss the loading dialog
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      // Handle post-dialog actions only when mounted
      if (mounted) {
        if (success) {
          // Show success message before navigating
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${order.items.length} items added to cart'),
              backgroundColor: AppColors.success,
              duration: const Duration(seconds: 2),
            ),
          );

          // Navigate to cart page
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const CartPage()),
          );
        } else {
          // Show error message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to reorder items. Please try again.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  void _resumePayment(order_model.Order order) async {
    if (!_canResumePayment(order)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment cannot be resumed for this order'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final checkoutUrl = order.paymongo.checkoutUrl!;
    AppLogger.d(
      'Resuming payment for order ${order.orderId} with URL: $checkoutUrl',
    );

    try {
      if (kIsWeb) {
        // For web, open in a new tab
        final uri = Uri.parse(checkoutUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);

          // Show a dialog to inform the user
          if (mounted) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                title: Row(
                  children: [
                    Icon(Icons.payment, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text('Payment Resumed'),
                  ],
                ),
                content: Text(
                  'Your payment page has been opened in a new tab. Please complete your payment and return to this page.',
                  style: AppTextStyles.bodyMedium,
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'OK',
                      style: TextStyle(color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            );
          }
        }
      } else {
        // For mobile, use WebView
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PaymongoWebViewPage(
                checkoutUrl: checkoutUrl,
                successUrl: 'https://dentpal-store.web.app/payment-success',
                cancelUrl: 'https://dentpal-store.web.app/payment-failed',
                onPaymentComplete: (isSuccess, orderId) {
                  AppLogger.d(
                    'Payment resumed completed. Success: $isSuccess, Order ID: $orderId',
                  );

                  if (isSuccess) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Payment completed successfully!'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                    // Refresh orders to show updated status
                    _refreshOrders();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Payment was cancelled or failed'),
                        backgroundColor: AppColors.warning,
                      ),
                    );
                  }
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      AppLogger.d('Error resuming payment: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to resume payment. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _cancelOrder(order_model.Order order) async {
    if (!_canCancelOrder(order)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('This order cannot be cancelled'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // Show cancellation reason dialog
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => _CancelOrderDialog(),
    );

    if (result == null) return; // User dismissed the dialog
    if (!context.mounted) return;

    final reason = result['reason']!;
    final customReason = result['customReason'];

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    bool success = false;

    try {
      // Build cancellation note
      final note = customReason != null && customReason.isNotEmpty
          ? '$reason: $customReason'
          : reason;

      await OrderService.cancelOrder(order.orderId, reason: note);
      
      success = true;
    } catch (e) {
      AppLogger.d('Error cancelling order: $e');
      success = false;
    } finally {
      // Always dismiss the loading dialog
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      // Handle post-dialog actions only when mounted
      if (mounted) {
        if (success) {
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Order cancelled successfully'),
              backgroundColor: AppColors.success,
              duration: const Duration(seconds: 2),
            ),
          );

          // Refresh orders
          _refreshOrders();
        } else {
          // Show error message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to cancel order. Please try again.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  String _shortenStatus(String status) {
    // Shorten status text for wide web view to prevent truncation
    switch (status) {
      case 'Pending Payment':
        return 'Pending';
      case 'Confirmed Payment':
        return 'Confirmed';
      case 'Processing':
        return 'In Progress';
      case 'Shipped':
        return 'On the Way';
      case 'Completed':
        return 'Delivered';
      case 'Cancelled':
        return 'Cancelled';
      case 'Refunded':
        return 'Refunded';
      case 'Payment Failed':
        return 'Failed';
      case 'Expired Payment':
        return 'Expired';
      default:
        return status;
    }
  }
}

/// Dialog for cancelling an order with reason selection
class _CancelOrderDialog extends StatefulWidget {
  const _CancelOrderDialog();

  @override
  State<_CancelOrderDialog> createState() => _CancelOrderDialogState();
}

class _CancelOrderDialogState extends State<_CancelOrderDialog> {
  String? selectedReason;
  final TextEditingController _customReasonController = TextEditingController();
  String? errorMessage;

  final List<String> cancellationReasons = [
    'Changed my mind',
    'Found a better price elsewhere',
    'Ordered by mistake',
    'Delivery time is too long',
    'Need to change shipping address',
    'Payment issues',
    'Product no longer needed',
    'Other',
  ];

  @override
  void dispose() {
    _customReasonController.dispose();
    super.dispose();
  }

  void _handleCancel() {
    // Validate selection
    if (selectedReason == null) {
      setState(() {
        errorMessage = 'Please select a reason for cancellation.';
      });
      return;
    }

    // Validate custom reason if "Other" is selected
    if (selectedReason == 'Other' &&
        _customReasonController.text.trim().isEmpty) {
      setState(() {
        errorMessage = 'Please specify your reason for cancellation.';
      });
      return;
    }

    // Close dialog and return result - explicitly create a Map<String, String>
    final result = <String, String>{
      'reason': selectedReason!,
      if (selectedReason == 'Other')
        'customReason': _customReasonController.text.trim(),
    };

    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(Icons.cancel_outlined, color: AppColors.error),
          const SizedBox(width: 8),
          const Text('Cancel Order'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Please tell us why you want to cancel this order:',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            if (errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: AppColors.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        errorMessage!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            ...cancellationReasons.map((reason) {
              return RadioListTile<String>(
                title: Text(reason, style: AppTextStyles.bodyMedium),
                value: reason,
                groupValue: selectedReason,
                activeColor: AppColors.primary,
                onChanged: (value) {
                  setState(() {
                    selectedReason = value;
                    errorMessage = null; // Clear error when selection changes
                  });
                },
                contentPadding: EdgeInsets.zero,
                visualDensity: const VisualDensity(
                  horizontal: -4,
                  vertical: -4,
                ),
              );
            }),
            if (selectedReason == 'Other') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _customReasonController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Please specify your reason...',
                  hintStyle: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.onSurface.withValues(alpha: 0.5),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.primary),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.primary, width: 2),
                  ),
                  filled: true,
                  fillColor: AppColors.background,
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Keep Order',
            style: TextStyle(color: AppColors.onSurface.withValues(alpha: 0.6)),
          ),
        ),
        ElevatedButton(
          onPressed: _handleCancel,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: AppColors.onPrimary,
          ),
          child: const Text('Cancel Order'),
        ),
      ],
    );
  }
}
