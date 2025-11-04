import 'package:cloud_functions/cloud_functions.dart';
import 'package:dentpal/utils/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/cart_model.dart';

class JRSShippingService {
  static const String _region = 'asia-southeast1';
  static FirebaseFunctions? _functions;

  // Get Firebase Functions instance with web compatibility
  static FirebaseFunctions get functions {
    if (_functions == null) {
      _functions = FirebaseFunctions.instanceFor(region: _region);
      
      // Configure for web compatibility
      if (kIsWeb) {
        // Use the emulator URL for web or configure CORS properly
        // This helps avoid dart2js Int64 issues
        print('🌐 [JRS] Configuring for web compatibility');
      }
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
      AppLogger.d('🚚 Calculating JRS shipping cost');
      AppLogger.d('   From: $sellerAddress');
      AppLogger.d('   To: $recipientAddress');
      AppLogger.d('   Items: ${cartItems.length}');
      
      // Add console logs for production debugging
      print('🚚 [JRS] Starting calculation: $sellerAddress → $recipientAddress (${cartItems.length} items)');
      if (kDebugMode) print('🔧 [JRS] Debug mode detected');
      if (!kDebugMode) print('🏭 [JRS] Production mode detected');

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

      AppLogger.d('🔧 JRS request data: $requestData');

      // Call the Firebase function with web compatibility
      print('🔥 [JRS] About to call Firebase function: calculateJRSShipping');
      
      late final dynamic result;
      
      if (kIsWeb) {
        // Use HTTP directly for web to avoid dart2js Int64 issues
        print('🌐 [JRS] Using HTTP call for web compatibility');
        final httpResult = await _callFirebaseFunctionViaHTTP(requestData);
        result = _MockCallableResult(httpResult);
      } else {
        // Use cloud_functions package for mobile
        final callable = functions.httpsCallable('calculateJRSShipping');
        result = await callable.call(requestData).timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw Exception('Firebase function call timed out');
          },
        );
      }
      
      print('🔥 [JRS] Firebase function call completed');

      AppLogger.d('📦 JRS function response: ${result.data}');
      print('📦 [JRS] Response received: ${result.data}');

      // Parse the response
      final data = result.data as Map<String, dynamic>;
      
      if (data['success'] == true) {
        final responseData = data['data'] as Map<String, dynamic>?;
        final shippingCost = (responseData?['shippingCost'] as num?)?.toDouble() ?? 50.0;
        
        AppLogger.d('✅ JRS shipping cost calculated: ₱$shippingCost');
        print('✅ [JRS] SUCCESS: ₱$shippingCost');
        
        return JRSShippingResult(
          success: true,
          shippingCost: shippingCost,
          message: 'Shipping cost calculated successfully',
        );
      } else {
        final error = data['error'] as String? ?? 'Unknown error';
        final fallbackCost = (data['data']?['shippingCost'] as num?)?.toDouble() ?? 50.0;
        
        AppLogger.d('⚠️ JRS API error, using fallback: $error');
        
        return JRSShippingResult(
          success: false,
          shippingCost: fallbackCost,
          message: 'Using fallback shipping cost: $error',
          error: error,
        );
      }

    } catch (e) {
      AppLogger.d('❌ Error calculating JRS shipping: $e');
      print('❌ [JRS] ERROR: $e');
      
      // Return fallback shipping cost to prevent checkout from breaking
      return JRSShippingResult(
        success: false,
        shippingCost: 50.0,
        message: 'Error calculating shipping cost, using fallback',
        error: e.toString(),
      );
    }
  }

  /// Test JRS API connection
  static Future<JRSConnectionTestResult> testConnection() async {
    try {
      AppLogger.d('🔍 Testing JRS API connection');

      final callable = functions.httpsCallable('testJRSConnection');
      final result = await callable.call();

      final data = result.data as Map<String, dynamic>;
      
      return JRSConnectionTestResult(
        success: data['success'] == true,
        message: data['message'] as String? ?? 'Unknown result',
        data: data['data'],
      );

    } catch (e) {
      AppLogger.d('❌ Error testing JRS connection: $e');
      
      return JRSConnectionTestResult(
        success: false,
        message: 'Connection test failed: $e',
      );
    }
  }

  /// Call Firebase function directly via HTTP for web compatibility
  static Future<dynamic> _callFirebaseFunctionViaHTTP(Map<String, dynamic> data) async {
    try {
      final url = 'https://asia-southeast1-dentpal-161e5.cloudfunctions.net/calculateJRSShipping';
      
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({'data': data}),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        return responseData['result'] ?? responseData;
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('❌ [JRS] HTTP call failed: $e');
      rethrow;
    }
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
      AppLogger.d('❌ Error parsing address for JRS: $e');
    }
    
    // Final fallback
    return 'Makati, Metro Manila';
  }
}

/// Result class for JRS shipping calculation
class JRSShippingResult {
  final bool success;
  final double shippingCost;
  final String message;
  final String? error;

  JRSShippingResult({
    required this.success,
    required this.shippingCost,
    required this.message,
    this.error,
  });

  @override
  String toString() {
    return 'JRSShippingResult(success: $success, cost: ₱$shippingCost, message: $message${error != null ? ', error: $error' : ''})';
  }
}

/// Result class for JRS connection test
class JRSConnectionTestResult {
  final bool success;
  final String message;
  final Map<String, dynamic>? data;

  JRSConnectionTestResult({
    required this.success,
    required this.message,
    this.data,
  });

  @override
  String toString() {
    return 'JRSConnectionTestResult(success: $success, message: $message)';
  }
}

/// Mock callable result for web HTTP calls
class _MockCallableResult {
  final dynamic data;
  
  _MockCallableResult(this.data);
}
