import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../../core/app_theme/app_colors.dart';
import '../../core/app_theme/app_text_styles.dart';
import '../../product/models/order_model.dart' as order_model;
import '../../product/pages/paymongo_webview_page.dart';
import '../../product/pages/cart_page.dart';
import '../../product/services/cart_service.dart';
import '../../product/services/jrs_tracking_service.dart';
import '../../utils/app_logger.dart';
import '../services/order_service.dart';

class OrderDetailsPage extends StatefulWidget {
  final order_model.Order order;

  const OrderDetailsPage({super.key, required this.order});

  @override
  State<OrderDetailsPage> createState() => _OrderDetailsPageState();
}

class _OrderDetailsPageState extends State<OrderDetailsPage> {
  JRSTrackingResult? _trackingResult;
  bool _isLoadingTracking = false;
  String? _trackingError;

  @override
  void initState() {
    super.initState();

    final trackingId = _getTrackingId();
    // Debug logging for tracking ID
    AppLogger.d(
      'Order tracking ID from shippingInfo: ${widget.order.shippingInfo.trackingId}',
    );
    AppLogger.d('Order tracking ID extracted: $trackingId');
    AppLogger.d('Order status: ${widget.order.status}');

    // Auto-load tracking if tracking ID is available
    if (trackingId != null) {
      AppLogger.d('Tracking ID available, loading tracking...');
      _loadTracking();
    } else {
      AppLogger.d('No tracking ID available for this order');
    }
  }

  /// Extract tracking ID from either shippingInfo or status history
  String? _getTrackingId() {
    // First check if trackingId is directly available in shippingInfo
    if (widget.order.shippingInfo.trackingId != null &&
        widget.order.shippingInfo.trackingId!.isNotEmpty) {
      AppLogger.d(
        'Found tracking ID in shippingInfo.trackingId: ${widget.order.shippingInfo.trackingId}',
      );
      return widget.order.shippingInfo.trackingId;
    }

    // Check if it's available in JRS response data (if shippingInfo has a Map structure)
    try {
      final shippingInfoData =
          widget.order.toMap()['shippingInfo'] as Map<String, dynamic>?;
      if (shippingInfoData != null) {
        // Check direct trackingId field
        final directTrackingId = shippingInfoData['trackingId'] as String?;
        if (directTrackingId != null && directTrackingId.isNotEmpty) {
          AppLogger.d(
            'Found tracking ID in shippingInfo data: $directTrackingId',
          );
          return directTrackingId;
        }

        // Check JRS response structure
        final jrsData = shippingInfoData['jrs'] as Map<String, dynamic>?;
        if (jrsData != null) {
          final response = jrsData['response'] as Map<String, dynamic>?;
          if (response != null) {
            final shippingDto =
                response['ShippingRequestEntityDto'] as Map<String, dynamic>?;
            if (shippingDto != null) {
              final trackingId = shippingDto['TrackingId'] as String?;
              if (trackingId != null && trackingId.isNotEmpty) {
                AppLogger.d('Found tracking ID in JRS response: $trackingId');
                return trackingId;
              }
            }
          }
        }
      }
    } catch (e) {
      AppLogger.d('Error extracting tracking ID from shipping info: $e');
    }

    // If not found in shipping info, try to extract from status history notes
    for (final status in widget.order.statusHistory.reversed) {
      if (status.note != null && status.note!.contains('Tracking:')) {
        final match = RegExp(r'Tracking:\s*(\d+)').firstMatch(status.note!);
        if (match != null) {
          AppLogger.d('Found tracking ID in status history: ${match.group(1)}');
          return match.group(1);
        }
      }
    }

    AppLogger.d('No tracking ID found');
    return null;
  }

