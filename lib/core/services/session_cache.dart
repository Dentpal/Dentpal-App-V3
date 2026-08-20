import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import 'package:dentpal/product/services/category_service.dart';
import 'package:dentpal/product/services/product_service.dart';
import 'package:dentpal/product/services/user_service.dart';
import 'package:dentpal/profile/services/order_service.dart';
import 'package:dentpal/utils/app_logger.dart';

/// Drops every per-account cache when the signed-in account changes.
///
/// The app caches reads in a handful of static holders so that returning to a
/// tab is free. All of them are scoped to one account, and sign-out happens in
/// eight different places — the login page, the auth wrapper, two signup steps,
/// the profile menu. Rather than remembering to clear caches at each of those,
/// this watches the one thing they all agree on: the auth state.
class SessionCache {
  SessionCache._();

  static StreamSubscription<User?>? _subscription;
  static String? _uid;
  static bool _started = false;

  /// Safe to call more than once; only the first call subscribes.
  static void start() {
    if (_started) return;
    _started = true;

    _uid = FirebaseAuth.instance.currentUser?.uid;
    _subscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user?.uid == _uid) return;
      AppLogger.d('SessionCache: account changed, clearing cached reads');
      _uid = user?.uid;
      clearAll();
    });
  }

  /// Clears everything cached against an account.
  ///
  /// Anything added to this list must be a *cache* — something that can be
  /// re-fetched — never the only copy of state.
  static void clearAll() {
    UserService.clearCache();
    CategoryService.clearCache();
    ProductService.clearCatalogueCache();
    OrderService.clearCache();
  }

  /// Only for tests.
  static void stop() {
    _subscription?.cancel();
    _subscription = null;
    _started = false;
  }
}
