import 'package:flutter/material.dart';

import '../../core/app_theme/app_text_styles.dart';
import '../../core/app_theme/ink_palette.dart';
import '../../core/app_theme/theme_utils.dart';
import '../../core/widgets/app_network_image.dart';
import '../../core/widgets/skeleton.dart';
import '../../product/models/order_model.dart' as order_model;
import '../../product/services/image_upload_service.dart';
import '../models/review_model.dart';
import '../services/review_service.dart';

/// Rating flow for a completed order.
///
/// Written as a checklist rather than a form: every item and every service
/// question is a card with one job, the bar at the bottom always says how much
/// is left, and submit only lights up when the whole thing is answered.
class AddReviewPage extends StatefulWidget {
  final order_model.Order order;

  const AddReviewPage({super.key, required this.order});

  @override
  State<AddReviewPage> createState() => _AddReviewPageState();
}

class _AddReviewPageState extends State<AddReviewPage> {
  static const int _maxPhotos = 5;

  /// Widest the content grows to before it centres. Narrower than the browse
  /// surfaces: this is a single column of questions, not a catalogue.
  static const double _kMaxContentWidth = 720;

  late final List<int> _productRatings;
  int _deliveryServiceRating = 0;
  int? _deliverySpeedRating;
  int? _driverServiceRating;
  final TextEditingController _commentController = TextEditingController();
  final List<String> _photoUrls = [];
  bool _anonymous = false;
  bool _recommend = true;
  bool _submitting = false;
  bool _uploadingPhoto = false;

  // Lazy: the service grabs FirebaseStorage.instance in its field initialiser,
  // so building it eagerly would tie merely *opening* this page to a live
  // Firebase app.
  late final ImageUploadService _imageUploadService = ImageUploadService();

  bool get _isPickup => widget.order.hasPickupShipping;

  @override
  void initState() {
    super.initState();
    _productRatings = List<int>.filled(widget.order.items.length, 0);
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    if (_productRatings.any((r) => r == 0)) return false;
    if (_deliveryServiceRating == 0) return false;
    if (!_isPickup) {
      if ((_deliverySpeedRating ?? 0) == 0) return false;
      if ((_driverServiceRating ?? 0) == 0) return false;
    }
    return true;
  }

  /// How many ratings the form asks for, and how many are answered — the bottom
  /// bar states this so "why is submit greyed out" never has to be guessed.
  int get _requiredRatings => widget.order.items.length + (_isPickup ? 1 : 3);

  int get _answeredRatings {
    var answered = _productRatings.where((r) => r > 0).length;
    if (_deliveryServiceRating > 0) answered++;
    if (!_isPickup) {
      if ((_deliverySpeedRating ?? 0) > 0) answered++;
      if ((_driverServiceRating ?? 0) > 0) answered++;
    }
    return answered;
  }

