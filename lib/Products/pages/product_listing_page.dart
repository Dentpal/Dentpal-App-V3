import 'package:flutter/material.dart';
import '../models/product_model.dart';
import '../services/product_service.dart';
import 'product_detail_page.dart';

class ProductListingPage extends StatefulWidget {
  const ProductListingPage({Key? key}) : super(key: key);

  @override
  _ProductListingPageState createState() => _ProductListingPageState();
}

class _ProductListingPageState extends State<ProductListingPage> {
  final ProductService _productService = ProductService();
  late Future<List<Product>> _productsFuture;
  bool _isLoading = false;
  String _selectedCategory = 'All';
  List<String> _categories = ['All'];
  String? _errorMessage;
  
  bool _isSeller = false;

  @override
  void initState() {
    super.initState();
    _productsFuture = _loadProducts();
    _checkSellerStatus();
  }
  
  Future<void> _checkSellerStatus() async {
    final result = await _productService.checkSellerStatus();
    setState(() {
      _isSeller = result['isSeller'];
    });
  }
  
  Future<List<Product>> _loadProducts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      print('🔄 ProductListingPage: Loading products...');
      
      final products = await _productService.getProducts();
      
      print('📋 ProductListingPage: Received ${products.length} products from service');
      
      // Extract all unique categories
      Set<String> categorySet = {'All'};
      for (var product in products) {
        if (product.category.isNotEmpty) {
          categorySet.add(product.category);
        }
      }
      
      _categories = categorySet.toList();
      
      setState(() {
        _isLoading = false;
      });
      
      return products;
    } catch (e) {
      print('❌ Error in _loadProducts: $e');
      print('Stack trace: ${StackTrace.current}');
      
      setState(() {
        _isLoading = false;
        // Store error message to display in UI
        _errorMessage = e.toString();
      });
      return [];
    }
  }
  
  List<Product> _filterProducts(List<Product> products) {
    if (_selectedCategory == 'All') {
      return products;
    }
    return products.where((product) => product.category == _selectedCategory).toList();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _productsFuture = _loadProducts();
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Refreshing products...')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // TODO: Implement search functionality
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Search not implemented yet')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.shopping_cart),
            onPressed: () {
              Navigator.pushNamed(context, '/cart');
            },
          ),
        ],
      ),
      floatingActionButton: _isSeller ? FloatingActionButton(
        onPressed: () {
          Navigator.pushNamed(context, '/add-product');
        },
        child: const Icon(Icons.add),
        tooltip: 'Add New Product',
      ) : null,
      body: Column(
        children: [
          // Categories filter
          SafeArea(
            child: Container(
              height: 50,
              margin: const EdgeInsets.only(top: 8.0),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                itemBuilder: (context, index) {
                  final category = _categories[index];
                  final isSelected = category == _selectedCategory;
                  
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: FilterChip(
                      label: Text(
                        category,
                        style: TextStyle(
                          fontSize: 14, // Slightly smaller font to avoid overflow
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          _selectedCategory = category;
                        });
                      },
                      labelPadding: const EdgeInsets.symmetric(horizontal: 8.0),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  );
                },
              ),
            ),
          ),
          
          // Product grid
          Expanded(
            child: FutureBuilder<List<Product>>(
              future: _productsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting || _isLoading) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        Text(
                          'Error loading products',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            '${snapshot.error}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 14),
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                } else if (_errorMessage != null) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        const Text(
                          'Error loading products',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 14),
                            maxLines: 5, // Limit lines to prevent extreme overflow
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _errorMessage = null;
                              _productsFuture = _loadProducts();
                            });
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.search_off, size: 48, color: Colors.grey),
                        const SizedBox(height: 16),
                        const Text(
                          'No products found',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        const Text('There are no products to display at this time.'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _productsFuture = _loadProducts();
                            });
                          },
                          child: const Text('Refresh'),
                        ),
                      ],
                    ),
                  );
                }
                
                final filteredProducts = _filterProducts(snapshot.data!);
                
                if (filteredProducts.isEmpty) {
                  return Center(
                    child: Text('No products found in $_selectedCategory category'),
                  );
                }
                
                return RefreshIndicator(
                  onRefresh: () async {
                    setState(() {
                      _productsFuture = _loadProducts();
                    });
                  },
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Calculate proper child aspect ratio and columns based on available width
                      final width = constraints.maxWidth;
                      
                      // Determine number of columns based on screen width
                      int crossAxisCount = 2; // Default for phones
                      if (width > 600) {
                        crossAxisCount = 3; // Tablets
                      }
                      if (width > 900) {
                        crossAxisCount = 4; // Large tablets/desktops
                      }
                      
                      final itemWidth = (width - (16 * (crossAxisCount + 1))) / crossAxisCount;
                      // Use fixed height calculation for more consistent cards
                      // 120px for image + 80px for text area (padding, title, price)
                      final itemHeight = 200.0;
                      final aspectRatio = itemWidth / itemHeight;
                      
                      return GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          childAspectRatio: aspectRatio,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 20, // Increased spacing between rows
                          mainAxisExtent: 200, // Fixed height for each card, matching SizedBox height
                        ),
                        itemCount: filteredProducts.length,
                        itemBuilder: (context, index) {
                          final product = filteredProducts[index];
                          return _buildProductCard(product);
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildProductCard(Product product) {
    // Get price from first variation or null if no variations
    double? price;
    String? imageUrl = product.imageURL;
    
    if (product.variations != null && product.variations!.isNotEmpty) {
      price = product.variations![0].price;
      if (product.variations![0].imageURL != null && 
          product.variations![0].imageURL!.isNotEmpty) {
        imageUrl = product.variations![0].imageURL;
      }
    }
    
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProductDetailPage(productId: product.productId),
          ),
        );
      },
      child: SizedBox(
        height: 200, // Fixed height for entire card
        child: Card(
          elevation: 3,
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product Image
              SizedBox(
                height: 120,
                width: double.infinity,
                child: imageUrl != null && imageUrl.isNotEmpty
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.grey[200],
                            child: const Center(child: Icon(Icons.image_not_supported)),
                          );
                        },
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: CircularProgressIndicator(
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded / 
                                      loadingProgress.expectedTotalBytes!
                                  : null,
                            ),
                          );
                        },
                      )
                    : Container(
                        color: Colors.grey[200],
                        child: const Center(child: Icon(Icons.image_not_supported)),
                      ),
              ),
              
              // Product Details
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Product Name
                      Text(
                        product.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    
                      // Price at the bottom
                      if (price != null)
                        Text(
                          '₱${price.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: Theme.of(context).primaryColor,
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                        )
                      else
                        Text(
                          'Price unavailable',
                          style: TextStyle(color: Colors.grey[600], fontSize: 14),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
