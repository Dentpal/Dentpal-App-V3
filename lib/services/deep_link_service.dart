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
        //AppLogger.d('App launched with initial link: $initialLink');
        _processDeepLink(initialLink);
      }
    } catch (e) {
      //AppLogger.d('Error handling initial link: $e');
    }
  }

  /// Handle incoming links while app is running
  static void _handleIncomingLinks() {
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (Uri uri) {
        //AppLogger.d('Received deep link: $uri');
        _processDeepLink(uri);
      },
      onError: (err) {
        //AppLogger.d('Deep link error: $err');
      },
    );
  }

  /// Process and route deep links
  static void _processDeepLink(Uri uri) {
    //AppLogger.d('Processing deep link: $uri');
    
    // Check if this is a Firebase auth callback - if so, ignore it and let Firebase handle it
    if (_isFirebaseAuthCallback(uri)) {
      //AppLogger.d('Firebase auth callback detected, ignoring deep link processing');
      return;
    }
    
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
        //AppLogger.d('Extracted product ID: $productId');
        _navigateToProduct(productId);
      } else {
        //AppLogger.d('Could not extract product ID from: $uri');
        // Don't navigate to home for unrecognized links - they might be for other services
        //AppLogger.d('Unrecognized deep link format, ignoring navigation');
      }
    } catch (e) {
      //AppLogger.d('Error processing deep link: $e');
      // Don't navigate on error - the link might be for another service
      //AppLogger.d('Deep link processing error, ignoring navigation');
    }
  }

  /// Check if the deep link is a Firebase auth callback that should be ignored
  static bool _isFirebaseAuthCallback(Uri uri) {
    //AppLogger.d('Checking if Firebase auth callback: ${uri.toString()}');
    
    // Check for Firebase auth callback patterns
    if (uri.scheme.contains('googleusercontent.apps') && uri.host == 'firebaseauth') {
      //AppLogger.d('Detected Google OAuth Firebase auth callback');
      return true;
    }
    
    // Check for Firebase auth domain callbacks
    if (uri.host.contains('firebaseapp.com') && uri.path.contains('/__/auth/callback')) {
      //AppLogger.d('Detected Firebase app domain auth callback');
      return true;
    }
    
    // Check for reCAPTCHA verification callbacks
    if (uri.queryParameters.containsKey('authType') && 
        uri.queryParameters['authType'] == 'verifyApp') {
      //AppLogger.d('Detected reCAPTCHA verification callback');
      return true;
    }
    
    // Check for recaptcha token in query parameters
    if (uri.queryParameters.containsKey('recaptchaToken')) {
      //AppLogger.d('Detected recaptcha token in query parameters');
      return true;
    }
    
    // Check for deep_link_id parameter which contains Firebase auth info
    if (uri.queryParameters.containsKey('deep_link_id')) {
      final deepLinkId = uri.queryParameters['deep_link_id'];
      if (deepLinkId != null && (deepLinkId.contains('firebaseapp.com') || 
          deepLinkId.contains('authType=verifyApp') || 
          deepLinkId.contains('recaptchaToken'))) {
        //AppLogger.d('Detected Firebase auth callback in deep_link_id parameter');
        return true;
      }
    }
    
    //AppLogger.d('Not a Firebase auth callback');
    return false;
  }

  /// Navigate to product detail page
  static void _navigateToProduct(String productId) {
    if (_navigatorKey?.currentState != null) {
      //AppLogger.d('Navigating to product: $productId');
      _navigatorKey!.currentState!.pushNamed('/product/$productId');
    } else {
      //AppLogger.d('Navigator not available for product navigation');
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