import 'package:flutter/material.dart';

/// App color constants for DentPal
class AppColors {
  AppColors._();

  // Primary Colors
  static const Color primary = Color(0xFF43A047);
  static const Color primaryLight = Color(0xFF71D374);
  static const Color primaryDark = Color(0xFF2E7D32);

  // Secondary Colors (Teal gradient)
  static const Color secondary = Color(0xFF2DD4BF);
  static const Color secondaryLight = Color(0xFF06B6D4);
  static const Color secondaryDark = Color(0xFF0891B2);

  // Background Colors
  static const Color background = Color(0xFFFAFAFA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF8F8F8);

  // Text Colors
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color onBackground = Color(0xFF333333);
  static const Color onSurface = Color(0xFF333333);
  static const Color onSurfaceVariant = Color(0xFF666666);

  // Accent Colors
  static const Color accent = Color(0xFFFF6B35);
  static const Color error = Color(0xFFE53E3E);
  static const Color warning = Color(0xFFFF8C00);
  static const Color success = Color(0xFF38A169);
  static const Color info = Color(0xFF3182CE);

  // Neutral Colors
  static const Color grey50 = Color(0xFFFAFAFA);
  static const Color grey100 = Color(0xFFF5F5F5);
  static const Color grey200 = Color(0xFFE5E5E5);
  static const Color grey300 = Color(0xFFD4D4D4);
  static const Color grey400 = Color(0xFFA3A3A3);
  static const Color grey500 = Color(0xFF737373);
  static const Color grey600 = Color(0xFF525252);
  static const Color grey700 = Color(0xFF404040);
  static const Color grey800 = Color(0xFF262626);
  static const Color grey900 = Color(0xFF171717);

  // Gradient Colors
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient secondaryGradient = LinearGradient(
    colors: [secondary, secondaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient tealGradient = LinearGradient(
    colors: [
      Color.fromRGBO(45, 212, 191, 1),
      Color.fromRGBO(6, 182, 212, 1),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
