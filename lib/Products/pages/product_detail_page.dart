import 'package:flutter/material.dart';
import '../models/product_model.dart';
import '../services/product_service.dart';
import '../services/cart_service.dart';
import '../widgets/loading_overlay.dart';
import '../utils/cart_feedback.dart';
import 'cart_page.dart';

class ProductDetailPage extends StatefulWidget {
  final String productId;

  const ProductDetailPage({Key? key, required this.productId}) : super(key: key);

  @override
  _ProductDetailPageState createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  final ProductService _productService = ProductService();
  final CartService _cartService = CartService();
  
  late Future<Product?> _productFuture;
  int _quantity = 1;
  ProductVariation? _selectedVariation;
  bool _isAddingToCart = false;
  DateTime? _lastAddToCartTime;
  
  @override
  void initState() {
    super.initState();
    _productFuture = _loadProduct();
  }
  
  Future<Product?> _loadProduct() async {
    try {
      final product = await _productService.getProductById(widget.productId);
      
      // Select the first variation by default if available
      if (product != null && 
          product.variations != null && 
          product.variations!.isNotEmpty) {
        _selectedVariation = product.variations![0];
      }
      
      return product;
    } catch (e) {
      print('Error loading product: $e');
      return null;
    }
  }
  
  void _addToCart(Product product) async {
    // Prevent multiple simultaneous requests
    if (_isAddingToCart) return;
    
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
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_cart),
            onPressed: () {
              Navigator.pushNamed(context, '/cart');
            },
          ),
        ],
      ),
      body: FutureBuilder<Product?>(
        future: _productFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data == null) {
            return const Center(child: Text('Product not found'));
          }
          
          final product = snapshot.data!;
          return _buildProductDetail(product);
        },
      ),
    );
  }
  
  Widget _buildProductDetail(Product product) {
    return Stack(
      children: [
        // Product details
        SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product image
              AspectRatio(
                aspectRatio: 1,
                child: _selectedVariation?.imageURL != null && _selectedVariation!.imageURL!.isNotEmpty
                  ? Image.network(
                      _selectedVariation!.imageURL!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return _buildImageFallback(product);
                      },
                    )
                  : _buildImageFallback(product),
              ),
              
              // Product info
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name and price
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            product.name,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (_selectedVariation != null)
                          Text(
                            '₱${_selectedVariation!.price.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                      ],
                    ),
                    
                    const SizedBox(height: 8),
                    
                    // Category
                    Text(
                      'Category: ${product.category}',
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Description
                    const Text(
                      'Description',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      product.description,
                      style: const TextStyle(fontSize: 16),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Variations
                    if (product.variations != null && product.variations!.isNotEmpty) ...[
                      const Text(
                        'Variations',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildVariationsSection(product.variations!),
                      const SizedBox(height: 16),
                    ],
                    
                    // Quantity selector
                    Row(
                      children: [
                        const Text(
                          'Quantity:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 16),
                        _buildQuantitySelector(),
                      ],
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Stock info
                    if (_selectedVariation != null)
                      Text(
                        'In Stock: ${_selectedVariation!.stock}',
                        style: TextStyle(
                          color: _selectedVariation!.stock > 0 ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    
                    const SizedBox(height: 24),
                    
                    // Reviews section (dummy for now)
                    const Text(
                      'Reviews',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildDummyReviews(),
                    
                    // Add bottom padding for the add to cart button
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        // Add to cart button (fixed at bottom)
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            height: 80,
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
            child: LoadingButton(
              text: 'Add to Cart',
              loadingText: 'Adding...',
              isLoading: _isAddingToCart,
              onPressed: _selectedVariation != null && _selectedVariation!.stock > 0
                  ? () => _addToCart(product)
                  : null,
              padding: const EdgeInsets.symmetric(vertical: 12),
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
  
  Widget _buildImageFallback(Product product) {
    if (product.imageURL.isNotEmpty) {
      return Image.network(
        product.imageURL,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: Colors.grey[200],
            child: const Center(child: Icon(Icons.image_not_supported, size: 50)),
          );
        },
      );
    }
    
    return Container(
      color: Colors.grey[200],
      child: const Center(child: Icon(Icons.image_not_supported, size: 50)),
    );
  }
  
  Widget _buildVariationsSection(List<ProductVariation> variations) {
    return SizedBox(
      height: 80,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: variations.length,
        itemBuilder: (context, index) {
          final variation = variations[index];
          final isSelected = _selectedVariation?.variationId == variation.variationId;
          
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedVariation = variation;
              });
            },
            child: Container(
              width: 80,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isSelected ? Theme.of(context).primaryColor : Colors.grey,
                  width: isSelected ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (variation.imageURL != null && variation.imageURL!.isNotEmpty)
                    Expanded(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                        child: Image.network(
                          variation.imageURL!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => const Icon(Icons.image_not_supported),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Text(
                      '₱${variation.price.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
  
  Widget _buildQuantitySelector() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          // Decrease button
          IconButton(
            icon: const Icon(Icons.remove),
            onPressed: _quantity > 1
                ? () {
                    setState(() {
                      _quantity--;
                    });
                  }
                : null,
            iconSize: 16,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
          ),
          
          // Quantity display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              _quantity.toString(),
              style: const TextStyle(fontSize: 16),
            ),
          ),
          
          // Increase button
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _selectedVariation != null && _quantity < _selectedVariation!.stock
                ? () {
                    setState(() {
                      _quantity++;
                    });
                  }
                : null,
            iconSize: 16,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDummyReviews() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Overall rating
        Row(
          children: [
            const Text('4.5', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Row(
              children: List.generate(5, (index) {
                return Icon(
                  index < 4 ? Icons.star : Icons.star_half,
                  color: Colors.amber,
                  size: 20,
                );
              }),
            ),
            const SizedBox(width: 8),
            Text('(24 reviews)', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
        const SizedBox(height: 16),
        
        // Sample reviews
        _buildReviewItem(
          name: 'John Doe',
          rating: 5,
          date: '2 weeks ago',
          comment: 'Great product! Really satisfied with the quality.',
        ),
        const Divider(),
        _buildReviewItem(
          name: 'Jane Smith',
          rating: 4,
          date: '1 month ago',
          comment: 'Good product but shipping took longer than expected.',
        ),
        const Divider(),
        _buildReviewItem(
          name: 'Mike Johnson',
          rating: 5,
          date: '2 months ago',
          comment: 'Exactly as described. Would definitely buy again!',
        ),
      ],
    );
  }
  
  Widget _buildReviewItem({
    required String name,
    required int rating,
    required String date,
    required String comment,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              date,
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: List.generate(5, (index) {
            return Icon(
              index < rating ? Icons.star : Icons.star_border,
              color: Colors.amber,
              size: 16,
            );
          }),
        ),
        const SizedBox(height: 8),
        Text(comment),
        const SizedBox(height: 8),
      ],
    );
  }
}
