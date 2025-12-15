import 'package:cloud_functions/cloud_functions.dart';
import 'package:dentpal/utils/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import '../models/cart_model.dart';

class JRSShippingService {
  static const String _region = 'asia-southeast1';
  static FirebaseFunctions? _functions;
  
  /// Default fallback shipping cost when JRS API is unavailable (₱250)
  /// This should match the backend fallback value in jrsShippingHelper.ts
  static const double defaultFallbackShippingCost = 250.0;

  // Get Firebase Functions instance with proper platform configuration
  static FirebaseFunctions get functions {
    if (_functions == null) {
      _functions = FirebaseFunctions.instanceFor(region: _region);
      
      // Configure for platform compatibility
      if (kIsWeb) {
        AppLogger.d('[JRS] Configuring Firebase Functions for web');
        // For web, functions should work out of the box
      } else {
        AppLogger.d('[JRS] Configuring Firebase Functions for mobile');
        // For mobile, ensure proper configuration
        // Check if we need to use emulator or specific settings
      }
      
      AppLogger.d('[JRS] Firebase Functions instance created for region: $_region');
    }
    return _functions!;
  }

  /// Calculate shipping cost using JRS Express API via Firebase Functions
  /// 
  /// [sellerAddress] - Seller's address in "City, Province" format
  /// [recipientAddress] - Recipient's address in "City, Province" format  
  /// [cartItems] - List of cart items to ship
  /// [express] - Whether to use express shipping (default: true)
  /// [insurance] - Whether to include insurance (default: true)
  /// [valuation] - Whether to include valuation (default: true)
  static Future<JRSShippingResult> calculateShippingCost({
    required String sellerAddress,
    required String recipientAddress,
    required List<CartItem> cartItems,
    bool express = true,
    bool insurance = true,
    bool valuation = true,
  }) async {
    try {
      AppLogger.d('Calculating JRS shipping cost');
      AppLogger.d('   From: $sellerAddress');
      AppLogger.d('   To: $recipientAddress');
      AppLogger.d('   Items: ${cartItems.length}');
      
      // Add console logs for production debugging
      AppLogger.d('[JRS] Starting calculation: $sellerAddress → $recipientAddress (${cartItems.length} items)');
      if (kDebugMode) AppLogger.d('[JRS] Debug mode detected');
      if (!kDebugMode) AppLogger.d('[JRS] Production mode detected');

      // Prepare the cart items data for the Firebase function
      final cartItemsData = cartItems.map((item) => item.toJRSShippingItem()).toList();

      // Prepare the request data
      final requestData = {
        'sellerAddress': sellerAddress,
        'recipientAddress': recipientAddress,
        'cartItems': cartItemsData,
        'express': express,
        'insurance': insurance,
        'valuation': valuation,
      };

      AppLogger.d('JRS request data: $requestData');

      // Call the Firebase function with platform-specific implementation
      AppLogger.d('[JRS] About to call Firebase function: calculateJRSShipping');
      
      late final dynamic result;
      
      if (kIsWeb) {
        // Use HTTP directly for web to avoid dart2js Int64 issues
        AppLogger.d('[JRS] Using HTTP call for web compatibility');
        try {
          final httpResult = await _callFirebaseFunctionViaHTTP(requestData);
          result = _MockCallableResult(httpResult);
        } catch (e) {
          AppLogger.d('[JRS] Web HTTP call failed: $e');
          // Fallback to cloud_functions for web if HTTP fails
          AppLogger.d('[JRS] Falling back to cloud_functions for web');
          final callable = functions.httpsCallable('calculateJRSShipping');
          result = await callable.call(requestData).timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception('Firebase function call timed out');
            },
          );
        }
      } else {
        // Use cloud_functions package for mobile
        AppLogger.d('[JRS] Using cloud_functions package for mobile');
        try {
          final callable = functions.httpsCallable('calculateJRSShipping');
          
          // Add debug info about Firebase setup
          AppLogger.d('[JRS] Firebase Functions region: $_region');
          AppLogger.d('[JRS] Calling function with data keys: ${requestData.keys.toList()}');
          
          result = await callable.call(requestData).timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception('Firebase function call timed out after 30 seconds');
            },
          );
          AppLogger.d('[JRS] Mobile cloud_functions call succeeded');
        } catch (e) {
          AppLogger.d('[JRS] Mobile cloud_functions call failed: $e');
          
          // Check if it's an authentication or permission issue
          if (e.toString().contains('UNAUTHENTICATED') || e.toString().contains('PERMISSION_DENIED')) {
            AppLogger.d('[JRS] Authentication/permission issue detected on mobile');
            AppLogger.d('JRS mobile auth issue: $e');
          } else if (e.toString().contains('UNAVAILABLE') || e.toString().contains('NETWORK')) {
            AppLogger.d('[JRS] Network issue detected on mobile');
            AppLogger.d('JRS mobile network issue: $e');
          } else {
            AppLogger.d('[JRS] Unknown mobile error: $e');
            AppLogger.d('JRS mobile unknown error: $e');
          }
          
          // For mobile, we can also try the HTTP fallback if cloud_functions fails
          AppLogger.d('[JRS] Trying HTTP fallback for mobile');
          try {
            final httpResult = await _callFirebaseFunctionViaHTTP(requestData);
            result = _MockCallableResult(httpResult);
            AppLogger.d('[JRS] Mobile HTTP fallback succeeded');
          } catch (httpError) {
            AppLogger.d('[JRS] Mobile HTTP fallback also failed: $httpError');
            rethrow; // Re-throw the original error
          }
        }
      }
      
      AppLogger.d('[JRS] Firebase function call completed');

      AppLogger.d('JRS function response: ${result.data}');
      AppLogger.d('[JRS] Response received: ${result.data}');

      // Parse the response with safe type conversion for mobile compatibility
      final rawData = result.data;
      Map<String, dynamic> data;
      
      if (rawData is Map<String, dynamic>) {
        data = rawData;
      } else if (rawData is Map) {
        // Convert Map<Object?, Object?> to Map<String, dynamic> for mobile compatibility
        data = Map<String, dynamic>.from(rawData.map((key, value) => MapEntry(key.toString(), value)));
      } else {
        throw Exception('Unexpected response type: ${rawData.runtimeType}');
      }
      
      if (data['success'] == true) {
        final responseDataRaw = data['data'];
        Map<String, dynamic>? responseData;
        
        if (responseDataRaw is Map<String, dynamic>) {
          responseData = responseDataRaw;
        } else if (responseDataRaw is Map) {
          responseData = Map<String, dynamic>.from(responseDataRaw.map((key, value) => MapEntry(key.toString(), value)));
        }
        
        final shippingCost = (responseData?['shippingCost'] as num?)?.toDouble() ?? 50.0;
        final buyerShippingCharge = (responseData?['buyerShippingCharge'] as num?)?.toDouble() ?? shippingCost;
        final sellerShippingCharge = (responseData?['sellerShippingCharge'] as num?)?.toDouble() ?? 0.0;
        final shippingSplitRule = (responseData?['shippingSplitRule'] as String?) ?? 'buyer_pays_full';
        
        AppLogger.d('JRS shipping cost calculated: ₱$shippingCost (buyer pays: ₱$buyerShippingCharge, rule: $shippingSplitRule)');
        AppLogger.d('[JRS] SUCCESS: ₱$shippingCost (buyer: ₱$buyerShippingCharge, seller: ₱$sellerShippingCharge, rule: $shippingSplitRule)');
        
        return JRSShippingResult(
          success: true,
          shippingCost: shippingCost,
          buyerShippingCharge: buyerShippingCharge,
          sellerShippingCharge: sellerShippingCharge,
          shippingSplitRule: shippingSplitRule,
          message: 'Shipping cost calculated successfully',
        );
      } else {
        final error = data['error'] as String? ?? 'Unknown error';
        final fallbackDataRaw = data['data'];
        Map<String, dynamic>? fallbackData;
        
        if (fallbackDataRaw is Map<String, dynamic>) {
          fallbackData = fallbackDataRaw;
        } else if (fallbackDataRaw is Map) {
          fallbackData = Map<String, dynamic>.from(fallbackDataRaw.map((key, value) => MapEntry(key.toString(), value)));
        }
        
        final fallbackCost = (fallbackData?['shippingCost'] as num?)?.toDouble() ?? defaultFallbackShippingCost;
        final fallbackBuyerCharge = (fallbackData?['buyerShippingCharge'] as num?)?.toDouble() ?? fallbackCost;
        
        AppLogger.d('JRS API error, using fallback: $error');
        AppLogger.d('[JRS] API ERROR: $error (using fallback: ₱$fallbackCost)');
        
        return JRSShippingResult(
          success: false,
          shippingCost: fallbackCost,
          buyerShippingCharge: fallbackBuyerCharge,
          message: 'JRS API issue, using fallback shipping cost',
          error: error,
        );
      }

    } catch (e) {
      AppLogger.d('Error calculating JRS shipping: $e');
      AppLogger.d('[JRS] ERROR: $e');
      
      // Return fallback shipping cost to prevent checkout from breaking
      return JRSShippingResult(
        success: false,
        shippingCost: defaultFallbackShippingCost,
        buyerShippingCharge: defaultFallbackShippingCost,
        message: 'Error calculating shipping cost, using fallback',
        error: e.toString(),
      );
    }
  }

  /// Call Firebase function directly via HTTP for cross-platform compatibility
  static Future<dynamic> _callFirebaseFunctionViaHTTP(Map<String, dynamic> data) async {
    try {
      final url = 'https://asia-southeast1-dentpal-161e5.cloudfunctions.net/calculateJRSShipping';
      
      AppLogger.d('[JRS] Making HTTP call to: $url');
      
      // Get Firebase Auth token
      String? authToken;
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          authToken = await user.getIdToken();
          AppLogger.d('[JRS] Got auth token for HTTP call');
        } else {
          AppLogger.d('[JRS] No authenticated user found');
        }
      } catch (e) {
        AppLogger.d('[JRS] Error getting auth token: $e');
      }
      
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        // Add CORS headers for better compatibility
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      };
      
      // Add auth token if available
      if (authToken != null) {
        headers['Authorization'] = 'Bearer $authToken';
        AppLogger.d('[JRS] Added Authorization header to HTTP request');
      }
      
      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: json.encode({'data': data}),
      ).timeout(const Duration(seconds: 30));

      AppLogger.d('[JRS] HTTP response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        AppLogger.d('[JRS] HTTP response data: $responseData');
        return responseData['result'] ?? responseData;
      } else {
        AppLogger.d('[JRS] HTTP error: ${response.statusCode} - ${response.body}');
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      AppLogger.d('[JRS] HTTP call failed: $e');
      rethrow;
    }
  }

  /// Test Firebase Functions connectivity specifically for debugging mobile issues
  static Future<Map<String, dynamic>> testFirebaseFunctionsConnectivity() async {
    final result = <String, dynamic>{
      'platform': kIsWeb ? 'web' : 'mobile',
      'region': _region,
      'timestamp': DateTime.now().toIso8601String(),
    };

    try {
      AppLogger.d('[JRS] Testing Firebase Functions connectivity...');
      
      // Test basic callable creation
      final callable = functions.httpsCallable('calculateJRSShipping');
      result['callable_creation'] = 'success';
      
      // Test simple call with minimal data
      final testData = {
        'sellerAddress': 'Makati, Metro Manila',
        'recipientAddress': 'Quezon City, Metro Manila',
        'cartItems': [
          {
            'productId': 'test',
            'quantity': 1,
            'price': 100.0,
          }
        ],
      };
      
      AppLogger.d('[JRS] Making test call...');
      final response = await callable.call(testData).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('Test call timed out');
        },
      );
      
      result['test_call'] = 'success';
      result['response_type'] = response.runtimeType.toString();
      result['has_data'] = response.data != null;
      
      if (response.data != null) {
        final data = response.data as Map<String, dynamic>;
        result['response_keys'] = data.keys.toList();
        result['response_success'] = data['success'];
      }
      
      AppLogger.d('[JRS] Firebase Functions connectivity test passed');
      
    } catch (e) {
      AppLogger.d('[JRS] Firebase Functions connectivity test failed: $e');
      result['error'] = e.toString();
      result['error_type'] = e.runtimeType.toString();
    }
    
    return result;
  }

  /// Format address to JRS-compatible format (City, Province)
  static String formatAddressForJRS(String? city, String? state) {
    if (city == null || city.isEmpty) {
      return 'Makati, Metro Manila'; // Default fallback
    }
    
    if (state == null || state.isEmpty) {
      return '$city, Metro Manila'; // Default to Metro Manila if no state
    }
    
    return '$city, $state';
  }

  /// Extract city and province from shipping address
  static String formatShippingAddressForJRS(String fullAddress) {
    try {
      // Split the address by commas and take relevant parts
      final parts = fullAddress.split(',').map((part) => part.trim()).toList();
      
      if (parts.length >= 2) {
        // Try to find city and state/province
        // Usually address format is: Street, City, State/Province, Postal, Country
        String city = '';
        String state = '';
        
        // Look for city (usually after street address)
        for (int i = 0; i < parts.length; i++) {
          final part = parts[i];
          
          // Skip obvious street addresses (contains numbers)
          if (RegExp(r'\d').hasMatch(part) && i == 0) {
            continue;
          }
          
          // First non-street part is likely the city
          if (city.isEmpty && !RegExp(r'^\d+$').hasMatch(part)) {
            city = part;
            continue;
          }
          
          // Next part is likely the state/province
          if (city.isNotEmpty && state.isEmpty && !RegExp(r'^\d+$').hasMatch(part)) {
            state = part;
            break;
          }
        }
        
        if (city.isNotEmpty) {
          return formatAddressForJRS(city, state.isNotEmpty ? state : null);
        }
      }
      
      // Fallback: try to extract meaningful parts
      if (parts.isNotEmpty) {
        final lastPart = parts.last;
        if (lastPart.toLowerCase().contains('manila') || 
            lastPart.toLowerCase().contains('metro manila')) {
          // If last part contains Manila, use the second to last as city
          if (parts.length >= 2) {
            return formatAddressForJRS(parts[parts.length - 2], 'Metro Manila');
          }
        }
      }
      
    } catch (e) {
      AppLogger.d('Error parsing address for JRS: $e');
    }
    
    // Final fallback
    return 'Makati, Metro Manila';
  }
}

/// Result class for JRS shipping calculation
class JRSShippingResult {
  final bool success;
  final double shippingCost;
  final double buyerShippingCharge; // What buyer actually pays after split
  final double sellerShippingCharge; // What seller pays after split
  final String shippingSplitRule; // 'buyer_pays_full' or 'split_50_50'
  final String message;
  final String? error;

  JRSShippingResult({
    required this.success,
    required this.shippingCost,
    this.buyerShippingCharge = 0.0,
    this.sellerShippingCharge = 0.0,
    this.shippingSplitRule = 'buyer_pays_full',
    required this.message,
    this.error,
  });

  @override
  String toString() {
    return 'JRSShippingResult(success: $success, cost: ₱$shippingCost, buyerPays: ₱$buyerShippingCharge, rule: $shippingSplitRule, message: $message${error != null ? ', error: $error' : ''})';
  }
}

/// Mock callable result for web HTTP calls
class _MockCallableResult {
  final dynamic data;
  
  _MockCallableResult(this.data);
}
