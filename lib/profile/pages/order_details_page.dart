import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../../core/app_theme/app_colors.dart';
import '../../core/app_theme/app_text_styles.dart';
import '../../product/models/order_model.dart' as order_model;
import '../../product/pages/paymongo_webview_page.dart';
import '../../utils/app_logger.dart';

class OrderDetailsPage extends StatelessWidget {
  final order_model.Order order;

  const OrderDetailsPage({
    super.key,
    required this.order,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        toolbarHeight: 60,
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Order Details',
          style: AppTextStyles.titleLarge.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Order Header Card
            _buildOrderHeaderCard(),
            const SizedBox(height: 16),

            // Status Timeline
            _buildStatusTimeline(),
            const SizedBox(height: 16),

            // Items Section
            _buildItemsSection(),
            const SizedBox(height: 16),

            // Shipping Information
            _buildShippingInfoSection(),
            const SizedBox(height: 16),

            // Payment Information
            _buildPaymentInfoSection(),
            const SizedBox(height: 16),

            // Order Summary
            _buildOrderSummarySection(),
            const SizedBox(height: 32),

            // Action Buttons
            _buildActionButtons(context),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderHeaderCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Order #${order.orderId.substring(0, 8).toUpperCase()}',
                    style: AppTextStyles.titleLarge.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Placed on ${_formatDate(order.createdAt)}',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
              _buildStatusChip(order.status),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(
                Icons.shopping_bag,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                '${order.items.length} item${order.items.length > 1 ? 's' : ''}',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                '₱${order.summary.total.toStringAsFixed(2)}',
                style: AppTextStyles.titleLarge.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTimeline() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Order Timeline',
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: order.statusHistory.length,
            separatorBuilder: (context, index) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final statusUpdate = order.statusHistory[index];
              final isLast = index == order.statusHistory.length - 1;
              
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _getStatusColor(statusUpdate.status),
                          shape: BoxShape.circle,
                        ),
                      ),
                      if (!isLast)
                        Container(
                          width: 2,
                          height: 40,
                          color: AppColors.onSurface.withValues(alpha: 0.2),
                          margin: const EdgeInsets.only(top: 8),
                        ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatStatusTitle(statusUpdate.status),
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (statusUpdate.note != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            statusUpdate.note!,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          _formatDateTime(statusUpdate.timestamp),
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildItemsSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Items (${order.items.length})',
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: order.items.length,
            separatorBuilder: (context, index) => const Divider(height: 24),
            itemBuilder: (context, index) {
              final item = order.items[index];
              return _buildOrderItem(item);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItem(order_model.OrderItem item) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Product Image
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: AppColors.grey200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: item.productImage.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    item.productImage,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(
                        Icons.inventory_2_outlined,
                        color: AppColors.grey500,
                        size: 30,
                      );
                    },
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                          ),
                        ),
                      );
                    },
                  ),
                )
              : Icon(
                  Icons.inventory_2_outlined,
                  color: AppColors.grey500,
                  size: 30,
                ),
        ),
        const SizedBox(width: 16),
        
        // Product Info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.productName,
                style: AppTextStyles.bodyLarge.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              if (item.variationName != null) ...[
                Text(
                  'Variation: ${item.variationName}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 4),
              ],
              Row(
                children: [
                  Text(
                    'Qty: ${item.quantity}',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '₱${item.price.toStringAsFixed(2)}',
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Sold by ${item.sellerName}',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildShippingInfoSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.local_shipping,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Shipping Information',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow('Name', order.shippingInfo.fullName),
          _buildInfoRow('Phone', order.shippingInfo.phoneNumber),
          _buildInfoRow(
            'Address',
            '${order.shippingInfo.addressLine1}'
            '${order.shippingInfo.addressLine2 != null ? '\n${order.shippingInfo.addressLine2}' : ''}'
            '\n${order.shippingInfo.city}, ${order.shippingInfo.state} ${order.shippingInfo.postalCode}'
            '\n${order.shippingInfo.country}',
          ),
          if (order.shippingInfo.notes != null)
            _buildInfoRow('Notes', order.shippingInfo.notes!),
        ],
      ),
    );
  }

  Widget _buildPaymentInfoSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.payment,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Payment Information',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow('Payment Method', _formatPaymentMethod(order.paymentInfo.method)),
          _buildInfoRow('Payment Status', _formatPaymentStatus(order.paymentInfo.status)),
          _buildInfoRow('Amount', '₱${order.paymentInfo.amount.toStringAsFixed(2)}'),
          _buildInfoRow('Currency', order.paymentInfo.currency),
          if (order.paymentInfo.paidAt != null)
            _buildInfoRow('Paid At', _formatDateTime(order.paymentInfo.paidAt!)),
          if (order.paymentInfo.checkoutSessionId != null)
            _buildInfoRow('Checkout Session ID', order.paymentInfo.checkoutSessionId!),
          if (order.paymentInfo.paymentIntentId != null)
            _buildInfoRow('Payment Intent ID', order.paymentInfo.paymentIntentId!),
          if (order.paymentInfo.checkoutUrl != null && _canResumePayment())
            _buildInfoRow('Payment URL', 'Available for payment resumption'),
        ],
      ),
    );
  }

  Widget _buildOrderSummarySection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Order Summary',
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          _buildSummaryRow('Subtotal', '₱${order.summary.subtotal.toStringAsFixed(2)}'),
          _buildSummaryRow('Shipping', '₱${order.summary.shippingCost.toStringAsFixed(2)}'),
          if (order.summary.taxAmount > 0)
            _buildSummaryRow('Tax', '₱${order.summary.taxAmount.toStringAsFixed(2)}'),
          if (order.summary.discountAmount > 0)
            _buildSummaryRow('Discount', '-₱${order.summary.discountAmount.toStringAsFixed(2)}'),
          const Divider(height: 24),
          _buildSummaryRow(
            'Total',
            '₱${order.summary.total.toStringAsFixed(2)}',
            isTotal: true,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Column(
      children: [
        if (_canResumePayment())
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _resumePayment(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Resume Payment'),
            ),
          ),
        if (_canResumePayment()) const SizedBox(height: 12),
        if (_canReorder())
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _reorderItems(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Reorder Items'),
            ),
          ),
        if (_canReorder()) const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => _contactSupport(context),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.primary),
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Contact Support'),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: isTotal
                ? AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.w700)
                : AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.onSurface.withValues(alpha: 0.6),
                  ),
          ),
          Text(
            value,
            style: isTotal
                ? AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    fontFamily: 'Roboto',
                  )
                : AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Roboto',
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(order_model.OrderStatus status) {
    Color backgroundColor;
    Color textColor;
    IconData icon;

    switch (status) {
      case order_model.OrderStatus.pending:
        backgroundColor = AppColors.warning.withValues(alpha: 0.1);
        textColor = AppColors.warning;
        icon = Icons.pending;
        break;
      case order_model.OrderStatus.confirmed:
        backgroundColor = AppColors.success.withValues(alpha: 0.1);
        textColor = AppColors.success;
        icon = Icons.check_circle_outline;
        break;
      case order_model.OrderStatus.processing:
        backgroundColor = AppColors.info.withValues(alpha: 0.1);
        textColor = AppColors.info;
        icon = Icons.autorenew;
        break;
      case order_model.OrderStatus.shipped:
        backgroundColor = AppColors.primary.withValues(alpha: 0.1);
        textColor = AppColors.primary;
        icon = Icons.local_shipping;
        break;
      case order_model.OrderStatus.delivered:
        backgroundColor = AppColors.success.withValues(alpha: 0.1);
        textColor = AppColors.success;
        icon = Icons.check_circle;
        break;
      case order_model.OrderStatus.cancelled:
        backgroundColor = AppColors.error.withValues(alpha: 0.1);
        textColor = AppColors.error;
        icon = Icons.cancel;
        break;
      case order_model.OrderStatus.refunded:
        backgroundColor = AppColors.grey400.withValues(alpha: 0.1);
        textColor = AppColors.grey600;
        icon = Icons.refresh;
        break;
      case order_model.OrderStatus.payment_failed:
        backgroundColor = AppColors.error.withValues(alpha: 0.1);
        textColor = AppColors.error;
        icon = Icons.error;
        break;
      case order_model.OrderStatus.expired:
        backgroundColor = AppColors.grey400.withValues(alpha: 0.1);
        textColor = AppColors.grey600;
        icon = Icons.access_time;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: textColor),
          const SizedBox(width: 4),
          Text(
            _formatStatus(status),
            style: AppTextStyles.bodySmall.copyWith(
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // Helper methods
  String _formatDate(DateTime date) {
    return DateFormat('MMM dd, yyyy').format(date);
  }

  String _formatDateTime(DateTime date) {
    return DateFormat('MMM dd, yyyy • hh:mm a').format(date);
  }

  String _formatStatus(order_model.OrderStatus status) {
    return status.displayName;
  }

  String _formatStatusTitle(order_model.OrderStatus status) {
    switch (status) {
      case order_model.OrderStatus.pending:
        return 'Order Placed';
      case order_model.OrderStatus.confirmed:
        return 'Payment Confirmed';
      case order_model.OrderStatus.processing:
        return 'Order Processing';
      case order_model.OrderStatus.shipped:
        return 'Order Shipped';
      case order_model.OrderStatus.delivered:
        return 'Order Completed';
      case order_model.OrderStatus.cancelled:
        return 'Order Cancelled';
      case order_model.OrderStatus.refunded:
        return 'Order Refunded';
      case order_model.OrderStatus.payment_failed:
        return 'Payment Failed';
      case order_model.OrderStatus.expired:
        return 'Payment Expired';
    }
  }

  String _formatPaymentMethod(order_model.PaymentMethod method) {
    switch (method) {
      case order_model.PaymentMethod.card:
        return 'Credit/Debit Card';
      case order_model.PaymentMethod.gcash:
        return 'GCash';
      case order_model.PaymentMethod.grabpay:
        return 'Grab Pay';
      case order_model.PaymentMethod.paymaya:
        return 'PayMaya';
      case order_model.PaymentMethod.billEase:
        return 'BillEase (Buy Now Pay Later)';
    }
  }

  String _formatPaymentStatus(order_model.PaymentStatus status) {
    switch (status) {
      case order_model.PaymentStatus.pending:
        return 'Pending';
      case order_model.PaymentStatus.paid:
        return 'Paid';
      case order_model.PaymentStatus.failed:
        return 'Failed';
      case order_model.PaymentStatus.refunded:
        return 'Refunded';
      case order_model.PaymentStatus.partially_refunded:
        return 'Partially Refunded';
    }
  }

  Color _getStatusColor(order_model.OrderStatus status) {
    switch (status) {
      case order_model.OrderStatus.pending:
        return AppColors.warning;
      case order_model.OrderStatus.confirmed:
        return AppColors.success;
      case order_model.OrderStatus.processing:
        return AppColors.info;
      case order_model.OrderStatus.shipped:
        return AppColors.primary;
      case order_model.OrderStatus.delivered:
        return AppColors.success;
      case order_model.OrderStatus.cancelled:
        return AppColors.error;
      case order_model.OrderStatus.refunded:
        return AppColors.grey600;
      case order_model.OrderStatus.payment_failed:
        return AppColors.error;
      case order_model.OrderStatus.expired:
        return AppColors.grey600;
    }
  }

  bool _canReorder() {
    return order.status == order_model.OrderStatus.confirmed ||
           order.status == order_model.OrderStatus.delivered ||
           order.status == order_model.OrderStatus.expired;
  }

  bool _canResumePayment() {
    // Can only resume payment if:
    // 1. Order status is pending
    // 2. Order is not expired
    // 3. Order has a checkout URL
    return order.status == order_model.OrderStatus.pending &&
           order.paymentInfo.checkoutUrl != null &&
           order.paymentInfo.checkoutUrl!.isNotEmpty;
  }


  void _reorderItems(BuildContext context) {
    // TODO: Implement reorder functionality
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Reorder functionality coming soon'),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  void _resumePayment(BuildContext context) async {
    if (!_canResumePayment()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment cannot be resumed for this order'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final checkoutUrl = order.paymentInfo.checkoutUrl!;
    AppLogger.d('Resuming payment for order ${order.orderId} with URL: $checkoutUrl');

    try {
      if (kIsWeb) {
        // For web, open in a new tab
        final uri = Uri.parse(checkoutUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          
          // Show a dialog to inform the user
          if (context.mounted) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: AppColors.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: Row(
                  children: [
                    Icon(Icons.payment, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text('Payment Resumed'),
                  ],
                ),
                content: Text(
                  'Your payment page has been opened in a new tab. Please complete your payment and return to this page.',
                  style: AppTextStyles.bodyMedium,
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('OK', style: TextStyle(color: AppColors.primary)),
                  ),
                ],
              ),
            );
          }
        }
      } else {
        // For mobile, use WebView
        if (context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PaymongoWebViewPage(
                checkoutUrl: checkoutUrl,
                successUrl: 'https://dentpal-store.web.app/payment-success',
                cancelUrl: 'https://dentpal-store.web.app/payment-failed',
                onPaymentComplete: (isSuccess, orderId) {
                  AppLogger.d('Payment resumed completed. Success: $isSuccess, Order ID: $orderId');
                  
                  if (isSuccess) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Payment completed successfully!'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                    // Navigate back to orders page
                    Navigator.of(context).pop();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Payment was cancelled or failed'),
                        backgroundColor: AppColors.warning,
                      ),
                    );
                  }
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      AppLogger.d('Error resuming payment: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to resume payment. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _contactSupport(BuildContext context) {
    // TODO: Implement contact support
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Contact support functionality coming soon'),
        backgroundColor: AppColors.primary,
      ),
    );
  }
}
