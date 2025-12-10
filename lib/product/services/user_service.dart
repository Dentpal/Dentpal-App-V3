import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dentpal/utils/app_logger.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Cache for user role to avoid repeated Firestore calls
  static bool? _cachedIsSeller;
  static bool? _cachedIsCustomerSupport;
  static String? _cachedUserId;

  // Get current user data
  Future<Map<String, dynamic>?> getCurrentUserData() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      final userData = await _firestore.collection('User').doc(user.uid).get();
      if (userData.exists) {
        return userData.data();
      }
      return null;
    } catch (e) {
      AppLogger.d('Error fetching user data: $e');
      return null;
    }
  }

  // Check if current user is a seller
  // A seller can have:
  // 1. Only a Seller collection document, OR
  // 2. Both User collection (with role='seller') AND Seller collection document
  Future<bool> isCurrentUserSeller({bool forceRefresh = false}) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        _cachedIsSeller = null;
        _cachedUserId = null;
        return false;
      }

      // Return cached value if available and user hasn't changed
      if (!forceRefresh &&
          _cachedIsSeller != null &&
          _cachedUserId == user.uid) {
        AppLogger.d(
          'Returning cached seller status: $_cachedIsSeller for user ${user.uid}',
        );
        return _cachedIsSeller!;
      }

      AppLogger.d('Checking seller status for user: ${user.uid}');

      // First, check if Seller document exists (primary check)
      // This handles sellers who may only have a Seller document
      final sellerDoc = await _firestore
          .collection('Seller')
          .doc(user.uid)
          .get();

      if (sellerDoc.exists) {
        final sellerData = sellerDoc.data() as Map<String, dynamic>;
        final isActive = sellerData['isActive'] as bool? ?? true;

        if (isActive) {
          _cachedIsSeller = true;
          _cachedUserId = user.uid;
          AppLogger.d(
            'User ${user.uid} is a verified seller (found in Seller collection)',
          );
          return true;
        } else {
          AppLogger.d('User ${user.uid} has inactive seller account');
          _cachedIsSeller = false;
          _cachedUserId = user.uid;
          return false;
        }
      }

      // Secondary check: User collection with role='seller'
      // This handles edge cases where User doc exists with seller role
      final userDoc = await _firestore.collection('User').doc(user.uid).get();

      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final userRole = userData['role'] as String?;

        if (userRole == 'seller') {
          // User has seller role but no Seller document
          // This might be an incomplete registration, but we should still show seller UI
          _cachedIsSeller = true;
          _cachedUserId = user.uid;
          AppLogger.d('User ${user.uid} has seller role in User collection');
          return true;
        }
      }

      _cachedIsSeller = false;
      _cachedUserId = user.uid;
      AppLogger.d(
        'User ${user.uid} is a buyer (not found in Seller collection, no seller role)',
      );
      return false;
    } catch (e) {
      AppLogger.d('Error checking seller status: $e');
      return false;
    }
  }

  // Check if a specific user ID is a seller
  Future<bool> isUserSeller(String userId) async {
    try {
      // First, check if the user exists in the Seller collection
      // A seller may only have a Seller document OR both User and Seller documents
      final sellerDoc = await _firestore.collection('Seller').doc(userId).get();

      if (sellerDoc.exists) {
        final sellerData = sellerDoc.data() as Map<String, dynamic>;
        final isActive = sellerData['isActive'] as bool? ?? true;
        if (!isActive) {
          AppLogger.d('User $userId has inactive seller account');
          return false;
        }
        AppLogger.d('User $userId found in Seller collection - is a seller');
        return true;
      }

      // Fallback: Check User collection for role='seller'
      final userDoc = await _firestore.collection('User').doc(userId).get();

      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final userRole = userData['role'] as String?;
        if (userRole == 'seller') {
          AppLogger.d('User $userId has role=seller in User collection');
          return true;
        }
      }

      return false;
    } catch (e) {
      AppLogger.d('Error checking seller status for $userId: $e');
      return false;
    }
  }

  // Get seller data for a user ID
  Future<Map<String, dynamic>?> getSellerData(String userId) async {
    try {
      final sellerDoc = await _firestore.collection('Seller').doc(userId).get();
      if (sellerDoc.exists) {
        return sellerDoc.data();
      }
      return null;
    } catch (e) {
      AppLogger.d('Error fetching seller data for $userId: $e');
      return null;
    }
  }

  // Get user's role
  Future<String> getUserRole() async {
    try {
      final userData = await getCurrentUserData();
      if (userData != null && userData['role'] != null) {
        return userData['role'] as String;
      }
      return 'buyer'; // Default role
    } catch (e) {
      AppLogger.d('Error getting user role: $e');
      return 'buyer';
    }
  }

  // Check if current user is a Customer Support Representative
  Future<bool> isCurrentUserCustomerSupport({bool forceRefresh = false}) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        _cachedIsCustomerSupport = null;
        AppLogger.d('isCurrentUserCustomerSupport: No user logged in');
        return false;
      }

      // Return cached value if available and user hasn't changed
      if (!forceRefresh &&
          _cachedIsCustomerSupport != null &&
          _cachedUserId == user.uid) {
        AppLogger.d(
          'Returning cached customer support status: $_cachedIsCustomerSupport for user ${user.uid}',
        );
        return _cachedIsCustomerSupport!;
      }

      AppLogger.d('Checking customer support status for user: ${user.uid} (forceRefresh: $forceRefresh)');

      // Check User collection for role='customer_support'
      final userDoc = await _firestore.collection('User').doc(user.uid).get();
      AppLogger.d('User document exists: ${userDoc.exists}');

      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final userRole = userData['role'] as String?;
        AppLogger.d('User role from Firestore: $userRole');

        if (userRole == 'customer_support') {
          _cachedIsCustomerSupport = true;
          _cachedUserId = user.uid;
          AppLogger.d('User ${user.uid} is a Customer Support Representative');
          return true;
        }
      }

      _cachedIsCustomerSupport = false;
      _cachedUserId = user.uid;
      AppLogger.d('User ${user.uid} is not a Customer Support Representative');
      return false;
    } catch (e) {
      AppLogger.d('Error checking customer support status: $e');
      return false;
    }
  }

  // Clear cache (call this on logout)
  static void clearCache() {
    _cachedIsSeller = null;
    _cachedIsCustomerSupport = null;
    _cachedUserId = null;
  }

  // Get user's first name
  Future<String> getUserFirstName() async {
    try {
      final userData = await getCurrentUserData();
      if (userData != null) {
        // First try to get from the firstName field
        if (userData['firstName'] != null &&
            userData['firstName'].toString().isNotEmpty) {
          return userData['firstName'] as String;
        }
        // Fall back to parsing fullName for backward compatibility
        if (userData['fullName'] != null) {
          final fullName = userData['fullName'] as String;
          return fullName.split(' ').first;
        }
      }
      return 'User';
    } catch (e) {
      AppLogger.d('Error getting user first name: $e');
      return 'User';
    }
  }

  // Get user's full name
  Future<String> getUserFullName() async {
    try {
      final userData = await getCurrentUserData();
      if (userData != null && userData['fullName'] != null) {
        return userData['fullName'] as String;
      }
      return 'User';
    } catch (e) {
      AppLogger.d('Error getting user full name: $e');
      return 'User';
    }
  }

  // Check if user is authenticated
  bool isUserAuthenticated() {
    return _auth.currentUser != null;
  }

  // Get current user ID
  String? getCurrentUserId() {
    return _auth.currentUser?.uid;
  }
}
