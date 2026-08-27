import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:dentpal/utils/app_logger.dart';
import '../../core/app_theme/app_text_styles.dart';
import '../../core/app_theme/ink_palette.dart';

/// The hosted PayMongo payment page, wrapped in our chrome.
///
/// Only the frame around it belongs to us — the page inside is served by
/// PayMongo and is deliberately not ours to restyle, because it is what makes
/// the payment PCI-compliant. So the chrome does the one job it can: say
/// plainly whose page this is and that the connection is secure, since a
/// payment form inside another app's shell is exactly where a buyer should be
/// checking. Hence the lock and the live host, rather than decoration.
class PaymongoWebViewPage extends StatefulWidget {
  final String checkoutUrl;
  final String? successUrl;
  final String? cancelUrl;
  final Function(bool isSuccess, String? orderId) onPaymentComplete;

  const PaymongoWebViewPage({
    super.key,
    required this.checkoutUrl,
    this.successUrl,
    this.cancelUrl,
    required this.onPaymentComplete,
  });

  @override
  State<PaymongoWebViewPage> createState() => _PaymongoWebViewPageState();
}

class _PaymongoWebViewPageState extends State<PaymongoWebViewPage> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String _currentUrl = '';
  bool _hasCalledCallback = false;

  /// Drives the thin progress line under the header. The page inside can take
  /// several seconds on a slow connection, and a bare spinner over a blank
  /// screen gives no sense of whether anything is happening.
  int _loadProgress = 0;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.checkoutUrl;
    _initializeWebView();
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (!mounted) return;
            setState(() => _loadProgress = progress);
          },
          onPageStarted: (String url) {
            AppLogger.d('WebView page started loading: $url');
            setState(() {
              _isLoading = true;
              _currentUrl = url;
            });
            _checkUrlForCompletion(url);
          },
          onPageFinished: (String url) {
            AppLogger.d('WebView page finished loading: $url');
            setState(() {
              _isLoading = false;
              _currentUrl = url;
            });
            _checkUrlForCompletion(url);
          },
          onNavigationRequest: (NavigationRequest request) {
            AppLogger.d('WebView navigation request: ${request.url}');
            _checkUrlForCompletion(request.url);

            final uri = Uri.parse(request.url);
            // Allow normal http/https navigation inside WebView
            if (uri.scheme == 'http' || uri.scheme == 'https') {
              return NavigationDecision.navigate;
            }

            // For custom schemes (gcash://, maya://, etc.), launch externally
            _launchExternalUrl(request.url);
            return NavigationDecision.prevent;
          },
          onWebResourceError: (WebResourceError error) {
            AppLogger.d('WebView error: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.checkoutUrl));
  }

  void _checkUrlForCompletion(String url) {
    // Prevent multiple callbacks
    if (_hasCalledCallback) return;

    AppLogger.d('Checking URL for completion: $url');

    // Check for new success URL pattern (payment-success)
    if (url.contains('payment-success') || url.contains('payment_success')) {
      AppLogger.d('Payment success detected from payment-success URL');
      _handlePaymentSuccess(url);
      return;
    }

    // Check for new failure URL pattern (payment-failed)
    if (url.contains('payment-failed') || url.contains('payment_failed')) {
      AppLogger.d('Payment failure detected from payment-failed URL');
      _handlePaymentFailure(url);
      return;
    }

    // Check for success URL pattern (legacy)
    if (widget.successUrl != null && url.contains(widget.successUrl!)) {
      AppLogger.d('Payment success detected');
      _handlePaymentSuccess(url);
      return;
    }

    // Check for cancel URL pattern (legacy)
    if (widget.cancelUrl != null && url.contains(widget.cancelUrl!)) {
      AppLogger.d('Payment cancelled detected');
      _handlePaymentFailure(url);
      return;
    }

    // Check for common PayMongo success patterns
    if (url.contains('success') || url.contains('payment_intent_id') || url.contains('session_id')) {
      AppLogger.d('Payment success detected by pattern matching');
      _handlePaymentSuccess(url);
      return;
    }

    // Check for common PayMongo cancel/error patterns
    if (url.contains('cancel') || url.contains('error') || url.contains('failed')) {
      AppLogger.d('Payment failure detected by pattern matching');
      _handlePaymentFailure(url);
      return;
    }
  }

  void _handlePaymentSuccess(String url) {
    if (_hasCalledCallback) return;
    _hasCalledCallback = true;

    // Extract order ID or session ID from URL if present
    String? orderId;
    String? sessionId;
    final uri = Uri.parse(url);

    // Try to extract session_id or order_id from query parameters
    orderId = uri.queryParameters['order_id'];
    sessionId = uri.queryParameters['session_id'] ??
                uri.queryParameters['payment_intent_id'];

    AppLogger.d('Payment completed successfully. Order ID: $orderId, Session ID: $sessionId');

    // Close WebView and notify parent directly - no popup
    if (mounted) {
      Navigator.of(context).pop(); // Close WebView
      widget.onPaymentComplete(true, orderId);
    }
  }

  void _handlePaymentFailure(String url) {
    if (_hasCalledCallback) return;
    _hasCalledCallback = true;

    // Extract order ID or session ID from URL if present
    String? orderId;
    String? sessionId;
    String? errorMessage;
    final uri = Uri.parse(url);

    orderId = uri.queryParameters['order_id'];
    sessionId = uri.queryParameters['session_id'];
    errorMessage = uri.queryParameters['error'] ??
                   uri.queryParameters['message'] ??
                   'Payment was cancelled or failed';

    AppLogger.d('Payment failed. Order ID: $orderId, Session ID: $sessionId, Error: $errorMessage');

    // Close WebView and notify parent directly - no popup
    if (mounted) {
      Navigator.of(context).pop(); // Close WebView
      widget.onPaymentComplete(false, orderId);
    }
  }

  Future<void> _launchExternalUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      AppLogger.d('Failed to launch external URL: $url, error: $e');
    }
  }

  InkPalette get ink => InkPalette.of(context);

  Color get _danger =>
      ink.isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);

  void _handleBackPress() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ink.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _danger.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.warning_amber_rounded, color: _danger, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Cancel payment?',
                style: AppTextStyles.titleMedium.copyWith(
                  color: ink.text,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'Your order won\'t be paid for, and your items stay in your cart. '
          'You can start the payment again from checkout.',
          style: AppTextStyles.bodyMedium.copyWith(
            color: ink.text.withValues(alpha: 0.75),
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: ink.text.withValues(alpha: 0.7),
            ),
            child: Text('Keep paying', style: AppTextStyles.buttonMedium),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(); // Close WebView
              widget.onPaymentComplete(false, null);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _danger,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text('Cancel payment', style: AppTextStyles.buttonMedium),
          ),
        ],
      ),
    );
  }

  /// Host of whatever is currently loaded, and whether it arrived over TLS.
  (String host, bool secure) get _origin {
    final uri = Uri.tryParse(_currentUrl);
    if (uri == null || uri.host.isEmpty) return ('', false);
    return (uri.host, uri.scheme == 'https');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackPress();
      },
      child: Scaffold(
        backgroundColor: ink.bg,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: Stack(
                  children: [
                    WebViewWidget(controller: _controller),
                    if (_isLoading) _buildLoadingCover(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The chrome. Not [AppPageHeader]: this is the one screen in the flow whose
  /// body is someone else's, so it wears a compact browser bar — close, origin,
  /// progress — rather than the app's page title.
  Widget _buildHeader() {
    final (host, secure) = _origin;

    return Container(
      decoration: BoxDecoration(
        color: ink.surface,
        border: Border(bottom: BorderSide(color: ink.border)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
            child: Row(
              children: [
                IconButton(
                  onPressed: _handleBackPress,
                  icon: Icon(Icons.close, color: ink.text),
                  tooltip: 'Cancel payment',
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'PayMongo checkout',
                        style: AppTextStyles.titleMedium.copyWith(
                          color: ink.text,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (host.isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              secure ? Icons.lock : Icons.lock_open,
                              size: 11,
                              color: secure
                                  ? ink.emerald
                                  : ink.text.withValues(alpha: 0.5),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                host,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: ink.text.withValues(alpha: 0.55),
                                  fontSize: 11.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // A 2px determinate line rather than a spinner in the actions slot:
          // it says how far along the load is without taking a tap target.
          SizedBox(
            height: 2,
            child: _isLoading
                ? LinearProgressIndicator(
                    value: _loadProgress <= 0 ? null : _loadProgress / 100,
                    minHeight: 2,
                    backgroundColor: ink.border,
                    valueColor: AlwaysStoppedAnimation(ink.emerald),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingCover() {
    return Container(
      color: ink.bg,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: ink.emerald,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Opening secure payment page…',
              style: AppTextStyles.bodyMedium.copyWith(
                color: ink.text.withValues(alpha: 0.7),
                fontSize: 13.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
