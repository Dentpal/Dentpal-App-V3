
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dentpal/product/products_module.dart';
import 'package:dentpal/product/pages/edit_product_page.dart';
import 'package:dentpal/profile/pages/seller_listings_page.dart';
import 'package:dentpal/auth_wrapper.dart';
import 'package:dentpal/home_page.dart';
import 'package:dentpal/login_page.dart';
import 'package:dentpal/core/app_theme/app_theme.dart';
import 'package:dentpal/services/deep_link_service.dart';
import 'firebase_options.dart';
import 'package:dentpal/utils/web_utils.dart';
import 'package:dentpal/utils/app_logger.dart';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Check if Firebase is already initialized
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    if (e.toString().contains('duplicate-app')) {
      // Firebase is already initialized, which is fine
      AppLogger.d('Firebase already initialized');
    } else {
      // Re-throw other errors
      rethrow;
    }
  }

  // Set Firestore cache size to 100MB
  FirebaseFirestore.instance.settings = Settings(
    persistenceEnabled: true,
    cacheSizeBytes: 100 * 1024 * 1024, // 100 MB
  );
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // Global navigator key for deep link navigation
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    // Initialize deep link service
    DeepLinkService.initialize(navigatorKey);
    
    return MaterialApp(
      title: 'DentPal',
      theme: AppTheme.lightTheme,
      navigatorKey: navigatorKey,
      initialRoute: _getInitialRoute(),
      routes: {
        '/': (context) => const HomePage(),
        '/login': (context) => const LoginPage(),
        '/auth': (context) => const AuthWrapper(),
        '/payment-success': (context) => const PaymentSuccessPage(),
        '/payment-failed': (context) => const PaymentFailedPage(),
        '/products': (context) => const ProductListingPage(),
        '/cart': (context) => const CartPage(),
        '/add-product': (context) => const AddProductPage(),
        '/seller-listings': (context) => const SellerListingsPage(),
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
        
        // Handle edit product route
        if (settings.name == '/edit-product') {
          final args = settings.arguments as Map<String, dynamic>?;
          if (args != null && args['productId'] != null) {
            return MaterialPageRoute(
              settings: settings,
              builder: (context) => FutureBuilder<Product?>(
                future: _getProductForEdit(args['productId']),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }
                  
                  if (snapshot.hasData && snapshot.data != null) {
                    return EditProductPage(product: snapshot.data!);
                  }
                  
                  return const Scaffold(
                    body: Center(
                      child: Text('Product not found'),
                    ),
                  );
                },
              ),
            );
          }
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
  
  // Helper method to get product for editing
  Future<Product?> _getProductForEdit(String productId) async {
    final productService = ProductService();
    return await productService.getProductById(productId);
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
