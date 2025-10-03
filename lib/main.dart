
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dentpal/Products/products_module.dart';
import 'package:dentpal/Products/pages/product_listing_page.dart';
import 'package:dentpal/Products/pages/product_detail_page.dart';
import 'package:dentpal/Products/pages/cart_page.dart';
import 'package:dentpal/Products/pages/add_product_page.dart';
import 'package:dentpal/Products/pages/payment_success_page.dart';
import 'package:dentpal/Products/pages/payment_failed_page.dart';
import 'package:dentpal/auth_wrapper.dart';
import 'package:dentpal/core/app_theme/app_theme.dart';
import 'firebase_options.dart';
import 'package:dentpal/utils/web_utils.dart';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Set Firestore cache size to 100MB
  FirebaseFirestore.instance.settings = Settings(
    persistenceEnabled: true,
    cacheSizeBytes: 100 * 1024 * 1024, // 100 MB
  );
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DentPal',
      theme: AppTheme.lightTheme,
      initialRoute: _getInitialRoute(),
      routes: {
        '/': (context) => const AuthWrapper(),
        '/payment-success': (context) => const PaymentSuccessPage(),
        '/payment-failed': (context) => const PaymentFailedPage(),
        '/products': (context) => const ProductListingPage(),
        '/cart': (context) => const CartPage(),
        '/add-product': (context) => const AddProductPage(),
      },
      onGenerateRoute: (settings) {
        // Handle dynamic product routes
        if (settings.name?.startsWith('/product/') ?? false) {
          final productId = settings.name!.split('/')[2];
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ProductDetailPage(productId: productId),
          );
        }
        
        // Default to AuthWrapper for unknown routes
        return MaterialPageRoute(
          settings: settings,
          builder: (context) => const AuthWrapper(),
        );
      },
      debugShowCheckedModeBanner: false,
    );
  }
  
  String _getInitialRoute() {
    if (kIsWeb) {
      final currentPath = getCurrentPath();
      // If we're on a payment route, return it directly
      if (currentPath == '/payment-success' || currentPath == '/payment-failed') {
        return currentPath;
      }
      // For other routes, check if they're valid
      final validRoutes = ['/products', '/cart', '/add-product'];
      if (validRoutes.contains(currentPath)) {
        return currentPath;
      }
      // For product detail routes
      if (currentPath.startsWith('/product/')) {
        return currentPath;
      }
    }
    // Default to home route
    return '/';
  }
}
