import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:dentpal/utils/app_logger.dart';
import 'package:dentpal/product/models/order_model.dart' as order_model;
import 'package:dentpal/profile/pages/order_details_page.dart';

/// Background message handler must be a top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  AppLogger.i('Handling background message: ${message.messageId}');
  AppLogger.i('Background notification: ${message.notification?.title}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // Navigation key for global navigation (set from main.dart)
  static GlobalKey<NavigatorState>? _navigatorKey;
  static GlobalKey<NavigatorState>? get navigatorKey => _navigatorKey;
  
  /// Set the navigator key from main.dart
  static void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  // Stream controller for in-app notifications
  final StreamController<RemoteMessage> _messageStreamController =
      StreamController<RemoteMessage>.broadcast();

  Stream<RemoteMessage> get messageStream => _messageStreamController.stream;

  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  /// Initialize the notification service
  Future<void> initialize() async {
    print('=== NotificationService.initialize() START ===');
    AppLogger.i('NotificationService initialize START');
    try {
      // Request permission for iOS
      if (Platform.isIOS) {
        await _requestIOSPermissions();
      }

      // Request permission for Android 13+
      if (Platform.isAndroid) {
        await _requestAndroidPermissions();
      }

      // Initialize local notifications
      await _initializeLocalNotifications();

      // Get FCM token
      await _getToken();

      // Configure foreground notification presentation
      await _configureForegroundNotifications();

      // Set up message handlers
      _setupMessageHandlers();

      // Listen for token refresh
      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        AppLogger.i('FCM Token refreshed: $newToken');
        _fcmToken = newToken;
        _saveTokenToFirestore(newToken);
      });

      AppLogger.i('Notification service initialized successfully');
    } catch (e) {
      AppLogger.e('Error initializing notification service: $e');
    }
  }

  /// Request iOS notification permissions
  Future<void> _requestIOSPermissions() async {
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    AppLogger.i('iOS notification permission: ${settings.authorizationStatus}');
  }

  /// Request Android notification permissions (Android 13+)
  Future<void> _requestAndroidPermissions() async {
    if (Platform.isAndroid) {
      final androidPlugin =
          _localNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.requestNotificationsPermission();
      }
    }
  }

  /// Initialize Flutter Local Notifications
  Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/launcher_icon');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
  }

  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    AppLogger.i('Notification tapped: ${response.payload}');
    
    if (response.payload != null) {
      try {
        // Parse the payload (it's a string representation of the data map)
        final payloadStr = response.payload!;
        AppLogger.i('Parsing notification payload: $payloadStr');
        
        // Extract orderId from the payload string
        // The payload format is like: "{type: order, orderId: ABC123, status: shipping, action: view_order}"
        final orderIdMatch = RegExp(r'orderId:\s*([^,}]+)').firstMatch(payloadStr);
        final typeMatch = RegExp(r'type:\s*([^,}]+)').firstMatch(payloadStr);
        
        if (typeMatch != null && orderIdMatch != null) {
          final type = typeMatch.group(1)?.trim();
          final orderId = orderIdMatch.group(1)?.trim();
          
          if (type == 'order' && orderId != null) {
            AppLogger.i('Navigating to order: $orderId');
            _navigateToOrder(orderId);
          }
        }
      } catch (e) {
        AppLogger.e('Error parsing notification payload: $e');
      }
    }
  }

  /// Get FCM token
  Future<void> _getToken() async {
    print('=== _getToken() START ===');
    try {
      AppLogger.i('Requesting FCM token from Firebase...');
      print('=== About to call getToken()...');
      _fcmToken = await _firebaseMessaging.getToken();
      print('=== getToken() returned: ${_fcmToken != null ? "Token received" : "NULL"}');
      if (_fcmToken != null) {
        AppLogger.i('FCM Token received: ${_fcmToken!.substring(0, 20)}...');
        print('=== Full FCM Token: $_fcmToken');
        
        // IMMEDIATELY save to Firestore
        print('=== Immediately saving token to Firestore...');
        await _saveTokenToFirestore(_fcmToken!);
      } else {
        AppLogger.e('FCM Token is NULL');
        print('=== ERROR: FCM Token is NULL');
      }
    } catch (e, stackTrace) {
      print('=== ERROR in _getToken(): $e');
      AppLogger.e('Error getting FCM token: $e');
      AppLogger.e('Stack trace: $stackTrace');
    }
  }

  /// Configure foreground notification presentation options
  Future<void> _configureForegroundNotifications() async {
    await _firebaseMessaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  /// Set up message handlers
  void _setupMessageHandlers() {
    // Handle messages when app is in foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      AppLogger.i('Foreground message received: ${message.messageId}');
      AppLogger.i('Notification: ${message.notification?.title}');
      
      // Add to stream for in-app notification
      _messageStreamController.add(message);

      // Show local notification
      _showLocalNotification(message);
    });

    // Handle notification tap when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      AppLogger.i('Notification opened app: ${message.messageId}');
      // TODO: Navigate to appropriate screen
      _handleNotificationNavigation(message);
    });

    // Check for initial message (app opened from terminated state)
    _firebaseMessaging.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        AppLogger.i('App opened from terminated state: ${message.messageId}');
        // TODO: Navigate to appropriate screen
        _handleNotificationNavigation(message);
      }
    });
  }

  /// Show local notification
  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'dentpal_channel', // Channel ID
      'DentPal Notifications', // Channel name
      channelDescription: 'Notifications for DentPal orders and updates',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/launcher_icon',
      groupKey: 'dentpal_orders', // Group notifications together
      setAsGroupSummary: false, // Individual notification
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      threadIdentifier: 'dentpal_orders', // iOS grouping
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Create a properly formatted payload with orderId for easy parsing
    String payload = '';
    if (message.data.containsKey('orderId')) {
      payload = 'type: ${message.data['type']}, orderId: ${message.data['orderId']}';
    }

    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      details,
      payload: payload.isNotEmpty ? payload : null,
    );
  }

  /// Handle notification navigation based on data
  void _handleNotificationNavigation(RemoteMessage message) {
    final data = message.data;
    
    AppLogger.i('Handling notification navigation with data: $data');
    
    // Navigate based on notification type
    if (data.containsKey('type')) {
      final type = data['type'];
      switch (type) {
        case 'order':
          final orderId = data['orderId'];
          if (orderId != null) {
            AppLogger.i('Navigate to order: $orderId');
            _navigateToOrder(orderId);
          }
          break;
        case 'message':
          final chatId = data['chatId'];
          AppLogger.i('Navigate to chat: $chatId');
          // TODO: Navigate to chat
          break;
        default:
          AppLogger.i('Unknown notification type: $type');
      }
    }
  }

  /// Navigate to order details page
  Future<void> _navigateToOrder(String orderId) async {
    try {
      if (_navigatorKey == null) {
        AppLogger.e('Navigator key is null, cannot navigate');
        return;
      }

      final context = _navigatorKey?.currentContext;
      if (context == null) {
        AppLogger.e('Navigator context is null, cannot navigate');
        return;
      }

      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      // Fetch the order details from Firestore
      final orderDoc = await FirebaseFirestore.instance
          .collection('Order')
          .doc(orderId)
          .get();

      // Close loading dialog
      final currentContext = _navigatorKey?.currentContext;
      if (currentContext != null) {
        Navigator.of(currentContext).pop();
      }

      if (orderDoc.exists) {
        // Convert to Order model using fromFirestore
        final order = order_model.Order.fromFirestore(orderDoc);
        
        // Navigate to order details page
        final navContext = _navigatorKey?.currentContext;
        if (navContext != null) {
          Navigator.of(navContext).push(
            MaterialPageRoute(
              builder: (context) => OrderDetailsPage(order: order),
            ),
          );
        }
      } else {
        AppLogger.e('Order not found: $orderId');
        _showErrorSnackBar('Order not found');
      }
    } catch (e) {
      AppLogger.e('Error navigating to order: $e');
      // Close loading dialog if still open
      final currentContext = _navigatorKey?.currentContext;
      if (currentContext != null) {
        Navigator.of(currentContext).pop();
      }
      _showErrorSnackBar('Failed to load order details');
    }
  }

  /// Show error snackbar
  void _showErrorSnackBar(String message) {
    final context = _navigatorKey?.currentContext;
    if (context != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  /// Subscribe to topic
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _firebaseMessaging.subscribeToTopic(topic);
      AppLogger.i('Subscribed to topic: $topic');
    } catch (e) {
      AppLogger.e('Error subscribing to topic: $e');
    }
  }

  /// Unsubscribe from topic
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _firebaseMessaging.unsubscribeFromTopic(topic);
      AppLogger.i('Unsubscribed from topic: $topic');
    } catch (e) {
      AppLogger.e('Error unsubscribing from topic: $e');
    }
  }

  /// Delete FCM token (for logout)
  Future<void> deleteToken() async {
    try {
      await _firebaseMessaging.deleteToken();
      _fcmToken = null;
      AppLogger.i('FCM token deleted');
    } catch (e) {
      AppLogger.e('Error deleting FCM token: $e');
    }
  }

  /// Save token to Firestore when it's refreshed
  Future<void> _saveTokenToFirestore(String token) async {
    print('=== _saveTokenToFirestore() START ===');
    try {
      final user = FirebaseAuth.instance.currentUser;
      print('=== Current user: ${user?.uid}');
      
      if (user == null) {
        AppLogger.w('No user logged in, cannot save FCM token');
        print('=== ERROR: No user logged in, skipping save');
        return;
      }

      print('=== Saving token to User/${user.uid}...');
      await FirebaseFirestore.instance
          .collection('User')
          .doc(user.uid)
          .set({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        'platform': Platform.isAndroid ? 'android' : Platform.isIOS ? 'ios' : 'unknown',
      }, SetOptions(merge: true));

      print('=== SUCCESS: Token saved to Firestore!');
      AppLogger.i('FCM token auto-saved to Firestore for user: ${user.uid}');
    } catch (e, stackTrace) {
      print('=== ERROR saving token: $e');
      print('=== Stack trace: $stackTrace');
      AppLogger.e('Error auto-saving FCM token: $e');
      AppLogger.e('Stack trace: $stackTrace');
      // Don't throw - this is a background operation
    }
  }

  /// Dispose resources
  void dispose() {
    _messageStreamController.close();
  }
}
