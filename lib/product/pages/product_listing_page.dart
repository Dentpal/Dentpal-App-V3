import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/product_model.dart';
import '../models/order_model.dart' as order_model;
import '../models/seller_display.dart';
import '../services/product_service.dart';
import '../services/banned_seller_service.dart';
import '../services/user_service.dart';
import '../services/category_service.dart';
import '../services/click_tracking_service.dart';
import '../../core/app_theme/app_text_styles.dart';
import '../../core/app_theme/ink_palette.dart';
import '../../core/app_theme/theme_utils.dart';
import '../../core/services/nav_badge_service.dart';
import '../../core/widgets/app_shell.dart';
import 'package:dentpal/utils/app_logger.dart';
import 'package:dentpal/utils/currency_formatter.dart';
import 'package:dentpal/utils/navigation_utils.dart';
import 'categories_page.dart';
import 'product_detail_page.dart';
import '../services/product_search_service.dart';
import '../../login_page.dart';
import 'package:flutter/services.dart';
import '../../profile/pages/orders_page.dart';
import '../../profile/pages/settings/notifications_page.dart';
import '../../profile/pages/order_details_page.dart';
import '../../profile/services/address_service.dart';
import '../../profile/services/order_service.dart';
import '../../public_support_page.dart';
import 'package:dentpal/core/widgets/app_network_image.dart';
import 'package:dentpal/core/widgets/skeleton.dart';
import 'package:dentpal/core/widgets/web_footer.dart';

// Custom cache manager with web compatibility
class ProductImageCacheManager {
  static const key = 'productImageCache';

  static CacheManager get instance {
    if (kIsWeb) {
      // For web, use a simplified cache manager without persistent storage
      return DefaultCacheManager();
    } else {
      // For mobile platforms, use the full cache manager with persistence
      return CacheManager(
        Config(
          key,
          stalePeriod: const Duration(days: 1),
          maxNrOfCacheObjects: 200,
          repo: JsonCacheInfoRepository(databaseName: key),
          fileService: HttpFileService(),
        ),
      );
    }
  }
}

class ProductListingPage extends StatefulWidget {
  const ProductListingPage({super.key, this.isStandalone = false});

  // Flag to indicate if this page is used standalone (not within bottom navigation)
  final bool isStandalone;

  @override
  _ProductListingPageState createState() => _ProductListingPageState();
}

