import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// A specialized widget for displaying currency values with proper peso sign support.
class CurrencyText extends StatelessWidget {
  final double amount;
  final TextStyle? style;
  final TextAlign textAlign;
  final int? maxLines;
  final TextOverflow overflow;
  
  // Static NumberFormat instance shared across all CurrencyText widgets
  static final _formatCurrency = NumberFormat.currency(
    locale: "en_PH", 
    symbol: "₱",
  );

  const CurrencyText({
    super.key,
    required this.amount,
    this.style,
    this.textAlign = TextAlign.start,
    this.maxLines,
    this.overflow = TextOverflow.clip,
  });

  @override
  Widget build(BuildContext context) {
    // Base style merged with user-provided style
    final TextStyle baseStyle = GoogleFonts.notoSans(
      fontWeight: FontWeight.normal,
      fontSize: 14.0,
    ).merge(style);
    
    return Text(
      _formatCurrency.format(amount),
      style: baseStyle,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
