import 'package:flutter/material.dart';
import 'package:dentpal/utils/app_logger.dart';
import '../../core/app_theme/app_colors.dart';
import '../../core/app_theme/app_text_styles.dart';
import 'dart:async';

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
    with TickerProviderStateMixin {
  late AnimationController _shakeController;
  late AnimationController _scaleController;
  late Animation<double> _shakeAnimation;
  late Animation<double> _scaleAnimation;
  Timer? _redirectTimer;
  int _countdown = 5;

  @override
  void initState() {
    super.initState();
    
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _shakeAnimation = Tween<double>(
      begin: -10.0,
      end: 10.0,
    ).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.elasticIn,
    ));
    
    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    ));

    // Start animations
    _scaleController.forward();
    _shakeController.repeat(reverse: true);

    // Start countdown timer
    _startCountdown();

    AppLogger.d('❌ Payment Failed Page loaded with sessionId: ${widget.sessionId}, orderId: ${widget.orderId}');
  }

  void _startCountdown() {
    _redirectTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _countdown--;
      });
      
      if (_countdown <= 0) {
        timer.cancel();
        _redirectToCart();
      }
    });
  }

  void _redirectToCart() {
    AppLogger.d('🔄 Redirecting to cart page...');
    // In a web environment, you would use:
    // html.window.location.href = '/cart';
    
    // For Flutter web, navigate back to cart
    Navigator.of(context).pushNamedAndRemoveUntil('/cart', (route) => false);
  }

  void _retryPayment() {
    AppLogger.d('🔄 Retrying payment...');
    // Navigate back to checkout
    Navigator.of(context).pushNamedAndRemoveUntil('/checkout', (route) => false);
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _scaleController.dispose();
    _redirectTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Failed Icon with Animation
                ScaleTransition(
                  scale: _scaleAnimation,
                  child: AnimatedBuilder(
                    animation: _shakeAnimation,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(_shakeAnimation.value, 0),
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.error.withValues(alpha: 0.3),
                                spreadRadius: 20,
                                blurRadius: 40,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 60,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // Failed Title
                Text(
                  'Payment Failed',
                  style: AppTextStyles.headlineMedium.copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 16),
                
                // Failed Message
                Text(
                  widget.errorMessage ?? 'Sorry, we couldn\'t process your payment.\nPlease try again or use a different payment method.',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.onSurface.withValues(alpha:0.8),
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 24),
                
                // Error Details Card
                if (widget.sessionId != null || widget.orderId != null)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.error.withValues(alpha:0.2),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: AppColors.error,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Transaction Details',
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.error,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (widget.sessionId != null) ...[
                          _buildDetailRow('Session ID', widget.sessionId!),
                          const SizedBox(height: 8),
                        ],
                        if (widget.orderId != null) ...[
                          _buildDetailRow('Order ID', widget.orderId!),
                        ],
                      ],
                    ),
                  ),
                
                const SizedBox(height: 40),
                
                // Action Buttons
                Row(
                  children: [
                    // Retry Payment Button
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _retryPayment,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.refresh),
                            const SizedBox(width: 8),
                            Text(
                              'Retry Payment',
                              style: AppTextStyles.buttonMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(width: 16),
                    
                    // Return to Cart Button
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _redirectToCart,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: BorderSide(color: AppColors.primary),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.shopping_cart),
                            const SizedBox(width: 8),
                            Text(
                              'Back to Cart',
                              style: AppTextStyles.buttonMedium.copyWith(
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 24),
                
                // Countdown Info
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.grey50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Returning to cart in',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.onSurface.withValues(alpha:0.7),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$_countdown',
                        style: AppTextStyles.headlineLarge.copyWith(
                          color: AppColors.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'seconds',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.onSurface.withValues(alpha:0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.onSurface.withValues(alpha:0.6),
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: AppTextStyles.bodySmall.copyWith(
              fontFamily: 'monospace',
              color: AppColors.onSurface,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
