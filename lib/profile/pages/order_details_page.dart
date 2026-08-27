import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../../core/app_theme/app_text_styles.dart';
import '../../core/app_theme/ink_palette.dart';
import '../../core/app_theme/theme_utils.dart';
import '../../core/widgets/app_network_image.dart';
import '../../product/models/order_model.dart' as order_model;
import '../../product/checkout_routes.dart';
import '../../product/pages/paymongo_webview_page.dart';
import '../../product/pages/cart_page.dart';
import '../../product/services/cart_service.dart';
import '../../product/services/jrs_tracking_service.dart';
import '../../product/services/user_service.dart';
import '../../product/widgets/loading_skeletons.dart';
import '../../services/chat_service.dart';
import '../../utils/app_logger.dart';
import '../../utils/currency_formatter.dart';
import '../services/order_service.dart';
import 'add_review_page.dart';
import 'orders_page.dart' show CancelOrderDialog;

/// A single order, in tracking order.
///
/// The screen answers its questions in the order they get asked: where is it,
/// when did each stage happen, what is in it, where is it going, what was paid.
/// Delivery state leads; the receipt follows.
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

  /// Widest the content grows to before it centres.
  static const double _kMaxContentWidth = 1060;

  /// The receipt column on desktop.
  static const double _kSideWidth = 360;

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
      if (!mounted) return;
      setState(() {
        _trackingResult = result;
        _isLoadingTracking = false;
        if (!result.success) {
          _trackingError =
              result.error ?? 'Failed to load tracking information';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingTracking = false;
        _trackingError = e.toString();
      });
      AppLogger.d('Error loading tracking: $e');
    }
  }

  // ── Palette ──────────────────────────────────────────────────────────────

  InkPalette get ink => InkPalette.of(context);

  /// Destructive red. [InkPalette] reserves amber for urgency, so danger needs
  /// its own tone that still reads in both themes.
  Color get _danger =>
      ink.isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);

  Color get _muted => ink.text.withValues(alpha: 0.6);

  @override
  Widget build(BuildContext context) {
    final isWide = context.isWideLayout;
    final horizontalPadding = isWide ? 24.0 : 16.0;

    return Scaffold(
      backgroundColor: ink.bg,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
            child: Column(
              children: [
                _buildAppBar(),
                Expanded(
                  child: isWide
                      ? _buildWideBody(horizontalPadding)
                      : _buildNarrowBody(horizontalPadding),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Back, the order number, and a direct line to the seller — the one thing a
  /// buyer reaches for when a delivery has gone wrong.
  Widget _buildAppBar() {
    final id = widget.order.orderId.length > 8
        ? widget.order.orderId.substring(0, 8)
        : widget.order.orderId;

    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
      decoration: BoxDecoration(
        color: ink.bg,
        border: Border(bottom: BorderSide(color: ink.border)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.arrow_back, color: ink.text),
            tooltip: 'Back',
          ),
          Expanded(
            child: Text(
              '#${id.toUpperCase()}',
              textAlign: TextAlign.center,
              style: AppTextStyles.titleMedium.copyWith(
                fontFamily: AppTextStyles.secondaryFont,
                color: ink.text,
                fontWeight: FontWeight.w700,
                fontSize: 15,
                letterSpacing: 1.0,
              ),
            ),
          ),
          IconButton(
            onPressed: () => _contactSeller(),
            icon: Icon(Icons.support_agent_outlined, color: ink.text),
            tooltip: 'Contact seller',
          ),
        ],
      ),
    );
  }

  // ── Layout ───────────────────────────────────────────────────────────────

  /// Delivery state, then the timeline, then what is in the box.
  List<Widget> _trackingColumn() {
    return [
      _buildStatusHeadline(),
      const SizedBox(height: 18),
      if (widget.order.hasSameDayShipping) ...[
        _buildLalamoveTrackingSection(),
        const SizedBox(height: 14),
      ],
      if (_getTrackingId() != null) ...[
        _buildTrackingSection(),
        const SizedBox(height: 14),
      ],
      _buildStatusTimeline(),
      const SizedBox(height: 14),
      _buildItemsSection(),
    ];
  }

  /// Where it is going, what it cost, and what can still be done about it.
  List<Widget> _receiptColumn() {
    return [
      _buildShippingInfoSection(),
      const SizedBox(height: 14),
      _buildPaymentInfoSection(),
      const SizedBox(height: 14),
      _buildOrderSummarySection(),
      const SizedBox(height: 20),
      _buildActionButtons(),
      const SizedBox(height: 18),
      _buildFooterNote(),
    ];
  }

  Widget _buildNarrowBody(double horizontalPadding) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        16,
        horizontalPadding,
        28,
      ),
      children: [
        ..._trackingColumn(),
        const SizedBox(height: 14),
        ..._receiptColumn(),
      ],
    );
  }

  /// On desktop the receipt sits beside the tracking rather than a screen below
  /// it: the two answer different questions and neither should scroll the other
  /// out of reach.
  Widget _buildWideBody(double horizontalPadding) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(horizontalPadding, 16, 8, 28),
            children: _trackingColumn(),
          ),
        ),
        SizedBox(
          width: _kSideWidth,
          child: ListView(
            padding: EdgeInsets.fromLTRB(8, 16, horizontalPadding, 28),
            children: _receiptColumn(),
          ),
        ),
      ],
    );
  }

  // ── Shared chrome ────────────────────────────────────────────────────────

  Widget _card({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink.border),
      ),
      child: child,
    );
  }

  Widget _cardTitle(String title, {IconData? icon, Widget? trailing}) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: ink.emerald),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            title,
            style: AppTextStyles.titleMedium.copyWith(
              color: ink.text,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _badge({
    required String label,
    required IconData icon,
    required Color tone,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: ink.isDark ? 0.16 : 0.11),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tone.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: tone),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: tone,
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _notice({
    required IconData icon,
    required Color tone,
    required String text,
    String? title,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: ink.isDark ? 0.14 : 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: tone, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: tone,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  text,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: title != null
                        ? tone
                        : ink.text.withValues(alpha: 0.75),
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filledButton({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
    Color? color,
    Color? onColor,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label, style: AppTextStyles.buttonMedium),
        style: ElevatedButton.styleFrom(
          backgroundColor: color ?? ink.emerald,
          foregroundColor: onColor ?? ink.onEmerald,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Widget _outlinedButton({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
    Color? tone,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label, style: AppTextStyles.buttonMedium),
        style: OutlinedButton.styleFrom(
          foregroundColor: tone ?? ink.text,
          side: BorderSide(
            color: tone == null ? ink.border : tone.withValues(alpha: 0.45),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  void _showSnack(
    String message, {
    Color? tone,
    IconData? icon,
    int seconds = 2,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 8),
            ],
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: tone ?? ink.emerald,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: Duration(seconds: seconds),
      ),
    );
  }

  Widget _loadingOverlay() =>
      Center(child: CircularProgressIndicator(color: ink.emerald));

  // ── Headline ─────────────────────────────────────────────────────────────

  /// The status badge and the one line that answers "where is my order",
  /// exactly as the orders list promised it.
  Widget _buildStatusHeadline() {
    final order = widget.order;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _badge(
              label: _formatStatus(order.status),
              icon: _statusIcon(order.status),
              tone: _statusTone(order.status),
            ),
            if (order.hasSameDayShipping) ...[
              const SizedBox(width: 8),
              _badge(
                label: 'Same Day',
                icon: Icons.motorcycle_outlined,
                tone: ink.emeraldSoft,
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Text(
          _headline(order),
          style: AppTextStyles.headlineSmall.copyWith(
            color: ink.text,
            fontWeight: FontWeight.w800,
            fontSize: 28,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Placed on ${_formatDate(order.createdAt)} · '
          '${order.items.length} item${order.items.length == 1 ? '' : 's'}',
          style: AppTextStyles.bodyMedium.copyWith(
            fontFamily: AppTextStyles.secondaryFont,
            color: _muted,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  String _headline(order_model.Order order) {
    switch (order.status) {
      case order_model.OrderStatus.pending:
        return 'Waiting for payment';
      case order_model.OrderStatus.confirmed:
        return 'Payment confirmed';
      case order_model.OrderStatus.to_ship:
        return 'Being packed';
      case order_model.OrderStatus.shipping:
        return order.hasSameDayShipping ? 'Arriving today' : 'On the way';
      case order_model.OrderStatus.delivered:
        return 'Delivered';
      case order_model.OrderStatus.completed:
        return 'Order completed';
      case order_model.OrderStatus.cancelled:
        return 'Order cancelled';
      default:
        return _formatStatus(order.status);
    }
  }

  // ── Same Day (Lalamove) ──────────────────────────────────────────────────

  /// Same Day Delivery tracking card. Streams the order doc so the rider
  /// status/driver refresh live (the webhook writes them), shows a phase
  /// timeline, the driver, and an embedded live map (Lalamove's share link).
  Widget _buildLalamoveTrackingSection() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('Order')
          .doc(widget.order.orderId)
          .snapshots(),
      builder: (context, snapshot) {
        // Prefer live doc data; fall back to the order passed into the page.
        Map<String, dynamic>? lalamove = widget.order.lalamove;
        final data = snapshot.data?.data();
        if (data != null && data['lalamove'] is Map) {
          lalamove = Map<String, dynamic>.from(data['lalamove'] as Map);
        }

        // First booked seller record (has a shareLink or a status).
        String? status;
        String? shareLink;
        Map? driver;
        if (lalamove != null) {
          for (final entry in lalamove.values) {
            if (entry is Map &&
                (entry['shareLink'] != null || entry['status'] != null)) {
              status = entry['status']?.toString();
              shareLink = entry['shareLink']?.toString();
              driver = entry['driver'] is Map ? entry['driver'] as Map : null;
              break;
            }
          }
        }
        if (shareLink != null && shareLink.isEmpty) shareLink = null;

        // Nothing cached and the first snapshot still in flight: hold the
        // card's shape rather than popping a timeline in a beat later.
        final waitingOnFirstSnapshot =
            snapshot.connectionState == ConnectionState.waiting &&
            widget.order.lalamove == null;

        return _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _cardTitle(
                'Same Day delivery',
                icon: Icons.motorcycle_outlined,
                trailing: status != null && status.isNotEmpty
                    ? _badge(
                        label: _prettyLalamoveStatus(status),
                        icon: Icons.bolt_outlined,
                        tone: _lalamovePhaseIndex(status) == -1
                            ? _danger
                            : ink.emeraldSoft,
                      )
                    : null,
              ),
              const SizedBox(height: 16),

              if (waitingOnFirstSnapshot)
                const TrackingSkeleton(eventCount: 4)
              else ...[
                _buildLalamoveTimeline(status),

                if (driver != null && driver['name'] != null) ...[
                  const SizedBox(height: 16),
                  _buildDriverCard(driver),
                ],

                // Lalamove's own page carries the moving driver, route and
                // ETA. It used to be embedded *and* linked; two copies of the
                // same map on one card was just noise, so only the link stays.
                if (shareLink != null) ...[
                  const SizedBox(height: 16),
                  _filledButton(
                    label: 'Open live map',
                    icon: Icons.open_in_new,
                    onTap: () async {
                      final uri = Uri.tryParse(shareLink!);
                      if (uri != null) {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                  ),
                ] else ...[
                  const SizedBox(height: 14),
                  _notice(
                    icon: Icons.info_outline,
                    tone: ink.emerald,
                    text: (status == null || status.isEmpty)
                        ? 'The seller is preparing your parcel. A rider is booked once it is ready, and live tracking appears here.'
                        : 'Waiting for a rider to be assigned. Live tracking appears here once your rider is on the way.',
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  /// Ordered phases a Same Day delivery moves through, mapped from Lalamove
  /// status.
  ///
  /// The rider is only booked when the seller marks the order ready-to-ship, so
  /// a null status means no Lalamove order exists yet — the parcel is still with
  /// the seller.
  static const List<String> _lalamovePhases = [
    'Seller preparing your parcel',
    'Finding a rider',
    'Rider heading to store',
    'Picked up — on the way to you',
    'Delivered',
  ];

  /// Index of the current phase (0-based), or -1 in a terminal failure state
  /// (canceled/rejected/expired).
  int _lalamovePhaseIndex(String? status) {
    final raw = (status ?? '').toUpperCase();
    if (raw.isEmpty) return 0;
    switch (raw) {
      case 'ASSIGNING_DRIVER':
        return 1;
      case 'ON_GOING':
        return 2;
      case 'PICKED_UP':
        return 3;
      case 'COMPLETED':
        return 4;
      case 'CANCELED':
      case 'REJECTED':
      case 'EXPIRED':
        return -1;
      // Booked, but a status we don't map yet — the rider hunt has begun.
      default:
        return 1;
    }
  }

  Widget _buildLalamoveTimeline(String? status) {
    final current = _lalamovePhaseIndex(status);

    if (current == -1) {
      return _notice(
        icon: Icons.cancel_outlined,
        tone: _danger,
        title: _prettyLalamoveStatus(status ?? ''),
        text: 'Contact the seller to arrange another delivery for this order.',
      );
    }

    return Column(
      children: List.generate(_lalamovePhases.length, (i) {
        return _timelineRow(
          title: _lalamovePhases[i],
          done: i < current,
          active: i == current,
          reached: i <= current,
          isLast: i == _lalamovePhases.length - 1,
        );
      }),
    );
  }

  /// One stop on a vertical timeline: the node, the rail below it, and the
  /// label. Shared by the Same Day phases and the order's own history.
  Widget _timelineRow({
    required String title,
    String? subtitle,
    required bool done,
    required bool active,
    required bool reached,
    required bool isLast,
  }) {
    final nodeColor = reached ? ink.emerald : ink.text.withValues(alpha: 0.2);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: reached ? ink.emerald : ink.bg,
                  shape: BoxShape.circle,
                  border: Border.all(color: nodeColor),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: ink.emerald.withValues(alpha: 0.22),
                            blurRadius: 0,
                            spreadRadius: 4,
                          ),
                        ]
                      : null,
                ),
                child: done || (reached && isLast)
                    ? Icon(Icons.check, size: 13, color: ink.onEmerald)
                    : null,
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: done
                        ? ink.emerald
                        : ink.text.withValues(alpha: 0.12),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18, top: 1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: reached
                          ? ink.text
                          : ink.text.withValues(alpha: 0.5),
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodySmall.copyWith(
                        fontFamily: AppTextStyles.secondaryFont,
                        color: ink.text.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverCard(Map driver) {
    final name = driver['name']?.toString() ?? 'Rider';
    final plate = driver['plateNumber']?.toString();
    final phone = driver['phone']?.toString();
    final photo = driver['photo']?.toString();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ink.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ink.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: ink.emerald.withValues(alpha: 0.15),
            backgroundImage: (photo != null && photo.isNotEmpty)
                ? NetworkImage(photo)
                : null,
            child: (photo == null || photo.isEmpty)
                ? Icon(Icons.person, color: ink.emerald)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: ink.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                if (plate != null && plate.isNotEmpty)
                  Text(
                    plate,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontFamily: AppTextStyles.secondaryFont,
                      color: _muted,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          if (phone != null && phone.isNotEmpty) ...[
            _circleAction(
              icon: Icons.phone,
              tooltip: 'Call rider',
              filled: true,
              onTap: () async {
                final uri = Uri(scheme: 'tel', path: phone);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
              },
            ),
            const SizedBox(width: 8),
          ],
          _circleAction(
            icon: Icons.chat_bubble_outline,
            tooltip: 'Message seller',
            onTap: () => _contactSeller(),
          ),
        ],
      ),
    );
  }

  Widget _circleAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: filled ? ink.emerald : ink.surface,
            shape: BoxShape.circle,
            border: Border.all(color: filled ? ink.emerald : ink.border),
          ),
          child: Icon(icon, size: 18, color: filled ? ink.onEmerald : ink.text),
        ),
      ),
    );
  }

  String _prettyLalamoveStatus(String raw) {
    switch (raw.toUpperCase()) {
      case 'ASSIGNING_DRIVER':
        return 'Finding a rider';
      case 'ON_GOING':
        return 'Heading to store';
      case 'PICKED_UP':
        return 'On the way to you';
      case 'COMPLETED':
        return 'Delivered';
      case 'CANCELED':
        return 'Delivery canceled';
      case 'REJECTED':
        return 'Rider unavailable';
      case 'EXPIRED':
        return 'Booking expired';
      default:
        return raw;
    }
  }

  // ── Courier tracking (JRS) ───────────────────────────────────────────────

  Widget _buildTrackingSection() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(
            'Package tracking',
            icon: Icons.local_shipping_outlined,
            trailing: _isLoadingTracking
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: ink.emerald,
                    ),
                  )
                : IconButton(
                    icon: Icon(Icons.refresh, color: ink.emerald, size: 20),
                    onPressed: _loadTracking,
                    tooltip: 'Refresh tracking',
                    visualDensity: VisualDensity.compact,
                  ),
          ),
          const SizedBox(height: 16),
          if (_isLoadingTracking)
            const TrackingSkeleton()
          else if (_trackingError != null)
            _notice(
              icon: Icons.error_outline,
              tone: _danger,
              title: 'Unable to load tracking',
              text: _trackingError!,
            )
          else if (_trackingResult != null)
            _buildTrackingResult()
          else
            _notice(
              icon: Icons.info_outline,
              tone: ink.amber,
              text:
                  'Tracking information will be available once your package is shipping.',
            ),
        ],
      ),
    );
  }

  Widget _buildTrackingResult() {
    final result = _trackingResult!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _infoRow('Tracking ID', _getTrackingId() ?? 'N/A'),
        _infoRow('Status', result.status),
        if (result.location != null)
          _infoRow('Current location', result.location!),
        if (result.timestamp != null)
          _infoRow('Last update', _formatTrackingDateTime(result.timestamp!)),
        if (result.events.isNotEmpty) ...[
          const SizedBox(height: 6),
          Divider(height: 1, color: ink.border),
          const SizedBox(height: 16),
          Text(
            'Tracking history',
            style: AppTextStyles.bodyMedium.copyWith(
              color: ink.text,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < result.events.length; i++)
            _buildTrackingEvent(
              result.events[i],
              isLast: i == result.events.length - 1,
              isFirst: i == 0,
            ),
        ],
      ],
    );
  }

  Widget _buildTrackingEvent(
    TrackingEvent event, {
    required bool isLast,
    required bool isFirst,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: isFirst
                      ? ink.emerald
                      : ink.text.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.only(top: 4),
                    color: ink.text.withValues(alpha: 0.12),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.status,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: ink.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                  Text(
                    event.location,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: _muted,
                      fontSize: 12.5,
                    ),
                  ),
                  if (event.description != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      event.description!,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: ink.text.withValues(alpha: 0.5),
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    _formatTrackingDateTime(event.timestamp),
                    style: AppTextStyles.bodySmall.copyWith(
                      fontFamily: AppTextStyles.secondaryFont,
                      color: ink.text.withValues(alpha: 0.45),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Progress ─────────────────────────────────────────────────────────────

  /// The order's own history, each stage carrying its timestamp — "when did it
  /// ship" is the second question after "where is it".
  Widget _buildStatusTimeline() {
    final history = widget.order.statusHistory;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('Progress', icon: Icons.timeline_outlined),
          const SizedBox(height: 18),
          if (history.isEmpty)
            Text(
              'No updates recorded yet.',
              style: AppTextStyles.bodySmall.copyWith(color: _muted),
            )
          else
            for (var i = 0; i < history.length; i++)
              _timelineRow(
                title: history[i].note ?? _formatStatusTitle(history[i].status),
                subtitle: _formatDateTime(history[i].timestamp),
                done: i < history.length - 1,
                active: i == history.length - 1,
                reached: true,
                isLast: i == history.length - 1,
              ),
        ],
      ),
    );
  }

  // ── Items ────────────────────────────────────────────────────────────────

  Widget _buildItemsSection() {
    final items = widget.order.items;

    return _card(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(
            'In this delivery',
            icon: Icons.inventory_2_outlined,
            trailing: Text(
              '${items.length} item${items.length == 1 ? '' : 's'}',
              style: AppTextStyles.bodySmall.copyWith(
                fontFamily: AppTextStyles.secondaryFont,
                color: _muted,
                fontSize: 12.5,
              ),
            ),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Divider(height: 1, color: ink.border),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: _buildOrderItem(items[i]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOrderItem(order_model.OrderItem item) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: ink.surfaceHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ink.border),
          ),
          child: item.productImage.isNotEmpty
              ? AppNetworkImage(
                  url: item.productImage,
                  width: 56,
                  height: 56,
                  backgroundColor: ink.surfaceHigh,
                  errorIconSize: 22,
                )
              : Icon(
                  Icons.inventory_2_outlined,
                  color: ink.text.withValues(alpha: 0.4),
                  size: 22,
                ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.productName,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: ink.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                [
                  if (item.variationName != null) item.variationName!,
                  'Qty ${item.quantity}',
                ].join(' · '),
                style: AppTextStyles.bodySmall.copyWith(
                  fontFamily: AppTextStyles.secondaryFont,
                  color: _muted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Sold by ${item.sellerName}',
                style: AppTextStyles.bodySmall.copyWith(
                  color: ink.text.withValues(alpha: 0.45),
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          CurrencyFormatter.formatWithPeso(item.price),
          style: AppTextStyles.bodyMedium.copyWith(
            fontFamily: AppTextStyles.secondaryFont,
            color: ink.text,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  // ── Receipt ──────────────────────────────────────────────────────────────

  Widget _buildShippingInfoSection() {
    final info = widget.order.shippingInfo;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('Delivery address', icon: Icons.place_outlined),
          const SizedBox(height: 16),
          _infoRow('Name', info.fullName),
          _infoRow('Phone', info.phoneNumber),
          _infoRow(
            'Address',
            '${info.addressLine1}'
                '${info.addressLine2 != null ? '\n${info.addressLine2}' : ''}'
                '\n${info.city}, ${info.state} ${info.postalCode}'
                '\n${info.country}',
          ),
          if (info.notes != null) _infoRow('Notes', info.notes!),
        ],
      ),
    );
  }

  Widget _buildPaymentInfoSection() {
    final paymongo = widget.order.paymongo;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('Payment', icon: Icons.credit_card_outlined),
          const SizedBox(height: 16),
          _infoRow('Method', _formatPaymentMethod(paymongo.paymentMethod)),
          _infoRow('Status', _formatPaymentStatus(paymongo.paymentStatus)),
          _infoRow(
            'Amount',
            '${CurrencyFormatter.formatWithPeso(paymongo.amount)} '
                '${paymongo.currency.toUpperCase()}',
          ),
          if (paymongo.paidAt != null)
            _infoRow('Paid at', _formatDateTime(paymongo.paidAt!)),
          if (paymongo.checkoutSessionId != null)
            _infoRow('Session ID', paymongo.checkoutSessionId!),
          if (paymongo.paymentIntentId != null)
            _infoRow('Intent ID', paymongo.paymentIntentId!),
          if (paymongo.checkoutUrl != null && _canResumePayment())
            _infoRow('Payment link', 'Available — resume below'),
        ],
      ),
    );
  }

  /// What the buyer actually paid for delivery.
  ///
  /// `buyerShippingCharge` is the buyer's share; `shippingCost` is the courier's
  /// full fee, which the seller may absorb in whole or in part. This row used to
  /// fall back to the latter whenever the former was zero, which meant a pickup
  /// order (nothing to deliver, ₱0 to the buyer) and a voucher-covered one both
  /// displayed a fee the buyer never paid — and one that did not reconcile with
  /// the Total directly underneath it.
  ///
  /// The fallback is kept for orders predating `buyerShippingCharge`, which
  /// recorded only `shippingCost`. Those are identifiable by having no
  /// per-seller breakdowns: every order written since the field was introduced
  /// carries them.
  String _buyerShippingLabel() {
    final summary = widget.order.summary;
    if (summary.buyerShippingCharge > 0) {
      return CurrencyFormatter.formatWithPeso(summary.buyerShippingCharge);
    }

    final isLegacyOrder = widget.order.sellerFeeBreakdowns.isEmpty;
    if (isLegacyOrder && summary.shippingCost > 0) {
      return CurrencyFormatter.formatWithPeso(summary.shippingCost);
    }

    // Naming the reason beats a bare "Free": on a pickup order the buyer should
    // see that there is no delivery fee because there is no delivery.
    if (widget.order.hasPickupShipping && !widget.order.hasSameDayShipping &&
        !widget.order.hasStandardShipping && !widget.order.hasExpressShipping) {
      return 'Free (pickup)';
    }
    return 'Free';
  }

  Widget _buildOrderSummarySection() {
    final summary = widget.order.summary;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('Order summary', icon: Icons.receipt_long_outlined),
          const SizedBox(height: 16),
          _summaryRow(
            'Subtotal',
            CurrencyFormatter.formatWithPeso(summary.subtotal),
          ),
          _summaryRow('Shipping', _buyerShippingLabel()),
          if (summary.taxAmount > 0)
            _summaryRow(
              'Tax',
              CurrencyFormatter.formatWithPeso(summary.taxAmount),
            ),
          if (summary.discountAmount > 0)
            _summaryRow(
              'Discount',
              '-${CurrencyFormatter.formatWithPeso(summary.discountAmount)}',
              good: true,
            ),
          const SizedBox(height: 12),
          Divider(height: 1, color: ink.border),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'Total',
                style: AppTextStyles.titleMedium.copyWith(
                  color: ink.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              Text(
                CurrencyFormatter.formatWithPeso(summary.total),
                style: AppTextStyles.headlineSmall.copyWith(
                  fontFamily: AppTextStyles.secondaryFont,
                  color: ink.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 24,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooterNote() {
    return Text(
      'Order total ${CurrencyFormatter.formatWithPeso(widget.order.summary.total)} '
      '· placed ${_formatDate(widget.order.createdAt)}',
      textAlign: TextAlign.center,
      style: AppTextStyles.bodySmall.copyWith(
        fontFamily: AppTextStyles.secondaryFont,
        color: ink.text.withValues(alpha: 0.45),
        fontSize: 12.5,
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: _muted,
                fontSize: 12.5,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.bodySmall.copyWith(
                color: ink.text,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool good = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: _muted,
              fontSize: 13,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: AppTextStyles.bodySmall.copyWith(
              fontFamily: AppTextStyles.secondaryFont,
              color: good ? ink.emerald : ink.text,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Widget _buildActionButtons() {
    final returnEligibility = _canRequestReturn();
    final canRequestReturn = returnEligibility['eligible'] == true;
    final status = widget.order.status;

    final List<Widget> buttons = [];

    if (status == order_model.OrderStatus.delivered) {
      if (canRequestReturn) {
        buttons.add(
          _filledButton(
            label:
                'Request return (${returnEligibility['daysRemaining']} days left)',
            icon: Icons.assignment_return_outlined,
            color: ink.amber,
            onColor: ink.onAmber,
            onTap: () => _requestReturn(),
          ),
        );
      }
      buttons.add(
        _filledButton(
          label: 'Complete order',
          icon: Icons.check_circle_outline,
          onTap: () => _completeOrder(),
        ),
      );
    } else if (status == order_model.OrderStatus.completed) {
      buttons.add(
        _filledButton(
          label: 'Add review',
          icon: Icons.star_outline,
          onTap: () => _addReview(),
        ),
      );
      buttons.add(
        _outlinedButton(
          label: 'Reorder items',
          icon: Icons.refresh,
          onTap: () => _reorderItems(),
        ),
      );
    } else if (status == order_model.OrderStatus.return_requested ||
        status == order_model.OrderStatus.return_approved ||
        status == order_model.OrderStatus.return_rejected ||
        status == order_model.OrderStatus.returned ||
        status == order_model.OrderStatus.cancelled) {
      buttons.add(
        _filledButton(
          label: 'Reorder items',
          icon: Icons.refresh,
          onTap: () => _reorderItems(),
        ),
      );
    } else {
      if (_canResumePayment()) {
        buttons.add(
          _filledButton(
            label: 'Resume payment',
            icon: Icons.payment,
            color: ink.amber,
            onColor: ink.onAmber,
            onTap: () => _resumePayment(),
          ),
        );
      }
      if (_canCancelOrder()) {
        buttons.add(
          _outlinedButton(
            label: 'Cancel order',
            icon: Icons.close,
            tone: _danger,
            onTap: () => _cancelOrder(),
          ),
        );
      }
    }

    buttons.add(
      _outlinedButton(
        label: 'Contact seller',
        icon: Icons.chat_bubble_outline,
        onTap: () => _contactSeller(),
      ),
    );

    return Column(
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          buttons[i],
        ],
      ],
    );
  }

  // ── Status vocabulary ────────────────────────────────────────────────────

  Color _statusTone(order_model.OrderStatus status) {
    switch (status) {
      case order_model.OrderStatus.pending:
        return ink.amber;
      case order_model.OrderStatus.confirmed:
      case order_model.OrderStatus.delivered:
      case order_model.OrderStatus.completed:
        return ink.emerald;
      case order_model.OrderStatus.to_ship:
      case order_model.OrderStatus.shipping:
      case order_model.OrderStatus.return_approved:
        return ink.emeraldSoft;
      case order_model.OrderStatus.cancelled:
      case order_model.OrderStatus.payment_failed:
      case order_model.OrderStatus.failed_delivery:
      case order_model.OrderStatus.return_rejected:
        return _danger;
      case order_model.OrderStatus.expired:
      case order_model.OrderStatus.return_requested:
        return ink.amber;
      case order_model.OrderStatus.refunded:
      case order_model.OrderStatus.returned:
        return ink.text.withValues(alpha: 0.55);
    }
  }

  IconData _statusIcon(order_model.OrderStatus status) {
    switch (status) {
      case order_model.OrderStatus.pending:
        return Icons.schedule;
      case order_model.OrderStatus.confirmed:
        return Icons.check_circle_outline;
      case order_model.OrderStatus.to_ship:
        return Icons.inventory_2_outlined;
      case order_model.OrderStatus.shipping:
        return Icons.local_shipping_outlined;
      case order_model.OrderStatus.delivered:
        return Icons.check_circle;
      case order_model.OrderStatus.completed:
        return Icons.verified_outlined;
      case order_model.OrderStatus.cancelled:
        return Icons.cancel_outlined;
      case order_model.OrderStatus.refunded:
        return Icons.replay;
      case order_model.OrderStatus.payment_failed:
        return Icons.error_outline;
      case order_model.OrderStatus.expired:
        return Icons.timer_off_outlined;
      case order_model.OrderStatus.failed_delivery:
        return Icons.report_gmailerrorred_outlined;
      case order_model.OrderStatus.return_requested:
        return Icons.assignment_return_outlined;
      case order_model.OrderStatus.return_approved:
        return Icons.assignment_turned_in_outlined;
      case order_model.OrderStatus.return_rejected:
        return Icons.assignment_late_outlined;
      case order_model.OrderStatus.returned:
        return Icons.assignment_returned_outlined;
    }
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
            return 'Order Delivered';
          case order_model.OrderStatus.completed:
            return 'Order Completed';
          case order_model.OrderStatus.cancelled:
            return 'Order Cancelled';
          case order_model.OrderStatus.refunded:
            return 'Order Refunded';
          case order_model.OrderStatus.payment_failed:
            return 'Payment Failed';
          case order_model.OrderStatus.expired:
            return 'Payment Expired';
          case order_model.OrderStatus.failed_delivery:
            return 'Delivery Failed';
          case order_model.OrderStatus.return_requested:
            return 'Return Requested';
          case order_model.OrderStatus.return_approved:
            return 'Return Approved';
          case order_model.OrderStatus.return_rejected:
            return 'Return Rejected';
          case order_model.OrderStatus.returned:
            return 'Order Returned';
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
        return 'Maya';
      case order_model.PaymentMethod.shopeePay:
        return 'Shopee Pay';
      case order_model.PaymentMethod.billEase:
        return 'BillEase (Buy Now Pay Later)';
      case order_model.PaymentMethod.cashOnDelivery:
        return 'Cash on Delivery';
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
        widget.order.paymongo.checkoutUrl != null &&
        widget.order.paymongo.checkoutUrl!.isNotEmpty;
  }

  /// Check if user can request a return for this order
  Map<String, dynamic> _canRequestReturn() {
    return OrderService.isEligibleForReturn(widget.order);
  }

  void _reorderItems() async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _loadingOverlay(),
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
      if (!mounted) return;
      Navigator.of(context).pop();

      // Navigate to cart page
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const CartPage()),
      );

      // Show success message
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _showSnack(
            '${widget.order.items.length} items added to cart',
            icon: Icons.shopping_cart_outlined,
          );
        }
      });
    } catch (e) {
      AppLogger.d('Error reordering items: $e');

      // Close loading dialog if still open
      if (!mounted) return;
      Navigator.of(context).pop();

      _showSnack(
        'Failed to reorder items. Please try again.',
        tone: _danger,
        icon: Icons.error_outline,
      );
    }
  }

  void _resumePayment() async {
    if (!_canResumePayment()) {
      _showSnack(
        'Payment cannot be resumed for this order',
        tone: _danger,
        icon: Icons.error_outline,
      );
      return;
    }

    final checkoutUrl = widget.order.paymongo.checkoutUrl!;
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
          if (!mounted) return;
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: ink.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  Icon(Icons.payment, color: ink.emerald),
                  const SizedBox(width: 8),
                  Text('Payment resumed', style: TextStyle(color: ink.text)),
                ],
              ),
              content: Text(
                'Your payment page has been opened in a new tab. Please complete your payment and return to this page.',
                style: AppTextStyles.bodyMedium.copyWith(color: _muted),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('OK', style: TextStyle(color: ink.emerald)),
                ),
              ],
            ),
          );
        }
      } else {
        // For mobile, use WebView
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            // Resuming a payment opens the same page as paying the first time,
            // so it answers to the same URL.
            settings: RouteSettings(
              name: checkoutSessionPath(
                widget.order.paymongo.checkoutSessionId ?? widget.order.orderId,
              ),
            ),
            builder: (context) => PaymongoWebViewPage(
              checkoutUrl: checkoutUrl,
              successUrl: 'https://dentpal-store.web.app/payment-success',
              cancelUrl: 'https://dentpal-store.web.app/payment-failed',
              onPaymentComplete: (isSuccess, orderId) {
                AppLogger.d(
                  'Payment resumed completed. Success: $isSuccess, Order ID: $orderId',
                );

                if (isSuccess) {
                  _showSnack(
                    'Payment completed successfully!',
                    icon: Icons.check_circle_outline,
                  );
                  // Navigate back to orders page
                  Navigator.of(context).pop();
                } else {
                  _showSnack(
                    'Payment was cancelled or failed',
                    tone: ink.amber,
                    icon: Icons.info_outline,
                  );
                }
              },
            ),
          ),
        );
      }
    } catch (e) {
      AppLogger.d('Error resuming payment: $e');
      if (mounted) {
        _showSnack(
          'Failed to resume payment. Please try again.',
          tone: _danger,
          icon: Icons.error_outline,
        );
      }
    }
  }

  void _cancelOrder() async {
    if (!_canCancelOrder()) {
      _showSnack(
        'This order cannot be cancelled',
        tone: _danger,
        icon: Icons.error_outline,
      );
      return;
    }

    // Show cancellation reason dialog
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => const CancelOrderDialog(),
    );

    if (result == null) return; // User dismissed the dialog
    if (!mounted) return;

    final reason = result['reason']!;
    final customReason = result['customReason'];

    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _loadingOverlay(),
      );

      // Build cancellation note
      final note = customReason != null && customReason.isNotEmpty
          ? '$reason: $customReason'
          : reason;

      await OrderService.cancelOrder(widget.order.orderId, reason: note);

      // Close loading dialog
      if (!mounted) return;
      Navigator.of(context).pop();

      _showSnack(
        'Order cancelled successfully',
        icon: Icons.check_circle_outline,
      );

      // Navigate back to orders page
      Navigator.of(context).pop();
    } catch (e) {
      AppLogger.d('Error cancelling order: $e');

      // Close loading dialog if still open
      if (!mounted) return;
      Navigator.of(context).pop();

      _showSnack(
        'Failed to cancel order. Please try again.',
        tone: _danger,
        icon: Icons.error_outline,
      );
    }
  }

  void _contactSeller() async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _loadingOverlay(),
    );

    try {
      // Get the primary seller ID from the order
      final sellerId = widget.order.sellerIds.isNotEmpty
          ? widget.order.sellerIds.first
          : widget.order.items.first.sellerId;

      if (sellerId.isEmpty) {
        throw Exception('No seller information found for this order');
      }

      final chatService = ChatService();
      final userService = UserService();

      // Get seller information
      final sellerData = await userService.getSellerData(sellerId);
      final sellerName =
          sellerData?['shopName'] ??
          sellerData?['fullName'] ??
          sellerData?['displayName'] ??
          'Seller';

      // Format order date
      final orderDate = DateFormat(
        'MMM dd, yyyy',
      ).format(widget.order.createdAt);

      // Format title as "Order ID - Date"
      final chatTitle = '${widget.order.orderId} - $orderDate';

      // Create or get existing chat room with the seller, including order info
      final chatRoomId = await chatService.getOrCreateChatRoom(
        sellerId,
        orderId: widget.order.orderId,
        orderDate: widget.order.createdAt,
      );

      // Close loading dialog
      if (!mounted) return;
      Navigator.of(context).pop();

      // Navigate to chat detail page with formatted title
      Navigator.of(context).pushNamed(
        '/profile/chats/$chatRoomId',
        arguments: <String, dynamic>{
          'otherUserId': sellerId,
          'otherUserName': chatTitle,
          'otherUserShopName': sellerName,
        },
      );
    } catch (e) {
      // Close loading dialog
      if (!mounted) return;
      Navigator.of(context).pop();

      AppLogger.e('Error contacting seller: $e');

      _showSnack(
        'Failed to contact seller. Please try again.',
        tone: _danger,
        icon: Icons.error_outline,
      );
    }
  }

  void _requestReturn() async {
    // Check eligibility again (in case it changed)
    final eligibility = _canRequestReturn();
    if (eligibility['eligible'] != true) {
      _showSnack(
        eligibility['reason'] ?? 'Cannot request return for this order.',
        tone: _danger,
        icon: Icons.error_outline,
      );
      return;
    }

    // Show return reason dialog
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => const _ReturnRequestDialog(),
    );

    if (result == null) return; // User dismissed the dialog
    if (!mounted) return;

    final reason = result['reason']!;
    final customReason = result['customReason'];

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _loadingOverlay(),
    );

    try {
      await OrderService.requestReturn(
        widget.order.orderId,
        reason: reason,
        customReason: customReason,
      );

      // Close loading dialog
      if (!mounted) return;
      Navigator.of(context).pop();

      _showSnack(
        'Return request submitted. Our team will review it within 1-2 business days.',
        icon: Icons.check_circle_outline,
        seconds: 4,
      );

      // Navigate back to orders page
      Navigator.of(context).pop();
    } catch (e) {
      AppLogger.d('Error requesting return: $e');

      // Close loading dialog if still open
      if (!mounted) return;
      Navigator.of(context).pop();

      _showSnack(
        'Failed to submit return request. Please try again.',
        tone: _danger,
        icon: Icons.error_outline,
      );
    }
  }

  void _completeOrder() async {
    // Confirm completion
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ink.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.check_circle_outline, color: ink.emerald),
            const SizedBox(width: 8),
            Text('Complete order', style: TextStyle(color: ink.text)),
          ],
        ),
        content: Text(
          'Mark this order as completed? This will deduct the stock count for these items and cannot be undone.',
          style: AppTextStyles.bodyMedium.copyWith(color: _muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: _muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: ink.emerald,
              foregroundColor: ink.onEmerald,
              elevation: 0,
            ),
            child: const Text('Complete order'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _loadingOverlay(),
    );

    try {
      await OrderService.markOrderComplete(widget.order.orderId);

      // Close loading dialog
      if (!mounted) return;
      Navigator.of(context).pop();

      _showSnack(
        'Order completed. Stock has been deducted.',
        icon: Icons.check_circle_outline,
        seconds: 3,
      );

      // Navigate back to orders page
      Navigator.of(context).pop();
    } catch (e) {
      AppLogger.d('Error completing order: $e');

      // Close loading dialog if still open
      if (!mounted) return;
      Navigator.of(context).pop();

      _showSnack(
        'Failed to complete order. Please try again.',
        tone: _danger,
        icon: Icons.error_outline,
      );
    }
  }

  void _addReview() async {
    // The review flow lives on its own page — the same one the orders list
    // opens. This used to be a "coming soon" snackbar, left over from before
    // that page existed.
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddReviewPage(order: widget.order)),
    );
    if (result == true && mounted) {
      _showSnack('Thanks for your review!', icon: Icons.star_outline);
    }
  }
}

