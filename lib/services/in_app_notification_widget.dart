import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Widget to display in-app notifications as a banner
class InAppNotificationBanner extends StatefulWidget {
  final RemoteMessage message;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;

  const InAppNotificationBanner({
    super.key,
    required this.message,
    this.onTap,
    this.onDismiss,
  });

  @override
  State<InAppNotificationBanner> createState() =>
      _InAppNotificationBannerState();
}

class _InAppNotificationBannerState extends State<InAppNotificationBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));
    _controller.forward();

    // Auto dismiss after 5 seconds
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        _dismiss();
      }
    });
  }

  void _dismiss() async {
    await _controller.reverse();
    widget.onDismiss?.call();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notification = widget.message.notification;
    if (notification == null) return const SizedBox.shrink();

    return SlideTransition(
      position: _slideAnimation,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () {
                _dismiss();
                widget.onTap?.call();
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    // Icon
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.notifications,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            notification.title ?? '',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (notification.body != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              notification.body!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Close button
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: _dismiss,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Widget to wrap around your app to show in-app notifications
class InAppNotificationWrapper extends StatefulWidget {
  final Widget child;
  final Stream<RemoteMessage> notificationStream;

  const InAppNotificationWrapper({
    super.key,
    required this.child,
    required this.notificationStream,
  });

  @override
  State<InAppNotificationWrapper> createState() =>
      _InAppNotificationWrapperState();
}

class _InAppNotificationWrapperState extends State<InAppNotificationWrapper> {
  final List<RemoteMessage> _notifications = [];

  @override
  void initState() {
    super.initState();
    widget.notificationStream.listen((message) {
      setState(() {
        _notifications.add(message);
      });
    });
  }

  void _removeNotification(int index) {
    setState(() {
      if (index < _notifications.length) {
        _notifications.removeAt(index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          widget.child,
          if (_notifications.isNotEmpty)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: InAppNotificationBanner(
                message: _notifications.first,
                onDismiss: () => _removeNotification(0),
                onTap: () {
                  // Handle notification tap
                  _removeNotification(0);
                },
              ),
            ),
        ],
      ),
    );
  }
}
