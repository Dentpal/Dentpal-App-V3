import 'package:flutter/material.dart';

import 'theme_controller.dart';

/// Palette for the marketplace surfaces, resolved against the appearance the
/// user has chosen (Profile → Appearance), or the device's setting under
/// "Auto".
///
/// These screens follow the DentPal marketplace design: one emerald brand
/// colour, amber reserved strictly for urgency (deal timers, alerts), and a
/// ground that flips between paper and near-black. It resolves the brightness
/// itself rather than reading [Theme.of], because `AppTheme.darkTheme` is still
/// the light theme — the screens that have been redesigned carry their own dark
/// surfaces, the rest are still hardcoded light. Fold this into [AppTheme] once
/// the app ships a real dark theme.
class InkPalette {
  const InkPalette({
    required this.isDark,
    required this.bg,
    required this.surface,
    required this.surfaceHigh,
    required this.border,
    required this.text,
    required this.emerald,
    required this.emeraldSoft,
    required this.onEmerald,
    required this.amber,
    required this.onAmber,
    required this.heroCard,
    required this.productBackdrop,
  });

  final bool isDark;

  /// Page ground.
  final Color bg;

  /// Raised card surface, and a step above it for nested blocks and chips.
  final Color surface;
  final Color surfaceHigh;

  /// Hairline separating cards from the ground.
  final Color border;

  /// Primary ink. Muted variants come from `.withValues(alpha:)` on this, so in
  /// dark mode it has to be the lightest tone rather than a mid grey.
  final Color text;

  /// Brand green, and the teal it pairs with.
  final Color emerald;
  final Color emeraldSoft;

  /// Ink to sit *on* a filled emerald surface, and on a filled amber one.
  final Color onEmerald;
  final Color amber;
  final Color onAmber;

  /// Surface for cards that sit inside the emerald hero, which is dark in both
  /// modes — so this is the one tone that does not simply follow [surface].
  final Color heroCard;

  /// Pedestal behind product photography. Shots are cut out on white and would
  /// otherwise float on the card.
  final RadialGradient productBackdrop;

  /// The hero keeps its emerald gradient in both modes; white text sits on it
  /// either way, so only the surfaces around it flip.
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2F6F53), Color(0xFF1B4B39), Color(0xFF123528)],
  );

  static const InkPalette _light = InkPalette(
    isDark: false,
    bg: Color(0xFFF4F7F5),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFEFF3F0),
    border: Color(0xFFDDE5E0),
    text: Color(0xFF10201B),
    emerald: Color(0xFF059669),
    emeraldSoft: Color(0xFF0D9488),
    onEmerald: Color(0xFFFFFFFF),
    amber: Color(0xFFD97706),
    onAmber: Color(0xFFFFFFFF),
    heroCard: Color(0xFFFFFFFF),
    productBackdrop: RadialGradient(
      center: Alignment.center,
      radius: 0.9,
      colors: [Color(0xFFFFFFFF), Color(0xFFEFF3F0)],
    ),
  );

  static const InkPalette _dark = InkPalette(
    isDark: true,
    bg: Color(0xFF0A0F0D),
    surface: Color(0xFF121A17),
    surfaceHigh: Color(0xFF18221E),
    border: Color(0xFF23302B),
    text: Color(0xFFEAF1EE),
    emerald: Color(0xFF34D399),
    emeraldSoft: Color(0xFF2DD4BF),
    onEmerald: Color(0xFF06251C),
    amber: Color(0xFFFBBF24),
    onAmber: Color(0xFF06251C),
    heroCard: Color(0xFF0B120F),
    productBackdrop: RadialGradient(
      center: Alignment.center,
      radius: 0.9,
      colors: [Color(0xFF2A3833), Color(0xFF141C19)],
    ),
  );

  /// The palette for a surface that is dark whatever the user chose.
  ///
  /// A camera viewfinder is the case this exists for: you cannot tint a live
  /// video feed to match a light appearance, so the chrome over it is always
  /// dark and its accents have to be the tones that read on black. Taking them
  /// from here rather than writing the hex codes into the page keeps one
  /// definition of the brand green.
  static const InkPalette onDarkSurface = _dark;

  /// Follows the user's [ThemeController] choice, falling back to the OS
  /// setting when that choice is "Auto".
  ///
  /// The OS path reads [MediaQuery], so it rebuilds when the device flips; an
  /// explicit Light/Dark choice rebuilds the app from the notifier instead.
  static InkPalette of(BuildContext context) {
    final mode = AppearanceScope.modeOf(context);
    final dark = mode == ThemeMode.system
        ? MediaQuery.platformBrightnessOf(context) == Brightness.dark
        : mode == ThemeMode.dark;
    return dark ? _dark : _light;
  }
}
