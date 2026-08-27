import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dentpal/utils/app_logger.dart';
import '../../core/app_theme/app_text_styles.dart';
import '../../core/app_theme/ink_palette.dart';
import '../../core/app_theme/theme_utils.dart';
import '../../core/widgets/app_page_header.dart';
import '../../core/widgets/app_shell.dart';
import 'cart_page.dart';

/// The other ending: a payment that was cancelled, declined or timed out.
///
/// Reached at `/cart/checkout/fail`. Deliberately the calm twin of the success
/// page rather than an alarm — nothing has gone wrong with the buyer's account,
/// the order simply was not paid for, and the useful thing to do is try again.
/// The previous version shook a red circle on an endless repeating animation,
/// which read as a fault report for what is usually just a cancelled payment.
class PaymentFailedPage extends StatefulWidget {
  final String? sessionId;
  final String? orderId;
  final String? errorMessage;

  const PaymentFailedPage({
    super.key,
    this.sessionId,
    this.orderId,
    this.errorMessage,
  });

  @override
  State<PaymentFailedPage> createState() => _PaymentFailedPageState();
}

class _PaymentFailedPageState extends State<PaymentFailedPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _markScale;
  late final Animation<double> _fade;
  late final Animation<Offset> _rise;

  Timer? _redirectTimer;
  int _countdown = 10;
  bool _isRedirecting = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );

    _markScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.6, curve: Curves.easeOutBack),
      ),
    );

    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    _rise = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 1, curve: Curves.easeOutCubic),
      ),
    );

    _controller.forward();
    _startCountdown();

    AppLogger.d(
      'Payment Failed Page loaded with sessionId: ${widget.sessionId}, '
      'orderId: ${widget.orderId}',
    );
  }

  /// Longer than the success page's: there is a decision to make here, and
  /// being bounced away mid-read is worse than waiting a moment more.
  void _startCountdown() {
    _redirectTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdown <= 1) {
        timer.cancel();
        _redirectToCart();
        return;
      }
      setState(() => _countdown--);
    });
  }

  void _redirectToCart() {
    if (_isRedirecting) return;
    setState(() => _isRedirecting = true);
    _redirectTimer?.cancel();

    AppLogger.d('Returning to cart after a failed payment');

    // Back into the shell on the Cart tab — this page is pushed on top of it,
    // so the way back is to pop, not to build a second cart outside the
    // navigation bar.
    final shell = AppShell.instance;
    if (shell != null) {
      shell.openTab(ShellTab.cart);
      return;
    }

    // No shell — a cold load of the legacy /payment-failed route. A standalone
    // cart is the only thing left to offer.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const CartPage()),
      (route) => false,
    );
  }

  /// "Try again" means the cart, not a bare checkout route: checkout needs the
  /// selected items and vouchers handed to it, and only the cart has those.
  /// The old version pushed a named '/checkout' route that does not exist, so
  /// the app fell through to its unknown-route handler and landed the buyer on
  /// the auth wrapper.
  void _retryPayment() {
    AppLogger.d('Retrying payment — returning to cart to re-enter checkout');
    _redirectToCart();
  }

  @override
  void dispose() {
    _controller.dispose();
    _redirectTimer?.cancel();
    super.dispose();
  }

  InkPalette get ink => InkPalette.of(context);

  /// [InkPalette] reserves amber for urgency, so danger carries its own tone.
  Color get _danger =>
      ink.isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ink.bg,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppLayout.maxContentWidth,
            ),
            child: Column(
              children: [
                AppPageHeader(
                  title: 'Payment not completed',
                  subtitle: 'Nothing has been charged',
                  showBack: false,
                ),
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppLayout.gutter,
        8,
        AppLayout.gutter,
        28,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _rise,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  _buildMark(),
                  const SizedBox(height: 24),
                  Text(
                    'Payment wasn\'t completed',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.headlineSmall.copyWith(
                      color: ink.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 24,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.errorMessage ??
                        'The payment was cancelled or couldn\'t be processed. '
                            'Your items are still in your cart — you can try '
                            'again with the same or a different payment method.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: ink.text.withValues(alpha: 0.65),
                      fontSize: 13.5,
                      height: 1.5,
                    ),
                  ),
                  if (widget.sessionId != null || widget.orderId != null) ...[
                    const SizedBox(height: 24),
                    _buildDetailsCard(),
                  ],
                  const SizedBox(height: 24),
                  _buildActions(),
                  const SizedBox(height: 12),
                  _buildCountdownNote(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMark() {
    return ScaleTransition(
      scale: _markScale,
      child: Center(
        child: Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _danger.withValues(alpha: ink.isDark ? 0.16 : 0.1),
            border: Border.all(
              color: _danger.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Icon(Icons.close_rounded, size: 44, color: _danger),
        ),
      ),
    );
  }

  Widget _buildDetailsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: ink.text.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 8),
              Text(
                'Transaction details',
                style: AppTextStyles.titleMedium.copyWith(
                  color: ink.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (widget.orderId != null) _detailRow('Order ID', widget.orderId!),
          if (widget.sessionId != null) ...[
            if (widget.orderId != null) const SizedBox(height: 10),
            _detailRow('Reference', widget.sessionId!),
          ],
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.bodyMedium.copyWith(
            color: ink.text.withValues(alpha: 0.6),
            fontSize: 13,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: AppTextStyles.bodySmall.copyWith(
              color: ink.text,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              fontSize: 12.5,
            ),
          ),
        ),
      ],
    );
  }

  /// Stacked rather than side by side: at 480px two buttons sharing a row put
  /// "Back to cart" and "Try again" a thumb's width apart, and one of them
  /// re-opens a payment.
  Widget _buildActions() {
    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _isRedirecting ? null : _retryPayment,
            style: ElevatedButton.styleFrom(
              backgroundColor: ink.emerald,
              foregroundColor: ink.onEmerald,
              disabledBackgroundColor: ink.surfaceHigh,
              disabledForegroundColor: ink.text.withValues(alpha: 0.38),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.refresh, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Try again',
                  style: AppTextStyles.buttonLarge.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 48,
          child: OutlinedButton(
            onPressed: _isRedirecting ? null : _redirectToCart,
            style: OutlinedButton.styleFrom(
              foregroundColor: ink.text.withValues(alpha: 0.8),
              side: BorderSide(color: ink.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.shopping_cart_outlined, size: 17),
                const SizedBox(width: 8),
                Text(
                  'Back to cart',
                  style: AppTextStyles.buttonMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCountdownNote() {
    return Text(
      _isRedirecting
          ? 'Taking you back…'
          : 'Returning to your cart in $_countdown second'
              '${_countdown == 1 ? '' : 's'}',
      textAlign: TextAlign.center,
      style: AppTextStyles.bodySmall.copyWith(
        color: ink.text.withValues(alpha: 0.45),
        fontSize: 12,
      ),
    );
  }
}