/// Dialog for requesting a return with reason selection
class _ReturnRequestDialog extends StatefulWidget {
  const _ReturnRequestDialog();

  @override
  State<_ReturnRequestDialog> createState() => _ReturnRequestDialogState();
}

class _ReturnRequestDialogState extends State<_ReturnRequestDialog> {
  String? selectedReason;
  final TextEditingController _customReasonController = TextEditingController();
  String? errorMessage;

  final List<String> returnReasons = [
    'Item is defective or damaged',
    'Wrong item received',
    'Item does not match description',
    'Item quality is not as expected',
    'Changed my mind',
    'Item arrived too late',
    'Better price found elsewhere',
    'Other',
  ];

  @override
  void dispose() {
    _customReasonController.dispose();
    super.dispose();
  }

  void _handleReturn() {
    // Validate selection
    if (selectedReason == null) {
      setState(() {
        errorMessage = 'Please select a reason for the return.';
      });
      return;
    }

    // Validate custom reason if "Other" is selected
    if (selectedReason == 'Other' &&
        _customReasonController.text.trim().isEmpty) {
      setState(() {
        errorMessage = 'Please specify your reason for the return.';
      });
      return;
    }

    // Close dialog and return result
    final result = <String, String>{
      'reason': selectedReason!,
      if (selectedReason == 'Other')
        'customReason': _customReasonController.text.trim(),
    };

    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);
    final danger = ink.isDark
        ? const Color(0xFFF87171)
        : const Color(0xFFDC2626);

