import 'package:dentpal/core/app_theme/index.dart';
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
import '../widgets/loading_overlay.dart';
import '../utils/cart_feedback.dart';
import 'cart_page.dart';
import 'edit_product_page.dart';
import 'store_page.dart';
import '../../login_page.dart';
import 'package:dentpal/utils/app_logger.dart';
import 'package:dentpal/utils/navigation_utils.dart';
import 'package:dentpal/services/chat_service.dart';
import 'package:dentpal/profile/pages/chat_detail_page.dart';


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
        onTap: () => Navigator.of(context).pop(), // dismiss when tapping outside
        child: Stack(
          children: [
            Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 600, maxHeight: 600),
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
                        placeholder: (context, url) =>
                            const Center(child: CircularProgressIndicator()),
                        errorWidget: (context, url, error) => const Icon(
                          Icons.broken_image,
                          color: AppColors.error,
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
                    color: AppColors.error,
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
  
  late Future<Product?> _productFuture;
  int _quantity = 1;
  ProductVariation? _selectedVariation;
  bool _isAddingToCart = false;
  DateTime? _lastAddToCartTime;
  
  // Controller for quantity input (web view)
  final TextEditingController _quantityController = TextEditingController();
  
  // Cache for category names to avoid repeated Firestore calls
  final Map<String, String> _categoryNames = {};
  
  // Cache for seller data to avoid repeated Firestore calls
  final Map<String, Map<String, dynamic>> _sellerData = {};
  
  // Cache management
  Product? _cachedProduct;
  DateTime? _cacheTimestamp;
  
  // Check if current user is the seller of this product
  bool _isCurrentUserSeller(Product product) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return false;
    return currentUser.uid == product.sellerId;
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
        if (product.variations != null && 
            product.variations!.isNotEmpty) {
          _selectedVariation = product.variations![0];
          // Update text controller for web view
          _quantityController.text = _quantity.toString();
        }
        
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
        final sellerInfo = {
          'shopName': data['shopName'] ?? 'DentPal Store',
          'address': data['address'] ?? 'No address provided',
          'contactEmail': data['contactEmail'] ?? '',
          'contactNumber': data['contactNumber'] ?? '',
          'isActive': data['isActive'] ?? true,
        };
        _sellerData[sellerId] = sellerInfo;
        return sellerInfo;
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
          AppLogger.d('Product data changed: Variation ${oldVar.name} has differences');
          return true;
        }
      }
    }
    
    return false;
  }

  // Handle pull-to-refresh with cache-first approach and change detection
  Future<void> _handleRefresh() async {
    AppLogger.d('ProductDetailPage: Pull-to-refresh triggered (cache-first approach)');
    
    try {
      // Keep current data as backup
      final currentProduct = _cachedProduct;
      final currentTimestamp = _cacheTimestamp;
      
      AppLogger.d('Current cache: ${currentProduct?.name ?? 'No cached product'}');
      
      // Fetch fresh data from Firebase
      AppLogger.d('Fetching fresh product data from Firebase...');
      final freshProduct = await _productService.getProductById(widget.productId);
      
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
          if (freshProduct?.variations != null && freshProduct!.variations!.isNotEmpty) {
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
        
        AppLogger.d('Product data updated: ${freshProduct?.name ?? 'Product removed'}');
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
            backgroundColor: AppColors.error,
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
        'Cannot add more items than available stock (${_selectedVariation!.stock})'
      );
      setState(() {
        _quantity = _selectedVariation!.stock > 0 ? _selectedVariation!.stock : 1;
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
          'Added $_quantity ${product.name} to cart'
        );
      }
    } catch (e) {
      if (mounted) {
        CartFeedback.showError(
          context, 
          'Failed to add item to cart: ${e.toString()}'
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
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
            'You need to login to add items to your cart. Would you like to login now?',
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
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
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

      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      // Navigate to chat
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatDetailPage(
              chatRoomId: chatRoomId,
              otherUserId: product.sellerId,
              otherUserName: 'Seller', // Will be updated with actual seller name in chat page
            ),
          ),
        );
      }
    } catch (e) {
      // Close loading dialog if still open
      if (mounted) Navigator.of(context).pop();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start chat: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
  
  void _shareProduct(Product product) {
    // On mobile, use native share directly without showing our modal
    if (!kIsWeb) {
      final shareUrl = NavigationUtils.getProductShareUrl(product.productId);
      final shareText = '${product.name}\n\nCheck out this product on DentPal: $shareUrl';
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
    final shareText = '${product.name}\n\nCheck out this product on DentPal: $shareUrl';
    
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
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
                color: AppColors.onSurface.withValues(alpha: 0.3),
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
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.share,
                          color: AppColors.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Share Product',
                        style: AppTextStyles.titleLarge.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.onSurface,
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
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.link,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    'Copy Link',
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    shareUrl,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.onSurface.withValues(alpha: 0.6),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(
                    Icons.copy,
                    color: AppColors.primary,
                    size: 20,
                  ),
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
            child: Icon(
              icon,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.onSurface.withValues(alpha: 0.7),
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
    final facebookUrl = 'https://www.facebook.com/sharer/sharer.php?u=${Uri.encodeComponent(url)}';
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
    final messengerUrl = 'https://www.messenger.com/new?text=${Uri.encodeComponent(text)}';
    _openUrl(messengerUrl);
  }

  void _shareToEmail(String url, String text) {
    // Email should work on both mobile and web
    final emailUrl = 'mailto:?subject=${Uri.encodeComponent('Check out this product on DentPal')}&body=${Uri.encodeComponent(text)}';
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
                Icon(
                  Icons.check_circle,
                  color: AppColors.onPrimary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    customMessage ?? 'Link copied to clipboard!',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.primary,
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
      backgroundColor: AppColors.background,
      body: FutureBuilder<Product?>(
        future: _productFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return _buildErrorState();
          } else if (!snapshot.hasData || snapshot.data == null) {
            return _buildNotFoundState();
          }
          
          final product = snapshot.data!;
          return _buildModernProductDetail(product);
        },
      ),
    );
  }

  Widget _buildErrorState() {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red,
              ),
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
            Text(
              'Unable to load product details',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _productFuture = _loadProduct();
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
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotFoundState() {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
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
              'Product Not Found',
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'The product you\'re looking for doesn\'t exist',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Go Back'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernProductDetail(Product product) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWebView = screenWidth > 1024;
    final isTabletView = screenWidth > 768 && screenWidth <= 1024;
    
    if (isWebView || isTabletView) {
      return _buildWebLayout(product);
    }
    
    return _buildMobileLayout(product);
  }

  Widget _buildMobileLayout(Product product) {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _handleRefresh,
          color: AppColors.primary,
          backgroundColor: AppColors.surface,
          displacement: 40,
          strokeWidth: 2.5,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
            // Modern SliverAppBar with product image
            SliverAppBar(
              expandedHeight: 400,
              floating: false,
              pinned: true,
              elevation: 0,
              backgroundColor: AppColors.surface,
              leading: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .9),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              actions: [
                Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .9),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Edit button - only show if current user is the seller
                      if (_isCurrentUserSeller(product)) ...[
                        IconButton(
                          icon: const Icon(Icons.edit, color: AppColors.primary),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => EditProductPage(product: product),
                              ),
                            ).then((_) {
                              // Refresh product data after edit
                              _handleRefresh();
                            });
                          },
                        ),
                        Container(
                          width: 1,
                          height: 24,
                          color: AppColors.onSurface.withValues(alpha: .1),
                        ),
                      ],
                      // Share button
                      IconButton(
                        icon: const Icon(Icons.share, color: AppColors.onSurface),
                        onPressed: () => _shareProduct(product),
                      ),
                      Container(
                        width: 1,
                        height: 24,
                        color: AppColors.onSurface.withValues(alpha: .1),
                      ),
                      IconButton(
                        icon: const Icon(Icons.shopping_cart, color: AppColors.onSurface),
                        onPressed: () {
                          // Check if user is authenticated before navigating to cart
                          final user = FirebaseAuth.instance.currentUser;
                          if (user == null) {
                            _showLoginRequiredDialog();
                          } else {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (context) => const CartPage()),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Hero(
                  tag: 'product-${product.productId}',
                  child: _buildProductImageSection(product),
                ),
              ),
            ),
            
            // Product Information
            SliverToBoxAdapter(
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Column(
                  children: [
                    _buildProductInfo(product),
                    _buildVariationsSection(product),
                    _buildQuantityAndStock(),
                    _buildDescriptionSection(product),
                    _buildReviewsSection(),
                    const SizedBox(height: 80), // Bottom padding for fixed button
                  ],
                ),
              ),
            ),
          ],
        ), // End CustomScrollView
        ), // End RefreshIndicator
        
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text(
          product.name,
          style: AppTextStyles.titleLarge.copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.onSurface,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // Edit button - only show if current user is the seller
          if (_isCurrentUserSeller(product))
            IconButton(
              icon: const Icon(Icons.edit, color: AppColors.primary),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EditProductPage(product: product),
                  ),
                ).then((_) {
                  // Refresh product data after edit
                  _handleRefresh();
                });
              },
            ),
          // Share button
          IconButton(
            icon: const Icon(Icons.share, color: AppColors.onSurface),
            onPressed: () => _shareProduct(product),
          ),
          IconButton(
            icon: const Icon(Icons.shopping_cart, color: AppColors.onSurface),
            onPressed: () {
              // Check if user is authenticated before navigating to cart
              final user = FirebaseAuth.instance.currentUser;
              if (user == null) {
                _showLoginRequiredDialog();
              } else {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const CartPage()),
                );
              }
            },
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _handleRefresh,
            color: AppColors.primary,
            backgroundColor: AppColors.surface,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Row 1: Image + Product Info + Actions
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left side - Product Image
                          Expanded(
                            flex: 6,
                            child: Container(
                              height: 600,
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: _buildWebProductImageSection(product),
                              ),
                            ),
                          ),
                          
                          const SizedBox(width: 40),
                          
                          // Right side - Product Details & Actions
                          Expanded(
                            flex: 5,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildProductInfo(product),
                                _buildVariationsSection(product),
                                _buildQuantityAndStock(),
                                const SizedBox(height: 24),
                                // Web Add to Cart Button
                                _buildWebAddToCartButton(product),
                              ],
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 40),
                      
                      // Row 2: Description (Full Width)
                      SizedBox(
                        width: double.infinity,
                        child: _buildDescriptionSection(product),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Row 3: Reviews (Full Width)
                      SizedBox(
                        width: double.infinity,
                        child: _buildReviewsSection(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          
          // Loading overlay
          LoadingOverlay(
            message: 'Adding to cart...',
            isVisible: _isAddingToCart,
          ),
        ],
      ),
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
        decoration: BoxDecoration(
          color: Colors.white,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              Colors.grey.shade50,
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                child: imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover, // Changed from cover to contain for consistency
                        filterQuality: FilterQuality.high,
                        fadeInDuration: const Duration(milliseconds: 300),
                        placeholder: (context, url) => Container(
                          color: Colors.white,
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.white,
                          child: const Center(
                            child: Icon(Icons.image_not_supported,
                                size: 64, color: Colors.grey),
                          ),
                        ),
                      )
                    : Container(
                        color: Colors.white,
                        child: const Center(
                          child: Icon(Icons.image_not_supported,
                              size: 64, color: Colors.grey),
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
                  height: 90, // Increased height for better thumbnail visibility
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: product.variations!.length,
                    itemBuilder: (context, index) {
                      final variation = product.variations![index];
                      final isSelected = _selectedVariation?.variationId == variation.variationId;
                      
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
                            color: isSelected ? AppColors.primary.withValues(alpha: 0.1) : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected ? AppColors.primary : Colors.grey.shade300,
                              width: isSelected ? 3 : 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: isSelected 
                                    ? AppColors.primary.withValues(alpha: 0.2)
                                    : Colors.black.withValues(alpha: 0.1),
                                blurRadius: isSelected ? 8 : 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14), // Slightly smaller to account for border
                            child: SizedBox(
                              width: 90,
                              height: 90,
                              child: variation.imageURL != null && variation.imageURL!.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: variation.imageURL!,
                                      fit: BoxFit.cover, // Ensures image fills the entire container
                                      width: 90,
                                      height: 90,
                                      filterQuality: FilterQuality.high,
                                      fadeInDuration: const Duration(milliseconds: 200),
                                      placeholder: (context, url) => Container(
                                        width: 90,
                                        height: 90,
                                        color: Colors.grey.shade100,
                                        child: const Center(
                                          child: SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          ),
                                        ),
                                      ),
                                      errorWidget: (context, url, error) => Container(
                                        width: 90,
                                        height: 90,
                                        color: Colors.grey.shade100,
                                        child: const Center(
                                          child: Icon(
                                            Icons.image_not_supported,
                                            size: 24,
                                            color: Colors.grey,
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
                                      color: Colors.grey.shade100,
                                      child: const Center(
                                        child: Icon(
                                          Icons.image_not_supported,
                                          size: 24,
                                          color: Colors.grey,
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: LoadingButton(
        text: _selectedVariation != null && _selectedVariation!.stock > 0
            ? 'Add to Cart • ₱${(_selectedVariation!.price * _quantity).toStringAsFixed(2)}'
            : 'Out of Stock',
        loadingText: 'Adding to cart...',
        isLoading: _isAddingToCart,
        onPressed: _selectedVariation != null && _selectedVariation!.stock > 0
            ? () => _addToCart(product)
            : null,
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
    final imageUrl = _selectedVariation?.imageURL ?? product.imageURL;
    // Track swipe direction for animation
    Offset _swipeOffset = const Offset(0.2, 0);

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (product.variations == null || product.variations!.isEmpty) return;
        final currentIndex = product.variations!
            .indexWhere((v) => v.variationId == _selectedVariation?.variationId);

        if (details.primaryVelocity != null) {
          // Swipe right (velocity > 0): previous variation
          if (details.primaryVelocity! > 0) {
            if (currentIndex > 0) {
              setState(() {
                _swipeOffset = const Offset(-0.2, 0); // slide in from left
                _selectedVariation = product.variations![currentIndex - 1];
                if (_quantity > _selectedVariation!.stock) {
                  _quantity = _selectedVariation!.stock > 0 ? 1 : 0;
                }
                // Update text controller for web view
                _quantityController.text = _quantity.toString();
              });
            }
          }
          // Swipe left (velocity < 0): next variation
          else if (details.primaryVelocity! < 0) {
            if (currentIndex < product.variations!.length - 1) {
              setState(() {
                _swipeOffset = const Offset(0.2, 0); // slide in from right
                _selectedVariation = product.variations![currentIndex + 1];
                if (_quantity > _selectedVariation!.stock) {
                  _quantity = _selectedVariation!.stock > 0 ? 1 : 0;
                }
                // Update text controller for web view
                _quantityController.text = _quantity.toString();
              });
            }
          }
        }
      },
      onTap: () {
        if (imageUrl.isNotEmpty) {
          _showFullImagePopup(imageUrl);
        }
      },
      child: Container(
        width: double.infinity,
        height: 400,
        decoration: BoxDecoration(
          color: Colors.white,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              Colors.grey.shade50,
            ],
          ),
        ),
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
                  key: ValueKey(imageUrl), // important for detecting image change
                  width: double.infinity,
                  height: double.infinity,
                  child: imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover, // Changed from cover to contain for better aspect ratio
                          filterQuality: FilterQuality.high,
                          fadeInDuration: const Duration(milliseconds: 300),
                          fadeOutDuration: const Duration(milliseconds: 100),
                          placeholder: (context, url) => Container(
                            color: Colors.white,
                            child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: Colors.white,
                            child: const Center(
                              child: Icon(Icons.image_not_supported,
                                  size: 64, color: Colors.grey),
                            ),
                          ),
                          memCacheWidth: 800, // Optimized cache size
                          memCacheHeight: 600,
                        )
                      : Container(
                          color: Colors.white,
                          child: const Center(
                            child: Icon(Icons.image_not_supported,
                                size: 64, color: Colors.grey),
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
                    final isSelected = _selectedVariation?.variationId == entry.value.variationId;
                    final hasImage = entry.value.imageURL != null && entry.value.imageURL!.isNotEmpty;

                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: isSelected ? 32 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary
                            : hasImage 
                                ? Colors.white.withValues(alpha: 0.7)
                                : Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(isSelected ? 6 : 50),
                        border: isSelected ? Border.all(
                          color: Colors.white,
                          width: 1,
                        ) : null,
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }


  Widget _buildProductInfo(Product product) {
    return Container(
      padding: const EdgeInsets.all(24),
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
                    _selectedVariation != null && _selectedVariation!.name.isNotEmpty
                        ? RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: product.name,
                                  style: AppTextStyles.headlineSmall.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.onSurface,
                                  ),
                                ),
                                TextSpan(
                                  text: ' - ',
                                  style: AppTextStyles.headlineSmall.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.onSurface,
                                  ),
                                ),
                                TextSpan(
                                  text: _selectedVariation!.name,
                                  style: AppTextStyles.headlineSmall.copyWith(
                                    color: AppColors.grey400,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Text(
                            product.name,
                            style: AppTextStyles.headlineSmall.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.onSurface,
                            ),
                          ),
                    const SizedBox(height: 8),
                    FutureBuilder<String>(
                      future: _getCategoryName(product.categoryId),
                      builder: (context, snapshot) {
                        final categoryName = snapshot.data ?? 'Loading...';
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.onSurfaceVariant.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            categoryName,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.grey500,
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
                final sellerData = sellerSnapshot.data ?? {
                  'shopName': 'DentPal Store',
                  'address': 'Loading...',
                  'isActive': true,
                };
                
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.store,
                          color: AppColors.onPrimary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sellerData['shopName'] ?? 'Store name not available',
                              style: AppTextStyles.titleLarge.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              sellerData['address'] ?? 'Address not available',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.onSurface.withValues(alpha: 0.7),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          // Visit Store button
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => StorePage(
                                        sellerId: product.sellerId,
                                        sellerData: sellerData,
                                      ),
                                    ),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  child: Text(
                                    'Visit Store',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: AppColors.onPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          
                          const SizedBox(width: 8),
                          
                          // Inquire button
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _inquireAboutProduct(product),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  child: Text(
                                    'Inquire',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: AppColors.onSecondary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.tune,
                  color: AppColors.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Variations',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 70, // Increased height for better visibility
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: product.variations!.length,
              itemBuilder: (context, index) {
                final variation = product.variations![index];
                final isSelected = _selectedVariation?.variationId == variation.variationId;
                
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
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 70, // Increased width for better visibility
                    height: 70,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primary.withValues(alpha: 0.1) : AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? AppColors.primary : AppColors.onSurface.withValues(alpha: 0.2),
                        width: isSelected ? 2 : 1,
                      ),
                      boxShadow: isSelected ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.2),
                          blurRadius: 6,
                          offset: const Offset(0, 1),
                        ),
                      ] : [],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14), // Slightly smaller to account for border
                      child: SizedBox(
                        width: 70,
                        height: 70,
                        child: variation.imageURL != null && variation.imageURL!.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: variation.imageURL!,
                                fit: BoxFit.cover, // Ensures image fills the entire container
                                width: 70,
                                height: 70,
                                filterQuality: FilterQuality.high,
                                fadeInDuration: const Duration(milliseconds: 200),
                                placeholder: (context, url) => Container(
                                  width: 70,
                                  height: 70,
                                  color: AppColors.background,
                                  child: const Center(
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  ),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  width: 70,
                                  height: 70,
                                  color: AppColors.background,
                                  child: const Center(
                                    child: Icon(
                                      Icons.image_not_supported,
                                      size: 20,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                                // Optimized cache size for thumbnails
                                memCacheWidth: 300,
                                memCacheHeight: 300,
                              )
                            : Container(
                                width: 70,
                                height: 70,
                                color: AppColors.background,
                                child: const Center(
                                  child: Icon(
                                    Icons.image_not_supported,
                                    size: 20,
                                    color: Colors.grey,
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
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildQuantityAndStock() {
    if (_selectedVariation == null) return const SizedBox.shrink();

    final screenWidth = MediaQuery.of(context).size.width;
    final isWebView = screenWidth > 1024;

    return Container(
      margin: const EdgeInsets.fromLTRB(24, 4, 24, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.onSurface.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.shopping_bag,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Quantity',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                '${_selectedVariation!.stock} available',
                style: AppTextStyles.bodySmall.copyWith(
                  color: _quantity >= _selectedVariation!.stock 
                      ? Colors.orange 
                      : AppColors.onSurface.withValues(alpha: 0.7),
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
                      color: AppColors.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  Text(
                    '₱${_selectedVariation!.price.toStringAsFixed(2)}',
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                      fontFamily: 'Roboto', // Use Roboto for peso sign support
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Total',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  Text(
                    '₱${(_selectedVariation!.price * _quantity).toStringAsFixed(2)}',
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
    );
  }

  // Mobile quantity selector with buttons
  Widget _buildMobileQuantitySelector() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.remove, color: AppColors.primary),
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
                color: AppColors.primary,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, color: AppColors.primary),
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
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
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
                      ? AppColors.primary 
                      : AppColors.primary.withValues(alpha: 0.3),
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
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
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
                  _quantityController.text = value.replaceFirst(RegExp(r'^0+'), '');
                  _quantityController.selection = TextSelection.fromPosition(
                    TextPosition(offset: _quantityController.text.length),
                  );
                  return;
                }
                final parsedValue = int.tryParse(value);
                if (parsedValue != null && parsedValue > 0) {
                  final clampedValue = parsedValue.clamp(1, _selectedVariation!.stock);
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
                      ? AppColors.primary 
                      : AppColors.primary.withValues(alpha: 0.3),
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
      margin: const EdgeInsets.fromLTRB(24, 4, 24, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.onSurface.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.description,
                  color: AppColors.secondary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Description',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            product.description,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.onSurface.withValues(alpha: 0.8),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewsSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 4, 24, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.onSurface.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.star,
                  color: Colors.amber,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Reviews',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  // TODO: Navigate to reviews page
                },
                child: Text(
                  'See All',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Rating summary
          Row(
            children: [
              Text(
                '4.5',
                style: AppTextStyles.headlineSmall.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: List.generate(5, (index) {
                      return Icon(
                        index < 4 ? Icons.star : Icons.star_half,
                        color: Colors.amber,
                        size: 16,
                      );
                    }),
                  ),
                  Text(
                    '24 reviews',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Sample reviews
          _buildModernReviewItem(
            name: 'John Doe',
            rating: 5,
            date: '2 weeks ago',
            comment: 'Great product! Really satisfied with the quality.',
          ),
          const SizedBox(height: 16),
          _buildModernReviewItem(
            name: 'Jane Smith',
            rating: 4,
            date: '1 month ago',
            comment: 'Good product but shipping took longer than expected.',
          ),
        ],
      ),
    );
  }

  Widget _buildModernReviewItem({
    required String name,
    required int rating,
    required String date,
    required String comment,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    name[0].toUpperCase(),
                    style: AppTextStyles.titleSmall.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                    ),
                    Row(
                      children: [
                        Row(
                          children: List.generate(5, (index) {
                            return Icon(
                              index < rating ? Icons.star : Icons.star_border,
                              color: Colors.amber,
                              size: 14,
                            );
                          }),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          date,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            comment,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.onSurface.withValues(alpha: 0.8),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFixedAddToCartButton(Product product) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
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
          child: LoadingButton(
            text: _selectedVariation != null && _selectedVariation!.stock > 0
                ? 'Add to Cart • ₱${(_selectedVariation!.price * _quantity).toStringAsFixed(2)}'
                : 'Out of Stock',
            loadingText: 'Adding to cart...',
            isLoading: _isAddingToCart,
            onPressed: _selectedVariation != null && _selectedVariation!.stock > 0
                ? () => _addToCart(product)
                : null,
            padding: const EdgeInsets.symmetric(vertical: 14),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              fontFamily: 'Roboto', // Use Roboto for peso sign support
            ),
          ),
        ),
      ),
    );
  }
}
