import 'package:flutter/material.dart';
import '../../core/app_theme/app_colors.dart';
import '../../core/app_theme/app_text_styles.dart';
import '../../product/models/order_model.dart' as order_model;
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
    order_model.OrderStatus.processing,
    order_model.OrderStatus.shipped,
    order_model.OrderStatus.delivered,
    order_model.OrderStatus.cancelled,
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: filterOptions.length + 1, vsync: this);
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
      result = result.where((order) => order.status == selectedFilter).toList();
    }
    
    // Apply search filter
    if (searchQuery.isNotEmpty) {
      result = result.where((order) {
        final orderIdMatch = order.orderId.toLowerCase().contains(searchQuery.toLowerCase());
        final itemsMatch = order.items.any((item) => 
          item.productName.toLowerCase().contains(searchQuery.toLowerCase()));
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
      body: Column(
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
                    prefixIcon: Icon(Icons.search, color: AppColors.onSurface.withValues(alpha: 0.5)),
                    suffixIcon: searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear, color: AppColors.onSurface.withValues(alpha: 0.5)),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.onSurface.withValues(alpha: 0.2)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.primary, width: 2),
                    ),
                    filled: true,
                    fillColor: AppColors.background,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
              isScrollable: true,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.onSurface.withValues(alpha: 0.6),
              indicatorColor: AppColors.primary,
              labelStyle: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600),
              unselectedLabelStyle: AppTextStyles.bodyMedium,
              tabs: [
                Tab(text: 'All (${orders.length})'),
                ...filterOptions.map((status) {
                  final count = orders.where((order) => order.status == status).length;
                  return Tab(text: '${_formatStatus(status)} ($count)');
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
      ),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: AppColors.error,
            ),
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
                    fontFamily: 'Roboto'
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Action Buttons
            Row(
              children: [
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
                if (_canReorder(order.status))
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
                            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
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
            fontFamily: 'Roboto'
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
        backgroundColor = AppColors.warning.withValues(alpha: 0.1);
        textColor = AppColors.warning;
        icon = Icons.pending;
        break;
      case order_model.OrderStatus.confirmed:
        backgroundColor = AppColors.success.withValues(alpha: 0.1);
        textColor = AppColors.success;
        icon = Icons.check_circle_outline;
        break;
      case order_model.OrderStatus.processing:
        backgroundColor = AppColors.info.withValues(alpha: 0.1);
        textColor = AppColors.info;
        icon = Icons.autorenew;
        break;
      case order_model.OrderStatus.shipped:
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
      case order_model.OrderStatus.processing:
        return 'Processing';
      case order_model.OrderStatus.shipped:
        return 'Shipped';
      case order_model.OrderStatus.delivered:
        return 'Delivered';
      case order_model.OrderStatus.cancelled:
        return 'Cancelled';
      case order_model.OrderStatus.refunded:
        return 'Refunded';
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
    return status == order_model.OrderStatus.confirmed || 
           status == order_model.OrderStatus.delivered || 
           status == order_model.OrderStatus.cancelled;
  }

  void _viewOrderDetails(order_model.Order order) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => OrderDetailsPage(order: order),
      ),
    );
  }

  void _reorderItems(order_model.Order order) {
    // TODO: Implement reorder functionality
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Reorder functionality coming soon'),
        backgroundColor: AppColors.primary,
      ),
    );
  }
}
