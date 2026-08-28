import 'package:dentpal/core/app_theme/index.dart';
import 'package:dentpal/core/app_theme/ink_palette.dart';
import 'package:dentpal/core/app_theme/theme_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../models/product_model.dart';
import '../services/product_service.dart';
import '../services/cart_service.dart';
import '../services/category_service.dart';
import '../services/banned_seller_service.dart';
import '../widgets/loading_overlay.dart';
import '../widgets/similar_products_section.dart';
import '../utils/cart_feedback.dart';
import 'cart_page.dart';
import 'edit_product_page.dart';
import 'package:dentpal/utils/app_logger.dart';
import 'package:dentpal/utils/navigation_utils.dart';
import 'package:dentpal/utils/currency_formatter.dart';
import 'package:dentpal/services/chat_service.dart';
import 'package:dentpal/core/widgets/app_page_header.dart';
import 'package:dentpal/core/widgets/web_footer.dart';
import '../widgets/loading_skeletons.dart';

class ProductDetailPage extends StatefulWidget {
  final String productId;

  const ProductDetailPage({super.key, required this.productId});

  @override
  _ProductDetailPageState createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  void _showFullImagePopup(String imageUrl) {
    final TransformationController _transformationController =
        TransformationController();

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () =>
              Navigator.of(context).pop(), // dismiss when tapping outside
          child: Stack(
            children: [
              Center(
                child: Container(
                  constraints: const BoxConstraints(
                    maxWidth: 600,
                    maxHeight: 600,
                  ),
                  child: GestureDetector(
                    onTap: () {}, // absorb taps on the image
                    onDoubleTap: () {
                      // Reset zoom and pan on double tap
                      _transformationController.value = Matrix4.identity();
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: InteractiveViewer(
                        transformationController: _transformationController,
                        minScale: 1.0,
                        maxScale: 4.0,
                        panEnabled: true,
                        child: CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.contain,
                          memCacheWidth: 1080,
                          maxWidthDiskCache: 1080,
                          placeholder: (context, url) =>
                              const Center(child: CircularProgressIndicator()),
                          errorWidget: (context, url, error) => Icon(
                            Icons.broken_image,
                            color: _danger,
                            size: 48,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 16,
                right: 16,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _danger,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Icon(Icons.close, color: Colors.white, size: 28),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  final ProductService _productService = ProductService();
  final CartService _cartService = CartService();
  final CategoryService _categoryService = CategoryService();

  // ── Palette ──────────────────────────────────────────────────────────────

  InkPalette get ink => InkPalette.of(context);

  /// Destructive red. [InkPalette] reserves amber for urgency, so an error or a
  /// removal needs its own tone that still reads in both appearances.
  Color get _danger =>
      ink.isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);

  late Future<Product?> _productFuture;
  int _quantity = 1;
  ProductVariation? _selectedVariation;
  bool _isAddingToCart = false;
  DateTime? _lastAddToCartTime;

  // Gallery carousel: swipe through product.images first, then into variations.
  int _galleryImageIndex = 0;
  bool _inGallery = false;

  // Controller for quantity input (web view)
  final TextEditingController _quantityController = TextEditingController();

  // Cache for category names to avoid repeated Firestore calls
  final Map<String, String> _categoryNames = {};

  // Cache for subcategory names to avoid repeated Firestore calls
  final Map<String, String> _subCategoryNames = {};

  // Cache for seller data to avoid repeated Firestore calls
  final Map<String, Map<String, dynamic>> _sellerData = {};

  // Cache management
  Product? _cachedProduct;
  DateTime? _cacheTimestamp;

  /// The four same-category products shown under the specifications.
  ///
  /// Started the first time the section is built rather than in [initState],
  /// because it needs the loaded product's category — and kept in a field so a
  /// rebuild (picking a variation, changing the quantity) does not re-query.
  Future<List<Product>>? _similarFuture;
  String? _similarForProductId;

  // Check if current user is the seller of this product
  bool _isCurrentUserSeller(Product product) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return false;
    return currentUser.uid == product.sellerId;
  }

  // Navigate back to product listing page and clear URL
  void _navigateBackToProductListing() {
    // Clear the URL back to root (clean URL)
    NavigationUtils.updatePageUrl('/');

    // Pop back to previous page or go to product listing
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      // If no page to pop to, navigate to product listing
      Navigator.of(context).pushReplacementNamed('/');
    }
  }

  @override
  void initState() {
    super.initState();
    _productFuture = _loadProduct();
    _quantityController.text = _quantity.toString();

    // Update URL for deep linking support
    NavigationUtils.updatePageUrl('/product/${widget.productId}');
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  Future<Product?> _loadProduct() async {
    try {
      AppLogger.d('ProductDetailPage: Loading product ${widget.productId}...');
      final product = await _productService.getProductById(widget.productId);

      if (product != null) {
        // Cache the product data
        _cachedProduct = product;
        _cacheTimestamp = DateTime.now();

        // Select the first variation by default if available
        if (product.variations != null && product.variations!.isNotEmpty) {
          _selectedVariation = product.variations![0];
          // Update text controller for web view
          _quantityController.text = _quantity.toString();
        }

        // Start in gallery mode if the product has gallery images.
        _inGallery = product.images.isNotEmpty;
        _galleryImageIndex = 0;

        AppLogger.d('ProductDetailPage: Loaded product ${product.name}');
      }

      return product;
    } catch (e) {
      AppLogger.d('Error loading product: $e');
      return null;
    }
  }

  // Fetch category name by ID and cache it
  Future<String> _getCategoryName(String categoryId) async {
    if (_categoryNames.containsKey(categoryId)) {
      return _categoryNames[categoryId]!;
    }

    try {
      final category = await _categoryService.getCategoryById(categoryId);
      final categoryName = category?.categoryName ?? 'Unknown Category';
      _categoryNames[categoryId] = categoryName;
      return categoryName;
    } catch (e) {
      AppLogger.d('Error fetching category name for $categoryId: $e');
      _categoryNames[categoryId] = 'Unknown Category';
      return 'Unknown Category';
    }
  }

  // Fetch subcategory name by IDs and cache it
  Future<String> _getSubCategoryName(
    String categoryId,
    String subCategoryId,
  ) async {
    final cacheKey = '$categoryId|$subCategoryId';
    if (_subCategoryNames.containsKey(cacheKey)) {
      return _subCategoryNames[cacheKey]!;
    }

    try {
      final subCategory = await _categoryService.getSubCategoryById(
        categoryId,
        subCategoryId,
      );
      final subCategoryName = subCategory?.subCategoryName ?? '';
      _subCategoryNames[cacheKey] = subCategoryName;
      return subCategoryName;
    } catch (e) {
      AppLogger.d('Error fetching subcategory name for $subCategoryId: $e');
      _subCategoryNames[cacheKey] = '';
      return '';
    }
  }

  // Fetch seller data by ID and cache it
  Future<Map<String, dynamic>> _getSellerData(String sellerId) async {
    if (_sellerData.containsKey(sellerId)) {
      return _sellerData[sellerId]!;
    }

    try {
      final sellerDoc = await FirebaseFirestore.instance
          .collection('Seller')
          .doc(sellerId)
          .get();

      if (sellerDoc.exists) {
        final data = sellerDoc.data() as Map<String, dynamic>;

        // Safely read nested vendor > company fields
        final vendor = (data['vendor'] is Map)
            ? data['vendor'] as Map<String, dynamic>
            : const {};
        final company = (vendor['company'] is Map)
            ? vendor['company'] as Map<String, dynamic>
            : const {};

        // Fetch profileImage URL from vendor.profileImage
        String profileImageURL = '';
        if (vendor['profileImage'] is Map &&
            vendor['profileImage']['url'] is String) {
          profileImageURL = vendor['profileImage']['url'] as String;
        }

        // Store name from vendor.company.storeName, fallback to previous keys or default
        final String storeName =
            (company['storeName'] as String?) ??
            (data['storeName'] as String?) ??
            'DentPal Store';

        // Address: vendor.company.address.city and province concatenated
        String address = 'Store location not available';
        final addressMap = (company['address'] is Map)
            ? company['address'] as Map<String, dynamic>
            : const {};
        final String? city = addressMap['city'] as String?;
        final String? province = addressMap['province'] as String?;
        if ((city != null && city.isNotEmpty) ||
            (province != null && province.isNotEmpty)) {
          address = [
            city,
            province,
          ].whereType<String>().where((e) => e.isNotEmpty).join(', ');
        } else {
          // fallback to flat address if present
          address = (data['address'] as String?) ?? 'No address provided';
        }

        return {
          'shopName': storeName,
          'address': address,
          'contactEmail': data['contactEmail'] ?? '',
          'contactNumber': data['contactNumber'] ?? '',
          'isActive': data['isActive'] ?? true,
          'profileImageURL': profileImageURL,
        };
      } else {
        // Default data if seller not found
        final defaultData = {
          'shopName': 'DentPal Store',
          'address': 'Store location not available',
          'contactEmail': '',
          'contactNumber': '',
          'isActive': true,
        };
        _sellerData[sellerId] = defaultData;
        return defaultData;
      }
    } catch (e) {
      AppLogger.d('Error fetching seller data for $sellerId: $e');
      final defaultData = {
        'shopName': 'DentPal Store',
        'address': 'Store location not available',
        'contactEmail': '',
        'contactNumber': '',
        'isActive': true,
      };
      _sellerData[sellerId] = defaultData;
      return defaultData;
    }
  }

  // Check if cache is expired (older than 10 minutes for product details)
  bool _isCacheExpired() {
    if (_cacheTimestamp == null) return true;

    final now = DateTime.now();
    final difference = now.difference(_cacheTimestamp!);
    return difference.inMinutes >= 10;
  }

  // Helper method to compare products for change detection
  bool _hasProductChanged(Product? oldProduct, Product? newProduct) {
    if (oldProduct == null && newProduct == null) return false;
    if (oldProduct == null || newProduct == null) return true;

    // Compare basic product properties
    if (oldProduct.productId != newProduct.productId ||
        oldProduct.name != newProduct.name ||
        oldProduct.description != newProduct.description ||
        oldProduct.imageURL != newProduct.imageURL ||
        oldProduct.categoryId != newProduct.categoryId ||
        oldProduct.lowestPrice != newProduct.lowestPrice) {
      AppLogger.d('Product data changed: Basic properties differ');
      return true;
    }

    // Compare variations
    if (oldProduct.variations?.length != newProduct.variations?.length) {
      AppLogger.d('Product data changed: Variation count differs');
      return true;
    }

    if (oldProduct.variations != null && newProduct.variations != null) {
      for (int i = 0; i < oldProduct.variations!.length; i++) {
        final oldVar = oldProduct.variations![i];
        final newVar = newProduct.variations![i];

        if (oldVar.variationId != newVar.variationId ||
            oldVar.name != newVar.name ||
            oldVar.price != newVar.price ||
            oldVar.stock != newVar.stock ||
            oldVar.imageURL != newVar.imageURL) {
          AppLogger.d(
            'Product data changed: Variation ${oldVar.name} has differences',
          );
          return true;
        }
      }
    }

    return false;
  }

  // Handle pull-to-refresh with cache-first approach and change detection
  Future<void> _handleRefresh() async {
    AppLogger.d(
      'ProductDetailPage: Pull-to-refresh triggered (cache-first approach)',
    );

    try {
      // Keep current data as backup
      final currentProduct = _cachedProduct;
      final currentTimestamp = _cacheTimestamp;

      AppLogger.d(
        'Current cache: ${currentProduct?.name ?? 'No cached product'}',
      );

      // Fetch fresh data from Firebase
      AppLogger.d('Fetching fresh product data from Firebase...');
      final freshProduct = await _productService.getProductById(
        widget.productId,
      );

      // Compare data for changes
      final hasChanges = _hasProductChanged(currentProduct, freshProduct);

      if (hasChanges || currentTimestamp == null || _isCacheExpired()) {
        AppLogger.d('Changes detected or cache expired - updating data');

        // Update with fresh data
        setState(() {
          _cachedProduct = freshProduct;
          _cacheTimestamp = DateTime.now();
          _productFuture = Future.value(freshProduct);

          // Re-select variation if it still exists, otherwise select first available
          if (freshProduct?.variations != null &&
              freshProduct!.variations!.isNotEmpty) {
            final currentVariationId = _selectedVariation?.variationId;
            final foundVariation = freshProduct.variations!
                .where((v) => v.variationId == currentVariationId)
                .firstOrNull;

            if (foundVariation != null) {
              _selectedVariation = foundVariation;
              // Adjust quantity if it exceeds new stock
              if (_quantity > foundVariation.stock) {
                _quantity = foundVariation.stock > 0 ? 1 : 0;
              }
            } else {
              // Current variation no longer exists, select first one
              _selectedVariation = freshProduct.variations![0];
              if (_quantity > _selectedVariation!.stock) {
                _quantity = _selectedVariation!.stock > 0 ? 1 : 0;
              }
            }
            // Update text controller for web view
            _quantityController.text = _quantity.toString();
          }
        });

        AppLogger.d(
          'Product data updated: ${freshProduct?.name ?? 'Product removed'}',
        );
      } else {
        // No changes detected, just refresh timestamp
        setState(() {
          _cacheTimestamp = DateTime.now();
        });

        AppLogger.d('No changes detected - cache timestamp refreshed');
      }
    } catch (e) {
      AppLogger.d('Refresh error: $e');
      AppLogger.d('Stack trace: ${StackTrace.current}');

      // Show error but keep existing data
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to refresh: ${e.toString()}'),
            backgroundColor: _danger,
          ),
        );
      }
    }

    AppLogger.d('ProductDetailPage: Pull-to-refresh completed');
  }

  void _addToCart(Product product) async {
    // Check if user is authenticated first
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showLoginRequiredDialog();
      return;
    }

    // Prevent multiple simultaneous requests
    if (_isAddingToCart) return;

    // Additional safety check for stock availability
    if (_selectedVariation != null && _quantity > _selectedVariation!.stock) {
      CartFeedback.showError(
        context,
        'Cannot add more items than available stock (${_selectedVariation!.stock})',
      );
      setState(() {
        _quantity = _selectedVariation!.stock > 0
            ? _selectedVariation!.stock
            : 1;
      });
      return;
    }

    // Debounce: Prevent rapid button taps (minimum 1 second between requests)
    final now = DateTime.now();
    if (_lastAddToCartTime != null &&
        now.difference(_lastAddToCartTime!).inSeconds < 1) {
      CartFeedback.showInfo(context, 'Please wait before adding another item');
      return;
    }

    _lastAddToCartTime = now;

    setState(() {
      _isAddingToCart = true;
    });

    try {
      await CartPage.addItemOptimistically(
        productId: product.productId,
        quantity: _quantity,
        variationId: _selectedVariation?.variationId,
        cartService: _cartService,
      );

      if (mounted) {
        CartFeedback.showSuccess(
          context,
          'Added $_quantity ${product.name} to cart',
        );
      }
    } catch (e) {
      if (mounted) {
        CartFeedback.showError(
          context,
          'Failed to add item to cart: ${e.toString()}',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAddingToCart = false;
        });
      }
    }
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
            'You need to login to add items to your cart. Would you like to login now?',
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
                Navigator.of(context).pushNamed('/login');
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

  Future<void> _inquireAboutProduct(Product product) async {
    // Check if user is authenticated first
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showLoginRequiredDialog();
      return;
    }

    // Don't allow users to inquire about their own products
    if (user.uid == product.sellerId) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('You cannot inquire about your own product'),
          backgroundColor: _danger,
        ),
      );
      return;
    }

    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final chatService = ChatService();

