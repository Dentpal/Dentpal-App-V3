import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../../core/app_theme/app_text_styles.dart';
import '../../../core/app_theme/ink_palette.dart';
import '../../../core/app_theme/theme_utils.dart';
import '../../../core/widgets/app_page_header.dart';
import '../../../utils/app_logger.dart';
import '../../../product/models/order_model.dart' as order_model;
import '../../../product/widgets/loading_skeletons.dart';
import '../order_details_page.dart';

/// The buyer's notification inbox.
///
/// Grouped by age rather than listed flat: "did anything happen today" is the
/// question this screen exists to answer, and unread items are tinted so the
/// answer survives a glance.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  // Lazy so that merely constructing the page does not require a live Firebase
  // app — the plugins are only touched once the stream is actually built.
  late final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isMarkingAllRead = false;

  String get _userId => _auth.currentUser?.uid ?? '';

  /// The inbox feed, opened once per signed-in account.
  ///
  /// This used to be built inline as `stream: _getNotificationsStream()`, which
  /// handed `StreamBuilder` a brand new query object on every rebuild: it
  /// cancelled the live listener, opened a fresh Firestore subscription and
  /// dropped back to the loading skeleton — losing the scroll position — even
  /// though nothing about the inbox had changed. Marking one notification read
  /// was enough to do it, and so was switching to another tab and back.
  ///
  /// Holding the stream keeps the subscription alive across rebuilds while
  /// still delivering new notifications the moment they are written, because
  /// it is a snapshot stream rather than a one-shot read.
  Stream<QuerySnapshot>? _notificationsStream;
  String? _streamUserId;

  Stream<QuerySnapshot> _getNotificationsStream() {
    final userId = _userId;
    if (_notificationsStream != null && _streamUserId == userId) {
      return _notificationsStream!;
    }

    _streamUserId = userId;
    return _notificationsStream = userId.isEmpty
        ? const Stream.empty()
        : _firestore
              .collection('User')
              .doc(userId)
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
          .update({'read': true, 'readAt': FieldValue.serverTimestamp()});
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
        _showSnack(
          '${unreadNotifications.docs.length} notification'
          '${unreadNotifications.docs.length == 1 ? '' : 's'} marked as read',
          icon: Icons.done_all,
        );
      }
    } catch (e) {
      AppLogger.e('Error marking all as read: $e');
      if (mounted) {
        _showSnack(
          'Failed to mark notifications as read',
          tone: _danger,
          icon: Icons.error_outline,
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
        _showSnack('Notification deleted', icon: Icons.delete_outline);
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
          builder: (context) =>
              Center(child: CircularProgressIndicator(color: ink.emerald)),
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
            _showSnack(
              'Order not found',
              tone: _danger,
              icon: Icons.error_outline,
            );
          }
        } catch (e) {
          AppLogger.e('Error loading order: $e');
          if (mounted) {
            Navigator.of(context).pop(); // Close loading dialog
            _showSnack(
              'Failed to load order details',
              tone: _danger,
              icon: Icons.error_outline,
            );
          }
        }
      }
    } else if (type == 'message' && data != null) {
      final chatRoomId =
          data['chatRoomId'] as String? ?? data['chatId'] as String?;
      final otherUserId =
          data['otherUserId'] as String? ?? data['senderId'] as String?;
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
              displayName =
                  userData?['displayName'] ?? userData?['fullName'] ?? 'User';
              shopName = userData?['shopName'];
            }
          } catch (e) {
            AppLogger.e('Error fetching user data: $e');
          }
        }

        if (!mounted) return;

        // Navigate to chat detail page
        Navigator.of(context).pushNamed(
          '/profile/chats/$chatRoomId',
          arguments: <String, dynamic>{
            'otherUserId': otherUserId,
            'otherUserName': displayName,
            'otherUserShopName': shopName,
          },
        );
      }
    }
  }

  void _showSnack(String message, {Color? tone, IconData? icon}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 8),
            ],
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: tone ?? ink.emerald,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── Palette ──────────────────────────────────────────────────────────────

  InkPalette get ink => InkPalette.of(context);

  /// Destructive red. [InkPalette] reserves amber for urgency, so danger needs
  /// its own tone that still reads in both themes.
  Color get _danger =>
      ink.isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);

  Color get _muted => ink.text.withValues(alpha: 0.6);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ink.bg,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppLayout.maxContentWidth,
            ),
            child: StreamBuilder<QuerySnapshot>(
              stream: _getNotificationsStream(),
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? const [];
                final unreadCount = docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>?;
                  return data?['read'] == false;
                }).length;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(unreadCount),
                    Expanded(child: _buildBody(snapshot, docs)),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────

  Widget _buildHeader(int unreadCount) {
    return AppPageHeader(
      title: 'Notifications',
      subtitle: unreadCount > 0
          ? '$unreadCount unread'
          : 'You’re all caught up',
      subtitleColor: unreadCount > 0 ? ink.emerald : null,
      trailing: unreadCount > 0
          // Below ~430px the labelled button and the title fight over the same
          // row, so the action collapses to its icon.
          ? _buildMarkAllButton(compact: MediaQuery.sizeOf(context).width < 430)
          : null,
    );
  }

  /// Only offered when there is something to clear — a permanently visible
  /// "Mark all read" on an empty inbox is a control that can do nothing.
  Widget _buildMarkAllButton({bool compact = false}) {
    if (compact) {
      return Tooltip(
        message: 'Mark all read',
        child: IconButton(
          onPressed: _isMarkingAllRead ? null : _markAllAsRead,
          icon: _isMarkingAllRead
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: ink.emerald,
                  ),
                )
              : Icon(Icons.done_all, size: 20, color: ink.emerald),
          style: IconButton.styleFrom(
            backgroundColor: ink.emerald.withValues(
              alpha: ink.isDark ? 0.16 : 0.11,
            ),
            shape: const CircleBorder(),
          ),
        ),
      );
    }

    return SizedBox(
      height: 38,
      child: OutlinedButton.icon(
        onPressed: _isMarkingAllRead ? null : _markAllAsRead,
        icon: _isMarkingAllRead
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: ink.emerald,
                ),
              )
            : const Icon(Icons.done_all, size: 16),
        label: Text(
          'Mark all read',
          style: AppTextStyles.buttonMedium.copyWith(fontSize: 12.5),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: ink.emerald,
          disabledForegroundColor: ink.emerald.withValues(alpha: 0.6),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          side: BorderSide(color: ink.emerald.withValues(alpha: 0.4)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }

  // ── Body ─────────────────────────────────────────────────────────────────

  Widget _buildBody(
    AsyncSnapshot<QuerySnapshot> snapshot,
    List<QueryDocumentSnapshot> docs,
  ) {
    const listPadding = EdgeInsets.fromLTRB(
      AppLayout.gutter,
      4,
      AppLayout.gutter,
      24,
    );

    if (snapshot.hasError) {
      return _buildStateMessage(
        icon: Icons.cloud_off,
        tone: _danger,
        title: 'Couldn’t load notifications',
        detail:
            'Check your connection — this list updates on its own once it '
            'reconnects.',
      );
    }

    if (snapshot.connectionState == ConnectionState.waiting) {
      return NotificationsSkeleton(padding: listPadding);
    }

    if (docs.isEmpty) {
      return _buildStateMessage(
        icon: Icons.notifications_none,
        tone: ink.emerald,
        title: 'Nothing here yet',
        detail:
            'Order updates, seller replies and offers will land here as they '
            'happen.',
      );
    }

    // Grouped by age, newest group first. The query is already sorted, so this
    // only has to break the run at each boundary.
    final groups = <String, List<QueryDocumentSnapshot>>{};
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>?;
      final label = notificationGroupLabel(
        (data?['createdAt'] as Timestamp?)?.toDate(),
      );
      groups.putIfAbsent(label, () => []).add(doc);
    }

    return ListView(
      padding: listPadding,
      children: [
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 12, 0, 10),
            child: Text(
              entry.key,
              style: AppTextStyles.titleMedium.copyWith(
                color: ink.text,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
          for (final doc in entry.value) _buildDismissible(doc),
        ],
      ],
    );
  }

  Widget _buildDismissible(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: Key(doc.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 22),
          decoration: BoxDecoration(
            color: _danger.withValues(alpha: ink.isDark ? 0.22 : 0.12),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _danger.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Icon(Icons.delete_outline, color: _danger, size: 20),
              const SizedBox(width: 8),
              Text(
                'Delete',
                style: AppTextStyles.bodySmall.copyWith(
                  color: _danger,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
        confirmDismiss: (direction) => _confirmDelete(),
        onDismissed: (direction) => _deleteNotification(doc.id),
        child: NotificationCard(
          data: data,
          onTap: () => _handleNotificationTap({...data, 'id': doc.id}),
        ),
      ),
    );
  }

  Future<bool?> _confirmDelete() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ink.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.delete_outline, color: _danger),
            const SizedBox(width: 8),
            Text('Delete notification?', style: TextStyle(color: ink.text)),
          ],
        ),
        content: Text(
          'This notification will be permanently deleted.',
          style: AppTextStyles.bodyMedium.copyWith(color: _muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Keep', style: TextStyle(color: _muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _danger,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildStateMessage({
    required IconData icon,
    required Color tone,
    required String title,
    required String detail,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 40, 32, 60),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: tone.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 30, color: tone),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.titleMedium.copyWith(
                        color: ink.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      detail,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: _muted,
                        fontSize: 13.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One notification: type tile, title, body and stamp, tinted while unread.
///
/// Public and data-driven so the list's look can be exercised without a live
/// Firestore behind it.
class NotificationCard extends StatelessWidget {
  const NotificationCard({super.key, required this.data, required this.onTap});

  final Map<String, dynamic> data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);

    final isRead = data['read'] as bool? ?? false;
    final title = data['title'] as String? ?? 'Notification';
    final body = data['body'] as String? ?? '';
    final type = data['type'] as String?;
    final createdAt = data['createdAt'];
    final tone = notificationTone(type, ink);

    return Material(
      color: isRead
          ? ink.surface
          : Color.alphaBlend(
              ink.emerald.withValues(alpha: ink.isDark ? 0.10 : 0.07),
              ink.surface,
            ),
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isRead ? ink.border : ink.emerald.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: ink.isDark ? 0.18 : 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(notificationIcon(type), color: tone, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: ink.text,
                              fontWeight: isRead
                                  ? FontWeight.w600
                                  : FontWeight.w800,
                              fontSize: 13.5,
                              height: 1.3,
                            ),
                          ),
                        ),
                        if (!isRead) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(top: 5),
                            decoration: BoxDecoration(
                              color: ink.emerald,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        body,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: ink.text.withValues(alpha: 0.65),
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          formatNotificationTime(
                            createdAt is Timestamp ? createdAt.toDate() : null,
                          ),
                          style: AppTextStyles.bodySmall.copyWith(
                            fontFamily: AppTextStyles.secondaryFont,
                            color: ink.text.withValues(alpha: 0.45),
                            fontSize: 11.5,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: ink.text.withValues(alpha: 0.3),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Section a notification belongs to, by age.
String notificationGroupLabel(DateTime? date, {DateTime? now}) {
  if (date == null) return 'Earlier';

  final today = now ?? DateTime.now();
  final startOfToday = DateTime(today.year, today.month, today.day);
  final startOfDate = DateTime(date.year, date.month, date.day);
  final days = startOfToday.difference(startOfDate).inDays;

  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return 'This week';
  if (days < 30) return 'This month';
  return 'Earlier';
}

/// Relative stamp — exact clock time matters less than "how long ago".
String formatNotificationTime(DateTime? date, {DateTime? now}) {
  if (date == null) return '';

  final difference = (now ?? DateTime.now()).difference(date);

  if (difference.inMinutes < 1) return 'Just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
  if (difference.inHours < 24) return '${difference.inHours}h ago';
  if (difference.inDays < 7) return '${difference.inDays}d ago';
  return DateFormat('MMM d, yyyy').format(date);
}

IconData notificationIcon(String? type) {
  switch (type) {
    case 'order':
      return Icons.local_shipping_outlined;
    case 'message':
      return Icons.chat_bubble_outline;
    case 'promotion':
      return Icons.local_offer_outlined;
    default:
      return Icons.notifications_outlined;
  }
}

/// Type colour, taken from the palette so both themes stay in step. Amber is
/// reserved for urgency, which is exactly what a promotion's countdown is.
Color notificationTone(String? type, InkPalette ink) {
  switch (type) {
    case 'order':
      return ink.emerald;
    case 'message':
      return ink.emeraldSoft;
    case 'promotion':
      return ink.amber;
    default:
      return ink.emerald;
  }
}