  Future<void> _addPhoto() async {
    final source = await _imageUploadService.showImageSourceDialog(context);
    if (source == null) return;

    setState(() => _uploadingPhoto = true);
    try {
      final url = await _imageUploadService.pickResizeAndUpload(
        source: source,
        storagePath:
            'reviews/${widget.order.orderId}/${DateTime.now().millisecondsSinceEpoch}.jpg',
        maxWidth: 1024,
        maxHeight: 1024,
        quality: 75,
      );
      if (url != null && mounted) {
        setState(() => _photoUrls.add(url));
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit || _submitting) return;
    setState(() => _submitting = true);

    try {
      // Group each item's product rating by its seller so we can write one
      // review document per seller under Seller/{sellerId}/review.
      final Map<String, List<ProductRating>> ratingsBySeller = {};
      for (var i = 0; i < widget.order.items.length; i++) {
        final item = widget.order.items[i];
        ratingsBySeller
            .putIfAbsent(item.sellerId, () => [])
            .add(
              ProductRating(
                productId: item.productId,
                variationId: item.variationId,
                rating: _productRatings[i],
              ),
            );
      }

      final comment = _commentController.text.trim();
      for (final entry in ratingsBySeller.entries) {
        final review = Review(
          orderId: widget.order.orderId,
          userId: widget.order.userId,
          sellerId: entry.key,
          productRatings: entry.value,
          deliveryService: _deliveryServiceRating,
          deliverySpeed: _isPickup ? null : _deliverySpeedRating,
          driverService: _isPickup ? null : _driverServiceRating,
          comment: comment,
          photoUrls: _photoUrls,
          anonymous: _anonymous,
          recommend: _recommend,
        );
        await ReviewService.submitReview(review);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit review: $e'),
            backgroundColor: _danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
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
    final horizontalPadding = context.isWideLayout ? 24.0 : 16.0;

    return Scaffold(
      backgroundColor: ink.bg,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(horizontalPadding),
                Expanded(child: _buildBody(horizontalPadding)),
              ],
            ),
          ),
        ),
      ),
      // The commitment stays pinned: on a long order the submit button would
      // otherwise sit several screens below the last star.
      bottomNavigationBar: _buildSubmitBar(),
    );
  }

  Widget _buildHeader(double horizontalPadding) {
    final id = widget.order.orderId.length > 8
        ? widget.order.orderId.substring(0, 8)
        : widget.order.orderId;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding - 8,
        4,
        horizontalPadding,
        4,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.arrow_back, color: ink.text),
            tooltip: 'Back',
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rate your order',
                  style: AppTextStyles.titleLarge.copyWith(
                    color: ink.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 24,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '#${id.toUpperCase()} · ${widget.order.items.length} item'
                  '${widget.order.items.length == 1 ? '' : 's'}',
                  style: AppTextStyles.bodySmall.copyWith(
                    fontFamily: AppTextStyles.secondaryFont,
                    color: ink.text.withValues(alpha: 0.5),
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(double horizontalPadding) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        12,
        horizontalPadding,
        24,
      ),
      children: [
        _buildIntroNote(),
        const SizedBox(height: 20),

        _sectionLabel(
          widget.order.items.length == 1 ? 'The product' : 'The products',
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < widget.order.items.length; i++) ...[
          _buildProductCard(widget.order.items[i], i),
          const SizedBox(height: 12),
        ],

        const SizedBox(height: 8),
        _sectionLabel(_isPickup ? 'Pickup' : 'Delivery'),
        const SizedBox(height: 12),
        _buildServiceCard(),

        const SizedBox(height: 20),
        _sectionLabel('Your review'),
        const SizedBox(height: 12),
        _buildCommentCard(),
        const SizedBox(height: 12),
        _buildPhotoCard(),

        const SizedBox(height: 20),
        _sectionLabel('How it is posted'),
        const SizedBox(height: 12),
        _buildTogglesCard(),
      ],
    );
  }

  /// Why the ratings matter, in one line — sellers are ranked on them, and a
  /// buyer who knows that answers more carefully.
  Widget _buildIntroNote() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: ink.emerald.withValues(alpha: ink.isDark ? 0.12 : 0.09),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ink.emerald.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(Icons.workspace_premium_outlined, size: 18, color: ink.emerald),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Your rating sets this seller’s score and helps other clinics '
              'choose who to buy from.',
              style: AppTextStyles.bodySmall.copyWith(
                color: ink.emerald,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: AppTextStyles.titleMedium.copyWith(
        color: ink.text,
        fontWeight: FontWeight.w800,
        fontSize: 17,
      ),
    );
  }

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

  // ── Products ─────────────────────────────────────────────────────────────

  Widget _buildProductCard(order_model.OrderItem item, int index) {
    final rating = _productRatings[index];

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
              const SizedBox(width: 12),
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
                    if (item.variationName != null &&
                        item.variationName!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        item.variationName!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: _muted,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
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
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: ink.border),
          const SizedBox(height: 12),
          _buildStarBlock(
            value: rating,
            onChanged: (v) => setState(() => _productRatings[index] = v),
          ),
        ],
      ),
    );
  }

  // ── Service ──────────────────────────────────────────────────────────────

  Widget _buildServiceCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRatingRow(
            label: _isPickup ? 'Pickup experience' : 'Delivery service',
            detail: _isPickup
                ? 'Handover at the store'
                : 'Packaging and handover',
            value: _deliveryServiceRating,
            onChanged: (v) => setState(() => _deliveryServiceRating = v),
          ),
          if (!_isPickup) ...[
            const SizedBox(height: 14),
            Divider(height: 1, color: ink.border),
            const SizedBox(height: 14),
            _buildRatingRow(
              label: 'Delivery speed',
              detail: 'How fast it arrived',
              value: _deliverySpeedRating ?? 0,
              onChanged: (v) => setState(() => _deliverySpeedRating = v),
            ),
            const SizedBox(height: 14),
            Divider(height: 1, color: ink.border),
            const SizedBox(height: 14),
            _buildRatingRow(
              label: 'Driver service',
              detail: 'The rider who handed it over',
              value: _driverServiceRating ?? 0,
              onChanged: (v) => setState(() => _driverServiceRating = v),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRatingRow({
    required String label,
    required String detail,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.bodyMedium.copyWith(
            color: ink.text,
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          detail,
          style: AppTextStyles.bodySmall.copyWith(
            color: ink.text.withValues(alpha: 0.5),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 10),
        _buildStarBlock(value: value, onChanged: onChanged),
      ],
    );
  }

  /// Stars plus the word they mean. The word is what makes a four-star rating
  /// deliberate rather than "one off the end".
  Widget _buildStarBlock({
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      children: [
        _StarRating(value: value, onChanged: onChanged, tone: ink.amber),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _ratingWord(value),
            style: AppTextStyles.bodySmall.copyWith(
              color: value == 0 ? ink.text.withValues(alpha: 0.4) : ink.amber,
              fontWeight: value == 0 ? FontWeight.w500 : FontWeight.w700,
              fontSize: 12.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _ratingWord(int value) {
    switch (value) {
      case 1:
        return 'Poor';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Very good';
      case 5:
        return 'Excellent';
      default:
        return 'Tap to rate';
    }
  }

  // ── Comment & photos ─────────────────────────────────────────────────────

  Widget _buildCommentCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_outlined, size: 16, color: ink.emerald),
              const SizedBox(width: 8),
              Text(
                'Write a few words',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: ink.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
              const Spacer(),
              Text(
                'Optional',
                style: AppTextStyles.bodySmall.copyWith(
                  color: ink.text.withValues(alpha: 0.45),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _commentController,
            maxLines: 4,
            style: AppTextStyles.bodyMedium.copyWith(
              color: ink.text,
              fontSize: 13.5,
              height: 1.4,
            ),
            cursorColor: ink.emerald,
            decoration: InputDecoration(
              hintText:
                  'What worked, what didn’t — packaging, accuracy, condition on arrival.',
              hintStyle: AppTextStyles.bodySmall.copyWith(
                color: ink.text.withValues(alpha: 0.4),
                fontSize: 13,
                height: 1.4,
              ),
              filled: true,
              fillColor: ink.surfaceHigh,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: ink.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: ink.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: ink.emerald, width: 2),
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.photo_camera_outlined, size: 16, color: ink.emerald),
              const SizedBox(width: 8),
              Text(
                'Add photos',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: ink.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
              const Spacer(),
              Text(
                '${_photoUrls.length}/$_maxPhotos',
                style: AppTextStyles.bodySmall.copyWith(
                  fontFamily: AppTextStyles.secondaryFont,
                  color: ink.text.withValues(alpha: 0.45),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildPhotoRow(),
        ],
      ),
    );
  }

  Widget _buildPhotoRow() {
    return SizedBox(
      height: 76,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < _photoUrls.length; i++) ...[
            _buildPhotoTile(i),
            const SizedBox(width: 10),
          ],
          // An upload in flight gets its own shimmering slot, so the strip
          // grows where the photo will actually land.
          if (_uploadingPhoto) ...[
            const SkeletonShimmer(
              child: SkeletonBox(width: 76, height: 76, radius: 14),
            ),
            const SizedBox(width: 10),
          ],
          if (_photoUrls.length < _maxPhotos && !_uploadingPhoto)
            _buildAddPhotoTile(),
        ],
      ),
    );
  }

  Widget _buildPhotoTile(int index) {
    return SizedBox(
      width: 76,
      height: 76,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 76,
            height: 76,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: ink.surfaceHigh,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ink.border),
            ),
            child: AppNetworkImage(
              url: _photoUrls[index],
              width: 76,
              height: 76,
            ),
          ),
          // Kept inside the tile: the strip is exactly one tile tall, so a
          // chip hung off the corner would be clipped by the viewport.
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: () => setState(() => _photoUrls.removeAt(index)),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 13, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddPhotoTile() {
    return GestureDetector(
      onTap: _addPhoto,
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          color: ink.surfaceHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ink.emerald.withValues(alpha: 0.4)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo_outlined, size: 20, color: ink.emerald),
            const SizedBox(height: 4),
            Text(
              'Add',
              style: AppTextStyles.labelSmall.copyWith(
                color: ink.emerald,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Posting options ──────────────────────────────────────────────────────

  Widget _buildTogglesCard() {
    return _card(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          _buildToggle(
            icon: Icons.visibility_off_outlined,
            title: 'Post anonymously',
            detail: 'Your name is hidden from the review',
            value: _anonymous,
            onChanged: (v) => setState(() => _anonymous = v),
          ),
          Divider(height: 1, color: ink.border),
          _buildToggle(
            icon: Icons.thumb_up_outlined,
            title: 'Recommend this seller',
            detail: 'Shown alongside your rating',
            value: _recommend,
            onChanged: (v) => setState(() => _recommend = v),
          ),
        ],
      ),
    );
  }

  Widget _buildToggle({
    required IconData icon,
    required String title,
    required String detail,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: value ? ink.emerald : _muted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: ink.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: ink.text.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: ink.onEmerald,
            activeTrackColor: ink.emerald,
          ),
        ],
      ),
    );
  }

  // ── Submit ───────────────────────────────────────────────────────────────

  Widget _buildSubmitBar() {
    final remaining = _requiredRatings - _answeredRatings;

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: ink.surface,
        border: Border(top: BorderSide(color: ink.border)),
      ),
      // heightFactor: 1 is load-bearing. Scaffold lays a bottomNavigationBar out
      // with LOOSE constraints, and a bare Center takes every pixel it is
      // offered — which left the bar filling the screen and the form with zero
      // height. Hugging the child vertically keeps the bar bar-sized.
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kMaxContentWidth - 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    remaining == 0
                        ? Icons.check_circle_outline
                        : Icons.star_outline,
                    size: 15,
                    color: remaining == 0 ? ink.emerald : _muted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      remaining == 0
                          ? 'All set — $_requiredRatings of $_requiredRatings rated'
                          : '$remaining more rating${remaining == 1 ? '' : 's'} to go',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: remaining == 0 ? ink.emerald : _muted,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: (_canSubmit && !_submitting) ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ink.emerald,
                    foregroundColor: ink.onEmerald,
                    disabledBackgroundColor: ink.text.withValues(
                      alpha: ink.isDark ? 0.12 : 0.09,
                    ),
                    disabledForegroundColor: ink.text.withValues(alpha: 0.4),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _submitting
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: ink.onEmerald,
                          ),
                        )
                      : Text(
                          'Submit review',
                          style: AppTextStyles.buttonLarge.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Five stars, sized for a thumb.
class _StarRating extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final Color tone;

  const _StarRating({
    required this.value,
    required this.onChanged,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final starValue = index + 1;
        final filled = starValue <= value;
        return GestureDetector(
          onTap: () => onChanged(starValue),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 140),
              child: Icon(
                filled ? Icons.star_rounded : Icons.star_outline_rounded,
                key: ValueKey(filled),
                color: filled ? tone : ink.text.withValues(alpha: 0.25),
                size: 30,
              ),
            ),
          ),
        );
      }),
    );
  }
}
