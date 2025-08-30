import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Private constructor to prevent instantiation
  AppTheme._();

  // Create a custom theme with a Google font that supports the peso sign
  static ThemeData get lightTheme {
    // Noto Sans is well known for good Unicode support, including currency symbols
    final TextTheme textTheme = GoogleFonts.notoSansTextTheme();
    
    return ThemeData(
      primarySwatch: Colors.blue,
      textTheme: textTheme,
      // Apply the font to specific text styles that will be used for prices
      // This ensures the peso sign will display correctly
      typography: Typography.material2018(
        platform: TargetPlatform.android,
        englishLike: textTheme,
        dense: textTheme,
        tall: textTheme,
      ),
    );
  }

  // Alternative fonts that generally have good support for currency symbols:
  static ThemeData withRoboto() {
    return ThemeData(
      textTheme: GoogleFonts.robotoTextTheme(),
      primarySwatch: Colors.blue,
    );
  }

  static ThemeData withOpenSans() {
    return ThemeData(
      textTheme: GoogleFonts.openSansTextTheme(),
      primarySwatch: Colors.blue,
    );
  }

  static ThemeData withLato() {
    return ThemeData(
      textTheme: GoogleFonts.latoTextTheme(),
      primarySwatch: Colors.blue,
    );
  }
}
