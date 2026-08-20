import 'package:shared_preferences/shared_preferences.dart';

import 'package:dentpal/utils/app_logger.dart';

/// Which shell a signed-in account gets.
enum UserRole { buyer, seller, customerSupport }

/// Remembers the last resolved [UserRole] per account so the app can paint the
/// right shell on its first frame.
///
/// Resolving a role costs two Firestore reads, and the app used to block the
/// entire UI behind a bare centred spinner while they ran. The role of a given
/// account changes rarely (effectively never, between sessions), so the
/// last-known value is a safe thing to render immediately and reconcile behind.
/// It is only ever a *rendering* hint — every privileged action still checks
/// live state.
class RoleCache {
  RoleCache._();

  static const String _keyPrefix = 'dentpal:role:';

  /// Cached in memory too, so a tab switch never touches the disk.
  static final Map<String, UserRole> _memory = {};

  static UserRole? peek(String uid) => _memory[uid];

  static Future<UserRole?> load(String uid) async {
    final cached = _memory[uid];
    if (cached != null) return cached;

    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString('$_keyPrefix$uid');
      if (name == null) return null;

      final role = UserRole.values.where((r) => r.name == name).firstOrNull;
      if (role != null) _memory[uid] = role;
      return role;
    } catch (e) {
      AppLogger.d('RoleCache: load failed: $e');
      return null;
    }
  }

  static Future<void> save(String uid, UserRole role) async {
    _memory[uid] = role;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_keyPrefix$uid', role.name);
    } catch (e) {
      AppLogger.d('RoleCache: save failed: $e');
    }
  }

  static Future<void> clear(String uid) async {
    _memory.remove(uid);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_keyPrefix$uid');
    } catch (e) {
      AppLogger.d('RoleCache: clear failed: $e');
    }
  }
}
