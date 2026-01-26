import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dentpal/services/notification_service.dart';
import 'package:dentpal/utils/app_logger.dart';

/// Helper class to manage FCM token topics and cleanup
class FCMTokenManager {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final NotificationService _notificationService = NotificationService();

  /// Remove FCM token from Firestore (call on logout)
  static Future<void> removeFCMToken() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        AppLogger.w('No user logged in');
        return;
      }

      // Delete token from Firebase
      await _notificationService.deleteToken();

      // Remove from Firestore
      await _firestore.collection('User').doc(user.uid).update({
        'fcmToken': FieldValue.delete(),
        'fcmTokenUpdatedAt': FieldValue.delete(),
      });

      AppLogger.i('FCM token removed for user: ${user.uid}');
    } catch (e) {
      AppLogger.e('Error removing FCM token: $e');
    }
  }

  /// Subscribe user to role-based topics
  static Future<void> subscribeToRoleTopics(String role) async {
    try {
      // Subscribe to general topic
      await _notificationService.subscribeToTopic('all_users');

      // Subscribe to role-specific topics
      switch (role.toLowerCase()) {
        case 'seller':
          await _notificationService.subscribeToTopic('sellers');
          await _notificationService.subscribeToTopic('seller_updates');
          break;
        case 'buyer':
          await _notificationService.subscribeToTopic('buyers');
          await _notificationService.subscribeToTopic('promotions');
          break;
        case 'admin':
          await _notificationService.subscribeToTopic('admins');
          await _notificationService.subscribeToTopic('system_alerts');
          break;
        default:
          AppLogger.w('Unknown role: $role');
      }

      AppLogger.i('Subscribed to topics for role: $role');
    } catch (e) {
      AppLogger.e('Error subscribing to topics: $e');
    }
  }

  /// Unsubscribe from all topics (call on logout)
  static Future<void> unsubscribeFromAllTopics(String role) async {
    try {
      // Unsubscribe from general topics
      await _notificationService.unsubscribeFromTopic('all_users');

      // Unsubscribe from role-specific topics
      switch (role.toLowerCase()) {
        case 'seller':
          await _notificationService.unsubscribeFromTopic('sellers');
          await _notificationService.unsubscribeFromTopic('seller_updates');
          break;
        case 'buyer':
          await _notificationService.unsubscribeFromTopic('buyers');
          await _notificationService.unsubscribeFromTopic('promotions');
          break;
        case 'admin':
          await _notificationService.unsubscribeFromTopic('admins');
          await _notificationService.unsubscribeFromTopic('system_alerts');
          break;
      }

      AppLogger.i('Unsubscribed from all topics');
    } catch (e) {
      AppLogger.e('Error unsubscribing from topics: $e');
    }
  }

  /// Cleanup FCM for user (call on logout)
  static Future<void> cleanupForUser(String role) async {
    await unsubscribeFromAllTopics(role);
    await removeFCMToken();
  }
}
