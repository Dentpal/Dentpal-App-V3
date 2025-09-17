import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dentpal/utils/app_logger.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

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

  // Get user's first name
  Future<String> getUserFirstName() async {
    try {
      final userData = await getCurrentUserData();
      if (userData != null && userData['fullName'] != null) {
        final fullName = userData['fullName'] as String;
        return fullName.split(' ').first;
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
