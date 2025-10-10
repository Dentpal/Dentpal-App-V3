import 'package:flutter/material.dart';
import 'pages/product_listing_page.dart';
import 'pages/product_detail_page.dart';
import 'pages/cart_page.dart';
import 'pages/add_product_page.dart';
import 'pages/payment_success_page.dart';
import 'pages/payment_failed_page.dart';

// Export all the classes needed for the app
export 'pages/product_listing_page.dart';
export 'pages/product_detail_page.dart';
export 'pages/cart_page.dart';
export 'pages/add_product_page.dart';
export 'pages/paymongo_webview_page.dart';
export 'pages/payment_success_page.dart';
export 'pages/payment_failed_page.dart';
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
      // Payment success/failed routes are handled in generateRoute() to support query parameters
    };
  }
  
    // Method to handle dynamic routes like product details page
  static Route<dynamic>? generateRoute(RouteSettings settings) {
    final uri = Uri.tryParse(settings.name ?? '');
    if (uri == null) return null;

    // Parse product ID from route path like '/product/123'
    if (settings.name?.startsWith('/product/') ?? false) {
      final productId = settings.name!.split('/')[2];
      return MaterialPageRoute(
        settings: settings,
        builder: (context) => ProductDetailPage(productId: productId),
      );
    }
    
    // Handle payment success page with query parameters
    if (uri.path == '/payment-success') {
      final sessionId = uri.queryParameters['session_id'];
      final orderId = uri.queryParameters['order_id'];
      return MaterialPageRoute(
        settings: settings,
        builder: (context) => PaymentSuccessPage(
          sessionId: sessionId,
          orderId: orderId,
        ),
      );
    }
    
    // Handle payment failed page with query parameters
    if (uri.path == '/payment-failed') {
      final sessionId = uri.queryParameters['session_id'];
      final orderId = uri.queryParameters['order_id'];
      final errorMessage = uri.queryParameters['error'];
      return MaterialPageRoute(
        settings: settings,
        builder: (context) => PaymentFailedPage(
          sessionId: sessionId,
          orderId: orderId,
          errorMessage: errorMessage,
        ),
      );
    }
    
    return null;
  }
}
