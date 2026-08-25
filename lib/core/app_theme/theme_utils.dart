import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Theme utility extension for easy access to theme properties
extension ThemeExtension on BuildContext {
  /// Get current color scheme
  ColorScheme get colors => Theme.of(this).colorScheme;

  /// Get current text theme
  TextTheme get textTheme => Theme.of(this).textTheme;

  /// Common paddings
  EdgeInsets get paddingAll8 => const EdgeInsets.all(8);
  EdgeInsets get paddingAll16 => const EdgeInsets.all(16);
  EdgeInsets get paddingAll24 => const EdgeInsets.all(24);

  EdgeInsets get paddingH16 => const EdgeInsets.symmetric(horizontal: 16);
  EdgeInsets get paddingH24 => const EdgeInsets.symmetric(horizontal: 24);
  EdgeInsets get paddingV8 => const EdgeInsets.symmetric(vertical: 8);
  EdgeInsets get paddingV16 => const EdgeInsets.symmetric(vertical: 16);

  /// Common border radius
  BorderRadius get borderRadius8 => BorderRadius.circular(8);
  BorderRadius get borderRadius12 => BorderRadius.circular(12);
  BorderRadius get borderRadius16 => BorderRadius.circular(16);
  BorderRadius get borderRadius24 => BorderRadius.circular(24);

  /// Screen dimensions
  Size get screenSize => MediaQuery.of(this).size;
  double get screenWidth => screenSize.width;
  double get screenHeight => screenSize.height;

  /// Check if screen is considered small (width < 600)
  bool get isSmallScreen => screenWidth < 600;

  /// Check if screen is considered large (width >= 1200)
  bool get isLargeScreen => screenWidth >= 1200;

  /// Whether the app shell shows its side rail rather than the bottom tab bar.
  ///
  /// The single source of truth for that switch. Pages used to each pick their
  /// own threshold (800, 900, 1024, 1200), so between 900 and 1024 the shell
  /// believed it was on desktop while Cart still laid itself out for a phone.
  bool get isWideLayout => screenWidth >= Breakpoints.wide;
}

/// The page frame every buyer surface is laid out in.
///
/// These used to be per-page constants, and they had drifted: Browse centred at
/// 1200 with a 32px gutter, Cart at 1100/16, Orders at 1000/32, Notifications at
/// 760/16 — so the left edge of the content jumped every time you changed tab.
class AppLayout {
  AppLayout._();

  /// Widest the content grows to before it centres in the window.
  static const double maxContentWidth = 1100;

  /// Space between the content and the edge of that column.
  static const double gutter = 16;
}

/// Layout breakpoints, in logical pixels.
class Breakpoints {
  Breakpoints._();

  /// Rail-vs-bottom-bar threshold. Deliberately a width test rather than
  /// [kIsWeb]: a tablet held in landscape wants the rail just as much as a
  /// browser does.
  static const double wide = 900;
}

/// Common app gradients
class AppGradients {
  AppGradients._();

  static const LinearGradient primary = LinearGradient(
    colors: [AppColors.primary, AppColors.primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient secondary = LinearGradient(
    colors: [AppColors.secondary, AppColors.secondaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient teal = LinearGradient(
    colors: [Color.fromRGBO(138, 216, 196, 1), Color.fromRGBO(43, 129, 110, 1)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accent = LinearGradient(
    colors: [AppColors.accent, Color(0xFFFF8C42)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Common app shadows
class AppShadows {
  AppShadows._();

  static const List<BoxShadow> light = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 2)),
  ];

  static const List<BoxShadow> medium = [
    BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 4)),
  ];

  static const List<BoxShadow> strong = [
    BoxShadow(color: Color(0x1F000000), blurRadius: 16, offset: Offset(0, 8)),
  ];
}
