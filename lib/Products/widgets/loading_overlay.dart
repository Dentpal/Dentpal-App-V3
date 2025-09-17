import 'package:flutter/material.dart';

class LoadingOverlay extends StatelessWidget {
  final String message;
  final bool isVisible;
  final Color? backgroundColor;
  final Color? textColor;
  final Color? progressColor;
  final VoidCallback? onCancel;
  final bool showCancelButton;

  const LoadingOverlay({
    super.key,
    required this.message,
    required this.isVisible,
    this.backgroundColor,
    this.textColor,
    this.progressColor,
    this.onCancel,
    this.showCancelButton = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();

    return Container(
      color: backgroundColor ?? Colors.black.withValues(alpha: 0.5),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(
                progressColor ?? Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                color: textColor ?? Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            if (showCancelButton && onCancel != null) ...[
              const SizedBox(height: 20),
              TextButton(
                onPressed: onCancel,
                style: TextButton.styleFrom(
                  foregroundColor: textColor ?? Colors.white,
                  side: BorderSide(color: textColor ?? Colors.white),
                ),
                child: const Text('Cancel'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class LoadingButton extends StatelessWidget {
  final String text;
  final String loadingText;
  final bool isLoading;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry? padding;
  final TextStyle? textStyle;

  const LoadingButton({
    super.key,
    required this.text,
    required this.loadingText,
    required this.isLoading,
    this.onPressed,
    this.padding,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        padding: padding ?? const EdgeInsets.symmetric(vertical: 12),
      ),
      child: isLoading
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  loadingText,
                  style: textStyle ?? const TextStyle(fontSize: 16),
                ),
              ],
            )
          : Text(
              text,
              style: textStyle ?? const TextStyle(fontSize: 16),
            ),
    );
  }
}
