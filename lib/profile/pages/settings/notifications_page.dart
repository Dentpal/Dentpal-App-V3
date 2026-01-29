import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../../core/app_theme/app_colors.dart';
import '../../../core/app_theme/app_text_styles.dart';
import '../../../utils/app_logger.dart';
import '../../../product/models/order_model.dart' as order_model;
import '../order_details_page.dart';
import '../chat_detail_page.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isMarkingAllRead = false;

  String get _userId => _auth.currentUser?.uid ?? '';

  Stream<QuerySnapshot> _getNotificationsStream() {
    if (_userId.isEmpty) {
      return const Stream.empty();
    }

    return _firestore
        .collection('User')
        .doc(_userId)
        .collection('user_notifications')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots();
  }

  Future<void> _markAsRead(String notificationId) async {
    try {
      await _firestore
          .collection('User')
          .doc(_userId)
          .collection('user_notifications')
          .doc(notificationId)
          .update({
        'read': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      AppLogger.e('Error marking notification as read: $e');
    }
  }

  Future<void> _markAllAsRead() async {
    if (_userId.isEmpty) return;

    setState(() => _isMarkingAllRead = true);

    try {
      final unreadNotifications = await _firestore
          .collection('User')
          .doc(_userId)
          .collection('user_notifications')
          .where('read', isEqualTo: false)
          .get();

      final batch = _firestore.batch();
      for (var doc in unreadNotifications.docs) {
        batch.update(doc.reference, {
          'read': true,
          'readAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${unreadNotifications.docs.length} notifications marked as read'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      AppLogger.e('Error marking all as read: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to mark notifications as read'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isMarkingAllRead = false);
      }
    }
  }

  Future<void> _deleteNotification(String notificationId) async {
    try {
      await _firestore
          .collection('User')
          .doc(_userId)
          .collection('user_notifications')
          .doc(notificationId)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Notification deleted'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      AppLogger.e('Error deleting notification: $e');
    }
  }

  void _handleNotificationTap(Map<String, dynamic> notification) async {
    final notificationId = notification['id'] as String?;
    final isRead = notification['read'] as bool? ?? false;

    // Mark as read if unread
    if (!isRead && notificationId != null) {
      _markAsRead(notificationId);
    }

    // Handle navigation based on notification type
    final type = notification['type'] as String?;
    final data = notification['data'] as Map<String, dynamic>?;

    if (type == 'order' && data != null) {
      final orderId = data['orderId'] as String?;
      if (orderId != null) {
        AppLogger.i('Navigate to order: $orderId');
        
        // Show loading indicator
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(child: CircularProgressIndicator()),
        );

        try {
          // Fetch the order details from Firestore
          final orderDoc = await FirebaseFirestore.instance
              .collection('Order')
              .doc(orderId)
              .get();

          if (!mounted) return;
          
          // Close loading dialog
          Navigator.of(context).pop();

          if (orderDoc.exists) {
            // Convert to Order model using fromFirestore
            final order = order_model.Order.fromFirestore(orderDoc);
            
            // Navigate to order details page
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => OrderDetailsPage(order: order),
              ),
            );
          } else {
            _showErrorSnackBar('Order not found');
          }
        } catch (e) {
          AppLogger.e('Error loading order: $e');
          if (mounted) {
            Navigator.of(context).pop(); // Close loading dialog
            _showErrorSnackBar('Failed to load order details');
          }
        }
      }
    } else if (type == 'message' && data != null) {
      final chatRoomId = data['chatRoomId'] as String? ?? data['chatId'] as String?;
      final otherUserId = data['otherUserId'] as String? ?? data['senderId'] as String?;
      final otherUserName = data['otherUserName'] as String?;
      
      if (chatRoomId != null && otherUserId != null) {
        AppLogger.i('Navigate to chat: $chatRoomId');
        
        // Get other user's details if not in data
        String displayName = otherUserName ?? 'User';
        String? shopName;
        
        if (otherUserName == null || otherUserName.isEmpty) {
          try {
            final userDoc = await FirebaseFirestore.instance
                .collection('User')
                .doc(otherUserId)
                .get();
            
            if (userDoc.exists) {
              final userData = userDoc.data();
              displayName = userData?['displayName'] ?? userData?['fullName'] ?? 'User';
              shopName = userData?['shopName'];
            }
          } catch (e) {
            AppLogger.e('Error fetching user data: $e');
          }
        }
        
        if (!mounted) return;
        
        // Navigate to chat detail page
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ChatDetailPage(
              chatRoomId: chatRoomId,
              otherUserId: otherUserId,
              otherUserName: displayName,
              otherUserShopName: shopName,
            ),
          ),
        );
      }
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return '';

    final date = timestamp.toDate();
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return DateFormat('MMM d, yyyy').format(date);
    }
  }

  IconData _getNotificationIcon(String? type) {
    switch (type) {
      case 'order':
        return Icons.shopping_bag_outlined;
      case 'message':
        return Icons.chat_bubble_outline;
      case 'promotion':
        return Icons.local_offer_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color _getNotificationColor(String? type) {
    switch (type) {
      case 'order':
        return AppColors.primary;
      case 'message':
        return AppColors.success;
      case 'promotion':
        return AppColors.warning;
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        toolbarHeight: 60,
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Icon(Icons.notifications, color: AppColors.primary, size: 24),
            const SizedBox(width: 8),
            Text(
              'Notifications',
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        actions: [
          if (!_isMarkingAllRead)
            TextButton(
              onPressed: _markAllAsRead,
              child: Text(
                'Mark all read',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _getNotificationsStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: AppColors.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading notifications',
                    style: AppTextStyles.bodyLarge,
                  ),
                ],
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final notifications = snapshot.data?.docs ?? [];

          if (notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_none,
                    size: 80,
                    color: AppColors.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No notifications yet',
                    style: AppTextStyles.titleMedium.copyWith(
                      color: AppColors.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You\'ll see updates about your orders here',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            );
          }

          // Count unread notifications
          final unreadCount = notifications.where((doc) {
            final data = doc.data() as Map<String, dynamic>?;
            return data?['read'] == false;
          }).length;

          return Column(
            children: [
              if (unreadCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  color: AppColors.primary.withValues(alpha: 0.05),
                  child: Row(
                    children: [
                      Icon(
                        Icons.circle,
                        size: 8,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$unreadCount unread notification${unreadCount > 1 ? 's' : ''}',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: notifications.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final doc = notifications[index];
                    final data = doc.data() as Map<String, dynamic>?;
                    
                    if (data == null) return const SizedBox.shrink();

                    final notificationData = {
                      ...data,
                      'id': doc.id,
                    };

                    final isRead = data['read'] as bool? ?? false;
                    final title = data['title'] as String? ?? 'Notification';
                    final body = data['body'] as String? ?? '';
                    final type = data['type'] as String?;
                    final createdAt = data['createdAt'] as Timestamp?;

                    return Dismissible(
                      key: Key(doc.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.delete_outline,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      confirmDismiss: (direction) async {
                        return await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete notification?'),
                            content: const Text(
                              'This notification will be permanently deleted.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: Text(
                                  'Delete',
                                  style: TextStyle(color: AppColors.error),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                      onDismissed: (direction) {
                        _deleteNotification(doc.id);
                      },
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _handleNotificationTap(notificationData),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isRead
                                  ? AppColors.surface
                                  : AppColors.primary.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isRead
                                    ? AppColors.onSurface.withValues(alpha: 0.1)
                                    : AppColors.primary.withValues(alpha: 0.2),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.onSurface.withValues(alpha: 0.05),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Icon
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: _getNotificationColor(type)
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    _getNotificationIcon(type),
                                    color: _getNotificationColor(type),
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Content
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          if (!isRead)
                                            Container(
                                              margin: const EdgeInsets.only(right: 8),
                                              width: 8,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                color: AppColors.primary,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          Expanded(
                                            child: Text(
                                              title,
                                              style: AppTextStyles.bodyLarge.copyWith(
                                                fontWeight: isRead
                                                    ? FontWeight.w500
                                                    : FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (body.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          body,
                                          style: AppTextStyles.bodyMedium.copyWith(
                                            color: AppColors.onSurface
                                                .withValues(alpha: 0.7),
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                      const SizedBox(height: 8),
                                      Text(
                                        _formatTimestamp(createdAt),
                                        style: AppTextStyles.bodySmall.copyWith(
                                          color: AppColors.onSurface
                                              .withValues(alpha: 0.5),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
