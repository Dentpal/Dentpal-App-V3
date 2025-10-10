import 'package:flutter/material.dart';
import 'package:dentpal/utils/app_logger.dart';
import '../../core/app_theme/app_colors.dart';
import '../../core/app_theme/app_text_styles.dart';
import 'cart_page.dart';

class PaymentSuccessPage extends StatefulWidget {
  final String? orderId;
  final String? sessionId;
  final VoidCallback? onReturnToCart;

  const PaymentSuccessPage({
    super.key,
    this.orderId,
    this.sessionId,
    this.onReturnToCart,
  });

  @override
  State<PaymentSuccessPage> createState() => _PaymentSuccessPageState();
}

class _PaymentSuccessPageState extends State<PaymentSuccessPage>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  
  int _countdown = 5;
  bool _isRedirecting = false;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _startCountdown();
    
    AppLogger.d('💰 Payment Success Page - Order ID: ${widget.orderId}, Session ID: ${widget.sessionId}');
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    ));

    _animationController.forward();
  }

  void _startCountdown() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        _updateCountdown();
      }
    });
  }

  void _updateCountdown() {
    if (_countdown > 0 && mounted) {
      setState(() {
        _countdown--;
      });
      Future.delayed(const Duration(seconds: 1), _updateCountdown);
    } else if (_countdown == 0 && mounted && !_isRedirecting) {
      _redirectToCart();
    }
  }

  void _redirectToCart() {
    if (_isRedirecting) return;
    
    setState(() {
      _isRedirecting = true;
    });

    AppLogger.d('🔄 Redirecting to cart page after successful payment');
    
    if (widget.onReturnToCart != null) {
      widget.onReturnToCart!();
    } else {
      // Navigate to cart page using MaterialPageRoute to avoid URL changes
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const CartPage()),
        (route) => false,
      );
    }
  }

  void _goToCartNow() {
    if (!_isRedirecting) {
      _redirectToCart();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'Payment Successful',
          style: AppTextStyles.titleLarge.copyWith(
            color: AppColors.success,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Success Animation
              AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _scaleAnimation.value,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check_circle,
                          size: 80,
                          color: AppColors.success,
                        ),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 32),

              // Success Message
              FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  children: [
                    Text(
                      'Payment Successful!',
                      style: AppTextStyles.headlineMedium.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Thank you for your purchase. Your order has been confirmed and you will receive an email receipt shortly.',
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: AppColors.onSurface.withValues(alpha: 0.8),
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Order Information
              if (widget.orderId != null)
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.grey50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.success.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.receipt_long,
                              color: AppColors.success,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Order Details',
                              style: AppTextStyles.titleMedium.copyWith(
                                color: AppColors.success,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Order ID:',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                            Text(
                              widget.orderId!,
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                        if (widget.sessionId != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Session ID:',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.onSurface.withValues(alpha: 0.6),
                                ),
                              ),
                              Text(
                                widget.sessionId!.substring(0, 12) + '...',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 40),

              // Countdown and Redirect Info
              FadeTransition(
                opacity: _fadeAnimation,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isRedirecting 
                            ? 'Redirecting...'
                            : 'Redirecting to cart in $_countdown seconds',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Action Buttons
              FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isRedirecting ? null : _goToCartNow,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: _isRedirecting
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.onPrimary,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Redirecting...',
                                    style: AppTextStyles.buttonLarge,
                                  ),
                                ],
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.shopping_cart),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Return to Cart Now',
                                    style: AppTextStyles.buttonLarge,
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
