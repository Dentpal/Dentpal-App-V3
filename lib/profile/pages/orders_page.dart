import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import '../../core/app_theme/app_text_styles.dart';
import '../../core/app_theme/ink_palette.dart';
import '../../core/app_theme/theme_utils.dart';
import '../../core/widgets/app_page_header.dart';
import '../../core/widgets/app_network_image.dart';
import '../../product/models/order_model.dart' as order_model;
import '../../product/pages/paymongo_webview_page.dart';
import '../../product/pages/cart_page.dart';
import '../../product/services/cart_service.dart';
import '../../product/widgets/loading_skeletons.dart';
import '../../utils/app_logger.dart';
import '../../utils/currency_formatter.dart';
import '../services/order_service.dart';
import '../services/review_service.dart';
import 'order_details_page.dart';
import 'add_review_page.dart';

/// The buyer's orders.
///
/// Follows the DentPal marketplace design: the live order takes the top of the
/// screen with a progress rail, because "where is my delivery" is the only
/// question anyone opens this tab to ask. Everything below it is history, and
/// history exists mainly to be searched, tracked or repeated.
class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  List<order_model.Order> orders = [];
  List<order_model.Order> filteredOrders = [];
  bool isLoading = true;
  String? error;
  String? selectedTabFilter; // null = the "All" pill
  // Shipping-method sub-filter under "To Receive": null = All, else one of
  // 'standard' | 'express' | 'pickup' | 'sameday'.
  String? _selectedMethod;
  final TextEditingController _searchController = TextEditingController();
  String searchQuery = '';
  Set<String> _reviewedOrderIds = {};

  /// Live orders feed.
  ///
  /// Held so it can be cancelled: this used to call `.listen()` and drop the
  /// subscription on the floor, so every pull-to-refresh added another listener
  /// and every one of them outlived the page — the disposed screen kept being
  /// woken by Firestore for the rest of the session.
  StreamSubscription<List<order_model.Order>>? _ordersSubscription;

  // Consolidated lifecycle filter groups (keys align with the pill order after
  // "All"). "To Receive" holds in-transit orders and carries the
  // shipping-method sub-pills (Standard/Express/Pickup/Same Day).
  final Map<String, List<order_model.OrderStatus>> tabGroups = {
    'processing': [
      order_model.OrderStatus.pending,
      order_model.OrderStatus.confirmed,
      order_model.OrderStatus.to_ship,
    ],
    'to_receive': [order_model.OrderStatus.shipping],
    'delivered': [order_model.OrderStatus.delivered],
    'completed': [order_model.OrderStatus.completed],
    'returns_cancellations': [
      order_model.OrderStatus.return_requested,
      order_model.OrderStatus.return_approved,
      order_model.OrderStatus.return_rejected,
      order_model.OrderStatus.returned,
      order_model.OrderStatus.cancelled,
    ],
  };

  /// Filter labels for display (index 0 is "All"; the rest map to [tabGroups]).
  final List<String> tabLabels = [
    'All',
    'Processing',
    'To Receive',
    'Delivered',
    'Completed',
    'Returns',
  ];

  /// Shipping-method sub-filters shown under "To Receive". `null` key = All.
  static const List<(String?, String)> _methodSubTabs = [
    (null, 'All'),
    ('standard', 'Standard'),
    ('express', 'Express'),
    ('pickup', 'Pickup'),
    ('sameday', 'Same Day'),
  ];

  /// Orders currently in the "To Receive" stage (used for the method sub-tabs).
  List<order_model.Order> get _toReceiveOrders =>
      orders.where((o) => tabGroups['to_receive']!.contains(o.status)).toList();

  /// The order the hero card tracks: the most recent one still in flight.
  ///
  /// Only shown on the unfiltered, unsearched list — once the buyer is looking
  /// for something specific, a card pinned to the top is in the way.
  order_model.Order? get _activeOrder {
    if (selectedTabFilter != null || searchQuery.isNotEmpty) return null;
    for (final o in orders) {
      if (_liveStatuses.contains(o.status)) return o;
    }
    return null;
  }

  static const Set<order_model.OrderStatus> _liveStatuses = {
    order_model.OrderStatus.pending,
    order_model.OrderStatus.confirmed,
    order_model.OrderStatus.to_ship,
    order_model.OrderStatus.shipping,
  };

  @override
  void initState() {
    super.initState();
    _initializeOrdersStream();
  }

  @override
  void dispose() {
    _ordersSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _initializeOrdersStream() {
    try {
      // Paint whatever this session already knows, and only show the loading
      // state when there is genuinely nothing to show. The stream below
      // replaces it as soon as the first snapshot arrives.
      final cached = OrderService.cachedOrders;

      setState(() {
        error = null;
        if (cached != null) {
          orders = cached;
          _applyFilter();
          isLoading = false;
        } else {
          isLoading = true;
        }
      });

      // Replace any previous subscription rather than stacking on top of it.
      _ordersSubscription?.cancel();
      _ordersSubscription = OrderService.getUserOrdersStream().listen(
        (fetchedOrders) {
          if (mounted) {
            setState(() {
              orders = fetchedOrders;
              _applyFilter();
              isLoading = false;
            });
            _loadReviewedOrders();
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

  Future<void> _loadReviewedOrders() async {
    final reviewed = await ReviewService.getReviewedOrderIds();
    if (mounted) {
      setState(() => _reviewedOrderIds = reviewed);
    }
  }

  /// Whether any seller in [order] uses the shipping-method sub-tab [methodKey].
  bool _orderUsesMethod(order_model.Order order, String methodKey) =>
      order.usesShippingMethod(methodKey);

  void _applyFilter() {
    List<order_model.Order> result = orders;

    // Apply lifecycle group filter.
    if (selectedTabFilter != null) {
      final statusesInGroup = tabGroups[selectedTabFilter];
      if (statusesInGroup != null) {
        result = result
            .where((o) => statusesInGroup.contains(o.status))
            .toList();

        // Under "To Receive", narrow to the selected shipping method (if any).
        if (selectedTabFilter == 'to_receive' && _selectedMethod != null) {
          result = result
              .where((o) => _orderUsesMethod(o, _selectedMethod!))
              .toList();
        }
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

  void _onFilterChanged(String? tabKey) {
    setState(() {
      selectedTabFilter = tabKey;
      // Reset the method sub-filter when switching top-level filters.
      _selectedMethod = null;
      _applyFilter();
    });
  }

  void _onMethodChanged(String? methodKey) {
    setState(() {
      _selectedMethod = methodKey;
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

  // ── Palette ──────────────────────────────────────────────────────────────

  InkPalette get ink => InkPalette.of(context);

  /// Destructive red. [InkPalette] reserves amber for urgency, so danger needs
  /// its own tone that still reads in both themes.
  Color get _danger =>
      ink.isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);

  Color get _muted => ink.text.withValues(alpha: 0.6);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ink.bg,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppLayout.maxContentWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refreshOrders,
                    color: ink.emerald,
                    backgroundColor: ink.surface,
                    child: _buildBody(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return AppPageHeader(
      title: 'Orders',
      // Same shape as every other page: the screen's name, then one line of
      // state under it. This count used to sit in the far corner instead.
      subtitle: orders.isEmpty
          ? 'No orders yet'
          : '${orders.length} order${orders.length == 1 ? '' : 's'}',
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSearchField(),
          const SizedBox(height: 14),
          _buildFilterPills(),
          if (selectedTabFilter == 'to_receive') ...[
            const SizedBox(height: 10),
            _buildMethodSubTabs(),
          ],
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
              onChanged: _onSearchChanged,
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
                hintText: 'Search order number or item…',
                hintStyle: AppTextStyles.bodyMedium.copyWith(
                  color: ink.text.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
          if (searchQuery.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchController.clear();
                _onSearchChanged('');
              },
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

  /// Lifecycle filters, as pills with live counts.
  ///
  /// These were tabs, which forced every label onto one scrolling rail with an
  /// underline; pills carry a count without crowding and match the rest of the
  /// marketplace chrome.
  Widget _buildFilterPills() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < tabLabels.length; index++) ...[
            _buildPill(
              label: tabLabels[index],
              count: _lifecycleCount(index),
              selected: selectedTabFilter == _filterKeyAt(index),
              onTap: () => _onFilterChanged(_filterKeyAt(index)),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  /// Group key behind pill [index]; null for "All", which filters nothing.
  String? _filterKeyAt(int index) =>
      index == 0 ? null : tabGroups.keys.elementAt(index - 1);

  int _lifecycleCount(int index) {
    final key = _filterKeyAt(index);
    if (key == null) return orders.length;
    final statuses = tabGroups[key]!;
    return orders.where((order) => statuses.contains(order.status)).length;
  }

  /// Shipping-method sub-filters shown under "To Receive":
  /// All · Standard · Express · Pickup · Same Day, with live counts.
  Widget _buildMethodSubTabs() {
    final toReceive = _toReceiveOrders;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final m in _methodSubTabs) ...[
            _buildPill(
              label: m.$2,
              count: m.$1 == null
                  ? toReceive.length
                  : toReceive.where((o) => _orderUsesMethod(o, m.$1!)).length,
              selected: _selectedMethod == m.$1,
              onTap: () => _onMethodChanged(m.$1),
              small: true,
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildPill({
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
    bool small = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(
          horizontal: small ? 14 : 16,
          vertical: small ? 7 : 9,
        ),
        decoration: BoxDecoration(
          color: selected ? ink.emerald : ink.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: selected ? ink.emerald : ink.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppTextStyles.bodyMedium.copyWith(
                color: selected
                    ? ink.onEmerald
                    : ink.text.withValues(alpha: 0.8),
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: small ? 12.5 : 13.5,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              constraints: const BoxConstraints(minWidth: 20),
              decoration: BoxDecoration(
                color: selected
                    ? ink.onEmerald.withValues(alpha: 0.2)
                    : ink.text.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                textAlign: TextAlign.center,
                style: AppTextStyles.labelSmall.copyWith(
                  fontFamily: AppTextStyles.secondaryFont,
                  color: selected
                      ? ink.onEmerald
                      : ink.text.withValues(alpha: count == 0 ? 0.4 : 0.7),
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Body ─────────────────────────────────────────────────────────────────

  Widget _buildBody() {
    if (isLoading) return const OrdersSkeleton();

    if (error != null) {
      return _buildStateMessage(
        icon: Icons.error_outline,
        tone: _danger,
        title: 'Something went wrong',
        detail: error!,
        action: _buildFilledButton(
          label: 'Retry',
          icon: Icons.refresh,
          onTap: _initializeOrdersStream,
        ),
      );
    }

    if (orders.isEmpty) {
      return _buildStateMessage(
        icon: Icons.receipt_long_outlined,
        tone: ink.emerald,
        title: 'No orders yet',
        detail: 'Your orders will appear here once you make a purchase.',
      );
    }

    if (filteredOrders.isEmpty) {
      return _buildStateMessage(
        icon: Icons.filter_list_off,
        tone: ink.text.withValues(alpha: 0.5),
        title: searchQuery.isNotEmpty ? 'No matches' : 'Nothing here yet',
        detail: searchQuery.isNotEmpty
            ? 'No order number or item matches "$searchQuery".'
            : 'No orders are in this stage right now.',
      );
    }

    final active = _activeOrder;
    // The hero already tells this order's story in full; repeating it two rows
    // down would just be the same card twice.
    final history = filteredOrders
        .where((o) => o.orderId != active?.orderId)
        .toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppLayout.gutter,
        8,
        AppLayout.gutter,
        28,
      ),
      children: [
        if (active != null) ...[
          _buildActiveOrderCard(active),
          const SizedBox(height: 26),
        ],
        if (history.isNotEmpty) ...[
          Text(
            active != null ? 'Past orders' : _historyHeading(),
            style: AppTextStyles.titleMedium.copyWith(
              color: ink.text,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 14),
          for (final order in history) _buildOrderCard(order),
        ],
      ],
    );
  }

  String _historyHeading() {
    if (searchQuery.isNotEmpty) {
      return '${filteredOrders.length} result'
          '${filteredOrders.length == 1 ? '' : 's'}';
    }
    if (selectedTabFilter == null) return 'All orders';
    final index = tabGroups.keys.toList().indexOf(selectedTabFilter!) + 1;
    return tabLabels[index];
  }

  Widget _buildStateMessage({
    required IconData icon,
    required Color tone,
    required String title,
    required String detail,
    Widget? action,
  }) {
    // Scrollable so pull-to-refresh still works when there is nothing to show,
    // and centred against the space it actually gets.
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 40, 32, 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: tone.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 30, color: tone),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.titleMedium.copyWith(
                        color: ink.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      detail,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: _muted,
                        fontSize: 13.5,
                        height: 1.45,
                      ),
                    ),
                    if (action != null) ...[const SizedBox(height: 22), action],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Live order ───────────────────────────────────────────────────────────

  /// Ordered stops every order passes through, for the hero's rail.
  static const List<String> _railSteps = [
    'Placed',
    'Packed',
    'Shipped',
    'Arrived',
  ];

  /// Which stop [status] has reached, 0-based.
  int _railIndex(order_model.OrderStatus status) {
    switch (status) {
      case order_model.OrderStatus.pending:
        return 0;
      case order_model.OrderStatus.confirmed:
      case order_model.OrderStatus.to_ship:
        return 1;
      case order_model.OrderStatus.shipping:
        return 2;
      case order_model.OrderStatus.delivered:
      case order_model.OrderStatus.completed:
        return 3;
      default:
        return 0;
    }
  }

  /// The one line that answers "where is my order".
  String _heroHeadline(order_model.Order order) {
    switch (order.status) {
      case order_model.OrderStatus.pending:
        return 'Waiting for payment';
      case order_model.OrderStatus.confirmed:
        return 'Payment confirmed';
      case order_model.OrderStatus.to_ship:
        return 'Being packed';
      case order_model.OrderStatus.shipping:
        return order.hasSameDayShipping ? 'Arriving today' : 'On the way';
      default:
        return order.status.displayName;
    }
  }

  Widget _buildActiveOrderCard(order_model.Order order) {
    final current = _railIndex(order.status);
    final tone = _statusTone(order.status);

    // Material rather than a bare GestureDetector: the whole card is the tap
    // target for tracking, so it should show a press like every other control.
    return Material(
      color: ink.surface,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () => _viewOrderDetails(order),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: ink.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _buildBadge(
                          label: _formatStatus(order.status),
                          icon: _statusIcon(order.status),
                          tone: tone,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: _buildOrderIdLabel(order)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _heroHeadline(order),
                      style: AppTextStyles.headlineSmall.copyWith(
                        color: ink.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 25,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${order.items.length} item'
                      '${order.items.length == 1 ? '' : 's'} · '
                      '${CurrencyFormatter.formatWithPeso(order.summary.total)}',
                      style: AppTextStyles.bodySmall.copyWith(
                        fontFamily: AppTextStyles.secondaryFont,
                        color: _muted,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildProgressRail(current),
                  ],
                ),
              ),
              _buildHeroFooter(order),
            ],
          ),
        ),
      ),
    );
  }

  /// Dots fill left to right; the current one carries a ring so "where it is
  /// now" reads at a glance without counting.
  Widget _buildProgressRail(int current) {
    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < _railSteps.length; i++) ...[
              _buildRailDot(done: i < current, active: i == current),
              if (i < _railSteps.length - 1)
                Expanded(
                  child: Container(
                    height: 2,
                    color: i < current
                        ? ink.emerald
                        : ink.text.withValues(alpha: 0.12),
                  ),
                ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < _railSteps.length; i++)
              SizedBox(
                width: 56,
                child: Text(
                  _railSteps[i],
                  textAlign: i == 0
                      ? TextAlign.start
                      : (i == _railSteps.length - 1
                            ? TextAlign.end
                            : TextAlign.center),
                  style: AppTextStyles.labelSmall.copyWith(
                    color: i <= current
                        ? ink.text
                        : ink.text.withValues(alpha: 0.4),
                    fontWeight: i <= current
                        ? FontWeight.w700
                        : FontWeight.w500,
                    fontSize: 10.5,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildRailDot({required bool done, required bool active}) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: done || active ? ink.emerald : ink.bg,
        shape: BoxShape.circle,
        border: Border.all(
          color: done || active ? ink.emerald : ink.text.withValues(alpha: 0.2),
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: ink.emerald.withValues(alpha: 0.22),
                  blurRadius: 0,
                  spreadRadius: 4,
                ),
              ]
            : null,
      ),
      child: done ? Icon(Icons.check, size: 11, color: ink.onEmerald) : null,
    );
  }

  /// The tinted strip along the bottom of the hero — the live line, and the
  /// invitation to open tracking.
  Widget _buildHeroFooter(order_model.Order order) {
    final sameDay = order.hasSameDayShipping;
    final label = sameDay
        ? _sameDayShortLabel(order.lalamoveStatus)
        : (order.status == order_model.OrderStatus.shipping
              ? 'Track your package'
              : 'View order details');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: ink.emerald.withValues(alpha: ink.isDark ? 0.12 : 0.09),
        border: Border(top: BorderSide(color: ink.border)),
      ),
      child: Row(
        children: [
          Icon(
            sameDay ? Icons.motorcycle_outlined : Icons.place_outlined,
            size: 16,
            color: ink.emerald,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: ink.emerald,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(Icons.chevron_right, size: 18, color: ink.emerald),
        ],
      ),
    );
  }

  /// Short phase label for a Same Day order. A null status means the seller has
  /// not booked the rider yet — the parcel is still being prepared.
  String _sameDayShortLabel(String? status) {
    final raw = (status ?? '').toUpperCase();
    if (raw.isEmpty) return 'Same Day · preparing your parcel';
    switch (raw) {
      case 'ASSIGNING_DRIVER':
        return 'Same Day · finding a rider';
      case 'ON_GOING':
        return 'Same Day · rider heading to store';
      case 'PICKED_UP':
        return 'Same Day · rider is on the way';
      case 'COMPLETED':
        return 'Same Day · delivered';
      case 'CANCELED':
      case 'REJECTED':
      case 'EXPIRED':
        return 'Same Day · delivery unavailable';
      default:
        return 'Same Day delivery';
    }
  }

  // ── History cards ────────────────────────────────────────────────────────

  Widget _buildOrderCard(order_model.Order order) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildOrderIdLabel(order),
                      const SizedBox(height: 4),
                      Text(
                        _formatDate(order.createdAt),
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: ink.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${order.items.length} item'
                        '${order.items.length == 1 ? '' : 's'} · '
                        '${CurrencyFormatter.formatWithPeso(order.summary.total)}',
                        style: AppTextStyles.bodySmall.copyWith(
                          fontFamily: AppTextStyles.secondaryFont,
                          color: _muted,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildBadge(
                      label: _formatStatus(order.status),
                      icon: _statusIcon(order.status),
                      tone: _statusTone(order.status),
                    ),
                    if (order.hasSameDayShipping) ...[
                      const SizedBox(height: 6),
                      _buildBadge(
                        label: 'Same Day',
                        icon: Icons.motorcycle_outlined,
                        tone: ink.emeraldSoft,
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildItemStrip(order),
            const SizedBox(height: 14),
            _buildCardActions(order),
          ],
        ),
      ),
    );
  }

  /// Order number, set in the numeric face so it reads as an identifier rather
  /// than prose.
  Widget _buildOrderIdLabel(order_model.Order order) {
    final id = order.orderId.length > 8
        ? order.orderId.substring(0, 8)
        : order.orderId;
    return Text(
      '#${id.toUpperCase()}',
      style: AppTextStyles.bodySmall.copyWith(
        fontFamily: AppTextStyles.secondaryFont,
        color: ink.text.withValues(alpha: 0.5),
        fontSize: 11.5,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w600,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// What was bought, as a row of thumbnails — faster to recognise than a list
  /// of product names, and it keeps the card to a fixed height.
  Widget _buildItemStrip(order_model.Order order) {
    const maxShown = 3;
    final shown = order.items.take(maxShown).toList();
    final extra = order.items.length - shown.length;

    return Row(
      children: [
        for (final item in shown) ...[
          Container(
            width: 44,
            height: 44,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: ink.surfaceHigh,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: ink.border),
            ),
            child: item.productImage.isNotEmpty
                ? AppNetworkImage(
                    url: item.productImage,
                    width: 44,
                    height: 44,
                    backgroundColor: ink.surfaceHigh,
                    errorIconSize: 18,
                  )
                : Icon(
                    Icons.inventory_2_outlined,
                    size: 18,
                    color: ink.text.withValues(alpha: 0.4),
                  ),
          ),
          const SizedBox(width: 8),
        ],
        if (extra > 0)
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ink.surfaceHigh,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: ink.border),
            ),
            child: Text(
              '+$extra',
              style: AppTextStyles.bodySmall.copyWith(
                fontFamily: AppTextStyles.secondaryFont,
                color: _muted,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        const SizedBox(width: 4),
        // Names the first item so the row is legible without recognising the
        // photography — and readable to a screen reader.
        Expanded(
          child: Text(
            order.items.isNotEmpty ? order.items.first.productName : '',
            textAlign: TextAlign.end,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall.copyWith(
              color: _muted,
              fontSize: 12,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  /// "View details" always, plus the one action this stage actually affords.
  Widget _buildCardActions(order_model.Order order) {
    final status = order.status;
    Widget? primary;

    if (status == order_model.OrderStatus.delivered) {
      primary = OrderService.isEligibleForReturn(order)['eligible'] == true
          ? _buildFilledButton(
              label: 'Return',
              icon: Icons.assignment_return_outlined,
              color: ink.amber,
              onColor: ink.onAmber,
              onTap: () => _requestReturn(order),
            )
          : _buildFilledButton(
              label: 'Complete',
              icon: Icons.check_circle_outline,
              onTap: () => _completeOrder(order),
            );
    } else if (status == order_model.OrderStatus.completed) {
      primary = _buildReviewButton(order);
    } else if (status == order_model.OrderStatus.return_requested ||
        status == order_model.OrderStatus.return_approved ||
        status == order_model.OrderStatus.return_rejected ||
        status == order_model.OrderStatus.returned ||
        status == order_model.OrderStatus.cancelled) {
      primary = _buildFilledButton(
        label: 'Reorder',
        icon: Icons.refresh,
        onTap: () => _reorderItems(order),
      );
    } else if (_canResumePayment(order)) {
      // Offered ahead of cancelling: an unpaid order is far more likely to be
      // finished than abandoned.
      primary = _buildFilledButton(
        label: 'Resume payment',
        icon: Icons.payment,
        color: ink.amber,
        onColor: ink.onAmber,
        onTap: () => _resumePayment(order),
      );
    } else if (_canCancelOrder(order)) {
      primary = _buildOutlinedButton(
        label: 'Cancel order',
        icon: Icons.close,
        tone: _danger,
        onTap: () => _cancelOrder(order),
      );
    }

    return Row(
      children: [
        Expanded(
          child: _buildOutlinedButton(
            label: 'View details',
            icon: Icons.receipt_long_outlined,
            onTap: () => _viewOrderDetails(order),
          ),
        ),
        if (primary != null) ...[
          const SizedBox(width: 10),
          Expanded(child: primary),
        ],
      ],
    );
  }

  Widget _buildReviewButton(order_model.Order order) {
    if (_reviewedOrderIds.contains(order.orderId)) {
      return _buildOutlinedButton(
        label: 'Reviewed',
        icon: Icons.check_circle_outline,
        tone: ink.text.withValues(alpha: 0.4),
        onTap: null,
      );
    }
    return _buildFilledButton(
      label: 'Add review',
      icon: Icons.star_outline,
      onTap: () => _addReview(order),
    );
  }

  // ── Small parts ──────────────────────────────────────────────────────────

  Widget _buildBadge({
    required String label,
    required IconData icon,
    required Color tone,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: ink.isDark ? 0.16 : 0.11),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tone.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: tone),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: tone,
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilledButton({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
    Color? color,
    Color? onColor,
  }) {
    final background = color ?? ink.emerald;
    return SizedBox(
      height: 40,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.buttonMedium.copyWith(fontSize: 13),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: onColor ?? ink.onEmerald,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildOutlinedButton({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
    Color? tone,
  }) {
    final foreground = tone ?? ink.text;
    return SizedBox(
      height: 40,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.buttonMedium.copyWith(fontSize: 13),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          disabledForegroundColor: foreground,
          backgroundColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          side: BorderSide(
            color: tone == null ? ink.border : tone.withValues(alpha: 0.45),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  void _showSnack(String message, {Color? tone, IconData? icon}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 8),
            ],
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: tone ?? ink.emerald,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── Status vocabulary ────────────────────────────────────────────────────

  Color _statusTone(order_model.OrderStatus status) {
    switch (status) {
      case order_model.OrderStatus.pending:
        return ink.amber;
      case order_model.OrderStatus.confirmed:
      case order_model.OrderStatus.delivered:
      case order_model.OrderStatus.completed:
        return ink.emerald;
      case order_model.OrderStatus.to_ship:
      case order_model.OrderStatus.shipping:
      case order_model.OrderStatus.return_approved:
        return ink.emeraldSoft;
      case order_model.OrderStatus.cancelled:
      case order_model.OrderStatus.payment_failed:
      case order_model.OrderStatus.failed_delivery:
      case order_model.OrderStatus.return_rejected:
        return _danger;
      case order_model.OrderStatus.expired:
      case order_model.OrderStatus.return_requested:
        return ink.amber;
      case order_model.OrderStatus.refunded:
      case order_model.OrderStatus.returned:
        return ink.text.withValues(alpha: 0.55);
    }
  }

  IconData _statusIcon(order_model.OrderStatus status) {
    switch (status) {
      case order_model.OrderStatus.pending:
        return Icons.schedule;
      case order_model.OrderStatus.confirmed:
        return Icons.check_circle_outline;
      case order_model.OrderStatus.to_ship:
        return Icons.inventory_2_outlined;
      case order_model.OrderStatus.shipping:
        return Icons.local_shipping_outlined;
      case order_model.OrderStatus.delivered:
        return Icons.check_circle;
      case order_model.OrderStatus.completed:
        return Icons.verified_outlined;
      case order_model.OrderStatus.cancelled:
        return Icons.cancel_outlined;
      case order_model.OrderStatus.refunded:
        return Icons.replay;
      case order_model.OrderStatus.payment_failed:
        return Icons.error_outline;
      case order_model.OrderStatus.expired:
        return Icons.timer_off_outlined;
      case order_model.OrderStatus.failed_delivery:
        return Icons.report_gmailerrorred_outlined;
      case order_model.OrderStatus.return_requested:
        return Icons.assignment_return_outlined;
      case order_model.OrderStatus.return_approved:
        return Icons.assignment_turned_in_outlined;
      case order_model.OrderStatus.return_rejected:
        return Icons.assignment_late_outlined;
      case order_model.OrderStatus.returned:
        return Icons.assignment_returned_outlined;
    }
  }

  String _formatStatus(order_model.OrderStatus status) {
    switch (status) {
      case order_model.OrderStatus.pending:
        return 'Pending payment';
      case order_model.OrderStatus.confirmed:
        return 'Paid';
      case order_model.OrderStatus.to_ship:
        return 'Processing';
      case order_model.OrderStatus.shipping:
        return 'Shipping';
      case order_model.OrderStatus.delivered:
        return 'Delivered';
      case order_model.OrderStatus.completed:
        return 'Completed';
      case order_model.OrderStatus.cancelled:
        return 'Cancelled';
      case order_model.OrderStatus.refunded:
        return 'Refunded';
      case order_model.OrderStatus.payment_failed:
        return 'Payment failed';
      case order_model.OrderStatus.expired:
        return 'Expired';
      case order_model.OrderStatus.failed_delivery:
        return 'Delivery failed';
      case order_model.OrderStatus.return_requested:
        return 'Return requested';
      case order_model.OrderStatus.return_approved:
        return 'Return approved';
      case order_model.OrderStatus.return_rejected:
        return 'Return rejected';
      case order_model.OrderStatus.returned:
        return 'Returned';
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

  // ── Actions ──────────────────────────────────────────────────────────────

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
      builder: (context) =>
          Center(child: CircularProgressIndicator(color: ink.emerald)),
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
          _showSnack(
            '${order.items.length} items added to cart',
            icon: Icons.shopping_cart_outlined,
          );

          // Navigate to cart page
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const CartPage()),
          );
        } else {
          _showSnack(
            'Failed to reorder items. Please try again.',
            tone: _danger,
            icon: Icons.error_outline,
          );
        }
      }
    }
  }

  void _resumePayment(order_model.Order order) async {
    if (!_canResumePayment(order)) {
      _showSnack(
        'Payment cannot be resumed for this order',
        tone: _danger,
        icon: Icons.error_outline,
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
                backgroundColor: ink.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                title: Row(
                  children: [
                    Icon(Icons.payment, color: ink.emerald),
                    const SizedBox(width: 8),
                    Text('Payment resumed', style: TextStyle(color: ink.text)),
                  ],
                ),
                content: Text(
                  'Your payment page has been opened in a new tab. Please complete your payment and return to this page.',
                  style: AppTextStyles.bodyMedium.copyWith(color: _muted),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('OK', style: TextStyle(color: ink.emerald)),
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
                    _showSnack(
                      'Payment completed successfully!',
                      icon: Icons.check_circle_outline,
                    );
                    // Refresh orders to show updated status
                    _refreshOrders();
                  } else {
                    _showSnack(
                      'Payment was cancelled or failed',
                      tone: ink.amber,
                      icon: Icons.info_outline,
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
        _showSnack(
          'Failed to resume payment. Please try again.',
          tone: _danger,
          icon: Icons.error_outline,
        );
      }
    }
  }

  void _cancelOrder(order_model.Order order) async {
    if (!_canCancelOrder(order)) {
      _showSnack(
        'This order cannot be cancelled',
        tone: _danger,
        icon: Icons.error_outline,
      );
      return;
    }

    // Show cancellation reason dialog
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => const CancelOrderDialog(),
    );

    if (result == null) return; // User dismissed the dialog
    if (!mounted) return;

    final reason = result['reason']!;
    final customReason = result['customReason'];

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          Center(child: CircularProgressIndicator(color: ink.emerald)),
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
          _showSnack(
            'Order cancelled successfully',
            icon: Icons.check_circle_outline,
          );

          // Refresh orders
          _refreshOrders();
        } else {
          _showSnack(
            'Failed to cancel order. Please try again.',
            tone: _danger,
            icon: Icons.error_outline,
          );
        }
      }
    }
  }

  void _completeOrder(order_model.Order order) async {
    // Confirm completion
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ink.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.check_circle_outline, color: ink.emerald),
            const SizedBox(width: 8),
            Text('Complete order', style: TextStyle(color: ink.text)),
          ],
        ),
        content: Text(
          'Mark this order as completed? This will deduct the stock count for these items.',
          style: AppTextStyles.bodyMedium.copyWith(color: _muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: _muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: ink.emerald,
              foregroundColor: ink.onEmerald,
              elevation: 0,
            ),
            child: const Text('Complete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          Center(child: CircularProgressIndicator(color: ink.emerald)),
    );

    bool success = false;

    try {
      await OrderService.markOrderComplete(order.orderId);
      success = true;
    } catch (e) {
      AppLogger.d('Error completing order: $e');
      success = false;
    } finally {
      // Always dismiss the loading dialog
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      // Handle post-dialog actions only when mounted
      if (mounted) {
        if (success) {
          _showSnack(
            'Order completed successfully',
            icon: Icons.check_circle_outline,
          );

          // Refresh orders
          _refreshOrders();
        } else {
          _showSnack(
            'Failed to complete order. Please try again.',
            tone: _danger,
            icon: Icons.error_outline,
          );
        }
      }
    }
  }

  void _requestReturn(order_model.Order order) async {
    // Check eligibility
    final eligibility = OrderService.isEligibleForReturn(order);
    if (eligibility['eligible'] != true) {
      _showSnack(
        eligibility['reason'] ?? 'Cannot request return for this order',
        tone: _danger,
        icon: Icons.error_outline,
      );
      return;
    }

    // Navigate to order details page which has the return request functionality
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => OrderDetailsPage(order: order)),
    );
  }

  void _addReview(order_model.Order order) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddReviewPage(order: order)),
    );
    if (result == true && mounted) {
      setState(() => _reviewedOrderIds = {..._reviewedOrderIds, order.orderId});
      _loadReviewedOrders();
      _showSnack('Thanks for your review!', icon: Icons.star_outline);
    }
  }
}

/// Dialog for cancelling an order with reason selection.
///
/// Shared with [OrderDetailsPage], which offers the same action against the
/// same order — one list of reasons, one validation rule.
class CancelOrderDialog extends StatefulWidget {
  const CancelOrderDialog({super.key});

  @override
  State<CancelOrderDialog> createState() => _CancelOrderDialogState();
}

class _CancelOrderDialogState extends State<CancelOrderDialog> {
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
    final ink = InkPalette.of(context);
    final danger = ink.isDark
        ? const Color(0xFFF87171)
        : const Color(0xFFDC2626);

    return AlertDialog(
      backgroundColor: ink.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(Icons.cancel_outlined, color: danger),
          const SizedBox(width: 8),
          Text('Cancel order', style: TextStyle(color: ink.text)),
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
                color: ink.text.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            if (errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: danger.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: danger, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        errorMessage!,
                        style: AppTextStyles.bodySmall.copyWith(color: danger),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            ...cancellationReasons.map((reason) {
              return RadioListTile<String>(
                title: Text(
                  reason,
                  style: AppTextStyles.bodyMedium.copyWith(color: ink.text),
                ),
                value: reason,
                groupValue: selectedReason,
                activeColor: ink.emerald,
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
                style: AppTextStyles.bodyMedium.copyWith(color: ink.text),
                cursorColor: ink.emerald,
                decoration: InputDecoration(
                  hintText: 'Please specify your reason…',
                  hintStyle: AppTextStyles.bodyMedium.copyWith(
                    color: ink.text.withValues(alpha: 0.45),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: ink.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: ink.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: ink.emerald, width: 2),
                  ),
                  filled: true,
                  fillColor: ink.surfaceHigh,
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
            'Keep order',
            style: TextStyle(color: ink.text.withValues(alpha: 0.6)),
          ),
        ),
        ElevatedButton(
          onPressed: _handleCancel,
          style: ElevatedButton.styleFrom(
            backgroundColor: danger,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          child: const Text('Cancel order'),
        ),
      ],
    );
  }
}
