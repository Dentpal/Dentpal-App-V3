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
            AppLogger.d('🌐 WebView page started loading: $url');
            setState(() {
              _isLoading = true;
              _currentUrl = url;
            });
            _checkUrlForCompletion(url);
          },
          onPageFinished: (String url) {
            AppLogger.d('🌐 WebView page finished loading: $url');
            setState(() {
              _isLoading = false;
              _currentUrl = url;
            });
            _checkUrlForCompletion(url);
          },
          onNavigationRequest: (NavigationRequest request) {
            AppLogger.d('🌐 WebView navigation request: ${request.url}');
            _checkUrlForCompletion(request.url);
            return NavigationDecision.navigate;
          },
          onWebResourceError: (WebResourceError error) {
            AppLogger.d('❌ WebView error: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.checkoutUrl));
  }

  void _checkUrlForCompletion(String url) {
    // Prevent multiple callbacks
    if (_hasCalledCallback) return;

    AppLogger.d('🔍 Checking URL for completion: $url');

    // Check for success URL pattern
    if (widget.successUrl != null && url.contains(widget.successUrl!)) {
      AppLogger.d('✅ Payment success detected');
      _handlePaymentSuccess(url);
      return;
    }

    // Check for cancel URL pattern
    if (widget.cancelUrl != null && url.contains(widget.cancelUrl!)) {
      AppLogger.d('❌ Payment cancelled detected');
      _handlePaymentCancel();
      return;
    }

    // Check for common PayMongo success patterns
    if (url.contains('success') || url.contains('payment_intent_id') || url.contains('session_id')) {
      AppLogger.d('✅ Payment success detected by pattern matching');
      _handlePaymentSuccess(url);
      return;
    }

    // Check for common PayMongo cancel/error patterns
    if (url.contains('cancel') || url.contains('error') || url.contains('failed')) {
      AppLogger.d('❌ Payment failure detected by pattern matching');
      _handlePaymentCancel();
      return;
    }
  }

  void _handlePaymentSuccess(String url) {
    if (_hasCalledCallback) return;
    _hasCalledCallback = true;

    // Extract order ID or session ID from URL if present
    String? orderId;
    final uri = Uri.parse(url);
    
    // Try to extract session_id or order_id from query parameters
    orderId = uri.queryParameters['session_id'] ?? 
              uri.queryParameters['order_id'] ?? 
              uri.queryParameters['payment_intent_id'];

    AppLogger.d('✅ Payment completed successfully. Order ID: $orderId');
    
    // Show success message briefly before closing
    if (mounted) {
      _showCompletionDialog(
        title: 'Payment Successful!',
        message: 'Your payment has been processed successfully.',
        isSuccess: true,
        orderId: orderId,
      );
    }
  }

  void _handlePaymentCancel() {
    if (_hasCalledCallback) return;
    _hasCalledCallback = true;

    AppLogger.d('❌ Payment was cancelled');
    
    // Show cancel message briefly before closing
    if (mounted) {
      _showCompletionDialog(
        title: 'Payment Cancelled',
        message: 'Your payment was cancelled. You can try again if needed.',
        isSuccess: false,
        orderId: null,
      );
    }
  }

  void _showCompletionDialog({
    required String title,
    required String message,
    required bool isSuccess,
    String? orderId,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSuccess 
                    ? AppColors.success.withValues(alpha: 0.1)
                    : AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isSuccess ? Icons.check_circle : Icons.cancel,
                color: isSuccess ? AppColors.success : AppColors.warning,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.onSurface.withValues(alpha: 0.8),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(); // Close webview page
              widget.onPaymentComplete(isSuccess, orderId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isSuccess ? AppColors.success : AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              elevation: 0,
            ),
            child: Text('Continue', style: AppTextStyles.buttonMedium),
          ),
        ],
      ),
    );
  }

  void _handleBackPress() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.warning_outlined,
                color: AppColors.warning,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Cancel Payment?',
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to cancel the payment process? Your order will not be completed.',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.onSurface.withValues(alpha: 0.8),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.onSurface.withValues(alpha: 0.6),
            ),
            child: Text('Continue Payment', style: AppTextStyles.buttonMedium),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(); // Close webview page
              widget.onPaymentComplete(false, null);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: AppColors.onPrimary,
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
        if (!didPop) {
          _handleBackPress();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: AppColors.surface,
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
                    color: AppColors.onSurface.withValues(alpha: 0.6),
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
                      CircularProgressIndicator(color: AppColors.primary),
                      SizedBox(height: 16),
                      Text(
                        'Loading payment page...',
                        style: AppTextStyles.bodyMedium,
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
