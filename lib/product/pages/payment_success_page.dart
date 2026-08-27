import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dentpal/utils/app_logger.dart';
import 'package:dentpal/utils/currency_formatter.dart';
import '../../core/app_theme/app_text_styles.dart';
import '../../core/app_theme/ink_palette.dart';
import '../../core/app_theme/theme_utils.dart';
import '../../core/widgets/app_page_header.dart';
import '../../core/widgets/app_shell.dart';
import 'cart_page.dart';

/// The receipt: what a placed order looks like the moment it exists.
///
/// Reached at `/cart/checkout/success`, by three different roads — a completed
/// PayMongo payment in the in-app WebView, a Cash on Delivery order (which is
/// placed outright, with no payment page to visit), and the browser redirect
/// the provider sends after a payment on the web. It therefore has to stand up
/// with nothing but an order id, and often not even that.
class PaymentSuccessPage extends StatefulWidget {
  final String? orderId;
  final String? sessionId;

  /// Charged total, when the caller knows it. The COD path does; the payment
  /// redirect does not, and the row is simply left out rather than guessed.
  final double? totalAmount;

  /// A Cash on Delivery order is *placed*, not *paid* — the money changes hands
  /// at the door. Saying "Payment successful" over an unpaid order would be a
  /// lie, so the wording follows this flag.
  final bool isCashOnDelivery;

  final VoidCallback? onReturnToCart;

  const PaymentSuccessPage({
    super.key,
    this.orderId,
    this.sessionId,
    this.totalAmount,
    this.isCashOnDelivery = false,
    this.onReturnToCart,
  });

  @override
  State<PaymentSuccessPage> createState() => _PaymentSuccessPageState();
}

class _PaymentSuccessPageState extends State<PaymentSuccessPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _markScale;
  late final Animation<double> _fade;
  late final Animation<Offset> _rise;

  Timer? _timer;
  int _countdown = 8;
  bool _isRedirecting = false;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _startCountdown();

    AppLogger.d(
      'Payment Success Page - Order ID: ${widget.orderId}, '
      'Session ID: ${widget.sessionId}',
    );
  }

  void _initializeAnimations() {
    _controller = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );

    // The tick settles rather than bouncing: an elastic overshoot on a
    // confirmation screen reads as playful, and this is a receipt.
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
  }

  /// A single periodic timer rather than a chain of `Future.delayed` calls —
  /// the old chain kept firing after a manual tap and could not be cancelled.
  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
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

    setState(() {
      _isRedirecting = true;
    });
    _timer?.cancel();

    AppLogger.d('Returning to cart after a successful order');

    if (widget.onReturnToCart != null) {
      widget.onReturnToCart!();
      return;
    }

    // Back into the shell on the Cart tab — this page is pushed on top of it,
    // so the way back is to pop, not to build a second cart. Replacing the
    // whole stack with a bare CartPage (as this did before) left the buyer on
    // a cart with no navigation bar and no way out of it.
    final shell = AppShell.instance;
    if (shell != null) {
      shell.openTab(ShellTab.cart);
      return;
    }

    // No shell at all — a cold load of the legacy /payment-success route gets
    // this page and nothing underneath it. A standalone cart is the only thing
    // left to offer.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const CartPage()),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  InkPalette get ink => InkPalette.of(context);

  String get _title =>
      widget.isCashOnDelivery ? 'Order placed' : 'Payment successful';

  String get _message => widget.isCashOnDelivery
      ? 'Your order is confirmed. Please have the exact amount ready — you pay '
          'when your order is delivered.'
      : 'Thanks for your purchase. Your order is confirmed and a receipt is on '
          'its way to your email.';

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
                // Back is deliberately suppressed: the order exists, and the
                // route behind this one is the checkout form that created it.
                AppPageHeader(
                  title: 'Order confirmed',
                  subtitle: widget.isCashOnDelivery
                      ? 'Cash on Delivery'
                      : 'Payment complete',
                  subtitleColor: ink.emerald,
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
        // The receipt is a column of statements, not a full-width form — it
        // reads better narrow even when the window is wide.
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
                    _title,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.headlineSmall.copyWith(
                      color: ink.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 24,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _message,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: ink.text.withValues(alpha: 0.65),
                      fontSize: 13.5,
                      height: 1.5,
                    ),
                  ),
                  if (widget.orderId != null ||
                      widget.totalAmount != null ||
                      widget.sessionId != null) ...[
                    const SizedBox(height: 24),
                    _buildDetailsCard(),
                  ],
                  const SizedBox(height: 24),
                  _buildPrimaryButton(),
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
            color: ink.emerald.withValues(alpha: ink.isDark ? 0.16 : 0.1),
            border: Border.all(
              color: ink.emerald.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Icon(Icons.check_rounded, size: 46, color: ink.emerald),
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
              Icon(Icons.receipt_long_outlined, size: 18, color: ink.emerald),
              const SizedBox(width: 8),
              Text(
                'Order details',
                style: AppTextStyles.titleMedium.copyWith(
                  color: ink.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (widget.orderId != null)
            _detailRow('Order ID', widget.orderId!, mono: true),
          if (widget.totalAmount != null) ...[
            if (widget.orderId != null) const SizedBox(height: 10),
            _detailRow(
              widget.isCashOnDelivery ? 'Amount due on delivery' : 'Amount paid',
              CurrencyFormatter.formatWithPeso(widget.totalAmount!),
              emphasise: true,
            ),
          ],
          if (widget.sessionId != null) ...[
            if (widget.orderId != null || widget.totalAmount != null)
              const SizedBox(height: 10),
            _detailRow('Reference', widget.sessionId!, mono: true),
          ],
        ],
      ),
    );
  }

  Widget _detailRow(
    String label,
    String value, {
    bool mono = false,
    bool emphasise = false,
  }) {
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
            // Ids are long and worth keeping whole — they are what a buyer
            // quotes to support, so they wrap rather than being clipped.
            style: emphasise
                ? AppTextStyles.titleMedium.copyWith(
                    color: ink.emerald,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  )
                : AppTextStyles.bodySmall.copyWith(
                    color: ink.text,
                    fontWeight: FontWeight.w600,
                    fontFamily: mono ? 'monospace' : null,
                    fontSize: 12.5,
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildPrimaryButton() {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: _isRedirecting ? null : _redirectToCart,
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
            if (_isRedirecting) ...[
              SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: ink.text.withValues(alpha: 0.38),
                ),
              ),
              const SizedBox(width: 10),
            ] else ...[
              const Icon(Icons.shopping_bag_outlined, size: 18),
              const SizedBox(width: 8),
            ],
            Text(
              _isRedirecting ? 'Returning…' : 'Continue shopping',
              style: AppTextStyles.buttonLarge.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
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