  Future<void> _loadTracking() async {
    final trackingId = _getTrackingId();
    if (trackingId == null) return;

    setState(() {
      _isLoadingTracking = true;
      _trackingError = null;
    });

    try {
      final result = await JRSTrackingService.trackPackage(trackingId);
      setState(() {
        _trackingResult = result;
        _isLoadingTracking = false;
        if (!result.success) {
          _trackingError =
              result.error ?? 'Failed to load tracking information';
        }
      });
    } catch (e) {
      setState(() {
        _isLoadingTracking = false;
        _trackingError = e.toString();
      });
      AppLogger.d('Error loading tracking: $e');
    }
  }

  // Debug method to test tracking service
  @override
  Widget build(BuildContext context) {
    // Debug logging
    AppLogger.d(
      'Building OrderDetailsPage - Tracking ID: ${widget.order.shippingInfo.trackingId}',
    );

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
          style: AppTextStyles.titleLarge.copyWith(fontWeight: FontWeight.w700),
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

            // JRS Tracking Section (if tracking ID available)
            if (_getTrackingId() != null) ...[
              _buildTrackingSection(),
              const SizedBox(height: 16),
            ],

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
                    'Order #${widget.order.orderId.substring(0, 8).toUpperCase()}',
                    style: AppTextStyles.titleLarge.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Placed on ${_formatDate(widget.order.createdAt)}',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
              _buildStatusChip(widget.order.status),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.shopping_bag, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                '${widget.order.items.length} item${widget.order.items.length > 1 ? 's' : ''}',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                '₱${widget.order.summary.total.toStringAsFixed(2)}',
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

  Widget _buildTrackingSection() {
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
                Icons.local_shipping_outlined,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Package Tracking',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (!_isLoadingTracking)
                IconButton(
                  icon: Icon(Icons.refresh, color: AppColors.primary),
                  onPressed: _loadTracking,
                  tooltip: 'Refresh tracking',
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isLoadingTracking)
            Center(
              child: Column(
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Loading tracking information...',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            )
          else if (_trackingError != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: AppColors.error),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Unable to load tracking',
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.error,
                          ),
                        ),
                        Text(
                          _trackingError!,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else if (_trackingResult != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow('Tracking ID', _getTrackingId() ?? 'N/A'),
                _buildInfoRow('Status', _trackingResult!.status),
                if (_trackingResult!.location != null)
                  _buildInfoRow('Current Location', _trackingResult!.location!),
                if (_trackingResult!.timestamp != null)
                  _buildInfoRow(
                    'Last Update',
                    _formatTrackingDateTime(_trackingResult!.timestamp!),
                  ),

                if (_trackingResult!.events.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Tracking History',
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _trackingResult!.events.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final event = _trackingResult!.events[index];
                      final isLast =
                          index == _trackingResult!.events.length - 1;

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              if (!isLast)
                                Container(
                                  width: 2,
                                  height: 30,
                                  color: AppColors.onSurface.withValues(
                                    alpha: 0.2,
                                  ),
                                  margin: const EdgeInsets.only(top: 4),
                                ),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  event.status,
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  event.location,
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.onSurface.withValues(
                                      alpha: 0.7,
                                    ),
                                  ),
                                ),
                                if (event.description != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    event.description!,
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: AppColors.onSurface.withValues(
                                        alpha: 0.6,
                                      ),
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                                Text(
                                  _formatTrackingDateTime(event.timestamp),
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.onSurface.withValues(
                                      alpha: 0.5,
                                    ),
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
              ],
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.warning),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Tracking information will be available once your package is shipping.',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
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
            itemCount: widget.order.statusHistory.length,
            separatorBuilder: (context, index) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final statusUpdate = widget.order.statusHistory[index];
              final isLast = index == widget.order.statusHistory.length - 1;

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
                          statusUpdate.note ??
                              _formatStatusTitle(statusUpdate.status),
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
            'Items (${widget.order.items.length})',
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.order.items.length,
            separatorBuilder: (context, index) => const Divider(height: 24),
            itemBuilder: (context, index) {
              final item = widget.order.items[index];
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
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.primary,
                            ),
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
              Icon(Icons.local_shipping, color: AppColors.primary, size: 20),
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
          _buildInfoRow('Name', widget.order.shippingInfo.fullName),
          _buildInfoRow('Phone', widget.order.shippingInfo.phoneNumber),
          _buildInfoRow(
            'Address',
            '${widget.order.shippingInfo.addressLine1}'
                '${widget.order.shippingInfo.addressLine2 != null ? '\n${widget.order.shippingInfo.addressLine2}' : ''}'
                '\n${widget.order.shippingInfo.city}, ${widget.order.shippingInfo.state} ${widget.order.shippingInfo.postalCode}'
                '\n${widget.order.shippingInfo.country}',
          ),
          if (widget.order.shippingInfo.notes != null)
            _buildInfoRow('Notes', widget.order.shippingInfo.notes!),
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
              Icon(Icons.payment, color: AppColors.primary, size: 20),
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
          _buildInfoRow(
            'Payment Method',
            _formatPaymentMethod(widget.order.paymentInfo.method),
          ),
          _buildInfoRow(
            'Payment Status',
            _formatPaymentStatus(widget.order.paymentInfo.status),
          ),
          _buildInfoRow(
            'Amount',
            '₱${widget.order.paymentInfo.amount.toStringAsFixed(2)}',
          ),
          _buildInfoRow('Currency', widget.order.paymentInfo.currency),
          if (widget.order.paymentInfo.paidAt != null)
            _buildInfoRow(
              'Paid At',
              _formatDateTime(widget.order.paymentInfo.paidAt!),
            ),
          if (widget.order.paymentInfo.checkoutSessionId != null)
            _buildInfoRow(
              'Checkout Session ID',
              widget.order.paymentInfo.checkoutSessionId!,
            ),
          if (widget.order.paymentInfo.paymentIntentId != null)
            _buildInfoRow(
              'Payment Intent ID',
              widget.order.paymentInfo.paymentIntentId!,
            ),
          if (widget.order.paymentInfo.checkoutUrl != null &&
              _canResumePayment())
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
          _buildSummaryRow(
            'Subtotal',
            '₱${widget.order.summary.subtotal.toStringAsFixed(2)}',
          ),
          // Display only the buyer's shipping charge (what they actually paid)
          _buildSummaryRow(
            'Shipping',
            widget.order.summary.buyerShippingCharge > 0
                ? '₱${widget.order.summary.buyerShippingCharge.toStringAsFixed(2)}'
                : (widget.order.summary.shippingCost > 0
                      ? '₱${widget.order.summary.shippingCost.toStringAsFixed(2)}'
                      : 'Free'),
          ),
          if (widget.order.summary.taxAmount > 0)
            _buildSummaryRow(
              'Tax',
              '₱${widget.order.summary.taxAmount.toStringAsFixed(2)}',
            ),
          if (widget.order.summary.discountAmount > 0)
            _buildSummaryRow(
              'Discount',
              '-₱${widget.order.summary.discountAmount.toStringAsFixed(2)}',
            ),
          const Divider(height: 24),
          _buildSummaryRow(
            'Total',
            '₱${widget.order.summary.total.toStringAsFixed(2)}',
            isTotal: true,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Column(
      children: [
        if (_canCancelOrder())
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _cancelOrder(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Cancel Order'),
            ),
          ),
        if (_canCancelOrder()) const SizedBox(height: 12),
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
                ? AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  )
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
      case order_model.OrderStatus.to_ship:
        backgroundColor = AppColors.info.withValues(alpha: 0.1);
        textColor = AppColors.info;
        icon = Icons.autorenew;
        break;
      case order_model.OrderStatus.shipping:
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

  String _formatTrackingDateTime(String dateTimeString) {
    try {
      final dateTime = DateTime.parse(dateTimeString);
      return DateFormat('MMM dd, yyyy • hh:mm a').format(dateTime);
    } catch (e) {
      return dateTimeString; // Return original string if parsing fails
    }
  }

  String _formatStatus(order_model.OrderStatus status) {
    return status.displayName;
  }

  String _formatStatusTitle(order_model.OrderStatus status) {
    // Get the raw status string to handle additional fulfillment stages
    final statusString = status.toString().split('.').last;

    // Handle fulfillment stage statuses that might not be in the enum
    switch (statusString) {
      case 'pending':
        return 'Order Placed';
      case 'confirmed':
        return 'Payment Confirmed';
      case 'processing':
        return 'Order Processing';
      case 'to_ship':
        return 'Ready to Ship';
      case 'to_pack':
      case 'to-pack':
        return 'Packing Stage';
      case 'to_arrangement':
      case 'to-arrangement':
        return 'Arrangement Stage';
      case 'to_handover':
      case 'to-handover':
      case 'to_hand_over':
      case 'to-hand-over':
        return 'Hand Over Stage';
      case 'shipping':
        return 'Order shipping';
      case 'delivered':
        return 'Order Completed';
      case 'cancelled':
        return 'Order Cancelled';
      case 'refunded':
        return 'Order Refunded';
      case 'payment_failed':
        return 'Payment Failed';
      case 'expired':
        return 'Payment Expired';
      default:
        // Fallback to enum-based formatting for any other cases
        switch (status) {
          case order_model.OrderStatus.pending:
            return 'Order Placed';
          case order_model.OrderStatus.confirmed:
            return 'Payment Confirmed';
          case order_model.OrderStatus.to_ship:
            return 'Order Processing';
          case order_model.OrderStatus.shipping:
            return 'Order shipping';
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
      case order_model.OrderStatus.to_ship:
        return AppColors.info;
      case order_model.OrderStatus.shipping:
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
    return widget.order.status == order_model.OrderStatus.confirmed ||
        widget.order.status == order_model.OrderStatus.delivered ||
        widget.order.status == order_model.OrderStatus.expired;
  }

  bool _canCancelOrder() {
    // Can cancel if order is pending, confirmed, or to_ship (not yet shipping)
    return widget.order.status == order_model.OrderStatus.pending ||
        widget.order.status == order_model.OrderStatus.confirmed ||
        widget.order.status == order_model.OrderStatus.to_ship;
  }

  bool _canResumePayment() {
    // Can only resume payment if:
    // 1. Order status is pending
    // 2. Order is not expired
    // 3. Order has a checkout URL
    return widget.order.status == order_model.OrderStatus.pending &&
        widget.order.paymentInfo.checkoutUrl != null &&
        widget.order.paymentInfo.checkoutUrl!.isNotEmpty;
  }

  void _reorderItems(BuildContext context) async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final cartService = CartService();

      // Get all current cart items to deselect them
      final currentCartItems = await cartService.getCartItems();

      // Deselect all current cart items
      if (currentCartItems.isNotEmpty) {
        final Map<String, bool> itemSelections = {};
        for (var item in currentCartItems) {
          itemSelections[item.cartItemId] = false;
        }
        await cartService.batchUpdateItemSelections(itemSelections);
      }

      // Add each order item to the cart
      for (var orderItem in widget.order.items) {
        await cartService.addToCart(
          productId: orderItem.productId,
          quantity: orderItem.quantity,
          variationId: orderItem.variationId,
        );
      }

      // Mark cart as stale to trigger refresh
      CartPage.markCartAsStale();

      // Close loading dialog
      if (context.mounted) {
        Navigator.of(context).pop();

        // Navigate to cart page
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const CartPage()),
        );

        // Show success message
        Future.delayed(const Duration(milliseconds: 500), () {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${widget.order.items.length} items added to cart',
                ),
                backgroundColor: AppColors.success,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        });
      }
    } catch (e) {
      AppLogger.d('Error reordering items: $e');

      // Close loading dialog if still open
      if (context.mounted) {
        Navigator.of(context).pop();

        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reorder items. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
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

    final checkoutUrl = widget.order.paymentInfo.checkoutUrl!;
    AppLogger.d(
      'Resuming payment for order ${widget.order.orderId} with URL: $checkoutUrl',
    );

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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
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
                    child: Text(
                      'OK',
                      style: TextStyle(color: AppColors.primary),
                    ),
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
                  AppLogger.d(
                    'Payment resumed completed. Success: $isSuccess, Order ID: $orderId',
                  );

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

  void _cancelOrder(BuildContext context) async {
    if (!_canCancelOrder()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('This order cannot be cancelled'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // Show cancellation reason dialog
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => _CancelOrderDialog(),
    );

    if (result == null) return; // User dismissed the dialog
    if (!context.mounted) return;

    final reason = result['reason']!;
    final customReason = result['customReason'];

    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      // Build cancellation note
      final note = customReason != null && customReason.isNotEmpty
          ? '$reason: $customReason'
          : reason;

      await OrderService.cancelOrder(widget.order.orderId, reason: note);

      // Close loading dialog
      if (context.mounted) {
        Navigator.of(context).pop();

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Order cancelled successfully'),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 2),
          ),
        );

        // Navigate back to orders page
        Navigator.of(context).pop();
      }
    } catch (e) {
      AppLogger.d('Error cancelling order: $e');

      // Close loading dialog if still open
      if (context.mounted) {
        Navigator.of(context).pop();

        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to cancel order. Please try again.'),
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

/// Dialog for cancelling an order with reason selection
class _CancelOrderDialog extends StatefulWidget {
  const _CancelOrderDialog();

  @override
  State<_CancelOrderDialog> createState() => _CancelOrderDialogState();
}

class _CancelOrderDialogState extends State<_CancelOrderDialog> {
  String? selectedReason;
  final TextEditingController _customReasonController = TextEditingController();
  String? errorMessage;

  final List<String> cancellationReasons = [
    'Changed my mind',
    'Found a better price elsewhere',
    'Ordered by mistake',
    'Delivery time is too long',
    'Need to change shipping address',
    'Payment issues',
    'Product no longer needed',
    'Other',
  ];

  @override
  void dispose() {
    _customReasonController.dispose();
    super.dispose();
  }

  void _handleCancel() {
    // Validate selection
    if (selectedReason == null) {
      setState(() {
        errorMessage = 'Please select a reason for cancellation.';
      });
      return;
    }

    // Validate custom reason if "Other" is selected
    if (selectedReason == 'Other' &&
        _customReasonController.text.trim().isEmpty) {
      setState(() {
        errorMessage = 'Please specify your reason for cancellation.';
      });
      return;
    }

    // Close dialog and return result - explicitly create a Map<String, String>
    final result = <String, String>{
      'reason': selectedReason!,
      if (selectedReason == 'Other')
        'customReason': _customReasonController.text.trim(),
    };

    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(Icons.cancel_outlined, color: AppColors.error),
          const SizedBox(width: 8),
          const Text('Cancel Order'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Please tell us why you want to cancel this order:',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            if (errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: AppColors.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        errorMessage!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            ...cancellationReasons.map((reason) {
              return RadioListTile<String>(
                title: Text(reason, style: AppTextStyles.bodyMedium),
                value: reason,
                groupValue: selectedReason,
                activeColor: AppColors.primary,
                onChanged: (value) {
                  setState(() {
                    selectedReason = value;
                    errorMessage = null; // Clear error when selection changes
                  });
                },
                contentPadding: EdgeInsets.zero,
                visualDensity: const VisualDensity(
                  horizontal: -4,
                  vertical: -4,
                ),
              );
            }),
            if (selectedReason == 'Other') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _customReasonController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Please specify your reason...',
                  hintStyle: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.onSurface.withValues(alpha: 0.5),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.primary),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.primary, width: 2),
                  ),
                  filled: true,
                  fillColor: AppColors.background,
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Keep Order',
            style: TextStyle(color: AppColors.onSurface.withValues(alpha: 0.6)),
          ),
        ),
        ElevatedButton(
          onPressed: _handleCancel,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: AppColors.onPrimary,
          ),
          child: const Text('Cancel Order'),
        ),
      ],
    );
  }
}
