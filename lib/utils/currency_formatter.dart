import 'package:intl/intl.dart';

/// Utility class for formatting currency values consistently across the app.
class CurrencyFormatter {
  /// NumberFormat instance for Philippine Peso with thousand separators
  static final NumberFormat _formatter = NumberFormat('#,##0.00', 'en_PH');

  /// Formats a price value with thousand separators.
  /// Example: 1000.00 -> "1,000.00"
  /// Example: 15000.50 -> "15,000.50"
  static String format(double value) {
    return _formatter.format(value);
  }

  /// Formats a price value with peso sign prefix.
  /// Example: 1000.00 -> "₱1,000.00"
  /// Example: 15000.50 -> "₱15,000.50"
  static String formatWithPeso(double value) {
    return '₱${_formatter.format(value)}';
  }

  /// Formats a nullable price value with peso sign prefix.
  /// Returns null if the value is null.
  static String? formatWithPesoOrNull(double? value) {
    if (value == null) return null;
    return '₱${_formatter.format(value)}';
  }
}
