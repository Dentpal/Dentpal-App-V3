import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/app_theme/app_colors.dart';
import '../../core/app_theme/app_text_styles.dart';

/// Embeds Lalamove's live rider-tracking page (the booking `shareLink`) inside
/// the order screen. Lalamove's page renders the moving driver, the road route,
/// and ETA in real time — so there's no polling or extra API cost on our side.
///
/// On web, `webview_flutter` isn't supported, so we fall back to a button that
/// opens the same live-tracking page in a new tab.
class LalamoveTrackingMap extends StatefulWidget {
  final String shareLink;
  final double height;

  const LalamoveTrackingMap({
    super.key,
    required this.shareLink,
    this.height = 320,
  });

  @override
  State<LalamoveTrackingMap> createState() => _LalamoveTrackingMapState();
}

class _LalamoveTrackingMapState extends State<LalamoveTrackingMap> {
  WebViewController? _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) _initController();
  }

  void _initController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.shareLink));
  }

  @override
  void didUpdateWidget(covariant LalamoveTrackingMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload only when the tracking link actually changes, so live status
    // updates on the parent don't keep resetting the map.
    if (!kIsWeb && widget.shareLink != oldWidget.shareLink) {
      _controller?.loadRequest(Uri.parse(widget.shareLink));
    }
  }

  Future<void> _openExternally() async {
    final uri = Uri.tryParse(widget.shareLink);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || _controller == null) {
      return _WebFallback(onOpen: _openExternally);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            WebViewWidget(
              controller: _controller!,
              // Let the map pan/zoom without the surrounding scroll view
              // stealing the drag gestures.
              gestureRecognizers: {
                Factory<OneSequenceGestureRecognizer>(
                  () => EagerGestureRecognizer(),
                ),
              },
            ),
            if (_isLoading)
              Container(
                color: AppColors.surface,
                alignment: Alignment.center,
                child: const CircularProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shown on web (no in-app WebView): a card that opens the live map in a new tab.
class _WebFallback extends StatelessWidget {
  final VoidCallback onOpen;
  const _WebFallback({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, color: AppColors.primary, size: 28),
            const SizedBox(height: 8),
            Text(
              'Open live rider map',
              style: AppTextStyles.buttonMedium.copyWith(color: AppColors.primary),
            ),
            const SizedBox(height: 2),
            Text(
              'Tracks the driver location & route',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
