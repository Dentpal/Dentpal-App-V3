import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:dentpal/utils/app_logger.dart';
import '../../core/app_theme/app_colors.dart';
import '../../core/app_theme/app_text_styles.dart';

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

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
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
            return NavigationDecision.navigate;
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

  void _handleBackPress() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Cancel Payment',
          style: AppTextStyles.titleMedium.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Are you sure you want to cancel this payment? Your order will not be processed.',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.onSurface.withValues(alpha:0.8),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Continue Payment', style: AppTextStyles.buttonMedium),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(); // Close WebView
              widget.onPaymentComplete(false, null);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: Text('Cancel Payment', style: AppTextStyles.buttonMedium),
          ),
        ],
      ),
    );
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
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          leading: IconButton(
            onPressed: _handleBackPress,
            icon: const Icon(Icons.close, color: AppColors.onSurface),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PayMongo Checkout',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_currentUrl.isNotEmpty)
                Text(
                  Uri.parse(_currentUrl).host,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.onSurface.withValues(alpha:0.6),
                  ),
                ),
            ],
          ),
          actions: [
            if (_isLoading)
              Container(
                margin: const EdgeInsets.only(right: 16),
                child: const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                ),
              ),
          ],
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_isLoading)
              Container(
                color: AppColors.surface,
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 3,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Loading payment page...',
                        style: TextStyle(
                          color: AppColors.onSurface,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
