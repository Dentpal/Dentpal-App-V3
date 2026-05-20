import 'dart:async';
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
import '../services/product_service.dart';
import '../services/user_service.dart';
import '../services/category_service.dart';
import '../services/cart_service.dart';
import '../services/click_tracking_service.dart';
import '../widgets/product_card.dart';
import '../../core/app_theme/app_colors.dart';
import '../../core/app_theme/app_text_styles.dart';
import 'package:dentpal/utils/app_logger.dart';
import 'package:dentpal/utils/currency_formatter.dart';
import 'package:dentpal/utils/navigation_utils.dart';
import 'cart_page.dart';
import 'product_detail_page.dart';
import '../services/product_search_service.dart';
import '../../login_page.dart';
import 'package:flutter/services.dart';
import '../../profile/pages/profile_page.dart';
import '../../profile/services/address_service.dart';
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
  final ProductService _productService = ProductService();
  final UserService _userService = UserService();
  final CategoryService _categoryService = CategoryService();
  final ClickTrackingService _clickTrackingService = ClickTrackingService();
  final CartService _cartService = CartService();
  bool _isLoading = false;
  bool _isLoadingMore = false;
  List<String> _selectedCategories = [];
  List<String> _categories = ['All'];
  bool _showAllCategories = false;
  bool _categoryGridForceExpanded = false;
  String? _errorMessage;
  List<Product> _products = [];
  DateTime? _cacheTimestamp;
  DocumentSnapshot? _lastDocument;
  bool _hasMore = true;
  final int _pageSize = 50; // Fetch products in larger batches to accumulate stores
  static const int _storePageSize = 10; // Display 10 unique stores per page
  Set<String> _loadedSellerIds = {};
  final ScrollController _scrollController = ScrollController();
  final PageController _bannerPageController = PageController();
  Timer? _bannerAutoScrollTimer;

  bool _isSeller = false;
  String _userFirstName = 'User';
  String? _userRegion; // Classified region: 'NCR' | 'Luzon' | 'Visayas' | 'Mindanao'

  // Cart item count for badge
  int _cartItemCount = 0;
  StreamSubscription<int>? _cartCountSubscription;
  StreamSubscription<User?>? _authStateSubscription;

  // Active banner image URLs and target URLs loaded from Realtime Database
  List<String> _bannerImageUrls = [];
  List<String?> _bannerTargetUrls = [];
  int _currentBannerIndex = 0;

  // Cache for seller/vendor data fetched from Firestore, keyed by sellerId.
  // A null value means the document was fetched but does not exist in Firestore.
  Map<String, Map<String, dynamic>?> _sellerDataCache = {};
  Set<String> _sellerDataFetching = {};

  // Cache for active vouchers per seller, keyed by sellerId. Each value is
  // the list of currently-valid voucher documents (already date-filtered).
  final Map<String, List<Map<String, dynamic>>> _sellerVouchersCache = {};
  final Set<String> _sellerVouchersFetching = {};

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
  final List<String> _shippedFromOptions = ['All', 'Nearest You', 'NCR', 'Luzon', 'Visayas', 'Mindanao'];

  // Inline search state
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ProductSearchService _searchService = ProductSearchService();
  String _searchQuery = '';
  bool _isSearchMode = false;
  List<Product> _searchResults = [];
  List<String> _searchSuggestions = [];
  bool _showSearchSuggestions = false;
  bool _isSearching = false;
  bool _isLoadingMoreSearch = false;
  Timer? _searchDebounceTimer;
  SearchResult? _lastSearchResult;
  bool _showMobileSearchBar = false;

  // Override to keep this page alive when navigating away
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    // Simple initialization without singleton pattern to avoid rebuild loops
    _loadFirstPage();
    _checkSellerStatus();
    _loadUserName();
    _loadUserRegion();
    _loadActiveBanner(); // Load active banner image from Realtime Database
    _listenToCartCount(); // Listen to cart item count for badge
    _loadStoresForBrandSection(); // Load sellers for brand/store section

    // Add scroll listener for pagination
    _scrollController.addListener(_scrollListener);

    // Clean up old click tracking data (run async without waiting)
    _clickTrackingService.cleanupOldClickData();

    // Add debug log to track initialization
    AppLogger.d(
      "ProductListingPage initState called, products: ${_products.length}, timestamp: $_cacheTimestamp",
    );
  }

  // Brands for the brand section — list of {brand, brandImage}
  List<Map<String, String>> _brandList = [];

  // Load unique brands from Products collection (brand + brandImage)
  Future<void> _loadStoresForBrandSection() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('Product')
          .where('isActive', isEqualTo: true)
          .get();

      // Use lowercase key for deduplication, store original display name
      final Map<String, String> brandDisplayName = {}; // lowercased -> display name
      final Map<String, String> brandImageMap = {}; // lowercased -> brandImage url
      for (final doc in snapshot.docs) {
        final data = doc.data();
        // Filter out drafts client-side to avoid composite index requirement
        if (data['isDraft'] == true) continue;
        final rawBrand = data['brand'] as String?;
        if (rawBrand == null || rawBrand.trim().isEmpty) continue;
        final brandKey = rawBrand.trim().toLowerCase();
        if (!brandImageMap.containsKey(brandKey)) {
          brandDisplayName[brandKey] = rawBrand.trim();
          final img = (data['brandImage'] as String?) ?? (data['brandimage'] as String?) ?? '';
          brandImageMap[brandKey] = img;
        }
      }

      final List<Map<String, String>> brands = brandImageMap.entries
          .map((e) => {'brand': brandDisplayName[e.key]!, 'brandImage': e.value})
          .toList()
        ..sort((a, b) => a['brand']!.toLowerCase().compareTo(b['brand']!.toLowerCase()));

      if (mounted) {
        setState(() {
          _brandList = brands;
        });
      }
      AppLogger.d('Loaded ${_brandList.length} brands');
    } catch (e) {
      AppLogger.d('Error loading brands: $e');
    }
  }

  // Listen to auth state changes and (re)subscribe to cart count accordingly
  void _listenToCartCount() {
    _authStateSubscription?.cancel();
    _authStateSubscription = FirebaseAuth.instance.authStateChanges().listen((
      user,
    ) {
      _cartCountSubscription?.cancel();
      _cartCountSubscription = null;

      if (!mounted) return;

      if (user == null) {
        setState(() {
          _cartItemCount = 0;
        });
        return;
      }

      _cartCountSubscription = _cartService.cartItemCountStream().listen(
        (count) {
          if (mounted) {
            setState(() {
              _cartItemCount = count;
            });
          }
        },
        onError: (error) {
          AppLogger.d('Error listening to cart count: $error');
        },
      );
    });
  }

  // Fetch all active banner images from Firebase Realtime Database
  Future<void> _loadActiveBanner() async {
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
          AppLogger.d(
            'Navigating to product detail page with ID: $productId',
          );

          // Navigate to product detail page within the app
          if (mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) =>
                    ProductDetailPage(productId: productId),
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
    _bannerAutoScrollTimer?.cancel();
    _bannerPageController.dispose();
    _authStateSubscription?.cancel();
    _cartCountSubscription?.cancel();
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

  // ── Delivery estimation ────────────────────────────────────────────────
  // Mapping: FROM seller region → TO user region → estimated days label.
  static const Map<String, Map<String, String>> _deliveryEstimateMap = {
    'NCR': {
      'NCR': '2-4 days',
      'Luzon': '3-5 days',
      'Visayas': '6-8 days',
      'Mindanao': '6-10 days',
    },
    'Luzon': {
      'NCR': '3-5 days',
      'Luzon': '3-5 days',
      'Visayas': '6-8 days',
      'Mindanao': '6-8 days',
    },
    'Visayas': {
      'NCR': '5-7 days',
      'Luzon': '5-8 days',
      'Visayas': '5-8 days',
      'Mindanao': '6-9 days',
    },
    'Mindanao': {
      'NCR': '5-7 days',
      'Luzon': '5-8 days',
      'Visayas': '7-11 days',
      'Mindanao': '3-6 days',
    },
  };

  static const String _defaultDeliveryLabel = '3-7 days';

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
    final raw = _sellerDataCache[sellerId];
    if (raw == null) return null;
    final vendor = raw['vendor'] is Map
        ? raw['vendor'] as Map<String, dynamic>
        : <String, dynamic>{};
    final company = vendor['company'] is Map
        ? vendor['company'] as Map<String, dynamic>
        : <String, dynamic>{};
    final address = company['address'] is Map
        ? company['address'] as Map<String, dynamic>
        : <String, dynamic>{};
    final location = (address['location'] as String?) ??
        (address['province'] as String?);
    return _classifyRegion(location);
  }

  /// Returns a delivery-estimate label for shipping FROM the seller TO the
  /// current user. Falls back to [_defaultDeliveryLabel] when either side's
  /// region cannot be determined.
  String _estimateDelivery(String sellerId) {
    final from = _sellerRegion(sellerId);
    final to = _userRegion;
    if (from == null || to == null) return _defaultDeliveryLabel;
    return _deliveryEstimateMap[from]?[to] ?? _defaultDeliveryLabel;
  }

  void _showLoginRequiredDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.shopping_cart_outlined,
                  color: AppColors.primary,
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
              color: AppColors.onSurface.withValues(alpha: 0.8),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.onSurface.withValues(alpha: 0.6),
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
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
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
        _scrollController.position.maxScrollExtent - 200) return;
    if (_isSearchMode) {
      if (!_isSearching && !_isLoadingMoreSearch && (_lastSearchResult?.hasMore ?? false)) {
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
    if (isLoadMore && (_isLoadingMoreSearch || !(_lastSearchResult?.hasMore ?? true))) return;
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

  Future<void> _loadSearchSuggestions(String query) async {
    final suggestions = await _searchService.getSearchSuggestions(query);
    if (mounted) setState(() { _searchSuggestions = suggestions; });
  }

  void _onSuggestionTap(String suggestion) {
    _searchController.text = suggestion;
    setState(() {
      _searchQuery = suggestion;
      _showSearchSuggestions = false;
    });
    _performSearch();
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
      _showMobileSearchBar = false;
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
        _showAllCategories = false;
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
                  color: AppColors.accent,
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
                        color: isSelected ? AppColors.primary : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.onSurface.withValues(alpha: 0.2),
                          width: 1,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.2,
                                  ),
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
                                errorBuilder: (c, e, s) => Icon(
                                  Icons.category_rounded,
                                  size: 14,
                                  color: isSelected
                                      ? AppColors.onSecondary
                                      : AppColors.onSurface.withValues(
                                          alpha: 0.6,
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ] else ...[
                            Icon(
                              Icons.category_rounded,
                              size: 14,
                              color: isSelected
                                  ? AppColors.onSecondary
                                  : AppColors.onSurface.withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            subcategory.subCategoryName,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: isSelected
                                  ? AppColors.onSecondary
                                  : AppColors.onSurface,
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
                                      ? AppColors.onSecondary.withValues(
                                          alpha: 0.2,
                                        )
                                      : AppColors.primary.withValues(
                                          alpha: 0.1,
                                        ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '$clickCount',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: isSelected
                                        ? AppColors.onSecondary
                                        : AppColors.primary,
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

      // Reset seller tracking for first page
      _loadedSellerIds.clear();
      List<Product> allFetched = [];
      DocumentSnapshot? cursor;
      bool moreAvailable = true;

      // Fetch products in batches until we have _storePageSize unique sellers
      while (moreAvailable) {
        final result = await _productService.getProductsPaginated(
          limit: _pageSize,
          lastDocument: cursor,
          categoryId: filterCategoryId,
          subCategoryId: filterSubCategoryId,
          includeInactive: false,
          includeDrafts: false,
          includeArchived: false,
        );

        if (!mounted) return;

        final batch = result['products'] as List<Product>;
        cursor = result['lastDocument'] as DocumentSnapshot?;
        moreAvailable = result['hasMore'] as bool;

        allFetched.addAll(batch);

        // Count unique sellers so far
        for (final p in batch) {
          if (p.sellerId.isNotEmpty) _loadedSellerIds.add(p.sellerId);
        }

        // Stop if we have enough unique sellers or no more data
        if (_loadedSellerIds.length >= _storePageSize || !moreAvailable) break;
      }

      // Load categories only if they haven't been loaded yet
      if (_categories.length <= 1) {
        try {
          final allCategories = await _categoryService.getCategories();
          // Collect categoryIDs that are actually used by active products,
          // so empty categories don't crowd the grid.
          final productSnap = await FirebaseFirestore.instance
              .collection('Product')
              .where('isActive', isEqualTo: true)
              .get();
          final usedCategoryIds = productSnap.docs
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

      if (mounted) {
        setState(() {
          _products = allFetched;
          _lastDocument = cursor;
          _hasMore = moreAvailable;
          _isLoading = false;
          _cacheTimestamp = DateTime.now();
        });
      }

      // Pre-fetch vendor data for trader cards
      _prefetchSellerData(allFetched).then((_) {
        if (mounted) setState(() {});
      });

      AppLogger.d('Loaded ${allFetched.length} products covering ${_loadedSellerIds.length} stores (first page)');
    } catch (e) {
      AppLogger.d('Error loading first page: $e');

      if (mounted) {
        setState(() {
          _isLoading = false;
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

      final int sellersBefore = _loadedSellerIds.length;
      List<Product> allNewProducts = [];
      DocumentSnapshot? cursor = _lastDocument;
      bool moreAvailable = true;

      // Fetch batches until we accumulate _storePageSize new sellers
      while (moreAvailable) {
        final result = await _productService.getProductsPaginated(
          limit: _pageSize,
          lastDocument: cursor,
          categoryId: filterCategoryId,
          subCategoryId: filterSubCategoryId,
          includeInactive: false,
          includeDrafts: false,
          includeArchived: false,
        );

        if (!mounted) return;

        final batch = result['products'] as List<Product>;
        cursor = result['lastDocument'] as DocumentSnapshot?;
        moreAvailable = result['hasMore'] as bool;

        allNewProducts.addAll(batch);

        for (final p in batch) {
          if (p.sellerId.isNotEmpty) _loadedSellerIds.add(p.sellerId);
        }

        final newSellers = _loadedSellerIds.length - sellersBefore;
        if (newSellers >= _storePageSize || !moreAvailable) break;
      }

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

      final newSellers = _loadedSellerIds.length - sellersBefore;
      AppLogger.d('Loaded ${allNewProducts.length} more products covering $newSellers new stores');
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
      // Clear category cache on manual refresh to get fresh data
      CategoryService.clearCache();

      // Keep current data as backup
      final currentProducts = List<Product>.from(_products);
      final currentCategories = Map<String, String>.from(_categoryNameToId);
      final currentTimestamp = _cacheTimestamp;

      AppLogger.d(
        'Current cache: ${currentProducts.length} products, ${currentCategories.length} categories',
      );

      // Fetch fresh data from Firebase
      AppLogger.d('Fetching fresh data from Firebase...');
      final result = await _productService.getProductsPaginated(
        limit: _pageSize,
        categoryId: null,
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
            _sellerDataCache.clear(); // invalidate vendor cache on manual refresh
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
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
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
    final isWideScreen = MediaQuery.of(context).size.width >= 900;
    const double traderListMaxWidth = 720;
    final double tradersHorizontalPadding = (kIsWeb && isWideScreen)
        ? (MediaQuery.of(context).size.width - traderListMaxWidth) / 2
        : (MediaQuery.of(context).size.width >= 900
            ? (MediaQuery.of(context).size.width - 1100) / 2
            : 16);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        displacement: 40,
        strokeWidth: 2.5,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Header outside centered content for wide screens
            if (isWideScreen)
              SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.waving_hand,
                              color: AppColors.accent,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Welcome back!',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.onSurface.withValues(
                                    alpha: 0.6,
                                  ),
                                  fontSize: 11,
                                ),
                              ),
                              Text(
                                'Hi $_userFirstName',
                                style: AppTextStyles.titleMedium.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      // CENTER: Search bar (centered)
                      Expanded(
                        child: Center(
                          child: Container(
                            width: 420,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.primary.withOpacity(0.15),
                              ),
                            ),
                            child: Row(
                              children: [
                                const SizedBox(width: 12),
                                Icon(
                                  Icons.search,
                                  size: 20,
                                  color: AppColors.onSurface.withOpacity(0.6),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _searchController,
                                    focusNode: _searchFocusNode,
                                    decoration: InputDecoration(
                                      hintText: 'Search products...',
                                      border: InputBorder.none,
                                      hintStyle: AppTextStyles.bodySmall
                                          .copyWith(
                                            color: AppColors.onSurface
                                                .withOpacity(0.5),
                                          ),
                                    ),
                                    style: AppTextStyles.bodyMedium,
                                    onChanged: _onSearchChanged,
                                  ),
                                ),
                                if (_searchQuery.isNotEmpty)
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    color: AppColors.onSurface.withOpacity(0.5),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                    onPressed: _clearSearch,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // RIGHT: Navigation items (Products, Cart, Profile)
                      Row(
                        children: [
                          // Products (highlighted)
                          Row(
                            children: [
                              const Icon(
                                Icons.store,
                                size: 22,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Products',
                                style: AppTextStyles.titleMedium.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 24),
                          // Cart
                          GestureDetector(
                            onTap: () {
                              final user = FirebaseAuth.instance.currentUser;
                              if (user == null) {
                                _showLoginRequiredDialog();
                              } else {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => const CartPage(),
                                  ),
                                );
                              }
                            },
                            child: Row(
                              children: [
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Icon(
                                      Icons.shopping_cart_outlined,
                                      color: AppColors.onSurface.withOpacity(
                                        0.7,
                                      ),
                                      size: 22,
                                    ),
                                    if (_cartItemCount > 0)
                                      Positioned(
                                        right: -8,
                                        top: -6,
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          constraints: const BoxConstraints(
                                            minWidth: 18,
                                            minHeight: 18,
                                          ),
                                          decoration: const BoxDecoration(
                                            color: Colors.orange,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Text(
                                            _cartItemCount > 99
                                                ? '99+'
                                                : '$_cartItemCount',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Cart',
                                  style: AppTextStyles.titleMedium.copyWith(
                                    color: AppColors.onSurface.withOpacity(0.7),
                                    fontWeight: FontWeight.normal,
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 24),
                          // Profile
                          GestureDetector(
                            onTap: () {
                              final user = FirebaseAuth.instance.currentUser;
                              if (user == null) {
                                _showLoginRequiredDialog();
                              } else {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => const ProfilePage(),
                                  ),
                                );
                              }
                            },
                            child: Row(
                              children: [
                                Icon(
                                  Icons.person_outline,
                                  color: AppColors.onSurface.withOpacity(0.7),
                                  size: 22,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Profile',
                                  style: AppTextStyles.titleMedium.copyWith(
                                    color: AppColors.onSurface.withOpacity(0.7),
                                    fontWeight: FontWeight.normal,
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            // SliverAppBar for mobile/tablet only
            if (!isWideScreen)
              SliverAppBar(
                expandedHeight: 60,
                floating: false,
                pinned: true,
                elevation: 0,
                backgroundColor: AppColors.surface,
                automaticallyImplyLeading: false,
                title: _showMobileSearchBar
                    ? TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        autofocus: true,
                        onChanged: _onSearchChanged,
                        decoration: InputDecoration(
                          hintText: 'Search products...',
                          border: InputBorder.none,
                          hintStyle: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                        style: AppTextStyles.bodyMedium,
                      )
                    : Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.waving_hand,
                              color: AppColors.accent,
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
                                  'Welcome back!',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.onSurface.withValues(alpha: 0.6),
                                    fontSize: 11,
                                  ),
                                ),
                                Text(
                                  'Hi $_userFirstName',
                                  style: AppTextStyles.titleMedium.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
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
                          AppColors.primary.withValues(alpha: 0.05),
                          AppColors.secondary.withValues(alpha: 0.02),
                        ],
                      ),
                    ),
                  ),
                ),
                actions: [
                  Container(
                    margin: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          iconSize: 20,
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          icon: Icon(
                            _showMobileSearchBar ? Icons.close : Icons.search,
                            color: AppColors.onSurface,
                          ),
                          onPressed: () {
                            if (_showMobileSearchBar) {
                              _clearSearch();
                            } else {
                              setState(() { _showMobileSearchBar = true; });
                              WidgetsBinding.instance.addPostFrameCallback(
                                (_) => _searchFocusNode.requestFocus(),
                              );
                            }
                          },
                        ),
                        Container(
                          width: 1,
                          height: 20,
                          color: AppColors.onSurface.withValues(alpha: 0.1),
                        ),
                        IconButton(
                          iconSize: 20,
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          icon: const Icon(
                            Icons.menu,
                            color: AppColors.onSurface,
                          ),
                          onPressed: _showCategorySidebar,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            // Search suggestions overlay
            if (_isSearchMode && _showSearchSuggestions && _searchSuggestions.isNotEmpty)
              SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: isWideScreen ? 1100 : double.infinity,
                    ),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: _searchSuggestions.map((suggestion) {
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.search, size: 18),
                            title: Text(suggestion, style: AppTextStyles.bodyMedium),
                            onTap: () => _onSuggestionTap(suggestion),
                          );
                        }).toList(),
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
                          const Icon(Icons.search, color: AppColors.primary, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _isSearching
                                  ? 'Searching...'
                                  : 'Results for "$_searchQuery" (${_searchResults.length} products)',
                              style: AppTextStyles.titleMedium.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.onSurface,
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
              // Search results as trader cards
              if (_isSearching)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_searchResults.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off, size: 64, color: AppColors.onSurface.withValues(alpha: 0.3)),
                        const SizedBox(height: 16),
                        Text(
                          'No products found.',
                          style: AppTextStyles.titleMedium.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Try a different search term',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.symmetric(
                    horizontal: tradersHorizontalPadding,
                  ),
                  sliver: _buildSearchTradersList(),
                ),
              if (_isLoadingMoreSearch)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
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
                      const SizedBox(height: 8),
                      // Banner Slideshow
                      if (_bannerImageUrls.isNotEmpty)
                        Container(
                          margin: EdgeInsets.symmetric(
                            horizontal: MediaQuery.of(context).size.width >= 600
                                ? 16 // Standard margin for tablet/desktop
                                : 0, // No margin for mobile = full width = much taller banner
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              MediaQuery.of(context).size.width >= 600 ? 24 : 0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.2),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              MediaQuery.of(context).size.width >= 600 ? 24 : 0,
                            ),
                            child: AspectRatio(
                              aspectRatio:
                                  8 /
                                  3, // Keep original 8:3 ratio for all screens
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
                                              Container(
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    colors: [
                                                      AppColors.primary
                                                          .withValues(
                                                            alpha: 0.1,
                                                          ),
                                                      AppColors.accent
                                                          .withValues(
                                                            alpha: 0.1,
                                                          ),
                                                    ],
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                  ),
                                                ),
                                                child: const Center(
                                                  child:
                                                      CircularProgressIndicator(),
                                                ),
                                              ),
                                          errorWidget: (context, url, error) =>
                                              Container(
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    colors: [
                                                      AppColors.primary
                                                          .withValues(
                                                            alpha: 0.1,
                                                          ),
                                                      AppColors.accent
                                                          .withValues(
                                                            alpha: 0.1,
                                                          ),
                                                    ],
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
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
                                              ProductImageCacheManager.instance,
                                        ),
                                      );
                                    },
                                  ),
                                  // Banner indicator dots
                                  if (_bannerImageUrls.length > 1)
                                    Positioned(
                                      bottom: 16,
                                      left: 0,
                                      right: 0,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: List.generate(
                                          _bannerImageUrls.length,
                                          (index) {
                                            return GestureDetector(
                                              onTap: () {
                                                if (_bannerPageController
                                                    .hasClients) {
                                                  _bannerPageController
                                                      .animateToPage(
                                                        index,
                                                        duration:
                                                            const Duration(
                                                              milliseconds: 300,
                                                            ),
                                                        curve: Curves.easeInOut,
                                                      );
                                                }
                                              },
                                              child: AnimatedContainer(
                                                duration: const Duration(
                                                  milliseconds: 300,
                                                ),
                                                margin:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 5,
                                                    ),
                                                width:
                                                    _currentBannerIndex == index
                                                    ? 24
                                                    : 12,
                                                height: 12,
                                                decoration: BoxDecoration(
                                                  color:
                                                      _currentBannerIndex ==
                                                          index
                                                      ? AppColors.primary
                                                      : AppColors.primary
                                                            .withOpacity(0.3),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),

                      // Modern Categories Section
                      const SizedBox(height: 16),
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
                            padding: const EdgeInsets.symmetric(horizontal: 16),
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

                      // Explore Dental Traders Section Header (renamed from Products)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.store_rounded,
                                color: AppColors.accent,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Explore Dental Traders',
                                style: AppTextStyles.titleLarge.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.onSurface,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                '${_getFilteredProductsCount()} traders',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),

            // Traders List (Vertical List Layout - Foodpanda style)
            _isLoading && _products.isEmpty
                ? const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _errorMessage != null && _products.isEmpty
                ? SliverFillRemaining(child: _buildErrorState())
                : _products.isEmpty
                ? SliverFillRemaining(child: _buildEmptyState())
                : SliverPadding(
                    padding: EdgeInsets.symmetric(
                      horizontal: tradersHorizontalPadding,
                    ),
                    sliver: _buildTradersList(),
                  ),
            ], // end if (!_isSearchMode)

            // Web Footer
            const SliverToBoxAdapter(child: WebFooter()),
          ],
        ),
      ),
      floatingActionButton: _isSeller
          ? Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
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
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                elevation: 0,
                highlightElevation: 0,
                child: const Icon(Icons.add),
              ),
            )
          : null,
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
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              _errorMessage ?? 'Unable to load products at this time',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.7),
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
                  color: AppColors.primary.withValues(alpha: 0.2),
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
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
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
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.search_off,
              size: 64,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No products found',
            style: AppTextStyles.titleLarge.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'There are no products to display at this time.\nTry refreshing or check back later.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 32),
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
                AppLogger.d("Empty state refresh button pressed");
                _cacheTimestamp = null;
                ProductImageCacheManager.instance.emptyCache();
                _resetAndRefresh();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
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
  Widget _buildModernProductGrid() {
    AppLogger.d('DEBUG: _buildModernProductGrid called');
    AppLogger.d('Selected categories: $_selectedCategories');
    AppLogger.d('Selected subcategories: $_selectedSubCategories');
    AppLogger.d('Category name to ID mapping: $_categoryNameToId');
    AppLogger.d('Total products: ${_products.length}');

    // Calculate filtered products first
    final filteredProducts = _products.where((product) {
      // Exclude draft products from product listing page
      if (product.isDraft == true) return false;

      // Exclude inactive products from product listing page
      if (product.isActive == false) return false;

      // Exclude archived products from product listing page
      if (product.isArchived == true) return false;

      // If no categories selected, show all
      if (_selectedCategories.isEmpty) return true;

      // Get selected category IDs
      final selectedCategoryIds = _selectedCategories
          .map((categoryName) => _categoryNameToId[categoryName])
          .where((id) => id != null)
          .cast<String>()
          .toList();

      if (_selectedSubCategories.isNotEmpty) {
        final isInSelectedCategory = selectedCategoryIds.contains(
          product.categoryId,
        );

        final hasSubCategory = product.subCategoryId.isNotEmpty;
        final isInSelectedSubCategory = _selectedSubCategories.contains(
          product.subCategoryId,
        );
        final shouldShowProduct = !hasSubCategory || isInSelectedSubCategory;

        if (_products.indexOf(product) < 3) {
          // Only log first 3 products to avoid spam
          AppLogger.d(
            'Product ${product.name}: categoryId=${product.categoryId}, subCategoryId=${product.subCategoryId}',
          );
          AppLogger.d(
            'Is in selected category: $isInSelectedCategory, Has subcategory: $hasSubCategory, Is in selected subcategory: $isInSelectedSubCategory',
          );
          AppLogger.d(
            'Should show product: $shouldShowProduct (category match: $isInSelectedCategory)',
          );
        }

        return isInSelectedCategory && shouldShowProduct;
      }

      // Otherwise, filter by selected categories only
      return selectedCategoryIds.contains(product.categoryId);
    }).toList();

    final categoryDisplay = _selectedCategories.isEmpty
        ? 'All'
        : _selectedCategories.join(', ');
    AppLogger.d(
      'Displaying ${filteredProducts.length} products for categories: $categoryDisplay',
    );

    if (filteredProducts.isEmpty) {
      return SliverToBoxAdapter(
        child: Container(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.category,
                  size: 48,
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _selectedCategories.isEmpty
                    ? 'No products available'
                    : 'No products in ${_selectedCategories.join(', ')}',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Try selecting a different category',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _getResponsiveCrossAxisCount(context),
        childAspectRatio: _getResponsiveAspectRatio(context),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      delegate: SliverChildBuilderDelegate((context, index) {
        if (index >= filteredProducts.length) {
          // Show loading indicator if we're loading more
          if (_isLoadingMore) {
            return Container(
              padding: const EdgeInsets.all(32),
              child: const Center(child: CircularProgressIndicator()),
            );
          }
          return null;
        }

        final product = filteredProducts[index];
        return ProductCard(
          product: product,
          onTap: () {
            // Track product click
            _clickTrackingService.trackProductClick(product.productId);

            // Navigate to product detail page with deep linking support
            NavigationUtils.navigateToProductDetail(context, product.productId);
          },
        );
      }, childCount: filteredProducts.length + (_isLoadingMore ? 1 : 0)),
    );
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
      return 0.85; // Slightly taller cards for large desktop
    } else if (screenWidth >= 900) {
      return 0.8; // Desktop screens
    } else if (screenWidth >= 600) {
      return 0.78; // Tablet screens
    } else {
      return 0.75; // Mobile screens (same as original)
    }
  }

  int _getFilteredProductsCount() {
    // Collect unique seller IDs from filtered products
    final Set<String> sellerIds = {};
    for (final product in _products) {
      if (product.isDraft == true) continue;
      if (product.isActive == false) continue;
      if (product.isArchived == true) continue;

      // Apply brand filter
      if (_selectedBrand != null && product.brand != _selectedBrand) continue;

      // Apply category/subcategory filters
      if (_selectedCategories.isNotEmpty) {
        final selectedCategoryIds = _selectedCategories
            .map((categoryName) => _categoryNameToId[categoryName])
            .where((id) => id != null)
            .cast<String>()
            .toList();

        if (!selectedCategoryIds.contains(product.categoryId)) continue;

        if (_selectedSubCategories.isNotEmpty) {
          final hasSubCategory = product.subCategoryId.isNotEmpty;
          final isInSelectedSubCategory = _selectedSubCategories.contains(product.subCategoryId);
          if (hasSubCategory && !isInSelectedSubCategory) continue;
        }
      }

      if (product.sellerId.isNotEmpty) {
        sellerIds.add(product.sellerId);
      }
    }

    // Only count parent seller accounts (not sub-accounts)
    return sellerIds.where((sid) {
      final data = _sellerDataCache[sid];
      if (data == null) return true; // include if not yet cached
      final isSubAccount = data['isSubAccount'] == true;
      final role = data['role'] as String? ?? '';
      return !isSubAccount && role == 'seller';
    }).length;
  }

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
  void _showCategorySidebar() {
    // Initialise the sidebar's highlighted category to the first selected one
    // (or the first real category if nothing is selected yet).
    String initialCategory = _selectedCategories.isNotEmpty
        ? _selectedCategories.first
        : (_categories.length > 1 ? _categories[1] : 'All');

    // Pre-load subcategories for every category so the panel is responsive.
    for (final cat in _categories) {
      if (cat != 'All') _loadSubcategories(cat);
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Categories',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return _CategorySidebarSheet(
          categories: _categories,
          categoryNameToId: _categoryNameToId,
          categoryNameToImage: _categoryNameToImage,
          subcategoriesByCategory: _subcategoriesByCategory,
          selectedCategories: List.from(_selectedCategories),
          selectedSubCategories: List.from(_selectedSubCategories),
          initialHighlightedCategory: initialCategory,
          onCategorySelected: (cat) {
            Navigator.of(ctx).pop();
            _onCategorySelected(cat);
          },
          onSubCategorySelected: (subId, subName) {
            Navigator.of(ctx).pop();
            _onSubCategorySelected(subId, subName);
          },
          onLoadSubcategories: _loadSubcategories,
          onApplySelection: (newCategories, newSubCategories) {
            if (!mounted) return;

            // Track clicks for newly added categories (not previously selected)
            for (final categoryName in newCategories) {
              if (!_selectedCategories.contains(categoryName)) {
                final categoryId = _categoryNameToId[categoryName];
                if (categoryId != null) {
                  _clickTrackingService.trackCategoryClick(categoryId);
                }
              }
            }

            // Track clicks for newly added subcategories (not previously selected)
            for (final subCategoryId in newSubCategories) {
              if (!_selectedSubCategories.contains(subCategoryId)) {
                for (final entry in _subcategoriesByCategory.entries) {
                  if (entry.value.any(
                    (s) => s.subCategoryId == subCategoryId,
                  )) {
                    _clickTrackingService.trackSubCategoryClick(
                      entry.key,
                      subCategoryId,
                    );
                    break;
                  }
                }
              }
            }

            // Apply the full new selection set and reset pagination
            setState(() {
              _selectedCategories = List.from(newCategories);
              _selectedSubCategories = List.from(newSubCategories);
              _products = [];
              _lastDocument = null;
              _hasMore = true;
              _isLoading = false;
              _isLoadingMore = false;
            });

            // Ensure subcategories are loaded for all newly selected categories
            for (final categoryName in newCategories) {
              _loadSubcategories(categoryName);
            }

            _loadFirstPage();
          },
        );
      },
      transitionBuilder: (ctx, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // NEW WIDGET BUILDERS FOR REDESIGNED LAYOUT
  // ═══════════════════════════════════════════════════════════════════════════

  // Build Brand Section (horizontally scrollable, matches Categories style)
  Widget _buildBrandSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.verified_rounded,
                  color: AppColors.accent,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Brands',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_brandList.isEmpty) const SizedBox.shrink() else SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _brandList.length + 1, // +1 for "All" option
              itemBuilder: (context, index) {
                // First item is "All"
                if (index == 0) {
                  final isSelected = _selectedBrand == null;
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: GestureDetector(
                      onTap: () {
                        if (_selectedBrand != null) {
                          setState(() {
                            _selectedBrand = null;
                            _products = [];
                            _lastDocument = null;
                            _hasMore = true;
                            _loadedSellerIds = {};
                          });
                          _loadFirstPage();
                        }
                      },
                      child: IntrinsicWidth(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 80),
                          child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.accent : AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.accent
                                : AppColors.onSurface.withValues(alpha: 0.12),
                            width: 1.5,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: AppColors.accent.withValues(alpha: 0.25),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ]
                              : [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.04),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.white.withValues(alpha: 0.2)
                                      : AppColors.accent.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.grid_view_rounded,
                                    color: isSelected
                                        ? Colors.white.withValues(alpha: 0.9)
                                        : AppColors.accent.withValues(alpha: 0.7),
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(
                                'All',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: isSelected ? AppColors.onPrimary : AppColors.onSurface,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 10,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                          ),
                        ),
                      ),
                    ),
                  );
                }

                final brandIndex = index - 1;
                final brand = _brandList[brandIndex]['brand'] ?? '';
                final brandImage = _brandList[brandIndex]['brandImage'] ?? '';
                final isSelected = _selectedBrand == brand;

                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedBrand = isSelected ? null : brand;
                        _products = [];
                        _lastDocument = null;
                        _hasMore = true;
                        _loadedSellerIds = {};
                      });
                      _loadFirstPage();
                    },
                    child: IntrinsicWidth(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 80),
                        child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.accent : AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.accent
                              : AppColors.onSurface.withValues(alpha: 0.12),
                          width: 1.5,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: AppColors.accent.withValues(alpha: 0.25),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ]
                            : [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: brandImage.isNotEmpty
                                    ? Colors.transparent
                                    : isSelected
                                        ? Colors.white.withValues(alpha: 0.2)
                                        : AppColors.accent.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: brandImage.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: brandImage,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Center(
                                        child: Icon(
                                          Icons.verified_rounded,
                                          color: isSelected
                                              ? Colors.white.withValues(alpha: 0.7)
                                              : AppColors.accent.withValues(alpha: 0.5),
                                          size: 20,
                                        ),
                                      ),
                                      errorWidget: (context, url, error) => Center(
                                        child: Icon(
                                          Icons.verified_rounded,
                                          color: isSelected
                                              ? Colors.white.withValues(alpha: 0.7)
                                              : AppColors.accent.withValues(alpha: 0.5),
                                          size: 20,
                                        ),
                                      ),
                                    )
                                  : Center(
                                      child: Icon(
                                        Icons.verified_rounded,
                                        color: isSelected
                                            ? Colors.white.withValues(alpha: 0.9)
                                            : AppColors.accent.withValues(alpha: 0.7),
                                        size: 22,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              brand.length > 17 ? '${brand.substring(0, 17)}...' : brand,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: isSelected ? AppColors.onPrimary : AppColors.onSurface,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                fontSize: 10,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  int _categoryCrossAxisCount(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w >= 1200) return 7;
    if (w >= 900) return 6;
    if (w >= 600) return 5;
    return 4;
  }

  // Build Categories Section (responsive grid)
  Widget _buildCategoriesSection() {
    final crossAxisCount = _categoryCrossAxisCount(context);
    const maxCollapsedRows = 2;
    final collapsedLimit = crossAxisCount * maxCollapsedRows;

    final hasSelection = _selectedCategories.isNotEmpty;
    final isCollapsedToSelection = hasSelection && !_categoryGridForceExpanded;

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
    } else if (_showAllCategories || _categories.length <= collapsedLimit) {
      visibleIndices = List.generate(_categories.length, (i) => i);
    } else {
      visibleIndices = List.generate(collapsedLimit, (i) => i);
    }

    final hasMoreInDefault = _categories.length > collapsedLimit;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.category_rounded,
                  color: AppColors.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Categories',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: visibleIndices.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 0.85,
            ),
            itemBuilder: (context, index) {
              final categoryIndex = visibleIndices[index];
              final category = _categories[categoryIndex];
              final isSelected = category == 'All'
                  ? _selectedCategories.isEmpty
                  : _selectedCategories.contains(category);
              final imageUrl = category == 'All' ? null : _categoryNameToImage[category];
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
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
                label: Text(
                  'Change category',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                icon: const Icon(
                  Icons.keyboard_arrow_up_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
                label: Text(
                  'Hide other categories',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ] else if (hasMoreInDefault) ...[
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  setState(() => _showAllCategories = !_showAllCategories);
                },
                icon: Icon(
                  _showAllCategories
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
                label: Text(
                  _showAllCategories
                      ? 'Show less'
                      : 'Show all (${_categories.length})',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.06)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : AppColors.onSurface.withValues(alpha: 0.08),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(
                  alpha: isSelected ? 0.14 : 0.08,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: imageUrl != null && imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Center(
                        child: Icon(
                          Icons.category,
                          color: AppColors.primary.withValues(alpha: 0.5),
                          size: 16,
                        ),
                      ),
                      errorWidget: (context, url, error) => Center(
                        child: Icon(
                          Icons.category,
                          color: AppColors.primary.withValues(alpha: 0.5),
                          size: 16,
                        ),
                      ),
                    )
                  : Center(
                      child: Icon(
                        category == 'All' ? Icons.grid_view_rounded : Icons.category,
                        color: AppColors.primary,
                        size: 18,
                      ),
                    ),
            ),
            const SizedBox(height: 6),
            Flexible(
              child: Text(
                category,
                style: AppTextStyles.bodySmall.copyWith(
                  color: isSelected ? AppColors.primary : AppColors.onSurface,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 9.5,
                  height: 1.15,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
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
      color: AppColors.surface,
      itemBuilder: (context) => options.map((option) {
        final isSelectedOption = option == value;
        return PopupMenuItem<String>(
          value: option,
          child: Row(
            children: [
              if (isSelectedOption)
                Icon(Icons.check_rounded, color: AppColors.primary, size: 18)
              else
                const SizedBox(width: 18),
              const SizedBox(width: 8),
              Text(
                option,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: isSelectedOption ? AppColors.primary : AppColors.onSurface,
                  fontWeight: isSelectedOption ? FontWeight.w600 : FontWeight.normal,
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
          color: isActive ? AppColors.primary.withValues(alpha: 0.1) : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? AppColors.primary : AppColors.onSurface.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive ? AppColors.primary : AppColors.onSurface.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 6),
            Text(
              value == 'All' ? label : value,
              style: AppTextStyles.bodySmall.copyWith(
                color: isActive ? AppColors.primary : AppColors.onSurface,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: isActive ? AppColors.primary : AppColors.onSurface.withValues(alpha: 0.5),
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
    if (_sellerDataCache.containsKey(sellerId)) return _sellerDataCache[sellerId];
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

    final uncachedSellerIds =
        sellerIds.where((id) => !_sellerDataCache.containsKey(id)).toSet();
    if (uncachedSellerIds.isNotEmpty) {
      AppLogger.d('Pre-fetching seller data for ${uncachedSellerIds.length} sellers');
      await Future.wait(uncachedSellerIds.map(_getSellerDataCached));
      AppLogger.d('Seller data pre-fetch complete');
    }

    // Pre-fetch active vouchers for all sellers in view.
    final uncachedVoucherIds =
        sellerIds.where((id) => !_sellerVouchersCache.containsKey(id)).toSet();
    if (uncachedVoucherIds.isNotEmpty) {
      await Future.wait(uncachedVoucherIds.map(_fetchSellerVouchers));
    }
  }

  /// Fetches active, currently-valid vouchers for a single seller and caches
  /// them in [_sellerVouchersCache]. Caches an empty list on error so we don't
  /// retry on every rebuild.
  Future<void> _fetchSellerVouchers(String sellerId) async {
    if (_sellerVouchersCache.containsKey(sellerId)) return;
    if (_sellerVouchersFetching.contains(sellerId)) return;
    _sellerVouchersFetching.add(sellerId);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('Vouchers')
          .where('sellerId', isEqualTo: sellerId)
          .where('status', isEqualTo: 'active')
          .get();

      final now = DateTime.now();
      final valid = snapshot.docs
          .map((d) => d.data())
          .where((v) {
            final start = _parseVoucherDate(v['startDate']);
            final end = _parseVoucherDate(v['endDate']);
            if (start == null || end == null) return false;
            return !start.isAfter(now) && !end.isBefore(now);
          })
          .toList();

      _sellerVouchersCache[sellerId] = valid;
    } catch (e) {
      AppLogger.d('Error fetching vouchers for $sellerId: $e');
      _sellerVouchersCache[sellerId] = const [];
    } finally {
      _sellerVouchersFetching.remove(sellerId);
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
      List<Map<String, dynamic>> vouchers) {
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

  /// Renders a single orange voucher badge matching the existing tag style.
  Widget _buildVoucherBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.accent.withValues(alpha: 0.15),
            AppColors.primary.withValues(alpha: 0.15),
          ],
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.local_offer_rounded,
            size: 14,
            color: AppColors.accent,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.accent,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // Build Traders List (Foodpanda-style vertical list layout)
  Widget _buildTradersList() {
    // Group products by seller to create "business" cards
    final Map<String, List<Product>> productsBySeller = {};

    final filteredProducts = _products.where((product) {
      if (product.isDraft == true) return false;
      if (product.isActive == false) return false;
      if (product.isArchived == true) return false;

      // Apply brand filter
      if (_selectedBrand != null && product.brand != _selectedBrand) return false;

      // Apply category filter
      if (_selectedCategories.isNotEmpty) {
        final selectedCategoryIds = _selectedCategories
            .map((categoryName) => _categoryNameToId[categoryName])
            .where((id) => id != null)
            .cast<String>()
            .toList();

        if (!selectedCategoryIds.contains(product.categoryId)) return false;

        // Apply subcategory filter
        if (_selectedSubCategories.isNotEmpty) {
          final hasSubCategory = product.subCategoryId.isNotEmpty;
          final isInSelectedSubCategory = _selectedSubCategories.contains(product.subCategoryId);
          if (hasSubCategory && !isInSelectedSubCategory) return false;
        }
      }

      return true;
    }).toList();

    // Group by seller
    for (final product in filteredProducts) {
      final sellerId = product.sellerId.isNotEmpty ? product.sellerId : 'unknown';
      productsBySeller.putIfAbsent(sellerId, () => []).add(product);
    }

    // Apply Shipped From filter — based on seller region classified from
    // vendor.company.address.location. "Nearest You" matches the current
    // user's region; the four named regions filter strictly.
    List<String> sellerIds = productsBySeller.keys.toList();
    final String? targetRegion;
    if (_selectedShippedFrom == 'All') {
      targetRegion = null;
    } else if (_selectedShippedFrom == 'Nearest You') {
      targetRegion = _userRegion;
    } else {
      targetRegion = _selectedShippedFrom;
    }
    if (targetRegion != null) {
      sellerIds = sellerIds
          .where((sid) => _sellerRegion(sid) == targetRegion)
          .toList();
    }

    if (sellerIds.isEmpty) {
      return SliverToBoxAdapter(
        child: _buildEmptyState(),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index >= sellerIds.length) {
            if (_isLoadingMore) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            return const SizedBox.shrink();
          }

          final sellerId = sellerIds[index];
          final sellerProducts = productsBySeller[sellerId]!;

          return _buildTraderCard(sellerId, sellerProducts);
        },
        childCount: sellerIds.length + (_isLoadingMore ? 1 : 0),
      ),
    );
  }

  // Build trader cards from search results grouped by seller
  Widget _buildSearchTradersList() {
    final Map<String, List<Product>> productsBySeller = {};
    for (final product in _searchResults) {
      if (product.isDraft == true) continue;
      if (product.isActive == false) continue;
      if (product.isArchived == true) continue;
      final sellerId = product.sellerId.isNotEmpty ? product.sellerId : 'unknown';
      productsBySeller.putIfAbsent(sellerId, () => []).add(product);
    }

    final sellerIds = productsBySeller.keys.toList();

    if (sellerIds.isEmpty) {
      return SliverToBoxAdapter(child: _buildEmptyState());
    }

    // Pre-fetch seller data for search results
    _prefetchSellerData(_searchResults);

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index >= sellerIds.length) return const SizedBox.shrink();
          final sellerId = sellerIds[index];
          final sellerProducts = productsBySeller[sellerId]!;
          return _buildTraderCard(sellerId, sellerProducts);
        },
        childCount: sellerIds.length,
      ),
    );
  }

  /// Extracts display-ready vendor fields from a raw Firestore Seller document.
  /// Falls back gracefully at every level so the card always renders.
  static _SellerDisplayData _extractSellerDisplay(
    Map<String, dynamic>? raw,
    List<Product> products,
    Map<String, String> categoryIdToName,
  ) {
    // Fallback values derived from product data
    final fallbackName = products.first.brand?.isNotEmpty == true
        ? products.first.brand!
        : 'Dental Trader';
    var fallbackCats = products
        .map((p) => categoryIdToName[p.categoryId])
        .whereType<String>()
        .toSet()
        .take(2)
        .join(', ');
    if (fallbackCats.isEmpty) fallbackCats = 'Dental Products';

    if (raw == null) {
      return _SellerDisplayData(
        storeName: fallbackName,
        province: 'Metro Manila',
        coverImageUrl: products.first.imageURL,
        categories: fallbackCats,
      );
    }

    final vendor = raw['vendor'] is Map
        ? raw['vendor'] as Map<String, dynamic>
        : <String, dynamic>{};
    final company = vendor['company'] is Map
        ? vendor['company'] as Map<String, dynamic>
        : <String, dynamic>{};
    final address = company['address'] is Map
        ? company['address'] as Map<String, dynamic>
        : <String, dynamic>{};
    final coverImg = vendor['coverImage'];

    // Cover image: url → path → product image fallback
    String coverUrl = products.first.imageURL;
    if (coverImg is Map) {
      final u = coverImg['url'] as String?;
      final p = coverImg['path'] as String?;
      if (u != null && u.isNotEmpty) {
        coverUrl = u;
      } else if (p != null && p.isNotEmpty) {
        coverUrl = p;
      }
    }

    // Store name
    final storeName = (company['storeName'] as String?)?.isNotEmpty == true
        ? company['storeName'] as String
        : ((raw['storeName'] as String?) ?? fallbackName);

    // Province
    final province = (address['province'] as String?)?.isNotEmpty == true
        ? address['province'] as String
        : 'Metro Manila';

    // Categories — vendor.categories is an array of name strings
    var cats = fallbackCats;
    final rawCats = vendor['categories'];
    if (rawCats is List && rawCats.isNotEmpty) {
      final joined = rawCats.whereType<String>().take(2).join(', ');
      if (joined.isNotEmpty) cats = joined;
    }

    return _SellerDisplayData(
      storeName: storeName,
      province: province,
      coverImageUrl: coverUrl,
      categories: cats,
    );
  }

  // Build individual Trader/Business Card (Foodpanda style)
  Widget _buildTraderCard(String sellerId, List<Product> products) {
    // Price range indicator (₱/₱₱/₱₱₱) — hidden per request, leaving logic commented for future use.
    // final prices = products.map((p) => p.lowestPrice ?? 0).where((p) => p > 0).toList();
    // String priceIndicator = '₱';
    // if (prices.isNotEmpty) {
    //   final avgPrice = prices.reduce((a, b) => a + b) / prices.length;
    //   if (avgPrice > 5000) {
    //     priceIndicator = '₱₱₱';
    //   } else if (avgPrice > 1000) {
    //     priceIndicator = '₱₱';
    //   }
    // }

    // Read vendor data from cache (populated by pre-fetch before build)
    final stillLoading = !_sellerDataCache.containsKey(sellerId);
    final display = _extractSellerDisplay(
      stillLoading ? null : _sellerDataCache[sellerId],
      products,
      _categoryIdToName,
    );

    // Show loading skeleton while vendor fetch is in flight (edge case)
    if (stillLoading) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const AspectRatio(
          aspectRatio: 16 / 7,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    // Dynamic vouchers fetched from Firestore (pre-cached by _prefetchSellerData).
    // Sort by priority, format each into a label, drop invalid (null) entries.
    final sortedVouchers =
        _sortVouchersByPriority(_sellerVouchersCache[sellerId] ?? const []);
    final voucherLabels = sortedVouchers
        .map(_formatSingleVoucher)
        .whereType<String>()
        .toList();

    // Display rules:
    //   1 voucher  → show it
    //   2 vouchers → show both
    //   3+         → show first 2 + "+X more"
    final List<String> displayedVoucherLabels;
    if (voucherLabels.length <= 2) {
      displayedVoucherLabels = voucherLabels;
    } else {
      displayedVoucherLabels = [
        voucherLabels[0],
        voucherLabels[1],
        '+${voucherLabels.length - 2} more',
      ];
    }
    final hasVoucher = displayedVoucherLabels.isNotEmpty;

    return GestureDetector(
      onTap: () {
        final initialCategoryIds = _selectedCategories
            .map((name) => _categoryNameToId[name])
            .whereType<String>()
            .toList();
        NavigationUtils.navigateToStore(
          context,
          sellerId,
          sellerData: _sellerDataCache[sellerId],
          initialCategoryIds:
              initialCategoryIds.isEmpty ? null : initialCategoryIds,
          initialSubCategoryIds: _selectedSubCategories.isEmpty
              ? null
              : List<String>.from(_selectedSubCategories),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banner image from vendor coverImage
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              child: AspectRatio(
                aspectRatio: 16 / 7,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: display.coverImageUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        child: const Icon(Icons.store_rounded, size: 40, color: AppColors.primary),
                      ),
                      cacheManager: ProductImageCacheManager.instance,
                    ),
                    // Gradient overlay for text readability
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 60,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.4),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Product count badge
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.inventory_2_outlined, size: 14, color: AppColors.primary),
                            const SizedBox(width: 4),
                            Text(
                              '${products.length} items',
                              style: AppTextStyles.bodySmall.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.onSurface,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Info section
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: store name + price range badge
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          display.storeName,
                          style: AppTextStyles.titleMedium.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Price range badge (₱/₱₱/₱₱₱) — hidden per request.
                      // const SizedBox(width: 8),
                      // Container(
                      //   padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      //   decoration: BoxDecoration(
                      //     color: AppColors.accent.withValues(alpha: 0.1),
                      //     borderRadius: BorderRadius.circular(6),
                      //   ),
                      //   child: Text(
                      //     priceIndicator,
                      //     style: AppTextStyles.bodySmall.copyWith(
                      //       color: AppColors.accent,
                      //       fontWeight: FontWeight.bold,
                      //     ),
                      //   ),
                      // ),
                    ],
                  ),

                  const SizedBox(height: 4),

                  // Province / location row
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 14,
                        color: AppColors.onSurface.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          display.province,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.onSurface.withValues(alpha: 0.7),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Middle row: ETA pill + categories
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.access_time_rounded,
                              size: 12,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _estimateDelivery(sellerId),
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          display.categories,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.onSurface.withValues(alpha: 0.6),
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),

                  // Bottom row: voucher badges (horizontal list)
                  if (hasVoucher) ...[
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (int i = 0; i < displayedVoucherLabels.length; i++) ...[
                            if (i > 0) const SizedBox(width: 6),
                            _buildVoucherBadge(displayedVoucherLabels[i]),
                          ],
                        ],
                      ),
                    ),
                  ],
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
// Value object holding display-ready vendor fields for a trader card
// ─────────────────────────────────────────────────────────────────────────────
class _SellerDisplayData {
  final String storeName;
  final String province;
  final String coverImageUrl;
  final String categories;
  const _SellerDisplayData({
    required this.storeName,
    required this.province,
    required this.coverImageUrl,
    required this.categories,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Sidebar sheet widget – shown as a full-height right-side panel
// ─────────────────────────────────────────────────────────────────────────────
class _CategorySidebarSheet extends StatefulWidget {
  final List<String> categories;
  final Map<String, String> categoryNameToId;
  final Map<String, String?> categoryNameToImage;
  final Map<String, List<SubCategory>> subcategoriesByCategory;
  final List<String> selectedCategories;
  final List<String> selectedSubCategories;
  final String initialHighlightedCategory;
  final void Function(String category) onCategorySelected;
  final void Function(String subId, String subName) onSubCategorySelected;
  final Future<void> Function(String categoryName) onLoadSubcategories;
  final void Function(
    List<String> selectedCategories,
    List<String> selectedSubCategories,
  )
  onApplySelection;

  const _CategorySidebarSheet({
    required this.categories,
    required this.categoryNameToId,
    required this.categoryNameToImage,
    required this.subcategoriesByCategory,
    required this.selectedCategories,
    required this.selectedSubCategories,
    required this.initialHighlightedCategory,
    required this.onCategorySelected,
    required this.onSubCategorySelected,
    required this.onLoadSubcategories,
    required this.onApplySelection,
  });

  @override
  State<_CategorySidebarSheet> createState() => _CategorySidebarSheetState();
}

class _CategorySidebarSheetState extends State<_CategorySidebarSheet> {
  late String _highlightedCategory;
  late Map<String, List<SubCategory>> _localSubcategories;
  bool _loadingSubcategories = false;

  // Local mutable copies of the selection – updated immediately on every tap
  late List<String> _localSelectedCategories;
  late List<String> _localSelectedSubCategories;

  @override
  void initState() {
    super.initState();
    _highlightedCategory = widget.initialHighlightedCategory;
    _localSubcategories = Map.from(widget.subcategoriesByCategory);
    // Seed local selection from whatever is already active in the parent
    _localSelectedCategories = List.from(widget.selectedCategories);
    _localSelectedSubCategories = List.from(widget.selectedSubCategories);
    _ensureSubcategoriesLoaded(_highlightedCategory);
  }

  Future<void> _ensureSubcategoriesLoaded(String categoryName) async {
    final categoryId = widget.categoryNameToId[categoryName];
    if (categoryId == null) return;
    if (_localSubcategories.containsKey(categoryId)) return;

    if (mounted) setState(() => _loadingSubcategories = true);
    await widget.onLoadSubcategories(categoryName);

    // After the parent loads them, copy into local map
    if (mounted) {
      setState(() {
        final updated = widget.subcategoriesByCategory[categoryId];
        if (updated != null) _localSubcategories[categoryId] = updated;
        _loadingSubcategories = false;
      });
    }
  }

  List<SubCategory> get _currentSubcategories {
    final categoryId = widget.categoryNameToId[_highlightedCategory];
    if (categoryId == null) return [];
    return _localSubcategories[categoryId] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final sidebarWidth = (screenWidth * 0.88).clamp(0.0, 400.0);

    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: sidebarWidth,
          height: double.infinity,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              bottomLeft: Radius.circular(20),
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.category_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Shop by Category',
                        style: AppTextStyles.titleMedium.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ),

                // Body: left category rail + right subcategory grid
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Left rail: category list ──────────────────────────
                      Container(
                        width: 110,
                        color: const Color(0xFFF5F5F5),
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: widget.categories.length,
                          itemBuilder: (context, index) {
                            final category = widget.categories[index];
                            final isHighlighted =
                                category == _highlightedCategory;
                            final isSelected = category == 'All'
                                ? _localSelectedCategories.isEmpty
                                : _localSelectedCategories.contains(category);
                            final imageUrl = category == 'All'
                                ? null
                                : widget.categoryNameToImage[category];

                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _highlightedCategory = category;
                                  _loadingSubcategories = false;
                                });
                                if (category == 'All') {
                                  // Tapping "All" in the rail just highlights it;
                                  // clearing is done via the footer button.
                                } else {
                                  _ensureSubcategoriesLoaded(category);
                                }
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                color: isHighlighted
                                    ? Colors.white
                                    : Colors.transparent,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                  horizontal: 8,
                                ),
                                child: Column(
                                  children: [
                                    // Image / icon
                                    Container(
                                      width: 54,
                                      height: 54,
                                      decoration: BoxDecoration(
                                        color:
                                            imageUrl != null &&
                                                imageUrl.isNotEmpty
                                            ? Colors.transparent
                                            : isHighlighted
                                            ? AppColors.primary.withValues(
                                                alpha: 0.1,
                                              )
                                            : AppColors.primary.withValues(
                                                alpha: 0.05,
                                              ),
                                        borderRadius: BorderRadius.circular(10),
                                        border: isHighlighted
                                            ? Border.all(
                                                color: AppColors.primary,
                                                width: 1.5,
                                              )
                                            : null,
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(9),
                                        child:
                                            imageUrl != null &&
                                                imageUrl.isNotEmpty
                                            ? CachedNetworkImage(
                                                imageUrl: imageUrl,
                                                fit: BoxFit.cover,
                                                errorWidget: (c, u, e) =>
                                                    Center(
                                                      child: Icon(
                                                        Icons.category,
                                                        color: AppColors.primary
                                                            .withValues(
                                                              alpha: 0.5,
                                                            ),
                                                        size: 22,
                                                      ),
                                                    ),
                                              )
                                            : Center(
                                                child: Icon(
                                                  category == 'All'
                                                      ? Icons.grid_view_rounded
                                                      : Icons.category,
                                                  color: isHighlighted
                                                      ? AppColors.primary
                                                      : AppColors.primary
                                                            .withValues(
                                                              alpha: 0.5,
                                                            ),
                                                  size: 24,
                                                ),
                                              ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      category,
                                      style: AppTextStyles.bodySmall.copyWith(
                                        fontSize: 10,
                                        fontWeight: isHighlighted || isSelected
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                        color: isHighlighted
                                            ? AppColors.primary
                                            : AppColors.onSurface,
                                      ),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    // Active selection dot
                                    if (isSelected)
                                      Container(
                                        margin: const EdgeInsets.only(top: 3),
                                        width: 5,
                                        height: 5,
                                        decoration: BoxDecoration(
                                          color: AppColors.primary,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      // ── Vertical divider ──────────────────────────────────
                      Container(width: 1, color: const Color(0xFFE0E0E0)),

                      // ── Right panel: subcategories ────────────────────────
                      Expanded(
                        child: _highlightedCategory == 'All'
                            ? _buildAllCategoriesQuickPick()
                            : _buildSubcategoryGrid(),
                      ),
                    ],
                  ),
                ),

                // Footer row: "Show All" + "Apply" button
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      top: BorderSide(
                        color: Colors.grey.withValues(alpha: 0.15),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Clear / Show All
                      Expanded(
                        child: TextButton(
                          onPressed: () {
                            widget.onCategorySelected('All');
                          },
                          style: TextButton.styleFrom(
                            backgroundColor: AppColors.primary.withValues(
                              alpha: 0.08,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          child: Text(
                            'Show All',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Apply selection
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            // Commit every toggled category/subcategory to parent
                            widget.onApplySelection(
                              _localSelectedCategories,
                              _localSelectedSubCategories,
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          child: Text(
                            'Apply',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
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
    );
  }

  Widget _buildAllCategoriesQuickPick() {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.95,
      ),
      itemCount: widget.categories.length - 1, // exclude 'All'
      itemBuilder: (context, index) {
        final category = widget.categories[index + 1];
        final isSelected = _localSelectedCategories.contains(category);
        final imageUrl = widget.categoryNameToImage[category];

        return GestureDetector(
          onTap: () {
            setState(() {
              if (isSelected) {
                _localSelectedCategories.remove(category);
                // Also deselect any subcategories belonging to this category
                final categoryId = widget.categoryNameToId[category];
                if (categoryId != null &&
                    _localSubcategories.containsKey(categoryId)) {
                  final subIds = _localSubcategories[categoryId]!
                      .map((s) => s.subCategoryId)
                      .toList();
                  _localSelectedSubCategories.removeWhere(
                    (id) => subIds.contains(id),
                  );
                }
              } else {
                _localSelectedCategories.add(category);
              }
              // Also switch the rail highlight to this category
              _highlightedCategory = category;
            });
            _ensureSubcategoriesLoaded(category);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.08)
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? AppColors.primary
                    : Colors.grey.withValues(alpha: 0.2),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: imageUrl != null && imageUrl.isNotEmpty
                        ? Colors.transparent
                        : AppColors.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: imageUrl != null && imageUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            errorWidget: (c, u, e) => Icon(
                              Icons.category,
                              color: AppColors.primary.withValues(alpha: 0.5),
                              size: 24,
                            ),
                          )
                        : Icon(
                            Icons.category,
                            color: AppColors.primary.withValues(alpha: 0.5),
                            size: 24,
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  category,
                  style: AppTextStyles.bodySmall.copyWith(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? AppColors.primary : AppColors.onSurface,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSubcategoryGrid() {
    if (_loadingSubcategories) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.primary,
        ),
      );
    }

    final subs = _currentSubcategories;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category header – tap toggles this category's selection
        GestureDetector(
          onTap: () {
            setState(() {
              if (_localSelectedCategories.contains(_highlightedCategory)) {
                _localSelectedCategories.remove(_highlightedCategory);
                // Deselect subcategories of this category
                final categoryId =
                    widget.categoryNameToId[_highlightedCategory];
                if (categoryId != null &&
                    _localSubcategories.containsKey(categoryId)) {
                  final subIds = _localSubcategories[categoryId]!
                      .map((s) => s.subCategoryId)
                      .toList();
                  _localSelectedSubCategories.removeWhere(
                    (id) => subIds.contains(id),
                  );
                }
              } else {
                _localSelectedCategories.add(_highlightedCategory);
              }
            });
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            color: _localSelectedCategories.contains(_highlightedCategory)
                ? AppColors.primary.withValues(alpha: 0.08)
                : AppColors.primary.withValues(alpha: 0.05),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _highlightedCategory,
                    style: AppTextStyles.titleSmall.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                if (_localSelectedCategories.contains(_highlightedCategory))
                  const Icon(
                    Icons.check_circle,
                    color: AppColors.primary,
                    size: 16,
                  )
                else
                  Text(
                    'Select all ›',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (subs.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                'No subcategories',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
          )
        else
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(10),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.1,
              ),
              itemCount: subs.length,
              itemBuilder: (context, index) {
                final sub = subs[index];
                final isSelected = _localSelectedSubCategories.contains(
                  sub.subCategoryId,
                );

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _localSelectedSubCategories.remove(sub.subCategoryId);
                      } else {
                        // Auto-select the parent category if not yet selected
                        if (!_localSelectedCategories.contains(
                          _highlightedCategory,
                        )) {
                          _localSelectedCategories.add(_highlightedCategory);
                        }
                        _localSelectedSubCategories.add(sub.subCategoryId);
                      }
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.08)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : Colors.grey.withValues(alpha: 0.2),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color:
                                (sub.imageURL != null &&
                                    sub.imageURL!.isNotEmpty)
                                ? Colors.transparent
                                : isSelected
                                ? AppColors.primary.withValues(alpha: 0.12)
                                : AppColors.primary.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child:
                                (sub.imageURL != null &&
                                    sub.imageURL!.isNotEmpty)
                                ? Image.network(
                                    sub.imageURL!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (c, e, s) => Icon(
                                      Icons.category_rounded,
                                      color: isSelected
                                          ? AppColors.primary
                                          : AppColors.primary.withValues(
                                              alpha: 0.5,
                                            ),
                                      size: 22,
                                    ),
                                  )
                                : Icon(
                                    Icons.category_rounded,
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.primary.withValues(
                                            alpha: 0.5,
                                          ),
                                    size: 22,
                                  ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            sub.subCategoryName,
                            style: AppTextStyles.bodySmall.copyWith(
                              fontSize: 10,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.onSurface,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
