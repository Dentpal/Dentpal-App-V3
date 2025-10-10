import 'package:flutter/material.dart';
import 'package:dentpal/utils/web_utils.dart';
import 'package:dentpal/services/deep_link_service.dart';

/// Navigation utilities for handling deep linking and URL management
class NavigationUtils {
  /// Navigate to product detail page with proper URL updating for web
  static void navigateToProductDetail(BuildContext context, String productId) {
    // Update URL for web deep linking
    updateUrl('/product/$productId');
    
    // Navigate using named route to ensure proper routing
    Navigator.pushNamed(context, '/product/$productId');
  }
  
  /// Navigate to product detail page and replace current route with proper URL updating
  static void navigateToProductDetailReplacement(BuildContext context, String productId) {
    // Update URL for web deep linking
    updateUrl('/product/$productId');
    
    // Navigate using pushReplacement with named route
    Navigator.pushReplacementNamed(context, '/product/$productId');
  }
  
  /// Navigate to product detail page and remove all previous routes
  static void navigateToProductDetailAndClearStack(BuildContext context, String productId) {
    // Update URL for web deep linking
    updateUrl('/product/$productId');
    
    // Navigate and clear stack
    Navigator.pushNamedAndRemoveUntil(
      context, 
      '/product/$productId', 
      (route) => false,
    );
  }
  
  /// Get shareable URL for a product
  static String getProductShareUrl(String productId) {
    // Generate the universal deep link that works for both web and native app
    return DeepLinkService.generateProductLink(productId);
  }
  
  /// Generate full shareable URL with domain (for social media sharing)
  static String getFullProductShareUrl(String productId, {String? baseUrl}) {
    // Use the deep link service to generate proper links
    return DeepLinkService.generateProductLink(productId, customDomain: baseUrl);
  }
  
  /// Generate custom scheme link for native app sharing
  static String getCustomSchemeUrl(String productId) {
    return DeepLinkService.generateCustomSchemeLink(productId);
  }
  
  /// Update URL for current page (for web deep linking)
  static void updatePageUrl(String path) {
    updateUrl(path); // Call the web_utils updateUrl function
  }
}
