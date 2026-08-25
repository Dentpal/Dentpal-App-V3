import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:dentpal/product/services/cart_service.dart';
import 'package:dentpal/utils/app_logger.dart';

/// The counts shown on the navigation chrome's badges.
///
/// Before the app shell existed, the cart badge was subscribed to twice — once
/// by `HomePage` for the bottom bar and again by `ProductListingPage` for the
/// side rail — and the two could briefly disagree. The chrome now outlives
/// every page, so the subscription belongs here: started once, held for the
/// life of the session, and read by whichever surfaces care.
///
/// Exposed as [ValueListenable]s rather than a stream so a widget can paint the
/// current count on its first frame instead of waiting for a snapshot.
class NavBadgeService {
  NavBadgeService._();

  static final NavBadgeService instance = NavBadgeService._();

  final ValueNotifier<int> cartCount = ValueNotifier<int>(0);
  final ValueNotifier<int> unreadNotifications = ValueNotifier<int>(0);

  // Lazy: this singleton is constructed the first time any surface reads a
  // badge, which can happen before Firebase is up (and in a widget test, where
  // it never is). CartService grabs Firestore in its own field initialiser.
  late final CartService _cartService = CartService();

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<int>? _cartSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _notificationsSubscription;

  bool _started = false;

  /// Safe to call more than once; only the first call subscribes.
  void start() {
    if (_started) return;
    _started = true;

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
      _onUserChanged,
    );
  }

  void _onUserChanged(User? user) {
    _cartSubscription?.cancel();
    _cartSubscription = null;
    _notificationsSubscription?.cancel();
    _notificationsSubscription = null;

    if (user == null) {
      cartCount.value = 0;
      unreadNotifications.value = 0;
      return;
    }

    _cartSubscription = _cartService.cartItemCountStream().listen(
      (value) => cartCount.value = value,
      onError: (error) {
        AppLogger.d('NavBadgeService: cart count error: $error');
        cartCount.value = 0;
      },
    );

    // Counted client-side rather than with `where('read', isEqualTo: false)`:
    // notification documents are written without a `read` field until they are
    // first opened, and an equality filter skips documents missing the field
    // entirely — so a server-side count came back 0 for exactly the
    // notifications that have never been read. NotificationsPage treats a
    // missing `read` as unread too, so `read != true` is the rule that matches
    // what the buyer actually sees in the list.
    _notificationsSubscription = FirebaseFirestore.instance
        .collection('User')
        .doc(user.uid)
        .collection('user_notifications')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .listen(
          (snapshot) {
            unreadNotifications.value = snapshot.docs
                .where((doc) => doc.data()['read'] != true)
                .length;
          },
          onError: (error) {
            AppLogger.d('NavBadgeService: notifications error: $error');
          },
        );
  }

  /// Only for tests and a full sign-out teardown; the shell never disposes.
  void stop() {
    _authSubscription?.cancel();
    _authSubscription = null;
    _cartSubscription?.cancel();
    _cartSubscription = null;
    _notificationsSubscription?.cancel();
    _notificationsSubscription = null;
    cartCount.value = 0;
    unreadNotifications.value = 0;
    _started = false;
  }
}
