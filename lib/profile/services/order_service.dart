import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../product/models/order_model.dart' as order_model;
import '../../utils/app_logger.dart';

class OrderService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Fetch all orders for the current user (using direct Firestore for better performance)
  static Future<List<order_model.Order>> fetchUserOrders() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    try {
      //AppLogger.d('Fetching user orders via Firestore');
      
      // Query without orderBy to avoid composite index requirement
      final querySnapshot = await _firestore
          .collection('Order')
          .where('userId', isEqualTo: user.uid)
          .get();

      final orders = querySnapshot.docs
          .map((doc) => order_model.Order.fromFirestore(doc))
          .toList();

      // Sort in memory by createdAt (descending - newest first)
      orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      //AppLogger.d('Fetched ${orders.length} orders from Firestore');
      return orders;
    } catch (e) {
      //AppLogger.d('Error fetching user orders: $e');
      throw Exception('Failed to fetch orders: $e');
    }
  }

  /// Get order statistics for the current user (calculated from Firestore data)
  static Future<Map<String, dynamic>> getOrderStatistics() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    try {
      //AppLogger.d(' Calculating order statistics from Firestore');
      
      final querySnapshot = await _firestore
          .collection('Order')
          .where('userId', isEqualTo: user.uid)
          .get();

      final orders = querySnapshot.docs
          .map((doc) => order_model.Order.fromFirestore(doc))
          .toList();

      // Calculate statistics
      final totalOrders = orders.length;
      final totalSpent = orders.fold(0.0, (sum, order) => sum + order.summary.total);
      
      final deliveredOrders = orders.where((order) => 
        order.status == order_model.OrderStatus.delivered).length;
      
      final pendingOrders = orders.where((order) => 
        order.status == order_model.OrderStatus.pending).length;
      
      final cancelledOrders = orders.where((order) => 
        order.status == order_model.OrderStatus.cancelled).length;

      final statistics = {
        'totalOrders': totalOrders,
        'totalSpent': totalSpent,
        'deliveredOrders': deliveredOrders,
        'pendingOrders': pendingOrders,
        'cancelledOrders': cancelledOrders,
        'expiredOrders': orders.where((order) => 
          order.status == order_model.OrderStatus.expired).length,
      };

      //AppLogger.d('Calculated order statistics: $statistics');
      return statistics;
    } catch (e) {
      //AppLogger.d('Error calculating order statistics: $e');
      // Return default statistics on error
      return {
        'totalOrders': 0,
        'totalSpent': 0.0,
        'deliveredOrders': 0,
        'pendingOrders': 0,
        'cancelledOrders': 0,
        'expiredOrders': 0,
      };
    }
  }

  /// Get orders stream for real-time updates (using Firestore directly)
  static Stream<List<order_model.Order>> getUserOrdersStream() {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    //AppLogger.d('Starting real-time orders stream for user: ${user.uid}');

    return _firestore
        .collection('Order')
        .where('userId', isEqualTo: user.uid)
        .snapshots()
        .map((snapshot) {
          final orders = snapshot.docs
              .map((doc) => order_model.Order.fromFirestore(doc))
              .toList();
          
          // Sort in memory by createdAt (descending - newest first)
          orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          
          //AppLogger.d('Stream update: ${orders.length} orders');
          return orders;
        });
  }

  /// Search orders by query (product name, order ID, etc.) using Firestore
  static Future<List<order_model.Order>> searchOrders(String query) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    try {
      //AppLogger.d('Searching orders with query: $query');
      
      // Get all user orders first, then filter locally
      // This is more efficient for small datasets and avoids complex Firestore queries
      final querySnapshot = await _firestore
          .collection('Order')
          .where('userId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .get();

      final allOrders = querySnapshot.docs
          .map((doc) => order_model.Order.fromFirestore(doc))
          .toList();

      // Filter locally by order ID or product names
      final searchQuery = query.toLowerCase();
      final filteredOrders = allOrders.where((order) {
        // Search in order ID
        if (order.orderId.toLowerCase().contains(searchQuery)) {
          return true;
        }
        
        // Search in product names
        return order.items.any((item) => 
          item.productName.toLowerCase().contains(searchQuery));
      }).toList();

      //AppLogger.d('Found ${filteredOrders.length} orders matching query: $query');
      return filteredOrders;
    } catch (e) {
      //AppLogger.d('Error searching orders: $e');
      throw Exception('Failed to search orders: $e');
    }
  }

  /// Cancel order (for customers)
  static Future<void> cancelOrder(String orderId, {String? reason}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    try {
      //AppLogger.d('Cancelling order: $orderId');
      
      final idToken = await user.getIdToken();

      final response = await http.post(
        Uri.parse('https://asia-southeast1-dentpal-161e5.cloudfunctions.net/cancelOrder'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: json.encode({
          'orderId': orderId,
          'reason': reason,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to cancel order: ${response.body}');
      }

      final responseData = json.decode(response.body) as Map<String, dynamic>;
      
      if (responseData['success'] != true) {
        throw Exception(responseData['error'] ?? 'Failed to cancel order');
      }

      //AppLogger.d('Order cancelled successfully');
    } catch (e) {
      //AppLogger.d('Error cancelling order: $e');
      throw Exception('Failed to cancel order: $e');
    }
  }

  /// Get orders by status (using direct Firestore)
  static Future<List<order_model.Order>> fetchOrdersByStatus(order_model.OrderStatus status) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    try {
      //AppLogger.d('Fetching orders by status: ${status.toString().split('.').last}');
      
      final statusString = status.toString().split('.').last;
      final querySnapshot = await _firestore
          .collection('Order')
          .where('userId', isEqualTo: user.uid)
          .where('status', isEqualTo: statusString)
          .get();

      final orders = querySnapshot.docs
          .map((doc) => order_model.Order.fromFirestore(doc))
          .toList();

      // Sort in memory by createdAt (descending - newest first)
      orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      //AppLogger.d('Fetched ${orders.length} orders with status: $statusString');
      return orders;
    } catch (e) {
      //AppLogger.d('Error fetching orders by status: $e');
      throw Exception('Failed to fetch orders by status: $e');
    }
  }
}
