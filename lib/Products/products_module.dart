import 'package:flutter/material.dart';
import 'pages/product_listing_page.dart';
import 'pages/product_detail_page.dart';
import 'pages/cart_page.dart';
import 'pages/add_product_page.dart';

// Export all the classes needed for the app
export 'pages/product_listing_page.dart';
export 'pages/product_detail_page.dart';
export 'pages/cart_page.dart';
export 'pages/add_product_page.dart';
export 'models/product_model.dart';
export 'models/cart_model.dart';
export 'models/product_form_model.dart';
export 'services/product_service.dart';
export 'services/cart_service.dart';
export 'services/category_service.dart';

class ProductsModule {
  // Method to register routes for all product-related pages
  static Map<String, WidgetBuilder> getRoutes() {
    return {
      '/products': (context) => const ProductListingPage(),
      '/cart': (context) => const CartPage(),
      '/add-product': (context) => const AddProductPage(),
    };
  }
  
  // Method to handle dynamic routes like product details page
  static Route<dynamic>? generateRoute(RouteSettings settings) {
    // Parse product ID from route path like '/product/123'
    if (settings.name?.startsWith('/product/') ?? false) {
      final productId = settings.name!.split('/')[2];
      return MaterialPageRoute(
        settings: settings,
        builder: (context) => ProductDetailPage(productId: productId),
      );
    }
    
    return null;
  }
}
