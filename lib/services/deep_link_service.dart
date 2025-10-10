import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:dentpal/utils/app_logger.dart';

/// Service to handle incoming deep links from other apps, browsers, or shares
class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  static final AppLinks _appLinks = AppLinks();
  static StreamSubscription<Uri>? _linkSubscription;
  static GlobalKey<NavigatorState>? _navigatorKey;

  /// Initialize deep link handling
  static void initialize(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
    _initDeepLinks();
  }

  /// Set up deep link listeners
  static void _initDeepLinks() {
    // Handle app launch from deep link (when app is closed)
    _handleInitialLink();
    
    // Handle incoming deep links (when app is running)
    _handleIncomingLinks();
  }

  /// Handle the initial link when app is launched from a deep link
  static void _handleInitialLink() async {
    try {
      final Uri? initialLink = await _appLinks.getInitialLink();
      if (initialLink != null) {
        AppLogger.d('🔗 App launched with initial link: $initialLink');
        _processDeepLink(initialLink);
      }
    } catch (e) {
      AppLogger.d('❌ Error handling initial link: $e');
    }
  }

  /// Handle incoming links while app is running
  static void _handleIncomingLinks() {
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (Uri uri) {
        AppLogger.d('🔗 Received deep link: $uri');
        _processDeepLink(uri);
      },
      onError: (err) {
        AppLogger.d('❌ Deep link error: $err');
      },
    );
  }

  /// Process and route deep links
  static void _processDeepLink(Uri uri) {
    AppLogger.d('🔍 Processing deep link: $uri');
    
    try {
      String? productId;
      
      // Handle different URL formats:
      // https://dentpal-store.web.app/#/product/ABC123
      // https://dentpal-store-sandbox-testing.web.app/#/product/ABC123
      // dentpal://product/ABC123
      
      if (uri.scheme == 'https' || uri.scheme == 'http') {
        // Support both production and sandbox domains
        final supportedHosts = [
          'dentpal-store.web.app',
          'www.dentpal-store.web.app',
          'dentpal-store-sandbox-testing.web.app'
        ];
        
        if (supportedHosts.contains(uri.host)) {
          // Web URL format: https://domain/#/product/ABC123
          if (uri.fragment.isNotEmpty) {
            final fragment = uri.fragment;
            if (fragment.startsWith('/product/')) {
              productId = fragment.substring('/product/'.length);
            }
          }
          // Alternative path format: https://domain/product/ABC123
          else if (uri.path.startsWith('/product/')) {
            productId = uri.path.substring('/product/'.length);
          }
        }
      } else if (uri.scheme == 'dentpal') {
        // Custom scheme format: dentpal://product/ABC123
        if (uri.host == 'product' && uri.pathSegments.isNotEmpty) {
          productId = uri.pathSegments.first;
        } else if (uri.path.startsWith('/product/')) {
          productId = uri.path.substring('/product/'.length);
        }
      }

      if (productId != null && productId.isNotEmpty) {
        AppLogger.d('✅ Extracted product ID: $productId');
        _navigateToProduct(productId);
      } else {
        AppLogger.d('⚠️ Could not extract product ID from: $uri');
        _navigateToHome();
      }
    } catch (e) {
      AppLogger.d('❌ Error processing deep link: $e');
      _navigateToHome();
    }
  }

  /// Navigate to product detail page
  static void _navigateToProduct(String productId) {
    if (_navigatorKey?.currentState != null) {
      AppLogger.d('🚀 Navigating to product: $productId');
      _navigatorKey!.currentState!.pushNamed('/product/$productId');
    } else {
      AppLogger.d('❌ Navigator not available for product navigation');
    }
  }

  /// Navigate to home page as fallback
  static void _navigateToHome() {
    if (_navigatorKey?.currentState != null) {
      AppLogger.d('🏠 Navigating to home page');
      _navigatorKey!.currentState!.pushNamedAndRemoveUntil('/', (route) => false);
    } else {
      AppLogger.d('❌ Navigator not available for home navigation');
    }
  }

  /// Clean up resources
  static void dispose() {
    _linkSubscription?.cancel();
    _linkSubscription = null;
  }

  /// Generate shareable deep link for a product
  static String generateProductLink(String productId, {String? customDomain, bool useSandbox = false}) {
    String domain;
    if (customDomain != null) {
      domain = customDomain;
    } else if (useSandbox) {
      domain = 'https://dentpal-store-sandbox-testing.web.app';
    } else {
      domain = 'https://dentpal-store.web.app';
    }
    return '$domain/#/product/$productId';
  }

  /// Generate custom scheme link for a product (for native app sharing)
  static String generateCustomSchemeLink(String productId) {
    return 'dentpal://product/$productId';
  }
}
