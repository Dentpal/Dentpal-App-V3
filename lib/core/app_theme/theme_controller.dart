import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The appearance the user has chosen: follow the device, or force one.
///
/// [InkPalette] reads this rather than the platform brightness alone, so
/// "Light" holds even on a phone in dark mode. Kept as a [ValueNotifier] so the
/// app can rebuild on a change; the choice is remembered across launches.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController._() : super(ThemeMode.system);

  static final ThemeController instance = ThemeController._();

  static const String _storageKey = 'appearance_mode';

  /// Restores the saved choice. Call once, before `runApp`, so the first frame
  /// is already in the right appearance rather than flashing the wrong one.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      value = _decode(prefs.getString(_storageKey));
    } catch (e) {
      // A missing or unreadable store is not worth failing a launch over: the
      // device setting is a perfectly good default.
      debugPrint('Could not read the saved appearance: $e');
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == value) return;
    value = mode;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, _encode(mode));
    } catch (e) {
      debugPrint('Could not save the appearance: $e');
    }
  }

  /// Whether dark surfaces should be used, given the device's own setting.
  bool isDark(Brightness platformBrightness) => switch (value) {
    ThemeMode.dark => true,
    ThemeMode.light => false,
    ThemeMode.system => platformBrightness == Brightness.dark,
  };

  static String _encode(ThemeMode mode) => switch (mode) {
    ThemeMode.dark => 'dark',
    ThemeMode.light => 'light',
    ThemeMode.system => 'system',
  };

  static ThemeMode _decode(String? raw) => switch (raw) {
    'dark' => ThemeMode.dark,
    'light' => ThemeMode.light,
    _ => ThemeMode.system,
  };
}

/// Publishes the appearance choice *into the widget tree*.
///
/// Without this, changing the mode updated the controller and nothing else:
/// [InkPalette.of] read a plain static, so pages already on screen had no
/// dependency to invalidate and kept their old colours until something else
/// rebuilt them — which is why only "Auto" plus an OS flip appeared to work
/// (that path goes through [MediaQuery], which *is* inherited).
///
/// Sits above `MaterialApp`, so every route below it is a dependent.
class AppearanceScope extends InheritedNotifier<ThemeController> {
  const AppearanceScope({
    super.key,
    required ThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The chosen mode, registering the caller for a rebuild when it changes.
  ///
  /// Falls back to the singleton for trees that have no scope — a widget test
  /// pumping a page on its own, or a dialog in a detached overlay.
  static ThemeMode modeOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppearanceScope>();
    return scope?.notifier?.value ?? ThemeController.instance.value;
  }
}