class _ProductListingPageState extends State<ProductListingPage>
    with AutomaticKeepAliveClientMixin<ProductListingPage> {
  /// Colours for the current OS brightness. Read per build so a system theme
  /// change repaints the page.
  InkPalette get ink => InkPalette.of(context);

  /// Widest the centred content column grows to.
  static const double _kMaxContentWidth = 1100;

  /// Anchors the "Dental traders" heading so a browse selection can bring the
  /// filtered results into view.
  final GlobalKey _tradersSectionKey = GlobalKey();

  double get _bannerRadius =>
      MediaQuery.of(context).size.width >= 600 ? 24 : 20;

  /// Banner art is authored at 8:3. Inset into a card, that ratio leaves a
  /// short strip on a phone, so narrow screens trade a little of the width
  /// (cropped centrally by [BoxFit.cover]) for a taller, more legible card.
  double get _bannerAspectRatio =>
      MediaQuery.of(context).size.width >= 600 ? 8 / 3 : 2.2;

  /// Width available to the content, i.e. the window minus the shell's side
  /// rail. Grids size themselves against this rather than the raw window width,
  /// or they lay out a column too many next to the rail.
  ///
  /// The rail belongs to [AppShell] now, but `MediaQuery` still reports the
  /// whole window to this page, so the subtraction is still ours to do.
  double get _contentWidth {
    final width = MediaQuery.of(context).size.width;
    return width >= Breakpoints.wide ? width - kAppShellRailWidth : width;
  }

  final ProductService _productService = ProductService();
  final UserService _userService = UserService();
  final CategoryService _categoryService = CategoryService();
  final ClickTrackingService _clickTrackingService = ClickTrackingService();
  bool _isLoading = false;
  bool _isLoadingMore = false;

  /// False until the first catalogue fetch has settled, successfully or not.
  ///
  /// Distinct from [_isLoading], which only spans the fetch itself. The first
  /// fetch is preceded by an await on the banned-seller cache, and during that
  /// window the page has no products and is not "loading" — which used to
  /// render the "No products found" empty state before anything had been
  /// asked for. Every first-run placeholder is driven off this instead.
  bool _firstLoadDone = false;
  List<String> _selectedCategories = [];
  List<String> _categories = ['All'];
  // Number of category rows currently revealed in the default view.
  // Starts at one row; each "Show more" tap reveals one additional row.
  int _visibleCategoryRows = 1;
  bool _categoryGridForceExpanded = false;
  String? _errorMessage;
  List<Product> _products = [];
  DateTime? _cacheTimestamp;
  DocumentSnapshot? _lastDocument;
  bool _hasMore = true;

  /// Products per page. The grid loads another page when the buyer reaches
  /// the last row.
  static const int _pageSize = 30;

  /// Sellers surfaced so far — kept for the "Shipped From" filter, which
  /// classifies a product by the region its seller ships from.
  Set<String> _loadedSellerIds = {};
  final ScrollController _scrollController = ScrollController();
  final PageController _bannerPageController = PageController();
  Timer? _bannerAutoScrollTimer;

  bool _isSeller = false;
  String _userFirstName = 'User';
  String?
  _userRegion; // Classified region: 'NCR' | 'Luzon' | 'Visayas' | 'Mindanao'

  StreamSubscription<User?>? _authStateSubscription;

  /// Unread count for the mobile header's bell.
  ///
  /// Owned by [NavBadgeService] rather than subscribed here: the shell's rail
  /// shows the same number, and two independent listeners on the same
  /// collection could disagree for a frame.
  int get _unreadNotifications =>
      NavBadgeService.instance.unreadNotifications.value;

  // ── Hero state ───────────────────────────────────────────────────────────
  // Most recent order still in flight, surfaced as the hero tracking row.
  StreamSubscription<List<order_model.Order>>? _ordersSubscription;
  order_model.Order? _activeOrder;

  // Deal of the day: the best currently-valid seller voucher paired with one
  // of that seller's products. Null when no seller is running a promo.
  Product? _dealProduct;
  Map<String, dynamic>? _dealVoucher;
  DateTime? _dealEndsAt;

  // Four most-clicked products, highlighted above the categories grid.
  List<Product> _popularProducts = [];
  bool _isLoadingPopular = true;

  // Active banner image URLs and target URLs loaded from Realtime Database
  List<String> _bannerImageUrls = [];
  bool _isLoadingBanner = true;
  List<String?> _bannerTargetUrls = [];
  int _currentBannerIndex = 0;

  // Cache for seller/vendor data fetched from Firestore, keyed by sellerId.
  // A null value means the document was fetched but does not exist in Firestore.
  Map<String, Map<String, dynamic>?> _sellerDataCache = {};
  Set<String> _sellerDataFetching = {};

  // Mapping between category names and IDs for filtering
  Map<String, String> _categoryNameToId = {};
  Map<String, String> _categoryIdToName = {};
  Map<String, String?> _categoryNameToImage = {};

  // Subcategory state - now grouped by category
  Map<String, List<SubCategory>> _subcategoriesByCategory = {};
  List<String> _selectedSubCategories = [];

  // Brand filter — null means no filter (show all)
  String? _selectedBrand;

  // Filter state
  String _selectedShippedFrom = 'All';

  // Filter options
  final List<String> _shippedFromOptions = [
    'All',
    'Nearest You',
    'NCR',
    'Luzon',
    'Visayas',
    'Mindanao',
  ];

  // Inline search state
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ProductSearchService _searchService = ProductSearchService();
  String _searchQuery = '';
  bool _isSearchMode = false;
  List<Product> _searchResults = [];
  List<ProductSuggestion> _searchSuggestions = [];

  /// Every active product's name/photo, built from the catalogue read the
  /// brand + popular sections already perform. Type-ahead matches against this
  /// instead of querying Firestore per keystroke, which also means it searches
  /// the whole catalogue rather than whatever window a `limit()` returned.
  List<ProductSuggestion> _catalogueIndex = [];

  /// Lowest price per product id, filled in as suggestions are shown and kept
  /// for the rest of the session.
  final Map<String, double> _suggestionPrices = {};
  final Set<String> _pricesInFlight = {};
  bool _showSearchSuggestions = false;
  bool _isSearching = false;
  bool _isLoadingMoreSearch = false;
  Timer? _searchDebounceTimer;
  SearchResult? _lastSearchResult;

  // Override to keep this page alive when navigating away
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    // Load the set of sellers that have banned the current user first;
    // _loadFirstPage will then exclude their products.
    _loadBannedSellersThenFirstPage();
    _checkSellerStatus();
    _loadUserName();
    _loadUserRegion();
    _loadActiveBanner(); // Load active banner image from Realtime Database
    _listenToAccountStreams();

    NavBadgeService.instance.unreadNotifications.addListener(
      _onUnreadNotificationsChanged,
    );

    // Add scroll listener for pagination
    _scrollController.addListener(_scrollListener);

    // Browse is a sibling tab and cannot pop a result back to this page, so it
    // drops the selection here instead.
    pendingBrowseSelection.addListener(_applyPendingBrowseSelection);

    // Tapping Home while already on Home returns to the top.
    homeReselectTick.addListener(_onHomeReselected);

    // Clean up old click tracking data (run async without waiting)
    _clickTrackingService.cleanupOldClickData();

    // Add debug log to track initialization
    AppLogger.d(
      "ProductListingPage initState called, products: ${_products.length}, timestamp: $_cacheTimestamp",
    );
  }

  /// Reads the active catalogue once and derives everything the page needs
  /// from it: the type-ahead index and the Most Popular ranking.
  ///
  /// The read is cached by [ProductService], so returning to Home costs nothing
  /// within the cache window.
  Future<void> _loadCatalogueSnapshot({bool forceRefresh = false}) async {
    try {
      final docs = await _productService.getActiveCatalogue(
        forceRefresh: forceRefresh,
      );

      _buildCatalogueIndex(docs);
      await _rankPopularProducts(docs);
    } catch (e) {
      AppLogger.d('Error loading catalogue snapshot: $e');
      if (mounted) setState(() => _isLoadingPopular = false);
    }
  }

  /// Keeps the hero tracking row pointed at whichever account is signed in.
  ///
  /// The cart badge and the bell used to be subscribed here as well; both now
  /// come from [NavBadgeService], which the shell starts once per session.
  void _listenToAccountStreams() {
    _authStateSubscription?.cancel();
    _authStateSubscription = FirebaseAuth.instance.authStateChanges().listen((
      user,
    ) {
      if (!mounted) return;
      _listenToActiveOrder(user);
    });
  }

  /// Repaints the header bell when the shared unread count moves.
  void _onUnreadNotificationsChanged() {
    if (mounted) setState(() {});
  }

  /// Tapping Home while Home is already showing: drop any search and return to
  /// the top, which is what the rail's Home item used to do directly.
  void _onHomeReselected() {
    if (!mounted) return;
    if (_isSearchMode) _clearSearch();
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // ── Hero data loaders ────────────────────────────────────────────────────

  /// Statuses that mean the buyer still has something coming, in the order we
  /// prefer to surface them.
  static const Set<order_model.OrderStatus> _inFlightStatuses = {
    order_model.OrderStatus.shipping,
    order_model.OrderStatus.to_ship,
    order_model.OrderStatus.confirmed,
    order_model.OrderStatus.pending,
  };

  /// Subscribes to the signed-in buyer's orders and keeps the newest in-flight
  /// one in [_activeOrder] for the hero tracking row.
  void _listenToActiveOrder(User? user) {
    _ordersSubscription?.cancel();
    _ordersSubscription = null;

    if (user == null) {
      if (mounted) setState(() => _activeOrder = null);
      return;
    }

    _ordersSubscription = OrderService.getUserOrdersStream().listen(
      (orders) {
        if (!mounted) return;
        final inFlight =
            orders.where((o) => _inFlightStatuses.contains(o.status)).toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        setState(() {
          _activeOrder = inFlight.isNotEmpty ? inFlight.first : null;
        });
      },
      onError: (error) {
        AppLogger.d('Error listening to active order: $error');
      },
    );
  }

  /// Picks the four most-clicked active products out of [docs]. `clickCounter`
  /// cannot be ordered server-side alongside the `isActive` filter without a
  /// composite index, so the ranking is done client-side over the active set
  /// the caller already fetched.
  Future<void> _rankPopularProducts(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    try {
      final ranked =
          docs.where((doc) {
            final data = doc.data();
            if (data['isDraft'] == true) return false;
            if (data['isArchived'] == true) return false;
            final sellerId = (data['sellerId'] as String?) ?? '';
            if (sellerId.isEmpty) return false;
            if (BannedSellerService.instance.isBanned(sellerId)) return false;
            return true;
          }).toList()..sort((a, b) {
            final ca = (a.data()['clickCounter'] as num?)?.toInt() ?? 0;
            final cb = (b.data()['clickCounter'] as num?)?.toInt() ?? 0;
            return cb.compareTo(ca);
          });

      // Hydrate a few more than we need so products without a priced variation
      // can be skipped without leaving gaps in the row of four.
      final candidates = ranked.take(8).map((d) => d.id).toList();
      final hydrated = await Future.wait(
        candidates.map((id) => _productService.getProductById(id)),
      );

      final popular = hydrated
          .whereType<Product>()
          .where((p) => p.lowestPrice != null)
          .take(4)
          .toList();

      _cachePricesFrom(popular);

      if (mounted) {
        setState(() {
          _popularProducts = popular;
          _isLoadingPopular = false;
        });
      }
      AppLogger.d('Loaded ${popular.length} popular products');
    } catch (e) {
      AppLogger.d('Error loading popular products: $e');
      if (mounted) setState(() => _isLoadingPopular = false);
    }
  }

  /// Picks the strongest currently-valid voucher across all sellers and pairs
  /// it with one of that seller's products to form the Deal of the Day card.
  /// Leaves [_dealProduct] null when nobody is running a promo, in which case
  /// the card is not rendered at all.
  Future<void> _loadDealOfTheDay() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('Vouchers')
          .where('status', isEqualTo: 'active')
          .get();

      final now = DateTime.now();
      final valid = snapshot.docs.map((d) => d.data()).where((v) {
        final sellerId = (v['sellerId'] as String?) ?? '';
        if (sellerId.isEmpty) return false;
        if (BannedSellerService.instance.isBanned(sellerId)) return false;
        if (_formatSingleVoucher(v) == null) return false;
        final start = _parseVoucherDate(v['startDate']);
        final end = _parseVoucherDate(v['endDate']);
        if (start == null || end == null) return false;
        return !start.isAfter(now) && !end.isBefore(now);
      }).toList();

      if (valid.isEmpty) {
        AppLogger.d('No active vouchers for deal of the day');
        _clearDealOfTheDay();
        return;
      }

      // Try the best voucher first, falling back down the list when a seller
      // has no sellable product to feature.
      for (final voucher in _sortVouchersByPriority(valid).take(5)) {
        final sellerId = voucher['sellerId'] as String;
        final productSnap = await FirebaseFirestore.instance
            .collection('Product')
            .where('sellerId', isEqualTo: sellerId)
            .where('isActive', isEqualTo: true)
            .limit(10)
            .get();

        final docs =
            productSnap.docs.where((doc) {
              final data = doc.data();
              return data['isDraft'] != true && data['isArchived'] != true;
            }).toList()..sort((a, b) {
              final ca = (a.data()['clickCounter'] as num?)?.toInt() ?? 0;
              final cb = (b.data()['clickCounter'] as num?)?.toInt() ?? 0;
              return cb.compareTo(ca);
            });

        for (final doc in docs.take(3)) {
          final product = await _productService.getProductById(doc.id);
          if (product == null || product.lowestPrice == null) continue;

          if (!mounted) return;
          setState(() {
            _dealProduct = product;
            _dealVoucher = voucher;
            _dealEndsAt = _parseVoucherDate(voucher['endDate']);
          });
          AppLogger.d('Deal of the day: ${product.name} (seller $sellerId)');
          return;
        }
      }
    } catch (e) {
      AppLogger.d('Error loading deal of the day: $e');
    }
  }

  /// Drops the deal card (no live voucher, or the voucher just expired).
  void _clearDealOfTheDay() {
    if (!mounted) return;
    setState(() {
      _dealProduct = null;
      _dealVoucher = null;
      _dealEndsAt = null;
    });
  }

  // Fetch all active banner images from Firebase Realtime Database
  Future<void> _loadActiveBanner() async {
    // `finally` rather than a flag set at each exit: this method returns early
    // in several places, and a missed one would leave the banner slot showing
    // a placeholder forever.
    try {
      final databaseUrl =
          'https://dentpal-161e5-default-rtdb.asia-southeast1.firebasedatabase.app';
      final database = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: databaseUrl,
      );
      final bannersRef = database.ref('Banner');
      final snapshot = await bannersRef.get();
      if (!snapshot.exists) {
        AppLogger.d('No banners found in Realtime Database');
        return;
      }

      // Create a list to hold banner data with order
      List<Map<String, dynamic>> activeBanners = [];
      final currentTime = DateTime.now();

      final bannersData = snapshot.value as Map<dynamic, dynamic>?;
      if (bannersData != null) {
        for (final entry in bannersData.entries) {
          final bannerData = entry.value as Map<dynamic, dynamic>?;
          if (bannerData != null) {
            final isActive = bannerData['isActive'] == true;

            // Only process if banner is active
            if (isActive) {
              // Check duration.startTime if exists
              bool shouldDisplay = true;

              if (bannerData['duration'] != null) {
                final duration =
                    bannerData['duration'] as Map<dynamic, dynamic>?;
                if (duration != null && duration['startTime'] != null) {
                  final startTimeStr = duration['startTime'] as String?;
                  if (startTimeStr != null) {
                    try {
                      final startTime = DateTime.parse(startTimeStr);
                      // Only display if current time is after or equal to start time
                      shouldDisplay =
                          currentTime.isAfter(startTime) ||
                          currentTime.isAtSameMomentAs(startTime);

                      if (!shouldDisplay) {
                        AppLogger.d(
                          'Banner ${entry.key} not yet started. Start time: $startTimeStr, Current time: $currentTime',
                        );
                      }
                    } catch (e) {
                      AppLogger.d(
                        'Error parsing startTime for banner ${entry.key}: $e',
                      );
                      // If parsing fails, don't display the banner
                      shouldDisplay = false;
                    }
                  }
                }
              }

              if (shouldDisplay) {
                final bannerUrl =
                    bannerData['imageURL'] as String? ??
                    bannerData['imageUrl'] as String?;
                if (bannerUrl != null && bannerUrl.isNotEmpty) {
                  final targetUrl = bannerData['url'] as String?;
                  final rawOrder = bannerData['order'];
                  final int order;
                  if (rawOrder == null) {
                    order = 999;
                  } else if (rawOrder is int) {
                    order = rawOrder;
                  } else if (rawOrder is double) {
                    order = rawOrder.toInt();
                  } else if (rawOrder is String) {
                    order = int.tryParse(rawOrder) ?? 999;
                  } else {
                    order = 999;
                  }

                  activeBanners.add({
                    'imageURL': bannerUrl,
                    'targetURL': targetUrl,
                    'order': order,
                  });
                }
              }
            }
          }
        }
      }

      // Sort banners by order (ascending: 0, 1, 2, ...)
      activeBanners.sort(
        (a, b) =>
            (a['order'] as int? ?? 999).compareTo(b['order'] as int? ?? 999),
      );

      // Extract sorted URLs
      List<String> activeBannerUrls = activeBanners
          .map((b) => b['imageURL'] as String)
          .toList();
      List<String?> activeBannerTargetUrls = activeBanners
          .map((b) => b['targetURL'] as String?)
          .toList();

      if (mounted && activeBannerUrls.isNotEmpty) {
        setState(() {
          _bannerImageUrls = activeBannerUrls;
          _bannerTargetUrls = activeBannerTargetUrls;
        });
        AppLogger.d(
          '${activeBannerUrls.length} active banners loaded and sorted by order from Realtime Database',
        );
        _startBannerAutoScroll();
      } else {
        AppLogger.d('No active banners found in Realtime Database');
      }
    } catch (e) {
      AppLogger.d('Error loading active banners from Realtime Database: $e');
    } finally {
      if (mounted) setState(() => _isLoadingBanner = false);
    }
  }

  // Handle banner click and open URL
  Future<void> _onBannerTap(int index) async {
    AppLogger.d('Banner tapped at index: $index');
    if (index >= _bannerTargetUrls.length) return;

    final targetUrl = _bannerTargetUrls[index];
    AppLogger.d('Target URL: $targetUrl');

    if (targetUrl == null || targetUrl.isEmpty) {
      _showBannerSnack('No link configured for this banner.');
      return;
    }

    // Normalize URL: if it has no scheme (e.g. "meetperla-ai.com"),
    // assume https so url_launcher can resolve a browser intent.
    final normalizedUrl =
        targetUrl.startsWith(RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:'))
        ? targetUrl
        : 'https://$targetUrl';
    if (normalizedUrl != targetUrl) {
      AppLogger.d('Banner URL had no scheme, normalized to: $normalizedUrl');
    }

    try {
      // Check if it's a product URL (contains /product/)
      if (normalizedUrl.contains('/product/')) {
        // Extract product ID from URL
        final uri = Uri.parse(normalizedUrl);
        final pathSegments = uri.fragment.isNotEmpty
            ? uri.fragment.split('/')
            : uri.pathSegments;

        // Find the product ID (comes after 'product')
        final productIndex = pathSegments.indexOf('product');
        if (productIndex != -1 && productIndex < pathSegments.length - 1) {
          final productId = pathSegments[productIndex + 1];
          AppLogger.d('Navigating to product detail page with ID: $productId');

          // Navigate to product detail page within the app
          if (mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => ProductDetailPage(productId: productId),
              ),
            );
          }
          return;
        }
      }

      // If not a product URL, launch externally
      final uri = Uri.parse(normalizedUrl);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      AppLogger.d('Successfully launched URL externally: $normalizedUrl');
    } catch (e) {
      AppLogger.d('Error launching banner URL: $e');
      // Try alternative launch mode if first attempt fails
      try {
        final uri = Uri.parse(normalizedUrl);
        await launchUrl(uri, mode: LaunchMode.platformDefault);
        AppLogger.d(
          'Successfully launched URL with platformDefault mode: $normalizedUrl',
        );
      } catch (e2) {
        AppLogger.d('Error with platformDefault mode: $e2');
        _showBannerSnack('Unable to open the link.');
      }
    }
  }

  void _showBannerSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Start auto-scrolling banners every 5 seconds
  void _startBannerAutoScroll() {
    _bannerAutoScrollTimer?.cancel();
    if (_bannerImageUrls.length > 1) {
      _bannerAutoScrollTimer = Timer.periodic(const Duration(seconds: 5), (
        timer,
      ) {
        if (mounted && _bannerPageController.hasClients) {
          final nextPage = (_currentBannerIndex + 1) % _bannerImageUrls.length;
          _bannerPageController.animateToPage(
            nextPage,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    // Remove scroll listener to prevent memory leaks
    _scrollController.removeListener(_scrollListener);
    pendingBrowseSelection.removeListener(_applyPendingBrowseSelection);
    homeReselectTick.removeListener(_onHomeReselected);
    NavBadgeService.instance.unreadNotifications.removeListener(
      _onUnreadNotificationsChanged,
    );
    _bannerAutoScrollTimer?.cancel();
    _bannerPageController.dispose();
    _authStateSubscription?.cancel();
    _ordersSubscription?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchDebounceTimer?.cancel();

    AppLogger.d("ProductListingPage dispose called");
    super.dispose();
  }

  Future<void> _checkSellerStatus() async {
    try {
      AppLogger.d('ProductListingPage: Checking seller status...');

      // First check if user is authenticated
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        AppLogger.d(
          'ProductListingPage: User not authenticated, setting _isSeller to false',
        );
        if (mounted) {
          setState(() {
            _isSeller = false;
          });
        }
        return;
      }

      final result = await _productService.checkSellerStatus();
      AppLogger.d('ProductListingPage: Seller status result: $result');

      if (mounted) {
        setState(() {
          _isSeller = result['isSeller'] ?? false;
        });
        AppLogger.d('ProductListingPage: Updated _isSeller to: $_isSeller');
      }
    } catch (e) {
      AppLogger.d('ProductListingPage: Error checking seller status: $e');
      if (mounted) {
        setState(() {
          _isSeller = false;
        });
      }
    }
  }

  Future<void> _loadUserName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // User not authenticated, set generic name
      if (mounted) {
        setState(() {
          _userFirstName = 'User';
        });
      }
      return;
    }

    final firstName = await _userService.getUserFirstName();
    if (mounted) {
      setState(() {
        _userFirstName = firstName;
      });
    }
  }

  // Philippine province / city → region lookup (lowercased keys).
  static const Map<String, String> _provinceToRegion = {
    // NCR cities / municipalities
    'manila': 'NCR', 'quezon city': 'NCR', 'makati': 'NCR', 'pasig': 'NCR',
    'taguig': 'NCR', 'pasay': 'NCR', 'caloocan': 'NCR', 'mandaluyong': 'NCR',
    'muntinlupa': 'NCR', 'parañaque': 'NCR', 'paranaque': 'NCR',
    'las piñas': 'NCR', 'las pinas': 'NCR', 'marikina': 'NCR',
    'san juan': 'NCR', 'valenzuela': 'NCR', 'malabon': 'NCR',
    'navotas': 'NCR', 'pateros': 'NCR',

    // Luzon
    'ilocos norte': 'Luzon', 'ilocos sur': 'Luzon', 'la union': 'Luzon',
    'pangasinan': 'Luzon', 'cagayan': 'Luzon', 'isabela': 'Luzon',
    'nueva vizcaya': 'Luzon', 'quirino': 'Luzon', 'batanes': 'Luzon',
    'abra': 'Luzon', 'apayao': 'Luzon', 'benguet': 'Luzon',
    'ifugao': 'Luzon', 'kalinga': 'Luzon', 'mountain province': 'Luzon',
    'aurora': 'Luzon', 'bataan': 'Luzon', 'bulacan': 'Luzon',
    'nueva ecija': 'Luzon', 'pampanga': 'Luzon', 'tarlac': 'Luzon',
    'zambales': 'Luzon', 'batangas': 'Luzon', 'cavite': 'Luzon',
    'laguna': 'Luzon', 'quezon': 'Luzon', 'rizal': 'Luzon',
    'marinduque': 'Luzon', 'occidental mindoro': 'Luzon',
    'oriental mindoro': 'Luzon', 'palawan': 'Luzon', 'romblon': 'Luzon',
    'albay': 'Luzon', 'camarines norte': 'Luzon', 'camarines sur': 'Luzon',
    'catanduanes': 'Luzon', 'masbate': 'Luzon', 'sorsogon': 'Luzon',

    // Visayas
    'aklan': 'Visayas', 'antique': 'Visayas', 'capiz': 'Visayas',
    'guimaras': 'Visayas', 'iloilo': 'Visayas',
    'negros occidental': 'Visayas', 'bohol': 'Visayas', 'cebu': 'Visayas',
    'negros oriental': 'Visayas', 'siquijor': 'Visayas',
    'biliran': 'Visayas', 'eastern samar': 'Visayas', 'leyte': 'Visayas',
    'northern samar': 'Visayas', 'samar': 'Visayas',
    'southern leyte': 'Visayas',

    // Mindanao
    'zamboanga del norte': 'Mindanao', 'zamboanga del sur': 'Mindanao',
    'zamboanga sibugay': 'Mindanao', 'bukidnon': 'Mindanao',
    'camiguin': 'Mindanao', 'lanao del norte': 'Mindanao',
    'misamis occidental': 'Mindanao', 'misamis oriental': 'Mindanao',
    'davao de oro': 'Mindanao', 'davao del norte': 'Mindanao',
    'davao del sur': 'Mindanao', 'davao occidental': 'Mindanao',
    'davao oriental': 'Mindanao', 'cotabato': 'Mindanao',
    'sarangani': 'Mindanao', 'south cotabato': 'Mindanao',
    'sultan kudarat': 'Mindanao', 'agusan del norte': 'Mindanao',
    'agusan del sur': 'Mindanao', 'dinagat islands': 'Mindanao',
    'surigao del norte': 'Mindanao', 'surigao del sur': 'Mindanao',
    'basilan': 'Mindanao', 'lanao del sur': 'Mindanao',
    'maguindanao': 'Mindanao', 'sulu': 'Mindanao', 'tawi-tawi': 'Mindanao',
  };

  /// Classifies a free-form location string into one of NCR / Luzon /
  /// Visayas / Mindanao. Returns null if it cannot be classified.
  String? _classifyRegion(String? raw) {
    if (raw == null) return null;
    final v = raw.trim().toLowerCase();
    if (v.isEmpty) return null;

    // Direct region names
    if (v.contains('ncr') ||
        v.contains('metro manila') ||
        v.contains('national capital')) {
      return 'NCR';
    }
    if (v.contains('luzon')) return 'Luzon';
    if (v.contains('visayas')) return 'Visayas';
    if (v.contains('mindanao')) return 'Mindanao';

    // Exact province / city match
    final direct = _provinceToRegion[v];
    if (direct != null) return direct;

    // Substring match (handles values like "Bulacan, Philippines" or
    // "Cebu City"). Longest keys first so "negros occidental" wins over
    // "negros oriental" by specificity.
    final keys = _provinceToRegion.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final key in keys) {
      if (v.contains(key)) return _provinceToRegion[key];
    }
    return null;
  }

  Future<void> _loadUserRegion() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Priority 1: use the default address's `location` when one exists.
      try {
        final defaultAddress = await AddressService.getDefaultAddress();
        if (defaultAddress != null && defaultAddress.location.isNotEmpty) {
          final region = _classifyRegion(defaultAddress.location);
          if (mounted && region != null) {
            setState(() {
              _userRegion = region;
            });
            return;
          }
        }
      } catch (e) {
        AppLogger.d('Error reading default address for region: $e');
        // Fall through to legacy User.location.
      }

      // Priority 2: legacy User.location fallback.
      final doc = await FirebaseFirestore.instance
          .collection('User')
          .doc(user.uid)
          .get();
      if (!doc.exists) return;
      final data = doc.data();
      final location = data?['location'] as String?;
      final region = _classifyRegion(location);
      if (mounted && region != null) {
        setState(() {
          _userRegion = region;
        });
      }
    } catch (e) {
      AppLogger.d('Error loading user region: $e');
    }
  }

  /// Extracts the seller's region from cached seller data using
  /// vendor.company.address.location, falling back to address.province.
  String? _sellerRegion(String sellerId) {
    return _classifyRegion(
      SellerDisplay.locationOf(_sellerDataCache[sellerId]),
    );
  }

  void _showLoginRequiredDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: ink.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: ink.emerald.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.shopping_cart_outlined,
                  color: ink.emerald,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Login Required',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          content: Text(
            'You need to login to access your cart. Would you like to login now?',
            style: AppTextStyles.bodyMedium.copyWith(
              color: ink.text.withValues(alpha: 0.8),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: ink.text.withValues(alpha: 0.6),
              ),
              child: Text('Cancel', style: AppTextStyles.buttonMedium),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const LoginPage()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: ink.emerald,
                foregroundColor: ink.onEmerald,
                elevation: 0,
              ),
              child: Text('Login', style: AppTextStyles.buttonMedium),
            ),
          ],
        );
      },
    );
  }

  bool _isCacheExpired() {
    if (_cacheTimestamp == null) return true;

    final now = DateTime.now();
    final difference = now.difference(_cacheTimestamp!);
    return difference.inHours >= 12; // Cache expires after 12 hours
  }

  // Reset all pagination parameters and refresh the data
  void _resetAndRefresh() {
    if (!mounted) return;

    setState(() {
      _products = [];
      _lastDocument = null;
      _hasMore = true;
      _errorMessage = null;
      _cacheTimestamp = null;
      _loadedSellerIds.clear();
    });

    _loadFirstPage();
  }

  // Scroll listener for detecting when user reaches bottom
  void _scrollListener() {
    if (_scrollController.position.pixels <
        _scrollController.position.maxScrollExtent - 200)
      return;
    if (_isSearchMode) {
      if (!_isSearching &&
          !_isLoadingMoreSearch &&
          (_lastSearchResult?.hasMore ?? false)) {
        _performSearch(isLoadMore: true);
      }
    } else {
      if (!_isLoading && !_isLoadingMore && _hasMore) {
        _loadNextPage();
      }
    }
  }

  // ── Inline search methods ──────────────────────────────────────────────────

  void _onSearchChanged(String query) {
    _searchDebounceTimer?.cancel();
    setState(() {
      _searchQuery = query;
      _showSearchSuggestions = query.isNotEmpty;
    });
    if (query.isEmpty) {
      _clearSearch();
      return;
    }
    _searchDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      _performSearch();
      if (query.length > 1) _loadSearchSuggestions(query);
    });
  }

  Future<void> _performSearch({bool isLoadMore = false}) async {
    if (_searchQuery.trim().isEmpty) return;
    if (isLoadMore &&
        (_isLoadingMoreSearch || !(_lastSearchResult?.hasMore ?? true)))
      return;
    setState(() {
      if (isLoadMore) {
        _isLoadingMoreSearch = true;
      } else {
        _isSearching = true;
      }
    });
    final result = await _searchService.searchProducts(
      searchQuery: _searchQuery,
      filters: SearchFilters(),
      lastDocument: isLoadMore ? _lastSearchResult?.lastDocument : null,
    );
    if (!mounted) return;
    setState(() {
      _isSearchMode = true;
      _isSearching = false;
      _isLoadingMoreSearch = false;
      if (isLoadMore) {
        _searchResults.addAll(result.products);
      } else {
        _searchResults = result.products;
      }
      _lastSearchResult = result;
    });
  }

  /// Snapshots the sellable catalogue for type-ahead.
  void _buildCatalogueIndex(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final index = <ProductSuggestion>[];
    for (final doc in docs) {
      final data = doc.data();
      if (data['isDraft'] == true || data['isArchived'] == true) continue;
      final sellerId = (data['sellerId'] as String?) ?? '';
      if (sellerId.isEmpty) continue;
      if (BannedSellerService.instance.isBanned(sellerId)) continue;
      final name = (data['name'] as String?) ?? '';
      if (name.isEmpty) continue;

      final thumb = (data['thumbnailURL'] as String?) ?? '';
      index.add(
        ProductSuggestion(
          productId: doc.id,
          name: name,
          brand: data['brand'] as String?,
          imageUrl: thumb.isNotEmpty ? thumb : (data['imageURL'] as String?),
        ),
      );
    }
    _catalogueIndex = index;
    AppLogger.d('Type-ahead index built: ${index.length} products');
  }

  /// Local matches, best-first: names that start with the query come before
  /// names that merely contain it.
  List<ProductSuggestion> _matchCatalogue(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];

    final startsWith = <ProductSuggestion>[];
    final contains = <ProductSuggestion>[];
    for (final entry in _catalogueIndex) {
      final name = entry.name.toLowerCase();
      if (name.startsWith(q)) {
        startsWith.add(entry);
      } else if (name.contains(q) ||
          (entry.brand ?? '').toLowerCase().contains(q)) {
        contains.add(entry);
      }
      if (startsWith.length >= 8) break;
    }
    return [...startsWith, ...contains].take(8).toList();
  }

  Future<void> _loadSearchSuggestions(String query) async {
    // Fall back to a Firestore query only while the catalogue index is still
    // loading (first seconds after a cold open).
    final suggestions = _catalogueIndex.isNotEmpty
        ? _matchCatalogue(query)
        : await _searchService.getProductSuggestions(query);
    if (!mounted) return;
    setState(() {
      _searchSuggestions = suggestions;
    });

    // Prices live in each product's Variation subcollection, so they arrive
    // after the row is already on screen. Each one is awaited separately and
    // painted as it lands — batching them behind a single `Future.wait` would
    // hold every price hostage to the slowest read.
    for (final suggestion in suggestions) {
      final id = suggestion.productId;
      if (_suggestionPrices.containsKey(id) || _pricesInFlight.contains(id)) {
        continue;
      }
      _pricesInFlight.add(id);
      _searchService.getLowestPrice(id).then((price) {
        _pricesInFlight.remove(id);
        if (!mounted || price == null) return;
        setState(() {
          _suggestionPrices[id] = price;
        });
      });
    }
  }

  /// Seeds the suggestion price cache from products that were already
  /// hydrated with their variations (the listing, Most Popular, the deal), so
  /// type-ahead rows for them show a price with no extra read at all.
  void _cachePricesFrom(Iterable<Product> products) {
    for (final product in products) {
      final price = product.lowestPrice;
      if (price != null) _suggestionPrices[product.productId] = price;
    }
  }

  /// Submitting the field runs the search immediately rather than waiting out
  /// the debounce, and dismisses the type-ahead so the results are visible.
  void _onSearchSubmitted(String query) {
    _searchDebounceTimer?.cancel();
    if (query.trim().isEmpty) return;
    setState(() {
      _searchQuery = query;
      _showSearchSuggestions = false;
    });
    _searchFocusNode.unfocus();
    _performSearch();
  }

  /// A type-ahead entry names one product, so picking it opens that product
  /// instead of re-running the query and landing the buyer on a store list.
  void _onSuggestionTap(ProductSuggestion suggestion) {
    setState(() {
      _showSearchSuggestions = false;
    });
    _searchFocusNode.unfocus();
    _clickTrackingService.trackProductClick(suggestion.productId);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            ProductDetailPage(productId: suggestion.productId),
      ),
    );
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _isSearchMode = false;
      _searchResults = [];
      _searchSuggestions = [];
      _showSearchSuggestions = false;
      _lastSearchResult = null;
    });
    _searchFocusNode.unfocus();
  }

  // Handle category selection (now supports multiple selection)
  void _onCategorySelected(String category) {
    if (!mounted) return;

    if (category == 'All') {
      // Clear all selections when 'All' is selected
      setState(() {
        _selectedCategories = [];
        _selectedSubCategories = [];
        _subcategoriesByCategory.clear();
        _categoryGridForceExpanded = false;
        _visibleCategoryRows = 1;
        // Reset pagination parameters
        _products = [];
        _lastDocument = null;
        _hasMore = true;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } else {
      // Handle multiple category selection
      final categoryId = _categoryNameToId[category];
      if (categoryId != null) {
        // Track category click
        _clickTrackingService.trackCategoryClick(categoryId);

        setState(() {
          List<String> newSelectedCategories = List.from(_selectedCategories);
          if (newSelectedCategories.contains(category)) {
            // Remove category if already selected
            newSelectedCategories.remove(category);
            // Remove subcategories for this category
            _subcategoriesByCategory.remove(categoryId);
            // Remove any selected subcategories from this category
            if (_subcategoriesByCategory.containsKey(categoryId)) {
              final subcategoryIds = _subcategoriesByCategory[categoryId]!
                  .map((s) => s.subCategoryId)
                  .toList();
              _selectedSubCategories.removeWhere(
                (id) => subcategoryIds.contains(id),
              );
            }
          } else {
            // Add category to selection
            newSelectedCategories.add(category);
          }
          _selectedCategories = newSelectedCategories;
          _categoryGridForceExpanded = false;

          // Reset pagination parameters for the new selection
          _products = [];
          _lastDocument = null;
          _hasMore = true;
          _isLoading = false;
          _isLoadingMore = false;
        });

        // Load subcategories for all selected categories
        for (String selectedCategory in _selectedCategories) {
          _loadSubcategories(selectedCategory);
        }
      }
    }

    // Load first page with the new selection
    _loadFirstPage();
  }

  // Load subcategories for a given category
  Future<void> _loadSubcategories(String categoryName) async {
    if (!mounted) return;

    final categoryId = _categoryNameToId[categoryName];
    if (categoryId == null) {
      AppLogger.d('No categoryId found for category: $categoryName');
      return;
    }

    // Skip if subcategories already loaded for this category
    if (_subcategoriesByCategory.containsKey(categoryId)) {
      AppLogger.d(
        'Subcategories already loaded for category: $categoryName (ID: $categoryId)',
      );
      return;
    }

    try {
      AppLogger.d(
        'Loading subcategories for category: $categoryName (ID: $categoryId)',
      );
      final subcategoriesFuture = _categoryService.getSubCategories(categoryId);
      // Collect subCategoryIDs actually used by active products in this category.
      final productSnapFuture = FirebaseFirestore.instance
          .collection('Product')
          .where('isActive', isEqualTo: true)
          .where('categoryID', isEqualTo: categoryId)
          .get();

      final subcategories = await subcategoriesFuture;
      final productSnap = await productSnapFuture;

      final usedSubIds = productSnap.docs
          .map((d) => (d.data()['subCategoryID'] as String?) ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      final filtered = subcategories
          .where((s) => usedSubIds.contains(s.subCategoryId))
          .toList();

      AppLogger.d(
        'Loaded ${filtered.length}/${subcategories.length} subcategories for $categoryName',
      );

      if (!mounted) return;

      setState(() {
        _subcategoriesByCategory[categoryId] = filtered;
      });
    } catch (e) {
      AppLogger.d('Error loading subcategories for $categoryName: $e');
    }
  }

  // Handle subcategory selection (now supports multiple selection)
  void _onSubCategorySelected(String subCategoryId, String subCategoryName) {
    if (!mounted) return;

    AppLogger.d('Subcategory selected: $subCategoryName (ID: $subCategoryId)');

    setState(() {
      List<String> newSelectedSubCategories = List.from(_selectedSubCategories);
      if (newSelectedSubCategories.contains(subCategoryId)) {
        // Remove subcategory if already selected
        newSelectedSubCategories.remove(subCategoryId);
        AppLogger.d('Removed subcategory: $subCategoryName');
      } else {
        // Add subcategory to selection
        newSelectedSubCategories.add(subCategoryId);
        AppLogger.d('Added subcategory: $subCategoryName');
      }
      _selectedSubCategories = newSelectedSubCategories;

      AppLogger.d('Current selected subcategories: $_selectedSubCategories');

      // Reset pagination parameters for the new selection
      _products = [];
      _lastDocument = null;
      _hasMore = true;
      _isLoading = false;
      _isLoadingMore = false;
    });

    // Track subcategory click
    // Find the category for this subcategory
    for (final entry in _subcategoriesByCategory.entries) {
      final categoryId = entry.key;
      final subcategories = entry.value;
      if (subcategories.any((s) => s.subCategoryId == subCategoryId)) {
        _clickTrackingService.trackSubCategoryClick(categoryId, subCategoryId);
        break;
      }
    }

    // Load first page with the new selection
    _loadFirstPage();
  }

  // Build grouped subcategories section similar to search page
  List<Widget> _buildGroupedSubcategoriesSection() {
    List<Widget> widgets = [];

    // Iterate through selected categories that have subcategories
    for (String selectedCategory in _selectedCategories) {
      final categoryId = _categoryNameToId[selectedCategory];
      if (categoryId != null &&
          _subcategoriesByCategory.containsKey(categoryId)) {
        final subcategories = _subcategoriesByCategory[categoryId]!;

        if (subcategories.isNotEmpty) {
          // Add category header
          widgets.add(
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              child: Text(
                '$selectedCategory Subcategories',
                style: AppTextStyles.labelMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  color: ink.amber,
                ),
              ),
            ),
          );

          // Add subcategory chips for this category
          widgets.add(
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: subcategories.map((subcategory) {
                  final isSelected = _selectedSubCategories.contains(
                    subcategory.subCategoryId,
                  );
                  return GestureDetector(
                    onTap: () => _onSubCategorySelected(
                      subcategory.subCategoryId,
                      subcategory.subCategoryName,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected ? ink.emerald : ink.surfaceHigh,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? ink.emerald
                              : ink.text.withValues(alpha: 0.2),
                          width: 1,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: ink.emerald.withValues(alpha: 0.2),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : [],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Subcategory image or icon
                          if (subcategory.imageURL != null &&
                              subcategory.imageURL!.isNotEmpty) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.network(
                                subcategory.imageURL!,
                                width: 20,
                                height: 20,
                                fit: BoxFit.cover,
                                cacheWidth: 48,
                                cacheHeight: 48,
                                errorBuilder: (c, e, s) => Icon(
                                  Icons.category_rounded,
                                  size: 14,
                                  color: isSelected
                                      ? ink.onEmerald
                                      : ink.text.withValues(alpha: 0.6),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ] else ...[
                            Icon(
                              Icons.category_rounded,
                              size: 14,
                              color: isSelected
                                  ? ink.onEmerald
                                  : ink.text.withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            subcategory.subCategoryName,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: isSelected ? ink.onEmerald : ink.text,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 4),
                          FutureBuilder<int>(
                            future: _getSubCategoryClickCount(
                              subcategory.subCategoryId,
                            ),
                            builder: (context, snapshot) {
                              final clickCount = snapshot.data ?? 0;
                              if (clickCount == 0)
                                return const SizedBox.shrink();

                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? ink.onEmerald.withValues(alpha: 0.2)
                                      : ink.emerald.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '$clickCount',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: isSelected
                                        ? ink.onEmerald
                                        : ink.emerald,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 9,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          );
        }
      }
    }

    return widgets;
  }

  // Fetch the banned-seller cache for the current user, then trigger the
  // first product page load. Run sequentially so the first page already
  // filters banned sellers out instead of showing them then hiding.
  Future<void> _loadBannedSellersThenFirstPage() async {
    try {
      await BannedSellerService.instance.loadForCurrentUser();
    } catch (e) {
      AppLogger.d('ProductListingPage: banned seller load failed: $e');
    }
    if (!mounted) return;
    _loadFirstPage();

    // Everything below filters on the banned-seller cache, so it waits for the
    // load above rather than racing it.
    _loadCatalogueSnapshot(); // type-ahead index + Most Popular
    _loadDealOfTheDay(); // best live voucher + one of that seller's products
  }

  // Load the first page of products, accumulating until we have enough unique stores
  Future<void> _loadFirstPage() async {
    if (_isLoading || !mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      AppLogger.d('ProductListingPage: Loading first page of products...');

      // Use server-side filtering when possible
      String? filterCategoryId;
      String? filterSubCategoryId;

      if (_selectedCategories.length == 1) {
        filterCategoryId = _categoryNameToId[_selectedCategories.first];
      }
      if (_selectedSubCategories.length == 1) {
        filterSubCategoryId = _selectedSubCategories.first;
      }

      _loadedSellerIds.clear();

      final result = await _productService.getProductsPaginated(
        limit: _pageSize,
        categoryId: filterCategoryId,
        subCategoryId: filterSubCategoryId,
        includeInactive: false,
        includeDrafts: false,
        includeArchived: false,
        excludeSellerIds: BannedSellerService.instance.bannedSellerIds,
      );

      if (!mounted) return;

      final allFetched = List<Product>.from(
        result['products'] as List<Product>,
      );
      final cursor = result['lastDocument'] as DocumentSnapshot?;
      final moreAvailable = result['hasMore'] as bool;

      for (final p in allFetched) {
        if (p.sellerId.isNotEmpty) _loadedSellerIds.add(p.sellerId);
      }

      // Confirm ban status for every seller surfaced on this page via direct
      // doc gets (no composite index needed), then drop any products whose
      // seller turns out to have banned the current buyer.
      await BannedSellerService.instance.checkSellers(
        allFetched.map((p) => p.sellerId),
      );
      allFetched.removeWhere(
        (p) => BannedSellerService.instance.isBanned(p.sellerId),
      );

      // Load categories only if they haven't been loaded yet
      if (_categories.length <= 1) {
        try {
          final allCategories = await _categoryService.getCategories();
          // Collect categoryIDs that are actually used by active products, so
          // empty categories don't crowd the grid. Shares the cached catalogue
          // with _loadCatalogueSnapshot rather than re-reading the collection.
          final catalogue = await _productService.getActiveCatalogue();
          final usedCategoryIds = catalogue
              .map((d) => (d.data()['categoryID'] as String?) ?? '')
              .where((id) => id.isNotEmpty)
              .toSet();

          if (!mounted) return;

          Set<String> categorySet = {'All'};
          _categoryNameToId.clear();
          _categoryIdToName.clear();
          _categoryNameToImage.clear();

          for (var category in allCategories) {
            if (!usedCategoryIds.contains(category.categoryId)) continue;
            categorySet.add(category.categoryName);
            _categoryNameToId[category.categoryName] = category.categoryId;
            _categoryIdToName[category.categoryId] = category.categoryName;
            _categoryNameToImage[category.categoryName] =
                category.categoryImageUrl;
          }

          _categories = categorySet.toList();
        } catch (e) {
          AppLogger.d('Error loading categories: $e');
          _categories = ['All'];
        }
      }

      _cachePricesFrom(allFetched);

      if (mounted) {
        setState(() {
          _products = allFetched;
          _lastDocument = cursor;
          _hasMore = moreAvailable;
          _isLoading = false;
          _firstLoadDone = true;
          _cacheTimestamp = DateTime.now();
        });
      }

      // Pre-fetch vendor data for trader cards
      _prefetchSellerData(allFetched).then((_) {
        if (mounted) setState(() {});
      });

      AppLogger.d('Loaded ${allFetched.length} products (first page)');
    } catch (e) {
      AppLogger.d('Error loading first page: $e');

      if (mounted) {
        setState(() {
          _isLoading = false;
          _firstLoadDone = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  // Load the next page of products, accumulating until 10 new unique stores are found
  Future<void> _loadNextPage() async {
    if (_isLoadingMore || !_hasMore || _lastDocument == null || !mounted) {
      return;
    }

    setState(() {
      _isLoadingMore = true;
    });

    try {
      AppLogger.d('ProductListingPage: Loading more stores...');

      String? filterCategoryId;
      String? filterSubCategoryId;

      if (_selectedCategories.length == 1) {
        filterCategoryId = _categoryNameToId[_selectedCategories.first];
      }
      if (_selectedSubCategories.length == 1) {
        filterSubCategoryId = _selectedSubCategories.first;
      }

      final result = await _productService.getProductsPaginated(
        limit: _pageSize,
        lastDocument: _lastDocument,
        categoryId: filterCategoryId,
        subCategoryId: filterSubCategoryId,
        includeInactive: false,
        includeDrafts: false,
        includeArchived: false,
        excludeSellerIds: BannedSellerService.instance.bannedSellerIds,
      );

      if (!mounted) return;

      final allNewProducts = List<Product>.from(
        result['products'] as List<Product>,
      );
      final cursor = result['lastDocument'] as DocumentSnapshot?;
      final moreAvailable = result['hasMore'] as bool;

      for (final p in allNewProducts) {
        if (p.sellerId.isNotEmpty) _loadedSellerIds.add(p.sellerId);
      }

      // Confirm ban status for any new sellers surfaced in this batch, then
      // drop banned products before they reach the list.
      await BannedSellerService.instance.checkSellers(
        allNewProducts.map((p) => p.sellerId),
      );
      allNewProducts.removeWhere(
        (p) => BannedSellerService.instance.isBanned(p.sellerId),
      );

      _cachePricesFrom(allNewProducts);

      if (mounted) {
        setState(() {
          _products.addAll(allNewProducts);
          _lastDocument = cursor;
          _hasMore = moreAvailable;
          _isLoadingMore = false;
        });
      }

      // Pre-fetch vendor data for new traders
      _prefetchSellerData(allNewProducts).then((_) {
        if (mounted) setState(() {});
      });

      AppLogger.d('Loaded ${allNewProducts.length} more products');
    } catch (e) {
      AppLogger.d('Error loading more products: $e');

      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  // Helper method to compare product lists for change detection
  bool _hasDataChanged(List<Product> oldProducts, List<Product> newProducts) {
    if (oldProducts.length != newProducts.length) {
      AppLogger.d(
        'Data changed: Product count differs (${oldProducts.length} vs ${newProducts.length})',
      );
      return true;
    }

    for (int i = 0; i < oldProducts.length; i++) {
      final oldProduct = oldProducts[i];
      final newProduct = newProducts[i];

      if (oldProduct.productId != newProduct.productId ||
          oldProduct.name != newProduct.name ||
          oldProduct.lowestPrice != newProduct.lowestPrice ||
          oldProduct.imageURL != newProduct.imageURL ||
          oldProduct.categoryId != newProduct.categoryId) {
        AppLogger.d('Data changed: Product ${oldProduct.name} has differences');
        return true;
      }
    }

    return false;
  }

  // Helper method to compare category data for changes
  bool _hasCategoryDataChanged(
    Map<String, String> oldMapping,
    Map<String, String> newMapping,
  ) {
    if (oldMapping.length != newMapping.length) {
      AppLogger.d(
        'Categories changed: Count differs (${oldMapping.length} vs ${newMapping.length})',
      );
      return true;
    }

    for (final entry in oldMapping.entries) {
      if (newMapping[entry.key] != entry.value) {
        AppLogger.d('Categories changed: ${entry.key} mapping differs');
        return true;
      }
    }

    return false;
  }

  // Handle pull-to-refresh with cache-first approach and change detection
  Future<void> _handleRefresh() async {
    if (!mounted) return;

    AppLogger.d(
      'ProductListingPage: Pull-to-refresh triggered (cache-first approach)',
    );

    try {
      // Clear cached reads on manual refresh to get fresh data
      CategoryService.clearCache();
      ProductService.clearCatalogueCache();

      // Keep current data as backup
      final currentProducts = List<Product>.from(_products);
      final currentCategories = Map<String, String>.from(_categoryNameToId);
      final currentTimestamp = _cacheTimestamp;

      AppLogger.d(
        'Current cache: ${currentProducts.length} products, ${currentCategories.length} categories',
      );

      // Refresh banned-seller cache before fetching so newly added bans
      // take effect on this pull-to-refresh.
      await BannedSellerService.instance.loadForCurrentUser();

      // Rebuild the hero alongside the listing: popularity and live vouchers
      // both move independently of the product pages themselves.
      if (mounted) setState(() => _isLoadingPopular = true);
      _loadCatalogueSnapshot(forceRefresh: true);
      _loadDealOfTheDay();

      // Fetch fresh data from Firebase
      AppLogger.d('Fetching fresh data from Firebase...');
      final result = await _productService.getProductsPaginated(
        limit: _pageSize,
        categoryId: null,
        excludeSellerIds: BannedSellerService.instance.bannedSellerIds,
      );

      if (!mounted) return; // Check if widget is still mounted

      final freshProducts = result['products'] as List<Product>;

      // Fetch fresh categories
      Map<String, String> freshCategoryMapping = {};
      Map<String, String> freshCategoryIdToName = {};
      Map<String, String?> freshCategoryImageMapping = {};
      List<String> freshCategoriesList = ['All'];

      try {
        final allCategories = await _categoryService.getCategories();

        if (!mounted) return; // Check if widget is still mounted

        for (var category in allCategories) {
          freshCategoriesList.add(category.categoryName);
          freshCategoryMapping[category.categoryName] = category.categoryId;
          freshCategoryIdToName[category.categoryId] = category.categoryName;
          freshCategoryImageMapping[category.categoryName] =
              category.categoryImageUrl;
        }
        AppLogger.d('Fetched ${allCategories.length} fresh categories');
      } catch (e) {
        AppLogger.d('Error fetching fresh categories: $e');
        // Keep existing categories on error
        freshCategoryMapping = currentCategories;
        freshCategoriesList = _categories;
        freshCategoryImageMapping = Map.from(_categoryNameToImage);
      }

      if (!mounted) return; // Check if widget is still mounted

      // Compare data for changes
      final hasProductChanges = _hasDataChanged(currentProducts, freshProducts);
      final hasCategoryChanges = _hasCategoryDataChanged(
        currentCategories,
        freshCategoryMapping,
      );
      final hasAnyChanges = hasProductChanges || hasCategoryChanges;

      if (hasAnyChanges || currentTimestamp == null || _isCacheExpired()) {
        AppLogger.d('Changes detected or cache expired - updating data');

        if (mounted) {
          // Update with fresh data
          setState(() {
            _products = freshProducts;
            _lastDocument = result['lastDocument'] as DocumentSnapshot?;
            _hasMore = result['hasMore'] as bool;
            _categories = freshCategoriesList;
            _categoryNameToId = freshCategoryMapping;
            _categoryIdToName = freshCategoryIdToName;
            _categoryNameToImage = freshCategoryImageMapping;
            _cacheTimestamp = DateTime.now();
            _errorMessage = null;
            _sellerDataCache
                .clear(); // invalidate vendor cache on manual refresh
          });

          // Re-fetch vendor data after cache clear
          _prefetchSellerData(freshProducts).then((_) {
            if (mounted) setState(() {});
          });
        }

        // Clear image cache only if there are actual changes
        if (hasProductChanges) {
          AppLogger.d('Clearing image cache due to product changes');
          await ProductImageCacheManager.instance.emptyCache();
        }

        AppLogger.d(
          'Data updated: ${freshProducts.length} products, ${freshCategoriesList.length - 1} categories',
        );
      } else {
        // No changes detected, just refresh timestamp
        if (mounted) {
          setState(() {
            _cacheTimestamp = DateTime.now();
          });
        }

        AppLogger.d('No changes detected - cache timestamp refreshed');
      }
    } catch (e) {
      AppLogger.d('Refresh error: $e');
      AppLogger.d('Stack trace: ${StackTrace.current}');

      // Keep existing data on error, but show error state if we have no data
      if (_products.isEmpty && mounted) {
        setState(() {
          _errorMessage = 'Failed to refresh data: ${e.toString()}';
        });
      }
    }

    AppLogger.d('ProductListingPage: Pull-to-refresh completed');
  }

  Future<bool> _showExitConfirmation() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: ink.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: ink.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.exit_to_app, color: ink.amber, size: 24),
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
                color: ink.text.withValues(alpha: 0.8),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  foregroundColor: ink.text.withValues(alpha: 0.6),
                ),
                child: Text('Cancel', style: AppTextStyles.buttonMedium),
              ),
              ElevatedButton(
                onPressed: () {
                  SystemNavigator.pop(); // Sends to background or closes app
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: ink.amber,
                  foregroundColor: ink.onEmerald,
                  elevation: 0,
                ),
                child: Text('Exit', style: AppTextStyles.buttonMedium),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    // Only wrap with PopScope if used standalone (not within home page navigation)
    if (!widget.isStandalone) {
      return _buildScaffold();
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
      child: _buildScaffold(),
    );
  }

  Widget _buildScaffold() {
    // Must be the same threshold the shell uses to decide rail-vs-bottom-bar,
    // or this page lays out for a rail that isn't there (or vice versa).
    final isWideScreen = context.isWideLayout;
    // The side rail eats into the width the content has to lay out in, so
    // every centring calculation below works off what's left, not the screen.
    final contentWidth = _contentWidth;
    // The grid shares the 1100px column the rest of the page uses — the old
    // 720px cap was sized for a single-file list of trader cards.
    final double gridHorizontalPadding = isWideScreen
        ? ((contentWidth - _kMaxContentWidth) / 2).clamp(16.0, double.infinity)
        : 16;
    return Scaffold(
      backgroundColor: ink.bg,
      body: _buildScrollView(isWideScreen, gridHorizontalPadding),
      floatingActionButton: _isSeller
          ? Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: ink.emerald.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: FloatingActionButton(
                onPressed: () {
                  AppLogger.d(
                    'ProductListingPage: FAB pressed - navigating to add-product',
                  );
                  Navigator.pushNamed(context, '/add-product');
                },
                backgroundColor: ink.emerald,
                foregroundColor: ink.onEmerald,
                elevation: 0,
                highlightElevation: 0,
                child: const Icon(Icons.add),
              ),
            )
          : null,
    );
  }

  Widget _buildScrollView(bool isWideScreen, double gridHorizontalPadding) {
    final gridContentWidth =
        math.min(
          _contentWidth,
          isWideScreen ? _kMaxContentWidth : _contentWidth,
        ) -
        gridHorizontalPadding * 2;
    final filteredProducts = _filteredProducts();

    // One shimmer scope for the whole page: every placeholder below — banner,
    // categories, popular, the catalogue grid — reads its sweep from here, so
    // they animate in phase rather than each starting its own ticker.
    return SkeletonShimmer(
      child: RefreshIndicator(
        onRefresh: _handleRefresh,
        color: ink.emerald,
        backgroundColor: ink.surface,
        displacement: 40,
        strokeWidth: 2.5,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Hero: identity, search, tracking, the deal and the two quick
            // actions. Outside the search-mode branch below, because the
            // search field itself lives inside it.
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isWideScreen ? 1100 : double.infinity,
                  ),
                  child: _buildHeroHeader(isWide: isWideScreen),
                ),
              ),
            ),
            // Type-ahead. Not gated on _isSearchMode, so matches appear as soon
            // as they load rather than waiting for the first result set.
            if (_showSearchSuggestions && _searchSuggestions.isNotEmpty)
              SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: isWideScreen ? 1100 : double.infinity,
                    ),
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: ink.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: ink.border),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (
                            var i = 0;
                            i < _searchSuggestions.length;
                            i++
                          ) ...[
                            if (i > 0)
                              Divider(
                                height: 1,
                                thickness: 1,
                                color: ink.border,
                              ),
                            _buildSuggestionRow(_searchSuggestions[i]),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // Search mode content
            if (_isSearchMode) ...[
              // Search results header
              SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: isWideScreen ? 1100 : double.infinity,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        children: [
                          Icon(Icons.search, color: ink.emerald, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _isSearching
                                  ? 'Searching...'
                                  : 'Results for "$_searchQuery" (${_searchResults.length} products)',
                              style: AppTextStyles.titleMedium.copyWith(
                                fontWeight: FontWeight.bold,
                                color: ink.text,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _clearSearch,
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Search results as product tiles
              if (_isSearching)
                SliverPadding(
                  padding: EdgeInsets.symmetric(
                    horizontal: gridHorizontalPadding,
                  ),
                  sliver: _buildProductGridSkeleton(gridContentWidth),
                )
              else if (_searchResults.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 64,
                          color: ink.text.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No products found.',
                          style: AppTextStyles.titleMedium.copyWith(
                            fontWeight: FontWeight.bold,
                            color: ink.text,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Try a different search term',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: ink.text.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.symmetric(
                    horizontal: gridHorizontalPadding,
                  ),
                  sliver: _buildProductsSliver(
                    _searchResults,
                    gridContentWidth,
                  ),
                ),
              if (_isLoadingMoreSearch)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    gridHorizontalPadding,
                    12,
                    gridHorizontalPadding,
                    24,
                  ),
                  sliver: _buildProductGridSkeleton(gridContentWidth, rows: 1),
                ),
            ],

            // Normal browsing content
            if (!_isSearchMode) ...[
              // Main centered content
              SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: isWideScreen ? 1100 : double.infinity,
                    ),
                    child: Column(
                      children: [
                        // The hero is a top-level sliver above this column — it
                        // has to survive search mode, which this column does not.
                        const SizedBox(height: 20),
                        // Banner Slideshow — a card on every size, rather than
                        // bleeding to the edges on phones.
                        if (_bannerImageUrls.isEmpty && _isLoadingBanner)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                _bannerRadius,
                              ),
                              child: AspectRatio(
                                aspectRatio: _bannerAspectRatio,
                                child: const SkeletonBox(radius: 0),
                              ),
                            ),
                          ),
                        if (_bannerImageUrls.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                _bannerRadius,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: ink.emerald.withValues(alpha: 0.2),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                _bannerRadius,
                              ),
                              child: AspectRatio(
                                aspectRatio: _bannerAspectRatio,
                                child: Stack(
                                  children: [
                                    PageView.builder(
                                      controller: _bannerPageController,
                                      physics: kIsWeb
                                          ? const AlwaysScrollableScrollPhysics()
                                          : const PageScrollPhysics(),
                                      onPageChanged: (index) {
                                        setState(() {
                                          _currentBannerIndex = index;
                                        });
                                        _startBannerAutoScroll();
                                      },
                                      itemCount: _bannerImageUrls.length,
                                      itemBuilder: (context, index) {
                                        return GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () {
                                            AppLogger.d(
                                              'Banner GestureDetector tapped at index: $index',
                                            );
                                            _onBannerTap(index);
                                          },
                                          child: CachedNetworkImage(
                                            imageUrl: _bannerImageUrls[index],
                                            fit: BoxFit.cover,
                                            width: double.infinity,
                                            memCacheWidth: 1920,
                                            memCacheHeight: 720,
                                            placeholder: (context, url) =>
                                                const SkeletonShimmer(
                                                  child: SkeletonBox(radius: 0),
                                                ),
                                            errorWidget:
                                                (
                                                  context,
                                                  url,
                                                  error,
                                                ) => Container(
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      colors: [
                                                        ink.emerald.withValues(
                                                          alpha: 0.1,
                                                        ),
                                                        ink.amber.withValues(
                                                          alpha: 0.1,
                                                        ),
                                                      ],
                                                      begin: Alignment.topLeft,
                                                      end:
                                                          Alignment.bottomRight,
                                                    ),
                                                  ),
                                                  child: const Center(
                                                    child: Icon(
                                                      Icons.image_not_supported,
                                                      color: Colors.grey,
                                                      size: 40,
                                                    ),
                                                  ),
                                                ),
                                            cacheManager:
                                                ProductImageCacheManager
                                                    .instance,
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        // Dots sit under the card rather than over the art, so
                        // they never land on top of a banner's own artwork.
                        if (_bannerImageUrls.length > 1) ...[
                          const SizedBox(height: 12),
                          _buildBannerDots(),
                        ],

                        // Most Popular — the four most-viewed products, in place
                        // of a weekly deals rail.
                        const SizedBox(height: 20),
                        _buildPopularProductsSection(isWideScreen),

                        // Modern Categories Section
                        const SizedBox(height: 20),
                        _buildCategoriesSection(),

                        // Subcategories section (grouped by category) — when shown,
                        // the Shipped From filter is rendered below it; otherwise it
                        // stays in its default position right under Categories.
                        if (_selectedCategories.isNotEmpty &&
                            _subcategoriesByCategory.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: _buildGroupedSubcategoriesSection(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildFilterSection(),
                        ] else ...[
                          const SizedBox(height: 16),
                          _buildFilterSection(),
                        ],

                        const SizedBox(height: 24),

                        // Stores / merchants, kept in our own trader-card format
                        Padding(
                          key: _tradersSectionKey,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _buildSectionHead(
                            'All products',
                            trailing: _buildPill(
                              '${_filteredProducts().length} ITEMS',
                              color: ink.emerald,
                              icon: Icons.inventory_2_rounded,
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),

              // The catalogue itself
              if ((_isLoading || !_firstLoadDone) && _products.isEmpty)
                SliverPadding(
                  padding: EdgeInsets.symmetric(
                    horizontal: gridHorizontalPadding,
                  ),
                  sliver: _buildProductGridSkeleton(gridContentWidth),
                )
              else if (_errorMessage != null && _products.isEmpty)
                SliverFillRemaining(child: _buildErrorState())
              else if (filteredProducts.isEmpty)
                SliverFillRemaining(child: _buildEmptyState())
              else
                SliverPadding(
                  padding: EdgeInsets.symmetric(
                    horizontal: gridHorizontalPadding,
                  ),
                  sliver: _buildProductsSliver(
                    filteredProducts,
                    gridContentWidth,
                  ),
                ),
              // Next page lands under the last row.
              if (_isLoadingMore)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    gridHorizontalPadding,
                    12,
                    gridHorizontalPadding,
                    24,
                  ),
                  sliver: _buildProductGridSkeleton(gridContentWidth, rows: 1),
                ),
            ], // end if (!_isSearchMode)
            // Web Footer
            SliverToBoxAdapter(child: WebFooter(dark: ink.isDark)),
          ],
        ),
      ),
    );
  }

  /// Every rail destination past Home needs an account.
  void _pushIfSignedIn(Widget page) {
    if (FirebaseAuth.instance.currentUser == null) {
      _showLoginRequiredDialog();
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => page));
  }

  // ── Shared chrome ────────────────────────────────────────────────────────

  /// Section heading used throughout the page: a large bold title with an
  /// optional emerald action on the right.
  Widget _buildSectionHead(
    String title, {
    String? action,
    VoidCallback? onAction,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            title,
            style: AppTextStyles.titleLarge.copyWith(
              color: ink.text,
              fontWeight: FontWeight.w800,
              fontSize: 22,
              height: 1.1,
            ),
          ),
        ),
        if (trailing != null) trailing,
        if (action != null) ...[
          if (trailing != null) const SizedBox(width: 10),
          GestureDetector(
            onTap: onAction,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  action,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: ink.emerald,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: ink.emerald),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Small amber/emerald capsule used for eyebrows and counters.
  Widget _buildPill(String label, {Color? color, IconData? icon}) {
    final tone = color ?? ink.amber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: tone),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: tone,
              fontWeight: FontWeight.w800,
              fontSize: 10,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  /// Page indicators for the banner carousel.
  Widget _buildBannerDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_bannerImageUrls.length, (index) {
        final isCurrent = _currentBannerIndex == index;
        return GestureDetector(
          onTap: () {
            if (_bannerPageController.hasClients) {
              _bannerPageController.animateToPage(
                index,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: isCurrent ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: isCurrent ? ink.emerald : ink.text.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );
      }),
    );
  }

  /// One type-ahead row: photo, name, brand and price — enough to pick the
  /// right product without opening it first.
  Widget _buildSuggestionRow(ProductSuggestion suggestion) {
    final price = _suggestionPrices[suggestion.productId];
    final brand = suggestion.brand ?? '';

    return InkWell(
      onTap: () => _onSuggestionTap(suggestion),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(gradient: ink.productBackdrop),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: AppNetworkImage(
                    url: suggestion.imageUrl,
                    // Logical slot size — AppNetworkImage multiplies by DPR
                    // itself, so passing a padded number decodes oversized.
                    width: 42,
                    height: 42,
                    fit: BoxFit.contain,
                    backgroundColor: Colors.transparent,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    suggestion.name,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: ink.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (brand.isNotEmpty)
                    Text(
                      brand,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: ink.text.withValues(alpha: 0.5),
                        fontSize: 11.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Absent until the variation read lands; the row is usable without
            // it, so nothing is held back waiting for a price.
            if (price != null)
              Text(
                CurrencyFormatter.formatWithPeso(price),
                style: AppTextStyles.bodyMedium.copyWith(
                  color: ink.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Tile-shaped placeholders matching the catalogue grid, so the first
  /// payload lands where the skeleton already is.
  SliverGrid _buildProductGridSkeleton(double contentWidth, {int rows = 2}) {
    final columns = _productColumns(contentWidth);
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.74,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) => _buildDarkSkeleton(radius: 18),
        childCount: columns * rows,
      ),
    );
  }

  /// Stand-in used while a section's first payload is in flight.
  Widget _buildDarkSkeleton({double? height, double radius = 16}) {
    return SkeletonBox(height: height, radius: radius);
  }

  // ── Hero header ──────────────────────────────────────────────────────────

  String get _greetingLine {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning,';
    if (hour < 18) return 'Good afternoon,';
    return 'Good evening,';
  }

  String get _userInitials {
    final parts = _userFirstName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'D';
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  /// The emerald hero that opens the page: identity, search, the one order
  /// still in flight, today's deal, and the two shortcuts that have no other
  /// route in.
  ///
  /// On wide screens the identity row and search field are dropped — the
  /// desktop top bar already carries both — leaving the hero as a briefing.
  Widget _buildHeroHeader({required bool isWide}) {
    final hero = _buildHeroSurface(isWide: isWide);
    // Only the narrow native layout has a status bar to tint. On web the
    // annotation does nothing but add a view-level layer to every frame.
    if (isWide || kIsWeb) return hero;

    // The hero sits directly under the status bar (HomePage gives this page no
    // app bar), so it asks for light icons. Once it scrolls off the top the
    // annotation stops covering that strip and the default style returns.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
      ),
      child: hero,
    );
  }

  Widget _buildHeroSurface({required bool isWide}) {
    return Container(
      width: double.infinity,
      // The narrow hero runs to the top edge under the status bar; the wide
      // one is a card, so it needs room above it.
      margin: isWide
          ? const EdgeInsets.fromLTRB(16, 24, 16, 0)
          : EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.fromLTRB(
        16,
        isWide ? 20 : MediaQuery.of(context).padding.top + 14,
        16,
        20,
      ),
      decoration: BoxDecoration(
        gradient: InkPalette.heroGradient,
        borderRadius: isWide
            ? BorderRadius.circular(28)
            : const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeroIdentityRow(),
          const SizedBox(height: 18),
          _buildHeroSearchField(),
          // While a search is running the hero collapses to identity + field,
          // so the results start as high up the screen as possible.
          if (!_isSearchMode) ...[
            const SizedBox(height: 14),
            _buildOrderTrackingRow(),
            if (_dealProduct != null) ...[
              const SizedBox(height: 14),
              _buildDealOfTheDayCard(),
            ],
            const SizedBox(height: 20),
            _buildHeroQuickActions(),
          ],
        ],
      ),
    );
  }

  Widget _buildHeroIdentityRow() {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
          ),
          child: Text(
            _userInitials,
            style: AppTextStyles.titleMedium.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _greetingLine,
                style: AppTextStyles.bodySmall.copyWith(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
              Text(
                _userFirstName,
                style: AppTextStyles.titleLarge.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 24,
                  height: 1.15,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        // The only action in the hero. Cart and Categories live in the side
        // rail on wide screens and in the tab bar on narrow ones, so putting
        // them here too would just duplicate them.
        _buildHeroIconButton(
          icon: Icons.notifications_none_rounded,
          badgeCount: _unreadNotifications,
          tooltip: 'Notifications',
          onTap: () => _pushIfSignedIn(const NotificationsPage()),
        ),
      ],
    );
  }

  Widget _buildHeroIconButton({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
    int badgeCount = 0,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              if (badgeCount > 0)
                Positioned(
                  right: -3,
                  top: -3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: ink.amber,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      badgeCount > 99 ? '99+' : '$badgeCount',
                      style: TextStyle(
                        color: ink.onAmber,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroSearchField() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.search,
            size: 20,
            color: Colors.white.withValues(alpha: 0.75),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: _onSearchChanged,
              onSubmitted: _onSearchSubmitted,
              textInputAction: TextInputAction.search,
              style: AppTextStyles.bodyMedium.copyWith(color: Colors.white),
              cursorColor: Colors.white,
              // The app's global inputDecorationTheme fills fields with a
              // near-white surface and draws its own outline + 16px padding.
              // The glass field supplies all of that itself, so every one of
              // those has to be switched off explicitly — `border: none`
              // alone leaves the themed enabled/focused borders in place.
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                fillColor: Colors.transparent,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                hintText: 'Search products, brands…',
                hintStyle: AppTextStyles.bodyMedium.copyWith(
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
          if (_searchQuery.isNotEmpty)
            GestureDetector(
              onTap: _clearSearch,
              child: Icon(
                Icons.close,
                size: 18,
                color: Colors.white.withValues(alpha: 0.75),
              ),
            ),
        ],
      ),
    );
  }

  /// Wording for the stage an in-flight order is at.
  String _orderPhraseFor(order_model.OrderStatus status) {
    switch (status) {
      case order_model.OrderStatus.pending:
        return 'awaiting confirmation';
      case order_model.OrderStatus.confirmed:
        return 'being prepared';
      case order_model.OrderStatus.to_ship:
        return 'ready to ship';
      case order_model.OrderStatus.shipping:
        return 'on the way';
      default:
        return 'in progress';
    }
  }

  String _placedLabel(DateTime date) {
    final today = DateTime.now();
    final days = DateTime(
      today.year,
      today.month,
      today.day,
    ).difference(DateTime(date.year, date.month, date.day)).inDays;
    if (days <= 0) return 'placed today';
    if (days == 1) return 'placed yesterday';
    return 'placed $days days ago';
  }

  /// The single briefing row kept from the design: where the buyer's current
  /// order stands. Falls back to a prompt to open Orders when nothing is out.
  Widget _buildOrderTrackingRow() {
    final order = _activeOrder;
    final int itemCount = order == null
        ? 0
        : order.items.fold<int>(0, (total, i) => total + i.quantity);
    final shortId = order == null
        ? ''
        : (order.orderId.length > 8
              ? order.orderId.substring(order.orderId.length - 8)
              : order.orderId);

    return GestureDetector(
      onTap: () {
        if (FirebaseAuth.instance.currentUser == null) {
          _showLoginRequiredDialog();
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => order != null
                ? OrderDetailsPage(order: order)
                : const OrdersPage(),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.local_shipping_outlined,
              size: 20,
              color: Colors.white.withValues(alpha: 0.85),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    order == null
                        ? 'Track your orders'
                        : '$itemCount ${itemCount == 1 ? 'item' : 'items'} ${_orderPhraseFor(order.status)}',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    order == null
                        ? 'See where every delivery stands'
                        : 'Order #$shortId · ${_placedLabel(order.createdAt)}',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Track',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The deal card: a near-black panel inside the emerald hero, with the
  /// product photo bleeding off the right edge.
  Widget _buildDealOfTheDayCard() {
    final product = _dealProduct;
    final voucher = _dealVoucher;
    if (product == null || voucher == null) return const SizedBox.shrink();

    final voucherLabel = _formatSingleVoucher(voucher);
    final price = product.lowestPrice;
    final variation = product.variations?.isNotEmpty == true
        ? product.variations!.first
        : null;
    // The deal photo renders large, so full-size wins over the thumbnail here.
    final imageUrl = (variation?.imageURL?.isNotEmpty == true)
        ? variation!.imageURL
        : (product.imageURL.isNotEmpty
              ? product.imageURL
              : (variation?.thumbnailURL ?? product.thumbnailURL));

    return GestureDetector(
      onTap: () {
        _clickTrackingService.trackProductClick(product.productId);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) =>
                ProductDetailPage(productId: product.productId),
          ),
        );
      },
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: ink.heroCard,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Stack(
          children: [
            // Photo bleeds off the right edge rather than sitting in a framed
            // strip — that overlap is what stops the card reading as two boxes.
            Positioned(
              right: -14,
              top: 0,
              bottom: 0,
              width: 150,
              child: Center(
                child: SizedBox(
                  height: 130,
                  child: AppNetworkImage(
                    url: imageUrl,
                    width: 150,
                    height: 130,
                    fit: BoxFit.contain,
                    backgroundColor: Colors.transparent,
                  ),
                ),
              ),
            ),
            if (_dealEndsAt != null)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.schedule, size: 11, color: Colors.white),
                      const SizedBox(width: 4),
                      _DealCountdown(
                        endsAt: _dealEndsAt!,
                        onExpired: _clearDealOfTheDay,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 132, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildPill('DEAL OF THE DAY'),
                  const SizedBox(height: 10),
                  Text(
                    product.name,
                    style: AppTextStyles.titleLarge.copyWith(
                      color: ink.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 19,
                      height: 1.1,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if ((product.brand ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        product.brand!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: ink.text.withValues(alpha: 0.55),
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (price != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      CurrencyFormatter.formatWithPeso(price),
                      style: AppTextStyles.titleLarge.copyWith(
                        color: ink.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 25,
                        height: 1,
                      ),
                    ),
                  ],
                  if (voucherLabel != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      voucherLabel,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: ink.emerald,
                        fontWeight: FontWeight.w700,
                        fontSize: 11.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF34D399), Color(0xFF0F766E)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Shop now',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.arrow_forward,
                          size: 14,
                          color: Colors.white,
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
    );
  }

  /// The two shortcuts kept from the design's quick-action row: repeating a
  /// past order, and reaching a human.
  Widget _buildHeroQuickActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildHeroQuickAction(
          icon: Icons.refresh_rounded,
          label: 'Reorder',
          onTap: () {
            if (FirebaseAuth.instance.currentUser == null) {
              _showLoginRequiredDialog();
              return;
            }
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (context) => const OrdersPage()));
          },
        ),
        _buildHeroQuickAction(
          icon: Icons.headset_mic_outlined,
          label: 'Support',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const PublicSupportPage(),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildHeroQuickAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: Colors.white.withValues(alpha: 0.8),
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── Most popular ─────────────────────────────────────────────────────────

  /// Replaces the design's "deals of the week" rail: the four products buyers
  /// open most, sitting directly under the promo banner.
  Widget _buildPopularProductsSection(bool isWideScreen) {
    if (!_isLoadingPopular && _popularProducts.isEmpty) {
      return const SizedBox.shrink();
    }

    final width = _contentWidth;
    final crossAxisCount = width >= 860 ? 4 : (width >= 560 ? 3 : 2);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHead(
            'Most popular',
            trailing: _buildPill(
              'MOST VIEWED',
              color: ink.emerald,
              icon: Icons.local_fire_department_rounded,
            ),
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: _isLoadingPopular
                ? crossAxisCount
                : _popularProducts.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.74,
            ),
            itemBuilder: (context, index) {
              if (_isLoadingPopular) {
                return _buildDarkSkeleton(radius: 18);
              }
              // Actual cell width, so the shot decodes at its slot size
              // rather than a guessed constant.
              final cellWidth =
                  (width - 32 - 12 * (crossAxisCount - 1)) / crossAxisCount;
              // Same tile as the catalogue grid, with its rank badge on.
              return _buildProductCard(
                _popularProducts[index],
                cellWidth,
                rank: index + 1,
              );
            },
          ),
        ],
      ),
    );
  }

  // Build error state with modern design
  Widget _buildErrorState() {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.error_outline, size: 64, color: Colors.red),
          ),
          const SizedBox(height: 24),
          Text(
            'Oops! Something went wrong',
            style: AppTextStyles.titleLarge.copyWith(
              fontWeight: FontWeight.bold,
              color: ink.text,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              _errorMessage ?? 'Unable to load products at this time',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: ink.text.withValues(alpha: 0.7),
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
                  color: ink.emerald.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: () {
                AppLogger.d("Retry button pressed");
                _cacheTimestamp = null;
                ProductImageCacheManager.instance.emptyCache();
                _resetAndRefresh();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: ink.emerald,
                foregroundColor: ink.onEmerald,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
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

  // Build empty state with modern design
  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: ink.emerald.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.search_off, size: 64, color: ink.emerald),
          ),
          const SizedBox(height: 24),
          Text(
            'No products found',
            style: AppTextStyles.titleLarge.copyWith(
              fontWeight: FontWeight.bold,
              color: ink.text,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'There are no products to display at this time.\nTry refreshing or check back later.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: ink.text.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 32),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: ink.emerald.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: () {
                AppLogger.d("Empty state refresh button pressed");
                _cacheTimestamp = null;
                ProductImageCacheManager.instance.emptyCache();
                _resetAndRefresh();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: ink.emerald,
                foregroundColor: ink.onEmerald,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
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

  // Build modern product grid with enhanced design
  // Get subcategory click count from Firestore
  Future<int> _getSubCategoryClickCount(String subCategoryId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('SubCategoryClicks')
          .doc(subCategoryId)
          .get();

      if (doc.exists) {
        return doc.data()?['clickCounter'] ?? 0;
      }
      return 0;
    } catch (e) {
      AppLogger.d('Error getting subcategory click count: $e');
      return 0;
    }
  }

  // Open the full-screen category/subcategory sidebar from the right
  /// Opens the dedicated browse page and applies whatever comes back.
  ///
  /// Replaces the slide-in sheet this page used to show — a full page can
  /// carry product counts and brands, which a 400px drawer could not.
  Future<void> _openBrowsePage({
    BrowseFilter initialFilter = BrowseFilter.all,
  }) async {
    final selection = await Navigator.of(context).push<BrowseSelection>(
      MaterialPageRoute(
        builder: (context) => CategoriesPage(initialFilter: initialFilter),
      ),
    );
    if (!mounted || selection == null) return;
    _applyBrowseSelection(selection);
  }

  /// Picks up a selection made from a Browse page this state did not push.
  void _applyPendingBrowseSelection() {
    final selection = pendingBrowseSelection.value;
    if (selection == null || !mounted) return;
    pendingBrowseSelection.value = null;
    _applyBrowseSelection(selection);
  }

  void _applyBrowseSelection(BrowseSelection selection) {
    final categoryName = selection.categoryName;
    if (categoryName != null) {
      // Route through the normal handler so click tracking, subcategory
      // loading and pagination reset all behave as if it were tapped inline.
      if (!_selectedCategories.contains(categoryName)) {
        _onCategorySelected(categoryName);
      }
      _scrollToTraders();
      return;
    }

    final brand = selection.brand;
    if (brand != null) {
      setState(() {
        _selectedBrand = brand;
        _products = [];
        _lastDocument = null;
        _hasMore = true;
        _loadedSellerIds = {};
      });
      _loadFirstPage();
      _scrollToTraders();
    }
  }

  /// After a browse selection, put the results in view rather than leaving the
  /// buyer at the top of the hero wondering what changed. Deferred a frame so
  /// the heading exists after the filter rebuild.
  void _scrollToTraders() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final anchor = _tradersSectionKey.currentContext;
      if (anchor == null) return;
      Scrollable.ensureVisible(
        anchor,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        alignment: 0.05,
      );
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // NEW WIDGET BUILDERS FOR REDESIGNED LAYOUT
  // ═══════════════════════════════════════════════════════════════════════════

  // Build Brand Section (horizontally scrollable, matches Categories style)
  int _categoryCrossAxisCount(BuildContext context) {
    final w = _contentWidth;
    if (w >= 1200) return 7;
    if (w >= 900) return 6;
    if (w >= 600) return 5;
    return 4;
  }

  // Build Categories Section (responsive grid)
  /// True while the real category set is still on its way. The list is seeded
  /// with a lone 'All' entry, which is not something worth rendering on its own.
  bool get _categoriesPending =>
      (_isLoading || !_firstLoadDone) && _categories.length <= 1;

  Widget _buildCategoriesSection() {
    final crossAxisCount = _categoryCrossAxisCount(context);

    final hasSelection = _selectedCategories.isNotEmpty;
    final isCollapsedToSelection = hasSelection && !_categoryGridForceExpanded;

    // Default view reveals categories one row at a time.
    final defaultVisibleCount = (_visibleCategoryRows * crossAxisCount).clamp(
      0,
      _categories.length,
    );

    List<int> visibleIndices;
    if (isCollapsedToSelection) {
      final selectedRows = <int>{};
      for (var i = 0; i < _categories.length; i++) {
        if (_selectedCategories.contains(_categories[i])) {
          selectedRows.add(i ~/ crossAxisCount);
        }
      }
      visibleIndices = [
        for (var i = 0; i < _categories.length; i++)
          if (selectedRows.contains(i ~/ crossAxisCount)) i,
      ];
    } else {
      visibleIndices = List.generate(defaultVisibleCount, (i) => i);
    }

    // Whether more rows remain hidden / can be collapsed in the default view.
    final hasMoreRows = defaultVisibleCount < _categories.length;
    final canShowLess = _visibleCategoryRows > 1;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHead(
            'Top categories',
            action: 'See all',
            onAction: () =>
                _openBrowsePage(initialFilter: BrowseFilter.categories),
          ),
          const SizedBox(height: 14),
          if (_categoriesPending)
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: crossAxisCount,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1086 / 1448,
              ),
              itemBuilder: (context, index) => const SkeletonBox(radius: 14),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: visibleIndices.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                // Portrait 3:4 (width:height) category artwork.
                childAspectRatio: 1086 / 1448,
              ),
              itemBuilder: (context, index) {
                final categoryIndex = visibleIndices[index];
                final category = _categories[categoryIndex];
                final isSelected = category == 'All'
                    ? _selectedCategories.isEmpty
                    : _selectedCategories.contains(category);
                final imageUrl = category == 'All'
                    ? null
                    : _categoryNameToImage[category];
                return _buildCategoryGridTile(
                  category: category,
                  isSelected: isSelected,
                  imageUrl: imageUrl,
                );
              },
            ),
          if (isCollapsedToSelection) ...[
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  setState(() => _categoryGridForceExpanded = true);
                },
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: ink.emerald,
                ),
                label: Text(
                  'Change category',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: ink.emerald,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ] else if (hasSelection && _categoryGridForceExpanded) ...[
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  setState(() => _categoryGridForceExpanded = false);
                },
                icon: Icon(
                  Icons.keyboard_arrow_up_rounded,
                  size: 18,
                  color: ink.emerald,
                ),
                label: Text(
                  'Hide other categories',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: ink.emerald,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ] else if (hasMoreRows) ...[
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  setState(() => _visibleCategoryRows++);
                },
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: ink.emerald,
                ),
                label: Text(
                  'Show more',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: ink.emerald,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ] else if (canShowLess) ...[
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  setState(() => _visibleCategoryRows = 1);
                },
                icon: Icon(
                  Icons.keyboard_arrow_up_rounded,
                  size: 18,
                  color: ink.emerald,
                ),
                label: Text(
                  'Show less',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: ink.emerald,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCategoryGridTile({
    required String category,
    required bool isSelected,
    required String? imageUrl,
  }) {
    return GestureDetector(
      onTap: () => _onCategorySelected(category),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: ink.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? ink.emerald : ink.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        // Full-bleed category artwork (name is baked into the image graphic).
        child: category == 'All'
            ? Image.asset('lib/assets/icons/all.png', fit: BoxFit.cover)
            : imageUrl != null && imageUrl.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: ink.emerald.withValues(alpha: 0.08),
                  child: Center(
                    child: Icon(
                      Icons.category,
                      color: ink.emerald.withValues(alpha: 0.5),
                      size: 24,
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: ink.emerald.withValues(alpha: 0.08),
                  child: Center(
                    child: Icon(
                      Icons.category,
                      color: ink.emerald.withValues(alpha: 0.5),
                      size: 24,
                    ),
                  ),
                ),
              )
            : Container(
                color: ink.emerald.withValues(alpha: isSelected ? 0.14 : 0.08),
                child: Center(
                  child: Icon(Icons.category, color: ink.emerald, size: 28),
                ),
              ),
      ),
    );
  }

  // Build Filter Section (horizontal filter bar with chips)
  Widget _buildFilterSection() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Shipped From Filter
            _buildFilterChip(
              icon: Icons.local_shipping_rounded,
              label: 'Shipped From',
              value: _selectedShippedFrom,
              options: _shippedFromOptions,
              onSelected: (value) {
                setState(() {
                  _selectedShippedFrom = value;
                  _products = [];
                  _lastDocument = null;
                  _hasMore = true;
                });
                _loadFirstPage();
              },
            ),
          ],
        ),
      ),
    );
  }

  // Build individual filter chip with dropdown
  Widget _buildFilterChip({
    required IconData icon,
    required String label,
    required String value,
    required List<String> options,
    required Function(String) onSelected,
  }) {
    final isActive = value != 'All';

    return PopupMenuButton<String>(
      onSelected: onSelected,
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: ink.surface,
      itemBuilder: (context) => options.map((option) {
        final isSelectedOption = option == value;
        return PopupMenuItem<String>(
          value: option,
          child: Row(
            children: [
              if (isSelectedOption)
                Icon(Icons.check_rounded, color: ink.emerald, size: 18)
              else
                const SizedBox(width: 18),
              const SizedBox(width: 8),
              Text(
                option,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: isSelectedOption ? ink.emerald : ink.text,
                  fontWeight: isSelectedOption
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? ink.emerald.withValues(alpha: 0.1) : ink.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? ink.emerald : ink.text.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive ? ink.emerald : ink.text.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 6),
            Text(
              value == 'All' ? label : value,
              style: AppTextStyles.bodySmall.copyWith(
                color: isActive ? ink.emerald : ink.text,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: isActive ? ink.emerald : ink.text.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  // ── Seller data helpers ──────────────────────────────────────────────────

  /// Returns cached seller data or fetches from Firestore and caches the result.
  /// A cached null value means the document was queried but does not exist.
  Future<Map<String, dynamic>?> _getSellerDataCached(String sellerId) async {
    if (_sellerDataCache.containsKey(sellerId))
      return _sellerDataCache[sellerId];
    if (_sellerDataFetching.contains(sellerId)) {
      await Future.delayed(const Duration(milliseconds: 100));
      return _sellerDataCache[sellerId];
    }
    _sellerDataFetching.add(sellerId);
    try {
      final data = await _userService.getSellerData(sellerId);
      _sellerDataCache[sellerId] = data;
      return data;
    } catch (e) {
      AppLogger.d('Error fetching seller data for $sellerId: $e');
      _sellerDataCache[sellerId] = null;
      return null;
    } finally {
      _sellerDataFetching.remove(sellerId);
    }
  }

  /// Batch-fetches seller data for all unique sellerIds in [products] that are
  /// not already cached. Runs fetches concurrently.
  Future<void> _prefetchSellerData(List<Product> products) async {
    final sellerIds = products
        .map((p) => p.sellerId)
        .where((id) => id.isNotEmpty)
        .toSet();

    final uncachedSellerIds = sellerIds
        .where((id) => !_sellerDataCache.containsKey(id))
        .toSet();
    if (uncachedSellerIds.isNotEmpty) {
      AppLogger.d(
        'Pre-fetching seller data for ${uncachedSellerIds.length} sellers',
      );
      await Future.wait(uncachedSellerIds.map(_getSellerDataCached));
      AppLogger.d('Seller data pre-fetch complete');
    }
  }

  DateTime? _parseVoucherDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  /// Sorts vouchers by priority:
  ///   1. percentage (highest discountValue first)
  ///   2. fixed (highest discountValue first)
  ///   3. free_delivery
  /// Returns a new sorted list without mutating the input.
  List<Map<String, dynamic>> _sortVouchersByPriority(
    List<Map<String, dynamic>> vouchers,
  ) {
    int typeRank(String? type) {
      switch (type) {
        case 'percentage':
          return 0;
        case 'fixed':
          return 1;
        case 'free_delivery':
          return 2;
        default:
          return 3;
      }
    }

    final sorted = [...vouchers];
    sorted.sort((a, b) {
      final rankA = typeRank(a['discountType'] as String?);
      final rankB = typeRank(b['discountType'] as String?);
      if (rankA != rankB) return rankA.compareTo(rankB);
      final valA = (a['discountValue'] as num?)?.toDouble() ?? 0;
      final valB = (b['discountValue'] as num?)?.toDouble() ?? 0;
      return valB.compareTo(valA); // highest first
    });
    return sorted;
  }

  /// Formats a single voucher into its display label based on `discountType`.
  /// Returns null if the voucher has invalid data (e.g. 0% off, ₱0 off).
  String? _formatSingleVoucher(Map<String, dynamic> voucher) {
    final type = (voucher['discountType'] as String?) ?? '';
    final code = (voucher['code'] as String?) ?? '';
    final value = (voucher['discountValue'] as num?)?.toDouble() ?? 0;
    final minAmount = (voucher['minimumOrderAmount'] as num?)?.toDouble() ?? 0;

    switch (type) {
      case 'percentage':
        if (value <= 0) return null;
        final pct = value == value.roundToDouble()
            ? value.toStringAsFixed(0)
            : value.toString();
        return '$pct% OFF ${CurrencyFormatter.formatWithPeso(minAmount)} : $code';
      case 'fixed':
        if (value <= 0) return null;
        return '${CurrencyFormatter.formatWithPeso(value)} OFF : $code';
      case 'free_delivery':
        return 'Free Shipping';
      default:
        return null;
    }
  }

  /// Products left after every active filter. Category and subcategory are
  /// applied server-side when exactly one is selected, so this re-applies them
  /// for the multi-select case and handles the rest client-side.
  List<Product> _filteredProducts() {
    final targetRegion = _selectedShippedFrom == 'All'
        ? null
        : (_selectedShippedFrom == 'Nearest You'
              ? _userRegion
              : _selectedShippedFrom);

    return _products.where((product) {
      if (product.isDraft == true) return false;
      if (product.isActive == false) return false;
      if (product.isArchived == true) return false;
      if (BannedSellerService.instance.isBanned(product.sellerId)) return false;

      if (_selectedBrand != null && product.brand != _selectedBrand) {
        return false;
      }

      if (_selectedCategories.isNotEmpty) {
        final selectedCategoryIds = _selectedCategories
            .map((name) => _categoryNameToId[name])
            .whereType<String>()
            .toList();
        if (!selectedCategoryIds.contains(product.categoryId)) return false;

        if (_selectedSubCategories.isNotEmpty) {
          final hasSubCategory = product.subCategoryId.isNotEmpty;
          final isSelected = _selectedSubCategories.contains(
            product.subCategoryId,
          );
          if (hasSubCategory && !isSelected) return false;
        }
      }

      // Shipped From reads the seller's region, so it only bites once that
      // seller's document has been fetched.
      if (targetRegion != null &&
          _sellerRegion(product.sellerId) != targetRegion) {
        return false;
      }

      return true;
    }).toList();
  }

  /// The catalogue grid. Paginates by scroll position rather than a button —
  /// [_scrollListener] asks for the next page as the last row comes into view.
  Widget _buildProductsSliver(List<Product> products, double contentWidth) {
    final columns = _productColumns(contentWidth);
    final cellWidth = (contentWidth - 12 * (columns - 1)) / columns;

    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.74,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) => _buildProductCard(products[index], cellWidth),
        childCount: products.length,
      ),
    );
  }

  int _productColumns(double contentWidth) {
    if (contentWidth >= 1000) return 5;
    if (contentWidth >= 760) return 4;
    if (contentWidth >= 520) return 3;
    return 2;
  }

  /// One catalogue tile, in the same shape as the Most Popular cards so the
  /// page reads as one surface.
  Widget _buildProductCard(Product product, double cellWidth, {int? rank}) {
    final variation = product.variations?.isNotEmpty == true
        ? product.variations!.first
        : null;
    final imageUrl =
        variation?.thumbnailURL ??
        product.thumbnailURL ??
        variation?.imageURL ??
        product.imageURL;
    final price = product.lowestPrice;
    final brand = product.brand ?? '';

    return GestureDetector(
      onTap: () {
        _clickTrackingService.trackProductClick(product.productId);
        NavigationUtils.navigateToProductDetail(context, product.productId);
      },
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: ink.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ink.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product shots are cut out on white, so they get a neutral
            // pedestal rather than floating on the card.
            Expanded(
              child: Container(
                decoration: BoxDecoration(gradient: ink.productBackdrop),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: AppNetworkImage(
                        url: imageUrl,
                        width: cellWidth,
                        height: cellWidth,
                        fit: BoxFit.contain,
                        backgroundColor: Colors.transparent,
                      ),
                    ),
                    if (rank != null)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: ink.amber,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '#$rank',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: ink.onAmber,
                              fontWeight: FontWeight.w800,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (brand.isNotEmpty)
                    Text(
                      brand.toUpperCase(),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: ink.text.withValues(alpha: 0.45),
                        fontWeight: FontWeight.w700,
                        fontSize: 9,
                        letterSpacing: 0.7,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  Text(
                    product.name,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: ink.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      height: 1.25,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    price != null
                        ? CurrencyFormatter.formatWithPeso(price)
                        : 'Price on request',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: ink.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Deal countdown
// ─────────────────────────────────────────────────────────────────────────────

/// The ticking half of the deal chip.
///
/// It owns its own timer so a passing second rebuilds ~20 characters of text
/// rather than the whole listing page, and it stops the moment it leaves the
/// tree — a timer that outlives its widget keeps asking for frames, which on
/// web surfaces as `Trying to render a disposed EngineFlutterView`.
class _DealCountdown extends StatefulWidget {
  const _DealCountdown({
    required this.endsAt,
    required this.onExpired,
    required this.style,
  });

  final DateTime endsAt;
  final VoidCallback onExpired;
  final TextStyle style;

  @override
  State<_DealCountdown> createState() => _DealCountdownState();
}

class _DealCountdownState extends State<_DealCountdown> {
  Timer? _timer;
  late Duration _left = _remaining();

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(_DealCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.endsAt != widget.endsAt) {
      _left = _remaining();
      _start();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Duration _remaining() {
    final left = widget.endsAt.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final left = _remaining();
      if (left == Duration.zero) {
        timer.cancel();
        // Let the page retire the card after this frame, not during it.
        WidgetsBinding.instance.addPostFrameCallback((_) => widget.onExpired());
        return;
      }
      setState(() => _left = left);
    });
  }

  /// Beyond a day it reads in days/hours; inside the last day it ticks
  /// HH:MM:SS.
  String get _label {
    if (_left.inDays >= 1) {
      return '${_left.inDays}d ${_left.inHours % 24}h';
    }
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(_left.inHours)}:${two(_left.inMinutes % 60)}:'
        '${two(_left.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) => Text(_label, style: widget.style);
}

// ─────────────────────────────────────────────────────────────────────────────
// Dark loading placeholder
// ─────────────────────────────────────────────────────────────────────────────