      // Get current variation for product details
      final selectedVariation = _selectedVariation;
      String productName = product.name;
      if (selectedVariation != null && selectedVariation.name.isNotEmpty) {
        productName = '${product.name} - ${selectedVariation.name}';
      }

      // Create or get existing chat room
      final chatRoomId = await chatService.getOrCreateChatRoom(
        product.sellerId,
        productId: product.productId,
        productName: productName,
        productImage: selectedVariation?.imageURL ?? product.imageURL,
      );

      // Create inquiry record in the product's Inquiries sub-collection
      await FirebaseFirestore.instance
          .collection('Products')
          .doc(product.productId)
          .collection('Inquiries')
          .doc(user.uid)
          .set(
            {
              'userId': user.uid,
              'isCharged': false,
              'createdAt': FieldValue.serverTimestamp(),
              'lastInquiryAt':
                  FieldValue.serverTimestamp(), // Track latest inquiry
              'chatRoomId': chatRoomId,
              'variationId': selectedVariation?.variationId,
              'variationName': selectedVariation?.name,
            },
            SetOptions(
              mergeFields: [
                'lastInquiryAt',
                'chatRoomId',
                'variationId',
                'variationName',
              ],
            ),
          );
      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      // Navigate to chat
      if (mounted) {
        Navigator.of(context).pushNamed(
          '/profile/chats/$chatRoomId',
          arguments: <String, dynamic>{
            'otherUserId': product.sellerId,
            // Left unnamed: the chat page reads the real shop name off the
            // room, which beats showing a placeholder 'Seller' until it does.
          },
        );
      }
    } catch (e) {
      // Close loading dialog if still open
      if (mounted) Navigator.of(context).pop();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start chat: ${e.toString()}'),
            backgroundColor: _danger,
          ),
        );
      }
    }
  }

  void _shareProduct(Product product) {
    // On mobile, use native share directly without showing our modal
    if (!kIsWeb) {
      final shareUrl = NavigationUtils.getProductShareUrl(product.productId);
      final shareText =
          '${product.name}\n\nCheck out this product on DentPal: $shareUrl';
      Share.share(shareText, subject: 'Check out this product on DentPal');
      return;
    }

    // On web, show our custom modal
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _buildShareBottomSheet(product),
    );
  }

  Widget _buildShareBottomSheet(Product product) {
    final shareUrl = NavigationUtils.getProductShareUrl(product.productId);
    final shareText =
        '${product.name}\n\nCheck out this product on DentPal: $shareUrl';

    return Container(
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ink.text.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: ink.emerald.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.share, color: ink.emerald, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Share Product',
                        style: AppTextStyles.titleLarge.copyWith(
                          fontWeight: FontWeight.bold,
                          color: ink.text,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                        iconSize: 20,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Share options - horizontal scrollable list
            SizedBox(
              height: 100, // Fixed height to contain icon + label
              child: Center(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  shrinkWrap: true,
                  children: [
                    _buildShareOption(
                      icon: Icons.facebook,
                      label: 'Facebook',
                      color: const Color(0xFF1877F2),
                      onTap: () => _shareToFacebook(shareUrl, shareText),
                    ),
                    const SizedBox(width: 24),
                    _buildShareOption(
                      icon: Icons.messenger, // Facebook Messenger icon
                      label: 'Messenger',
                      color: const Color(0xFF00B2FF),
                      onTap: () => _shareToMessenger(shareUrl, shareText),
                    ),
                    const SizedBox(width: 24),
                    _buildShareOption(
                      icon: Icons.email,
                      label: 'Email',
                      color: const Color(0xFF34A853),
                      onTap: () => _shareToEmail(shareUrl, shareText),
                    ),
                    const SizedBox(width: 24),
                    _buildShareOption(
                      icon: Icons.message,
                      label: 'SMS',
                      color: const Color(0xFF0088CC),
                      onTap: () => _shareToSMS(shareUrl, shareText),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Copy link button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: ink.bg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: ink.emerald.withValues(alpha: 0.2)),
                ),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: ink.emerald.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.link, color: ink.emerald, size: 20),
                  ),
                  title: Text(
                    'Copy Link',
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontWeight: FontWeight.w600,
                      color: ink.text,
                    ),
                  ),
                  subtitle: Text(
                    shareUrl,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: ink.text.withValues(alpha: 0.6),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Icon(Icons.copy, color: ink.emerald, size: 20),
                  onTap: () => _copyLinkToClipboard(shareText),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildShareOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: ink.text.withValues(alpha: 0.7),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _shareToFacebook(String url, String text) {
    // On mobile, use native share dialog
    if (!kIsWeb) {
      Share.share(text, subject: 'Check out this product on DentPal');
      Navigator.pop(context);
      return;
    }

    // On web, open Facebook share URL
    final facebookUrl =
        'https://www.facebook.com/sharer/sharer.php?u=${Uri.encodeComponent(url)}';
    _openUrl(facebookUrl);
  }

  void _shareToMessenger(String url, String text) {
    // On mobile, use native share dialog
    if (!kIsWeb) {
      Share.share(text, subject: 'Check out this product on DentPal');
      Navigator.pop(context);
      return;
    }

    // On web, open Facebook Messenger with pre-filled message
    final messengerUrl =
        'https://www.messenger.com/new?text=${Uri.encodeComponent(text)}';
    _openUrl(messengerUrl);
  }

  void _shareToEmail(String url, String text) {
    // Email should work on both mobile and web
    final emailUrl =
        'mailto:?subject=${Uri.encodeComponent('Check out this product on DentPal')}&body=${Uri.encodeComponent(text)}';
    _openUrl(emailUrl);
  }

  void _shareToSMS(String url, String text) {
    // On mobile, use native share dialog
    if (!kIsWeb) {
      Share.share(text, subject: 'Check out this product on DentPal');
      Navigator.pop(context);
      return;
    }

    // On web, open SMS URL
    final smsUrl = 'sms:?body=${Uri.encodeComponent(text)}';
    _openUrl(smsUrl);
  }

  void _openUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (mounted) Navigator.pop(context);
      } else {
        // Fall back to copying to clipboard if URL can't be opened
        _copyLinkToClipboard(url, 'Link copied to clipboard!');
      }
    } catch (e) {
      // Fall back to copying to clipboard on error
      _copyLinkToClipboard(url, 'Link copied to clipboard!');
    }
  }

  void _copyLinkToClipboard(String text, [String? customMessage]) {
    Clipboard.setData(ClipboardData(text: text)).then((_) {
      Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: ink.onEmerald, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    customMessage ?? 'Link copied to clipboard!',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: ink.onEmerald,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: ink.emerald,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ink.bg,
      // Let the content run to the bottom edge; the Add to Cart bar keeps
      // itself clear of the home indicator with its own SafeArea.
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<Product?>(
          future: _productFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const ProductDetailSkeleton();
            } else if (snapshot.hasError) {
              return _buildErrorState();
            } else if (!snapshot.hasData || snapshot.data == null) {
              return _buildNotFoundState();
            }

            final product = snapshot.data!;
            return _buildModernProductDetail(product);
          },
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return _buildMessageState(
      icon: Icons.cloud_off,
      tone: _danger,
      title: 'Couldn’t load this product',
      message: 'Check your connection and try again.',
      actionLabel: 'Try again',
      actionIcon: Icons.refresh,
      onAction: () => setState(() => _productFuture = _loadProduct()),
    );
  }

  Widget _buildNotFoundState() {
    return _buildMessageState(
      icon: Icons.search_off,
      tone: ink.text.withValues(alpha: 0.5),
      title: 'Product not found',
      message: 'This listing may have been removed or is no longer available.',
      actionLabel: 'Back to browsing',
      actionIcon: Icons.arrow_back,
      onAction: _navigateBackToProductListing,
    );
  }

  /// The two dead ends — failed to load, and nothing there to load. Same frame
  /// as the page itself, so the header does not move when one of them lands.
  Widget _buildMessageState({
    required IconData icon,
    required Color tone,
    required String title,
    required String message,
    required String actionLabel,
    required IconData actionIcon,
    required VoidCallback onAction,
  }) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppLayout.maxContentWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppPageHeader(
              title: 'Product',
              showBack: true,
              onBack: _navigateBackToProductListing,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppLayout.gutter,
                  60,
                  AppLayout.gutter,
                  24,
                ),
                children: [
                  Center(
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: tone.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 30, color: tone),
                    ),
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
                    message,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: ink.text.withValues(alpha: 0.6),
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Center(
                    child: SizedBox(
                      height: 44,
                      child: ElevatedButton.icon(
                        onPressed: onAction,
                        icon: Icon(actionIcon, size: 18),
                        label: Text(
                          actionLabel,
                          style: AppTextStyles.buttonMedium,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ink.emerald,
                          foregroundColor: ink.onEmerald,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
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
    );
  }

  // ── Similar products ──────────────────────────────────────────────────────

  /// Same category, minus this product.
  ///
  /// Asks for more than it shows because the page it gets back is the newest
  /// products in the category — this one is very often among them, and a seller
  /// the viewer has been banned by may be too.
  Future<List<Product>> _loadSimilarProducts(Product product) async {
    if (product.categoryId.isEmpty) return const <Product>[];

    try {
      final result = await _productService.getProductsPaginated(
        limit: SimilarProductsSection.count * 3,
        categoryId: product.categoryId,
        excludeSellerIds: BannedSellerService.instance.bannedSellerIds,
      );

      final products = (result['products'] as List<Product>? ?? const [])
          .where((p) => p.productId != product.productId)
          .take(SimilarProductsSection.count)
          .toList();

      AppLogger.d(
        'ProductDetailPage: ${products.length} similar products for '
        '${product.productId}',
      );
      return products;
    } catch (e) {
      AppLogger.d('Error loading similar products: $e');
      return const <Product>[];
    }
  }

  Widget _buildSimilarProductsSection(Product product) {
    // Started here rather than in initState because it needs the loaded
    // product's category, and remembered so that picking a variation or
    // changing the quantity does not re-query.
    if (_similarForProductId != product.productId) {
      _similarForProductId = product.productId;
      _similarFuture = _loadSimilarProducts(product);
    }

    return SimilarProductsSection(
      products: _similarFuture!,
      onOpen: (similar) =>
          NavigationUtils.navigateToProductDetail(context, similar.productId),
    );
  }

  Widget _buildModernProductDetail(Product product) {
    // The shell's own threshold, rather than this page's old 768/1024 pair, so
    // the detail page switches to two columns at the same width Browse and Cart
    // switch to their wide layouts.
    if (context.isWideLayout) return _buildWebLayout(product);

    return _buildMobileLayout(product);
  }

  /// The header, on both layouts.
  ///
  /// This page used to carry two of them: a pinned `SliverAppBar` whose buttons
  /// floated in their own shadowed pills on a phone, and a plain Material
  /// `AppBar` on desktop. Neither matched Browse, Cart or Orders, so the top of
  /// the window jumped as you moved between them. It is [AppPageHeader] now,
  /// like every other buyer surface — the product's name where a page title
  /// goes, and the actions in the trailing slot.
  Widget _buildHeader(Product product) {
    final brand = product.brand?.trim() ?? '';

    return AppPageHeader(
      title: product.name,
      subtitle: brand.isNotEmpty ? brand : null,
      showBack: true,
      onBack: _navigateBackToProductListing,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isCurrentUserSeller(product))
            IconButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EditProductPage(product: product),
                  ),
                ).then((_) => _handleRefresh());
              },
              icon: const Icon(Icons.edit_outlined, size: 21),
              color: ink.emerald,
              tooltip: 'Edit product',
            ),
          IconButton(
            onPressed: () => _shareProduct(product),
            icon: const Icon(Icons.share_outlined, size: 21),
            color: ink.text.withValues(alpha: 0.55),
            tooltip: 'Share',
          ),
          IconButton(
            onPressed: () {
              final user = FirebaseAuth.instance.currentUser;
              if (user == null) {
                _showLoginRequiredDialog();
              } else {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const CartPage()),
                );
              }
            },
            icon: const Icon(Icons.shopping_cart_outlined, size: 21),
            color: ink.text.withValues(alpha: 0.55),
            tooltip: 'Cart',
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(Product product) {
    return Stack(
      children: [
        // One centred column for the whole page, header included — the frame
        // Cart and Browse are laid out in.
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppLayout.maxContentWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(product),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _handleRefresh,
                    color: ink.emerald,
                    backgroundColor: ink.surface,
                    displacement: 40,
                    strokeWidth: 2.5,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        // Product image as a separate 1:1 square section
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppLayout.gutter,
                              0,
                              AppLayout.gutter,
                              4,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: Hero(
                                tag: 'product-${product.productId}',
                                child: _buildProductImageSection(product),
                              ),
                            ),
                          ),
                        ),

                        SliverToBoxAdapter(
                          child: Column(
                            children: [
                              _buildProductInfo(product),
                              _buildVariationsSection(product),
                              _buildQuantityAndStock(),
                              _buildDescriptionSection(product),
                              _buildSpecificationsSection(product),
                              _buildSimilarProductsSection(product),
                              // Room for the fixed Add to Cart bar.
                              const SizedBox(height: 80),
                            ],
                          ),
                        ),

                        // Web Footer (only shows on web)
                        const SliverToBoxAdapter(child: WebFooter()),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Fixed Add to Cart Button
        _buildFixedAddToCartButton(product),

        // Loading overlay
        LoadingOverlay(
          message: 'Adding to cart...',
          isVisible: _isAddingToCart,
        ),
      ],
    );
  }

  Widget _buildWebLayout(Product product) {
    return Stack(
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppLayout.maxContentWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(product),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _handleRefresh,
                    color: ink.emerald,
                    backgroundColor: ink.surface,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(top: 4, bottom: 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // The shot on the left, what you are deciding on the
                          // right: name, variations, quantity and the button.
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppLayout.gutter,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 6,
                                  child: AspectRatio(
                                    aspectRatio: 1,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(18),
                                      child: _buildWebProductImageSection(
                                        product,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 24),
                                Expanded(
                                  flex: 5,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildProductInfo(product),
                                      _buildVariationsSection(product),
                                      _buildQuantityAndStock(),
                                      const SizedBox(height: 16),
                                      _buildWebAddToCartButton(product),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 8),
                          _buildDescriptionSection(product),
                          _buildSpecificationsSection(product),
                          _buildSimilarProductsSection(product),

                          const SizedBox(height: 32),
                          const WebFooter(),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Loading overlay
        LoadingOverlay(
          message: 'Adding to cart...',
          isVisible: _isAddingToCart,
        ),
      ],
    );
  }

  Widget _buildWebProductImageSection(Product product) {
    final imageUrl = _selectedVariation?.imageURL ?? product.imageURL;

    return GestureDetector(
      onTap: () {
        if (imageUrl.isNotEmpty) {
          _showFullImagePopup(imageUrl);
        }
      },
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(gradient: ink.productBackdrop),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                child: imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit
                            .cover, // Changed from cover to contain for consistency
                        filterQuality: FilterQuality.high,
                        memCacheWidth: 1080,
                        maxWidthDiskCache: 1080,
                        fadeInDuration: const Duration(milliseconds: 300),
                        placeholder: (context, url) => Container(
                          color: Colors.transparent,
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.transparent,
                          child: Center(
                            child: Icon(
                              Icons.image_not_supported,
                              size: 64,
                              color: ink.text.withValues(alpha: 0.35),
                            ),
                          ),
                        ),
                      )
                    : Container(
                        color: Colors.transparent,
                        child: Center(
                          child: Icon(
                            Icons.image_not_supported,
                            size: 64,
                            color: ink.text.withValues(alpha: 0.35),
                          ),
                        ),
                      ),
              ),
            ),

            // Variation thumbnails overlay for web - improved sizing
            if (product.variations != null && product.variations!.length > 1)
              Positioned(
                bottom: 16,
                left: 16,
                right: 16,
                child: SizedBox(
                  height:
                      90, // Increased height for better thumbnail visibility
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: product.variations!.length,
                    itemBuilder: (context, index) {
                      final variation = product.variations![index];
                      final isSelected =
                          _selectedVariation?.variationId ==
                          variation.variationId;

                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedVariation = variation;
                            if (_quantity > variation.stock) {
                              _quantity = variation.stock > 0 ? 1 : 0;
                            }
                            // Update text controller for web view
                            _quantityController.text = _quantity.toString();
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 90, // Increased size for better visibility
                          height: 90,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? ink.emerald.withValues(alpha: 0.1)
                                : ink.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected ? ink.emerald : ink.border,
                              width: isSelected ? 3 : 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: isSelected
                                    ? ink.emerald.withValues(alpha: 0.2)
                                    : Colors.black.withValues(alpha: 0.1),
                                blurRadius: isSelected ? 8 : 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              14,
                            ), // Slightly smaller to account for border
                            child: SizedBox(
                              width: 90,
                              height: 90,
                              child:
                                  variation.imageURL != null &&
                                      variation.imageURL!.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl:
                                          variation.thumbnailURL ??
                                          variation.imageURL!,
                                      fit: BoxFit
                                          .cover, // Ensures image fills the entire container
                                      width: 90,
                                      height: 90,
                                      filterQuality: FilterQuality.high,
                                      fadeInDuration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      placeholder: (context, url) => Container(
                                        width: 90,
                                        height: 90,
                                        color: ink.surfaceHigh,
                                        child: const Center(
                                          child: SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        ),
                                      ),
                                      errorWidget: (context, url, error) =>
                                          Container(
                                            width: 90,
                                            height: 90,
                                            color: ink.surfaceHigh,
                                            child: Center(
                                              child: Icon(
                                                Icons.image_not_supported,
                                                size: 24,
                                                color: ink.text.withValues(
                                                  alpha: 0.35,
                                                ),
                                              ),
                                            ),
                                          ),
                                      // Optimized cache size for web thumbnails
                                      memCacheWidth: 400,
                                      memCacheHeight: 400,
                                    )
                                  : Container(
                                      width: 90,
                                      height: 90,
                                      color: ink.surfaceHigh,
                                      child: Center(
                                        child: Icon(
                                          Icons.image_not_supported,
                                          size: 24,
                                          color: ink.text.withValues(
                                            alpha: 0.35,
                                          ),
                                        ),
                                      ),
                                    ),
                            ),
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
    );
  }

  Widget _buildWebAddToCartButton(Product product) {
    final bool isInStock =
        _selectedVariation != null && _selectedVariation!.stock > 0;
    final bool showContactAgent = product.allowInquiry;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppLayout.gutter),
      child: showContactAgent
          ? ElevatedButton(
              onPressed: () => _inquireAboutProduct(product),
              style: ElevatedButton.styleFrom(
                backgroundColor: ink.emerald,
                foregroundColor: ink.onEmerald,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Contact a Sales Agent',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            )
          : LoadingButton(
              text: isInStock
                  ? 'Add to Cart • ${CurrencyFormatter.formatWithPeso(_selectedVariation!.price * _quantity)}'
                  : 'Out of Stock',
              loadingText: 'Adding to cart...',
              isLoading: _isAddingToCart,
              onPressed: isInStock ? () => _addToCart(product) : null,
              backgroundColor: ink.emerald,
              foregroundColor: ink.onEmerald,
              borderRadius: BorderRadius.circular(14),
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                fontFamily: 'Roboto',
              ),
            ),
    );
  }

  Widget _buildProductImageSection(Product product) {
    final hasGallery = product.images.isNotEmpty;
    final variations = product.variations ?? const <ProductVariation>[];
    final hasVariations = variations.isNotEmpty;

    final imageUrl = (_inGallery && hasGallery)
        ? product.images[_galleryImageIndex]
        : (_selectedVariation?.imageURL ?? product.imageURL);

    // Track swipe direction for animation
    Offset _swipeOffset = const Offset(0.2, 0);

    void goToVariation(ProductVariation variation) {
      _selectedVariation = variation;
      if (_quantity > variation.stock) {
        _quantity = variation.stock > 0 ? 1 : 0;
      }
      _quantityController.text = _quantity.toString();
    }

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity;
        if (velocity == null) return;

        // Swipe LEFT (next frame): velocity < 0
        if (velocity < 0) {
          if (_inGallery && hasGallery) {
            if (_galleryImageIndex < product.images.length - 1) {
              setState(() {
                _swipeOffset = const Offset(0.2, 0);
                _galleryImageIndex++;
              });
            } else if (hasVariations) {
              // Past the last gallery image → enter variations.
              setState(() {
                _swipeOffset = const Offset(0.2, 0);
                _inGallery = false;
                goToVariation(variations.first);
              });
            }
          } else if (hasVariations) {
            final currentIndex = variations.indexWhere(
              (v) => v.variationId == _selectedVariation?.variationId,
            );
            if (currentIndex < variations.length - 1) {
              setState(() {
                _swipeOffset = const Offset(0.2, 0);
                goToVariation(variations[currentIndex + 1]);
              });
            }
          }
          return;
        }

        // Swipe RIGHT (previous frame): velocity > 0
        if (velocity > 0) {
          if (!_inGallery && hasVariations) {
            final currentIndex = variations.indexWhere(
              (v) => v.variationId == _selectedVariation?.variationId,
            );
            if (currentIndex > 0) {
              setState(() {
                _swipeOffset = const Offset(-0.2, 0);
                goToVariation(variations[currentIndex - 1]);
              });
            } else if (hasGallery) {
              // Back from the first variation → return to the last gallery image.
              setState(() {
                _swipeOffset = const Offset(-0.2, 0);
                _inGallery = true;
                _galleryImageIndex = product.images.length - 1;
              });
            }
          } else if (_inGallery && _galleryImageIndex > 0) {
            setState(() {
              _swipeOffset = const Offset(-0.2, 0);
              _galleryImageIndex--;
            });
          }
        }
      },
      onTap: () {
        if (imageUrl.isNotEmpty) {
          _showFullImagePopup(imageUrl);
        }
      },
      child: AspectRatio(
        aspectRatio: 1, // 720x720 square
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(gradient: ink.productBackdrop),
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) {
                    final offsetAnimation = Tween<Offset>(
                      begin: _swipeOffset,
                      end: Offset.zero,
                    ).animate(animation);

                    return SlideTransition(
                      position: offsetAnimation,
                      child: FadeTransition(opacity: animation, child: child),
                    );
                  },
                  child: SizedBox(
                    key: ValueKey(
                      imageUrl,
                    ), // important for detecting image change
                    width: double.infinity,
                    height: double.infinity,
                    child: imageUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.high,
                            fadeInDuration: const Duration(milliseconds: 300),
                            fadeOutDuration: const Duration(milliseconds: 100),
                            placeholder: (context, url) => Container(
                              color: Colors.transparent,
                              child: const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: Colors.transparent,
                              child: Center(
                                child: Icon(
                                  Icons.image_not_supported,
                                  size: 64,
                                  color: ink.text.withValues(alpha: 0.35),
                                ),
                              ),
                            ),
                            memCacheWidth: 720, // 720p square
                            memCacheHeight: 720,
                          )
                        : Container(
                            color: Colors.transparent,
                            child: Center(
                              child: Icon(
                                Icons.image_not_supported,
                                size: 64,
                                color: ink.text.withValues(alpha: 0.35),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.1),
                      ],
                    ),
                  ),
                ),
              ),
              // Updated variation indicators for mobile
              if (product.variations != null && product.variations!.length > 1)
                Positioned(
                  bottom: 16,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: product.variations!.asMap().entries.map((entry) {
                      final isSelected =
                          _selectedVariation?.variationId ==
                          entry.value.variationId;
                      final hasImage =
                          entry.value.imageURL != null &&
                          entry.value.imageURL!.isNotEmpty;

                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: isSelected ? 32 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? ink.emerald
                              : hasImage
                              ? Colors.white.withValues(alpha: 0.7)
                              : Colors.white.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(
                            isSelected ? 6 : 50,
                          ),
                          border: isSelected
                              ? Border.all(color: Colors.white, width: 1)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductInfo(Product product) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppLayout.gutter,
        14,
        AppLayout.gutter,
        6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product name and favorite
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: AppTextStyles.headlineSmall.copyWith(
                        fontWeight: FontWeight.bold,
                        color: ink.text,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FutureBuilder<String>(
                      future: _getCategoryName(product.categoryId),
                      builder: (context, snapshot) {
                        final categoryName = snapshot.data ?? 'Loading...';
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: ink.text.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            categoryName,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: ink.text.withValues(alpha: 0.5),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Shop name section
          if (_selectedVariation != null)
            FutureBuilder<Map<String, dynamic>>(
              future: _getSellerData(product.sellerId),
              builder: (context, sellerSnapshot) {
                final sellerData =
                    sellerSnapshot.data ??
                    {
                      'shopName': 'DentPal Store',
                      'address': 'Loading...',
                      'isActive': true,
                    };
                final profileImageURL =
                    sellerData['profileImageURL'] as String? ?? '';
                // Add cache-busting parameter for web
                final profileImageURLWithCache = profileImageURL.isNotEmpty
                    ? (profileImageURL.contains('?')
                          ? '$profileImageURL&v=${DateTime.now().millisecondsSinceEpoch}'
                          : '$profileImageURL?v=${DateTime.now().millisecondsSinceEpoch}')
                    : '';

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: ink.emerald.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: ink.emerald.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: ink.emerald.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: ink.emerald.withValues(alpha: 0.2),
                            width: 2,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: profileImageURL.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: profileImageURLWithCache,
                                  fit: BoxFit.cover,
                                  cacheKey: profileImageURL,
                                  memCacheWidth: 160,
                                  maxWidthDiskCache: 160,
                                  placeholder: (context, url) => Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        ink.emerald,
                                      ),
                                    ),
                                  ),
                                  errorWidget: (context, url, error) => Icon(
                                    Icons.store,
                                    size: 24,
                                    color: ink.emerald,
                                  ),
                                )
                              : Icon(Icons.store, size: 24, color: ink.emerald),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sellerData['shopName'] ??
                                  'Store name not available',
                              style: AppTextStyles.titleMedium.copyWith(
                                color: ink.emerald,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              sellerData['address'] ?? 'Address not available',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: ink.text.withValues(alpha: 0.7),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildVariationsSection(Product product) {
    if (product.variations == null || product.variations!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppLayout.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: ink.emerald.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.tune, color: ink.emerald, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                'Variations',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: ink.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 110, // Increased height to accommodate image + label
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: product.variations!.length,
              itemBuilder: (context, index) {
                final variation = product.variations![index];
                final isSelected =
                    _selectedVariation?.variationId == variation.variationId;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedVariation = variation;
                      // Reset quantity if it exceeds the new variation's stock
                      if (_quantity > variation.stock) {
                        _quantity = variation.stock > 0 ? 1 : 0;
                      }
                      // Update text controller for web view
                      _quantityController.text = _quantity.toString();
                    });
                  },
                  child: Container(
                    width: 80, // Increased width to accommodate longer names
                    margin: const EdgeInsets.only(right: 12),
                    child: Column(
                      children: [
                        // Image container
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? ink.emerald.withValues(alpha: 0.1)
                                : ink.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? ink.emerald
                                  : ink.text.withValues(alpha: 0.2),
                              width: isSelected ? 2 : 1,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: ink.emerald.withValues(alpha: 0.2),
                                      blurRadius: 6,
                                      offset: const Offset(0, 1),
                                    ),
                                  ]
                                : [],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: SizedBox(
                              width: 70,
                              height: 70,
                              child:
                                  variation.imageURL != null &&
                                      variation.imageURL!.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl:
                                          variation.thumbnailURL ??
                                          variation.imageURL!,
                                      fit: BoxFit.cover,
                                      width: 70,
                                      height: 70,
                                      filterQuality: FilterQuality.high,
                                      fadeInDuration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      placeholder: (context, url) => Container(
                                        width: 70,
                                        height: 70,
                                        color: ink.bg,
                                        child: const Center(
                                          child: SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        ),
                                      ),
                                      errorWidget: (context, url, error) =>
                                          Container(
                                            width: 70,
                                            height: 70,
                                            color: ink.bg,
                                            child: Center(
                                              child: Icon(
                                                Icons.image_not_supported,
                                                size: 20,
                                                color: ink.text.withValues(
                                                  alpha: 0.35,
                                                ),
                                              ),
                                            ),
                                          ),
                                      memCacheWidth: 300,
                                      memCacheHeight: 300,
                                    )
                                  : Container(
                                      width: 70,
                                      height: 70,
                                      color: ink.bg,
                                      child: Center(
                                        child: Icon(
                                          Icons.image_not_supported,
                                          size: 20,
                                          color: ink.text.withValues(
                                            alpha: 0.35,
                                          ),
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        // Variation name below image
                        const SizedBox(height: 6),
                        Text(
                          variation.name,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: isSelected
                                ? ink.emerald
                                : ink.text.withValues(alpha: 0.7),
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                            fontSize: 11,
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
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildQuantityAndStock() {
    if (_selectedVariation == null) return const SizedBox.shrink();

    final isWebView = context.isWideLayout;

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppLayout.gutter,
        4,
        AppLayout.gutter,
        8,
      ),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ink.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: ink.emerald.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.shopping_bag, color: ink.emerald, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                'Quantity',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: ink.text,
                ),
              ),
              const Spacer(),
              Text(
                '${_selectedVariation!.stock} available',
                style: AppTextStyles.bodySmall.copyWith(
                  color: _quantity >= _selectedVariation!.stock
                      ? Colors.orange
                      : ink.text.withValues(alpha: 0.7),
                  fontWeight: _quantity >= _selectedVariation!.stock
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // Quantity selector - different for web and mobile
              isWebView
                  ? _buildWebQuantitySelector()
                  : _buildMobileQuantitySelector(),
              const Spacer(),
              // Price and Total section
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Unit Price',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: ink.text.withValues(alpha: 0.7),
                    ),
                  ),
                  Text(
                    CurrencyFormatter.formatWithPeso(_selectedVariation!.price),
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      color: ink.text,
                      fontFamily: 'Roboto', // Use Roboto for peso sign support
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Total',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: ink.text.withValues(alpha: 0.7),
                    ),
                  ),
                  Text(
                    CurrencyFormatter.formatWithPeso(
                      _selectedVariation!.price * _quantity,
                    ),
                    style: AppTextStyles.titleMedium.copyWith(
                      fontWeight: FontWeight.bold,
                      color: ink.emerald,
                      fontFamily: 'Roboto', // Use Roboto for peso sign support
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Mobile quantity selector with buttons
  Widget _buildMobileQuantitySelector() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: ink.emerald.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.remove, color: ink.emerald),
            onPressed: _quantity > 1
                ? () {
                    setState(() {
                      _quantity--;
                    });
                  }
                : null,
            iconSize: 20,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _quantity.toString(),
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.bold,
                color: ink.emerald,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.add, color: ink.emerald),
            onPressed: _quantity < _selectedVariation!.stock
                ? () {
                    setState(() {
                      _quantity++;
                    });
                  }
                : null,
            iconSize: 20,
          ),
        ],
      ),
    );
  }

  // Web quantity selector with text input
  Widget _buildWebQuantitySelector() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: ink.emerald.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      height: 48,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Decrease button
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
              onTap: _quantity > 1
                  ? () {
                      setState(() {
                        _quantity--;
                        _quantityController.text = _quantity.toString();
                      });
                    }
                  : null,
              child: Container(
                width: 40,
                height: 48,
                alignment: Alignment.center,
                child: Icon(
                  Icons.remove,
                  color: _quantity > 1
                      ? ink.emerald
                      : ink.emerald.withValues(alpha: 0.3),
                  size: 20,
                ),
              ),
            ),
          ),
          // Quantity input field - simplified
          SizedBox(
            width: 80,
            height: 48,
            child: TextField(
              controller: _quantityController,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.bold,
                color: ink.emerald,
                height: 1.2,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                fillColor: Colors.transparent,
                filled: false,
                contentPadding: EdgeInsets.symmetric(vertical: 18),
                isCollapsed: false,
                isDense: true,
              ),
              textAlignVertical: TextAlignVertical.center,
              onChanged: (value) {
                if (value.startsWith('0')) {
                  _quantityController.text = value.replaceFirst(
                    RegExp(r'^0+'),
                    '',
                  );
                  _quantityController.selection = TextSelection.fromPosition(
                    TextPosition(offset: _quantityController.text.length),
                  );
                  return;
                }
                final parsedValue = int.tryParse(value);
                if (parsedValue != null && parsedValue > 0) {
                  final clampedValue = parsedValue.clamp(
                    1,
                    _selectedVariation!.stock,
                  );
                  if (clampedValue != parsedValue) {
                    // Clamp to max stock
                    _quantityController.text = clampedValue.toString();
                    _quantityController.selection = TextSelection.fromPosition(
                      TextPosition(offset: _quantityController.text.length),
                    );
                  }
                  setState(() {
                    _quantity = clampedValue;
                  });
                } else if (value.isEmpty) {
                  // Allow empty field temporarily
                  setState(() {
                    _quantity = 1;
                  });
                } else {
                  // Invalid input, reset to current quantity
                  _quantityController.text = _quantity.toString();
                  _quantityController.selection = TextSelection.fromPosition(
                    TextPosition(offset: _quantityController.text.length),
                  );
                }
              },
              onSubmitted: (value) {
                final parsedValue = int.tryParse(value);
                int newValue = 1;
                if (parsedValue != null && parsedValue > 0) {
                  newValue = parsedValue.clamp(1, _selectedVariation!.stock);
                }
                _quantityController.text = newValue.toString();
                setState(() {
                  _quantity = newValue;
                });
              },
              onTap: () {
                // Select all text when tapped for easier editing
                _quantityController.selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: _quantityController.text.length,
                );
              },
            ),
          ),
          // Increase button
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
              onTap: _quantity < _selectedVariation!.stock
                  ? () {
                      setState(() {
                        _quantity++;
                        _quantityController.text = _quantity.toString();
                      });
                    }
                  : null,
              child: Container(
                width: 40,
                height: 48,
                alignment: Alignment.center,
                child: Icon(
                  Icons.add,
                  color: _quantity < _selectedVariation!.stock
                      ? ink.emerald
                      : ink.emerald.withValues(alpha: 0.3),
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionSection(Product product) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppLayout.gutter,
        4,
        AppLayout.gutter,
        8,
      ),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ink.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: ink.emeraldSoft.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.description,
                  color: ink.emeraldSoft,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Description',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: ink.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            product.description,
            style: AppTextStyles.bodyMedium.copyWith(
              color: ink.text.withValues(alpha: 0.8),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecificationsSection(Product product) {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        _getCategoryName(product.categoryId),
        _getSubCategoryName(product.categoryId, product.subCategoryId),
        _getSellerData(product.sellerId),
      ]),
      builder: (context, snapshot) {
        final categoryName = snapshot.data?[0] as String? ?? '';
        final subCategoryName = snapshot.data?[1] as String? ?? '';
        final sellerData = snapshot.data?[2] as Map<String, dynamic>? ?? {};
        final sellerAddress = sellerData['address'] as String? ?? '';

        final hasWarranty =
            product.warrantyType != null && product.warrantyType!.isNotEmpty;

        // Get selected variation for pcsPerBox display
        final selectedVariation = _selectedVariation;

        return Container(
          margin: const EdgeInsets.fromLTRB(
            AppLayout.gutter,
            4,
            AppLayout.gutter,
            8,
          ),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ink.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ink.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: ink.emerald.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.info_outline_rounded,
                      color: ink.emerald,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Product Specifications',
                    style: AppTextStyles.titleMedium.copyWith(
                      fontWeight: FontWeight.bold,
                      color: ink.text,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Spec rows
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else ...[
                // Brand
                if (product.brand != null && product.brand!.isNotEmpty) ...[
                  _buildSpecRow(label: 'Brand', value: product.brand!),
                  const Divider(height: 20, thickness: 0.6),
                ],

                // Variation Name - pcsPerBox
                if (selectedVariation != null &&
                    selectedVariation.pcsPerBox != null) ...[
                  _buildSpecRow(
                    label: 'Variation',
                    value:
                        '${selectedVariation.name.isNotEmpty ? selectedVariation.name : 'Default'}  Pcs Per Box: ${selectedVariation.pcsPerBox}',
                  ),
                  const Divider(height: 20, thickness: 0.6),
                ],

                // Category / SubCategory
                _buildSpecRow(
                  label: 'Category',
                  value: subCategoryName.isNotEmpty
                      ? '$categoryName  ›  $subCategoryName'
                      : categoryName,
                ),
                const Divider(height: 20, thickness: 0.6),

                // Ships From
                _buildSpecRow(
                  label: 'Ships From',
                  value: sellerAddress.isNotEmpty ? sellerAddress : '—',
                ),
                const Divider(height: 20, thickness: 0.6),

                // Dangerous Goods
                _buildSpecRow(
                  label: 'Dangerous Goods',
                  value:
                      (product.dangerousGoods == null ||
                          product.dangerousGoods!.isEmpty ||
                          product.dangerousGoods!.toLowerCase() == 'none')
                      ? 'No'
                      : 'Yes - ${product.dangerousGoods![0].toUpperCase()}${product.dangerousGoods!.substring(1)}',
                ),
                const Divider(height: 20, thickness: 0.6),

                // Warranty block - Always show warranty info
                _buildSpecRow(
                  label: 'Warranty Type',
                  value: hasWarranty
                      ? '${product.warrantyType![0].toUpperCase()}${product.warrantyType!.substring(1)} Warranty'
                      : 'No Warranty',
                ),
                // Only show duration and policy if there is a warranty
                if (hasWarranty) ...[
                  // Warranty Duration (use warrantyDuration first, then fall back to warrantyPeriod)
                  if ((product.warrantyDuration != null &&
                          product.warrantyDuration!.isNotEmpty) ||
                      (product.warrantyPeriod != null &&
                          product.warrantyPeriod!.isNotEmpty)) ...[
                    const Divider(height: 20, thickness: 0.6),
                    _buildSpecRow(
                      label: 'Warranty Duration',
                      value:
                          product.warrantyDuration != null &&
                              product.warrantyDuration!.isNotEmpty
                          ? product.warrantyDuration!
                          : (product.warrantyPeriodUnit != null &&
                                    product.warrantyPeriodUnit!.isNotEmpty
                                ? '${product.warrantyPeriod} ${product.warrantyPeriodUnit}'
                                : product.warrantyPeriod!),
                    ),
                  ],
                  // Warranty Policy
                  if (product.warrantyPolicy != null &&
                      product.warrantyPolicy!.isNotEmpty) ...[
                    const Divider(height: 20, thickness: 0.6),
                    _buildWarrantyPolicyRow(product.warrantyPolicy!),
                  ],
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildSpecRow({required String label, required String value}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: ink.text.withValues(alpha: 0.55),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: AppTextStyles.bodySmall.copyWith(
              color: ink.text.withValues(alpha: 0.85),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWarrantyPolicyRow(String policy) {
    return _ExpandableWarrantyPolicy(policy: policy);
  }

  // Hidden: Static/fake review data - uncomment when real reviews are implemented
  // Widget _buildReviewsSection() {
  //   return Container(
  //     margin: const EdgeInsets.fromLTRB(24, 4, 24, 8),
  //     padding: const EdgeInsets.all(16),
  //     decoration: BoxDecoration(
  //       color: ink.surface,
  //       borderRadius: BorderRadius.circular(16),
  //       border: Border.all(
  //         color: ink.text.withValues(alpha: 0.1),
  //       ),
  //     ),
  //     child: Column(
  //       crossAxisAlignment: CrossAxisAlignment.start,
  //       children: [
  //         Row(
  //           children: [
  //             Container(
  //               padding: const EdgeInsets.all(8),
  //               decoration: BoxDecoration(
  //                 color: Colors.amber.withValues(alpha: 0.1),
  //                 borderRadius: BorderRadius.circular(8),
  //               ),
  //               child: const Icon(
  //                 Icons.star,
  //                 color: Colors.amber,
  //                 size: 20,
  //               ),
  //             ),
  //             const SizedBox(width: 12),
  //             Text(
  //               'Reviews',
  //               style: AppTextStyles.titleMedium.copyWith(
  //                 fontWeight: FontWeight.bold,
  //                 color: ink.text,
  //               ),
  //             ),
  //             const Spacer(),
  //             TextButton(
  //               onPressed: () {
  //                 // TODO: Navigate to reviews page
  //               },
  //               child: Text(
  //                 'See All',
  //                 style: AppTextStyles.bodySmall.copyWith(
  //                   color: ink.emerald,
  //                   fontWeight: FontWeight.w600,
  //                 ),
  //               ),
  //             ),
  //           ],
  //         ),
  //         const SizedBox(height: 16),
  //
  //         // Rating summary
  //         Row(
  //           children: [
  //             Text(
  //               '4.5',
  //               style: AppTextStyles.headlineSmall.copyWith(
  //                 fontWeight: FontWeight.bold,
  //                 color: ink.text,
  //               ),
  //             ),
  //             const SizedBox(width: 12),
  //             Column(
  //               crossAxisAlignment: CrossAxisAlignment.start,
  //               children: [
  //                 Row(
  //                   children: List.generate(5, (index) {
  //                     return Icon(
  //                       index < 4 ? Icons.star : Icons.star_half,
  //                       color: Colors.amber,
  //                       size: 16,
  //                     );
  //                   }),
  //                 ),
  //                 Text(
  //                   '24 reviews',
  //                   style: AppTextStyles.bodySmall.copyWith(
  //                     color: ink.text.withValues(alpha: 0.6),
  //                   ),
  //                 ),
  //               ],
  //             ),
  //           ],
  //         ),
  //
  //         const SizedBox(height: 20),
  //
  //         // Sample reviews
  //         _buildModernReviewItem(
  //           name: 'John Doe',
  //           rating: 5,
  //           date: '2 weeks ago',
  //           comment: 'Great product! Really satisfied with the quality.',
  //         ),
  //         const SizedBox(height: 16),
  //         _buildModernReviewItem(
  //           name: 'Jane Smith',
  //           rating: 4,
  //           date: '1 month ago',
  //           comment: 'Good product but shipping took longer than expected.',
  //         ),
  //       ],
  //     ),
  //   );
  // }

  // Widget _buildModernReviewItem({
  //   required String name,
  //   required int rating,
  //   required String date,
  //   required String comment,
  // }) {
  //   return Container(
  //     padding: const EdgeInsets.all(16),
  //     decoration: BoxDecoration(
  //       color: ink.bg,
  //       borderRadius: BorderRadius.circular(12),
  //     ),
  //     child: Column(
  //       crossAxisAlignment: CrossAxisAlignment.start,
  //       children: [
  //         Row(
  //           children: [
  //             Container(
  //               width: 36,
  //               height: 36,
  //               decoration: BoxDecoration(
  //                 color: ink.emerald.withValues(alpha: 0.1),
  //                 shape: BoxShape.circle,
  //               ),
  //               child: Center(
  //                 child: Text(
  //                   name[0].toUpperCase(),
  //                   style: AppTextStyles.titleSmall.copyWith(
  //                     color: ink.emerald,
  //                     fontWeight: FontWeight.bold,
  //                   ),
  //                 ),
  //               ),
  //             ),
  //             const SizedBox(width: 12),
  //             Expanded(
  //               child: Column(
  //                 crossAxisAlignment: CrossAxisAlignment.start,
  //                 children: [
  //                   Text(
  //                     name,
  //                     style: AppTextStyles.bodyMedium.copyWith(
  //                       fontWeight: FontWeight.w600,
  //                       color: ink.text,
  //                     ),
  //                   ),
  //                   Row(
  //                     children: [
  //                       Row(
  //                         children: List.generate(5, (index) {
  //                           return Icon(
  //                             index < rating ? Icons.star : Icons.star_border,
  //                             color: Colors.amber,
  //                             size: 14,
  //                           );
  //                         }),
  //                       ),
  //                       const SizedBox(width: 8),
  //                       Text(
  //                         date,
  //                         style: AppTextStyles.bodySmall.copyWith(
  //                           color: ink.text.withValues(alpha: 0.6),
  //                         ),
  //                       ),
  //                     ],
  //                   ),
  //                 ],
  //               ),
  //             ),
  //           ],
  //         ),
  //         const SizedBox(height: 12),
  //         Text(
  //           comment,
  //           style: AppTextStyles.bodyMedium.copyWith(
  //             color: ink.text.withValues(alpha: 0.8),
  //             height: 1.4,
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  Widget _buildFixedAddToCartButton(Product product) {
    // If the product is inquiry-only, replace Add to Cart with
    // "Contact a Sales Agent" regardless of stock status.
    final bool isInStock =
        _selectedVariation != null && _selectedVariation!.stock > 0;
    final bool showContactAgent = product.allowInquiry;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: ink.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: showContactAgent
              ? SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _inquireAboutProduct(product),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ink.emerald,
                      foregroundColor: ink.onEmerald,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Contact a Sales Agent',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
              : LoadingButton(
                  text: isInStock
                      ? 'Add to Cart • ${CurrencyFormatter.formatWithPeso(_selectedVariation!.price * _quantity)}'
                      : 'Out of Stock',
                  loadingText: 'Adding to cart...',
                  isLoading: _isAddingToCart,
                  onPressed: isInStock ? () => _addToCart(product) : null,
                  backgroundColor: ink.emerald,
                  foregroundColor: ink.onEmerald,
                  borderRadius: BorderRadius.circular(14),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Roboto',
                  ),
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Expandable warranty policy widget (max 3 lines → "Read more …" in blue)
// ─────────────────────────────────────────────────────────────────────────────

class _ExpandableWarrantyPolicy extends StatefulWidget {
  final String policy;

  const _ExpandableWarrantyPolicy({required this.policy});

  @override
  State<_ExpandableWarrantyPolicy> createState() =>
      _ExpandableWarrantyPolicyState();
}

class _ExpandableWarrantyPolicyState extends State<_ExpandableWarrantyPolicy> {
  bool _expanded = false;

  InkPalette get ink => InkPalette.of(context);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            'Warranty Policy',
            style: AppTextStyles.bodySmall.copyWith(
              color: ink.text.withValues(alpha: 0.55),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.policy,
                maxLines: _expanded ? null : 3,
                overflow: _expanded
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                style: AppTextStyles.bodySmall.copyWith(
                  color: ink.text.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                ),
              ),
              // Only show the toggle if content actually overflows 3 lines
              LayoutBuilder(
                builder: (ctx, constraints) {
                  final tp = TextPainter(
                    text: TextSpan(
                      text: widget.policy,
                      style: AppTextStyles.bodySmall.copyWith(
                        fontWeight: FontWeight.w500,
                        height: 1.5,
                      ),
                    ),
                    maxLines: 3,
                    textDirection: TextDirection.ltr,
                  )..layout(maxWidth: constraints.maxWidth);

                  final overflows = tp.didExceedMaxLines;
                  if (!overflows && !_expanded) return const SizedBox.shrink();

                  return GestureDetector(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _expanded ? 'Read less' : 'Read more ...',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: Colors.blue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
