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
        AppLogger.d('App launched with initial link: $initialLink');
        _processDeepLink(initialLink);
      }
    } catch (e) {
      AppLogger.d('Error handling initial link: $e');
    }
  }

  /// Handle incoming links while app is running
  static void _handleIncomingLinks() {
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (Uri uri) {
        AppLogger.d('Received deep link: $uri');
        _processDeepLink(uri);
      },
      onError: (err) {
        AppLogger.d('Deep link error: $err');
      },
    );
  }

  /// Process and route deep links
  static void _processDeepLink(Uri uri) {
    AppLogger.d('Processing deep link: $uri');

    // Check if this is a Firebase auth callback - if so, ignore it and let Firebase handle it
    if (_isFirebaseAuthCallback(uri)) {
      AppLogger.d(
        'Firebase auth callback detected, ignoring deep link processing',
      );
      return;
    }

    try {
      String? productId;
      String? sellerId;
      bool isResetPassword = false;
      bool isPrivacyPolicy = false;
      bool isTermsOfService = false;
      String? oobCode; // Firebase out-of-band code for password reset

      // Handle different URL formats:
      // https://dentpal-store.web.app/#/product/ABC123
      // https://dentpal-store.web.app/#/store/XYZ789
      // https://dentpal-store-sandbox-testing.web.app/#/product/ABC123
      // https://dentpal-store-sandbox-testing.web.app/#/store/XYZ789
      // https://dentpal-store.web.app/#/reset-password?oobCode=XXX
      // https://dentpal-store.web.app/#/privacy-policy
      // https://dentpal-store.web.app/#/terms-of-service
      // dentpal://product/ABC123
      // dentpal://store/XYZ789
      // dentpal://reset-password?oobCode=XXX
      // dentpal://privacy-policy
      // dentpal://terms-of-service

      if (uri.scheme == 'https' || uri.scheme == 'http') {
        // Support both production and sandbox domains
        final supportedHosts = [
          'dentpal-store.web.app',
          'dentpal-store-sandbox-testing.web.app',
          'dentpal.shop'
        ];

        if (supportedHosts.contains(uri.host)) {
          // Web URL format with fragment: https://domain/#/reset-password or https://domain/#/product/ABC123 or https://domain/#/store/XYZ789
          if (uri.fragment.isNotEmpty) {
            final fragment = uri.fragment;
            // Parse fragment for reset-password
            if (fragment.startsWith('/reset-password')) {
              isResetPassword = true;
              // Extract oobCode from fragment query params if present
              // Fragment format: /reset-password?oobCode=XXX
              final fragmentUri = Uri.parse('https://temp.com$fragment');
              oobCode = fragmentUri.queryParameters['oobCode'];
            } else if (fragment == '/privacy-policy' || fragment.startsWith('/privacy-policy')) {
              isPrivacyPolicy = true;
            } else if (fragment == '/terms-of-service' || fragment.startsWith('/terms-of-service')) {
              isTermsOfService = true;
            } else if (fragment.startsWith('/product/')) {
              productId = fragment.substring('/product/'.length);
            } else if (fragment.startsWith('/store/')) {
              sellerId = fragment.substring('/store/'.length);
            }
          }
          // Alternative path format: https://domain/reset-password or https://domain/product/ABC123 or https://domain/store/XYZ789
          else if (uri.path.startsWith('/reset-password')) {
            isResetPassword = true;
            oobCode = uri.queryParameters['oobCode'];
          } else if (uri.path == '/privacy-policy' || uri.path.startsWith('/privacy-policy')) {
            isPrivacyPolicy = true;
          } else if (uri.path == '/terms-of-service' || uri.path.startsWith('/terms-of-service')) {
            isTermsOfService = true;
          } else if (uri.path.startsWith('/product/')) {
            productId = uri.path.substring('/product/'.length);
          } else if (uri.path.startsWith('/store/')) {
            sellerId = uri.path.substring('/store/'.length);
          }
        }
      } else if (uri.scheme == 'dentpal') {
        // Custom scheme format: dentpal://reset-password?oobCode=XXX or dentpal://product/ABC123 or dentpal://store/XYZ789
        if (uri.host == 'reset-password') {
          isResetPassword = true;
          oobCode = uri.queryParameters['oobCode'];
        } else if (uri.path == '/reset-password' ||
            uri.path.startsWith('/reset-password')) {
          isResetPassword = true;
          oobCode = uri.queryParameters['oobCode'];
        } else if (uri.host == 'privacy-policy' || uri.path == '/privacy-policy') {
          isPrivacyPolicy = true;
        } else if (uri.host == 'terms-of-service' || uri.path == '/terms-of-service') {
          isTermsOfService = true;
        } else if (uri.host == 'product' && uri.pathSegments.isNotEmpty) {
          productId = uri.pathSegments.first;
        } else if (uri.path.startsWith('/product/')) {
          productId = uri.path.substring('/product/'.length);
        } else if (uri.host == 'store' && uri.pathSegments.isNotEmpty) {
          sellerId = uri.pathSegments.first;
        } else if (uri.path.startsWith('/store/')) {
          sellerId = uri.path.substring('/store/'.length);
        }
      }

      // Handle reset password navigation
      if (isResetPassword) {
        AppLogger.d(
          'Reset password deep link detected, oobCode: ${oobCode != null ? "present" : "not present"}',
        );
        _navigateToResetPassword(oobCode);
        return;
      }

      // Handle privacy policy navigation
      if (isPrivacyPolicy) {
        AppLogger.d('Privacy policy deep link detected');
        _navigateToPrivacyPolicy();
        return;
      }

      // Handle terms of service navigation
      if (isTermsOfService) {
        AppLogger.d('Terms of service deep link detected');
        _navigateToTermsOfService();
        return;
      }

      if (productId != null && productId.isNotEmpty) {
        AppLogger.d('Extracted product ID: $productId');
        _navigateToProduct(productId);
      } else if (sellerId != null && sellerId.isNotEmpty) {
        AppLogger.d('Extracted seller ID: $sellerId');
        _navigateToStore(sellerId);
      } else {
        AppLogger.d('Could not extract product ID or seller ID from: $uri');
        // Don't navigate to home for unrecognized links - they might be for other services
        AppLogger.d('Unrecognized deep link format, ignoring navigation');
      }
    } catch (e) {
      AppLogger.d('Error processing deep link: $e');
      // Don't navigate on error - the link might be for another service
      AppLogger.d('Deep link processing error, ignoring navigation');
    }
  }

  /// Check if the deep link is a Firebase auth callback that should be ignored
  static bool _isFirebaseAuthCallback(Uri uri) {
    AppLogger.d('Checking if Firebase auth callback: ${uri.toString()}');

    // Check for Firebase auth callback patterns
    if (uri.scheme.contains('googleusercontent.apps') &&
        uri.host == 'firebaseauth') {
      AppLogger.d('Detected Google OAuth Firebase auth callback');
      return true;
    }

    // Check for Firebase auth domain callbacks
    if (uri.host.contains('firebaseapp.com') &&
        uri.path.contains('/__/auth/callback')) {
      AppLogger.d('Detected Firebase app domain auth callback');
      return true;
    }

    // Check for reCAPTCHA verification callbacks
    if (uri.queryParameters.containsKey('authType') &&
        uri.queryParameters['authType'] == 'verifyApp') {
      AppLogger.d('Detected reCAPTCHA verification callback');
      return true;
    }

    // Check for recaptcha token in query parameters
    if (uri.queryParameters.containsKey('recaptchaToken')) {
      AppLogger.d('Detected recaptcha token in query parameters');
      return true;
    }

    // Check for deep_link_id parameter which contains Firebase auth info
    if (uri.queryParameters.containsKey('deep_link_id')) {
      final deepLinkId = uri.queryParameters['deep_link_id'];
      if (deepLinkId != null &&
          (deepLinkId.contains('firebaseapp.com') ||
              deepLinkId.contains('authType=verifyApp') ||
              deepLinkId.contains('recaptchaToken'))) {
        AppLogger.d(
          'Detected Firebase auth callback in deep_link_id parameter',
        );
        return true;
      }
    }

    AppLogger.d('Not a Firebase auth callback');
    return false;
  }

  /// Navigate to product detail page
  static void _navigateToProduct(String productId) {
    if (_navigatorKey?.currentState != null) {
      AppLogger.d('Navigating to product: $productId');
      _navigatorKey!.currentState!.pushNamed('/product/$productId');
    } else {
      AppLogger.d('Navigator not available for product navigation');
    }
  }

  /// Navigate to store page
  static void _navigateToStore(String sellerId) {
    if (_navigatorKey?.currentState != null) {
      AppLogger.d('Navigating to store: $sellerId');
      _navigatorKey!.currentState!.pushNamed('/store/$sellerId');
    } else {
      AppLogger.d('Navigator not available for store navigation');
    }
  }

  /// Navigate to reset password page
  /// For web: navigates to ChangePasswordStandalonePage
  /// For mobile: navigates to ResetPasswordPage with oobCode
  static void _navigateToResetPassword(String? oobCode) {
    if (_navigatorKey?.currentState != null) {
      AppLogger.d('Navigating to reset password page');
      _navigatorKey!.currentState!.pushNamed(
        '/reset-password',
        arguments: {'oobCode': oobCode},
      );
    } else {
      AppLogger.d('Navigator not available for reset password navigation');
    }
  }

  /// Navigate to privacy policy page
  static void _navigateToPrivacyPolicy() {
    if (_navigatorKey?.currentState != null) {
      AppLogger.d('Navigating to privacy policy page');
      _navigatorKey!.currentState!.pushNamed('/privacy-policy');
    } else {
      AppLogger.d('Navigator not available for privacy policy navigation');
    }
  }

  /// Navigate to terms of service page
  static void _navigateToTermsOfService() {
    if (_navigatorKey?.currentState != null) {
      AppLogger.d('Navigating to terms of service page');
      _navigatorKey!.currentState!.pushNamed('/terms-of-service');
    } else {
      AppLogger.d('Navigator not available for terms of service navigation');
    }
  }

  /// Clean up resources
  static void dispose() {
    _linkSubscription?.cancel();
    _linkSubscription = null;
  }

  /// Generate shareable deep link for a product
  static String generateProductLink(
    String productId, {
    String? customDomain,
    bool useSandbox = false,
  }) {
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
  
  /// Generate shareable deep link for a store
  static String generateStoreLink(
    String sellerId, {
    String? customDomain,
    bool useSandbox = false,
  }) {
    String domain;
    if (customDomain != null) {
      domain = customDomain;
    } else if (useSandbox) {
      domain = 'https://dentpal-store-sandbox-testing.web.app';
    } else {
      domain = 'https://dentpal-store.web.app';
    }
    return '$domain/#/store/$sellerId';
  }
  
  /// Generate custom scheme link for a store (for native app sharing)
  static String generateStoreCustomSchemeLink(String sellerId) {
    return 'dentpal://store/$sellerId';
  }

  /// Generate shareable deep link for reset password
  static String generateResetPasswordLink({
    String? customDomain,
    bool useSandbox = false,
    String? oobCode,
  }) {
    String domain;
    if (customDomain != null) {
      domain = customDomain;
    } else if (useSandbox) {
      domain = 'https://dentpal-store-sandbox-testing.web.app';
    } else {
      domain = 'https://dentpal-store.web.app';
    }
    final queryString = oobCode != null ? '?oobCode=$oobCode' : '';
    return '$domain/#/reset-password$queryString';
  }

  /// Generate custom scheme link for reset password (for native app)
  static String generateResetPasswordCustomSchemeLink({String? oobCode}) {
    final queryString = oobCode != null ? '?oobCode=$oobCode' : '';
    return 'dentpal://reset-password$queryString';
  }

  /// Generate shareable deep link for privacy policy
  static String generatePrivacyPolicyLink({
    String? customDomain,
    bool useSandbox = false,
  }) {
    String domain;
    if (customDomain != null) {
      domain = customDomain;
    } else if (useSandbox) {
      domain = 'https://dentpal-store-sandbox-testing.web.app';
    } else {
      domain = 'https://dentpal-store.web.app';
    }
    return '$domain/#/privacy-policy';
  }

  /// Generate custom scheme link for privacy policy (for native app)
  static String generatePrivacyPolicyCustomSchemeLink() {
    return 'dentpal://privacy-policy';
  }

  /// Generate shareable deep link for terms of service
  static String generateTermsOfServiceLink({
    String? customDomain,
    bool useSandbox = false,
  }) {
    String domain;
    if (customDomain != null) {
      domain = customDomain;
    } else if (useSandbox) {
      domain = 'https://dentpal-store-sandbox-testing.web.app';
    } else {
      domain = 'https://dentpal-store.web.app';
    }
    return '$domain/#/terms-of-service';
  }

  /// Generate custom scheme link for terms of service (for native app)
  static String generateTermsOfServiceCustomSchemeLink() {
    return 'dentpal://terms-of-service';
  }
}