    return AlertDialog(
      backgroundColor: ink.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(Icons.assignment_return_outlined, color: ink.amber),
          const SizedBox(width: 8),
          Text('Request return', style: TextStyle(color: ink.text)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ink.emerald.withValues(alpha: ink.isDark ? 0.14 : 0.09),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ink.emerald.withValues(alpha: 0.28)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: ink.emerald, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Return requests are reviewed within 1-2 business days. If approved, you will receive return shipping instructions.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: ink.emerald,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Please tell us why you want to return this order:',
              style: AppTextStyles.bodyMedium.copyWith(
                color: ink.text.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            if (errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: danger.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: danger, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        errorMessage!,
                        style: AppTextStyles.bodySmall.copyWith(color: danger),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            ...returnReasons.map((reason) {
              return RadioListTile<String>(
                title: Text(
                  reason,
                  style: AppTextStyles.bodyMedium.copyWith(color: ink.text),
                ),
                value: reason,
                groupValue: selectedReason,
                activeColor: ink.emerald,
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
                style: AppTextStyles.bodyMedium.copyWith(color: ink.text),
                cursorColor: ink.emerald,
                decoration: InputDecoration(
                  hintText: 'Please describe the issue with your order…',
                  hintStyle: AppTextStyles.bodyMedium.copyWith(
                    color: ink.text.withValues(alpha: 0.45),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: ink.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: ink.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: ink.emerald, width: 2),
                  ),
                  filled: true,
                  fillColor: ink.surfaceHigh,
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
            'Cancel',
            style: TextStyle(color: ink.text.withValues(alpha: 0.6)),
          ),
        ),
        ElevatedButton(
          onPressed: _handleReturn,
          style: ElevatedButton.styleFrom(
            backgroundColor: ink.amber,
            foregroundColor: ink.onAmber,
            elevation: 0,
          ),
          child: const Text('Submit request'),
        ),
      ],
    );
  }
}
