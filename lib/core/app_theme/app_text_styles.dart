import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Typography styles for DentPal app
class AppTextStyles {
  AppTextStyles._();

  // Font families
  static const String primaryFont = 'Poppins';
  static const String secondaryFont = 'Roboto';

  // Headlines
  static const TextStyle headlineLarge = TextStyle(
    fontFamily: secondaryFont,
    fontWeight: FontWeight.w900,
    fontSize: 32,
    height: 1.2,
    letterSpacing: -0.5,
    color: AppColors.onBackground,
  );

  static const TextStyle headlineMedium = TextStyle(
    fontFamily: secondaryFont,
    fontWeight: FontWeight.w900,
    fontSize: 24,
    height: 1.3,
    letterSpacing: -0.25,
    color: AppColors.onBackground,
  );

  static const TextStyle headlineSmall = TextStyle(
    fontFamily: secondaryFont,
    fontWeight: FontWeight.w700,
    fontSize: 20,
    height: 1.3,
    letterSpacing: 0,
    color: AppColors.onBackground,
  );

  // Titles
  static const TextStyle titleLarge = TextStyle(
    fontFamily: primaryFont,
    fontWeight: FontWeight.w600,
    fontSize: 18,
    height: 1.4,
    letterSpacing: 0,
    color: AppColors.onBackground,
  );

  static const TextStyle titleMedium = TextStyle(
    fontFamily: primaryFont,
    fontWeight: FontWeight.w600,
    fontSize: 16,
    height: 1.4,
    letterSpacing: 0.15,
    color: AppColors.onBackground,
  );

  static const TextStyle titleSmall = TextStyle(
    fontFamily: primaryFont,
    fontWeight: FontWeight.w600,
    fontSize: 14,
    height: 1.4,
    letterSpacing: 0.1,
    color: AppColors.onBackground,
  );

  // Labels
  static const TextStyle labelLarge = TextStyle(
    fontFamily: primaryFont,
    fontWeight: FontWeight.w500,
    fontSize: 14,
    height: 1.4,
    letterSpacing: 0.1,
    color: AppColors.onBackground,
  );

  static const TextStyle labelMedium = TextStyle(
    fontFamily: primaryFont,
    fontWeight: FontWeight.w500,
    fontSize: 12,
    height: 1.3,
    letterSpacing: 0.5,
    color: AppColors.onBackground,
  );

  static const TextStyle labelSmall = TextStyle(
    fontFamily: primaryFont,
    fontWeight: FontWeight.w500,
    fontSize: 11,
    height: 1.4,
    letterSpacing: 0.5,
    color: AppColors.onBackground,
  );

  // Body text
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: primaryFont,
    fontWeight: FontWeight.w400,
    fontSize: 16,
    height: 1.5,
    letterSpacing: 0.15,
    color: AppColors.onBackground,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: primaryFont,
    fontWeight: FontWeight.w400,
    fontSize: 14,
    height: 1.4,
    letterSpacing: 0.25,
    color: AppColors.onBackground,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: primaryFont,
    fontWeight: FontWeight.w400,
    fontSize: 12,
    height: 1.3,
    letterSpacing: 0.4,
    color: AppColors.onSurfaceVariant,
  );

  // Button text styles
  static const TextStyle buttonLarge = TextStyle(
    fontFamily: primaryFont,
    fontWeight: FontWeight.w600,
    fontSize: 16,
    height: 1.2,
    letterSpacing: 0.5,
  );

  static const TextStyle buttonMedium = TextStyle(
    fontFamily: primaryFont,
    fontWeight: FontWeight.w600,
    fontSize: 14,
    height: 1.2,
    letterSpacing: 0.5,
  );

  static const TextStyle buttonSmall = TextStyle(
    fontFamily: primaryFont,
    fontWeight: FontWeight.w500,
    fontSize: 12,
    height: 1.2,
    letterSpacing: 0.5,
  );

  // Input text styles
  static const TextStyle inputText = TextStyle(
    fontFamily: primaryFont,
    fontWeight: FontWeight.w400,
    fontSize: 16,
    height: 1.5,
    letterSpacing: 0.15,
    color: AppColors.onSurface,
  );

  static const TextStyle inputLabel = TextStyle(
    fontFamily: primaryFont,
    fontWeight: FontWeight.w500,
    fontSize: 14,
    height: 1.4,
    letterSpacing: 0.1,
    color: AppColors.onSurfaceVariant,
  );

  static const TextStyle inputHint = TextStyle(
    fontFamily: primaryFont,
    fontWeight: FontWeight.w400,
    fontSize: 16,
    height: 1.5,
    letterSpacing: 0.15,
    color: AppColors.grey400,
  );
}
