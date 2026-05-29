import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/app_theme/app_colors.dart';
import '../../core/app_theme/app_text_styles.dart';
import '../../product/models/order_model.dart' as order_model;
import '../../product/services/image_upload_service.dart';
import '../models/review_model.dart';
import '../services/review_service.dart';

class AddReviewPage extends StatefulWidget {
  final order_model.Order order;

  const AddReviewPage({super.key, required this.order});

  @override
  State<AddReviewPage> createState() => _AddReviewPageState();
}

class _AddReviewPageState extends State<AddReviewPage> {
  static const int _maxPhotos = 5;

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

  final ImageUploadService _imageUploadService = ImageUploadService();

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
        ratingsBySeller.putIfAbsent(item.sellerId, () => []).add(ProductRating(
              productId: item.productId,
              variationId: item.variationId,
              rating: _productRatings[i],
            ));
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
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

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
          'Rate Product',
          style: AppTextStyles.titleLarge.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Per-item product rating cards
            for (var i = 0; i < widget.order.items.length; i++) ...[
              _buildProductCard(widget.order.items[i], i),
              const SizedBox(height: 12),
            ],

            // Order-level service ratings
            _buildSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildRatingRow(
                    'Delivery Service',
                    _deliveryServiceRating,
                    (v) => setState(() => _deliveryServiceRating = v),
                  ),
                  if (!_isPickup) ...[
                    const Divider(height: 24, color: AppColors.grey200),
                    _buildRatingRow(
                      'Delivery Speed',
                      _deliverySpeedRating ?? 0,
                      (v) => setState(() => _deliverySpeedRating = v),
                    ),
                    const Divider(height: 24, color: AppColors.grey200),
                    _buildRatingRow(
                      'Driver Service',
                      _driverServiceRating ?? 0,
                      (v) => setState(() => _driverServiceRating = v),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Written comment
            _buildSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Review',
                    style: AppTextStyles.titleSmall
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _commentController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Share your experience (optional)',
                      hintStyle: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.onSurface.withValues(alpha: 0.5),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.grey300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.grey300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: AppColors.primary, width: 2),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                    style: AppTextStyles.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Photo upload
            _buildSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Add Photos',
                        style: AppTextStyles.titleSmall
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '(${_photoUrls.length}/$_maxPhotos)',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildPhotoRow(),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Toggles
            _buildSectionCard(
              child: Column(
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: AppColors.primary,
                    value: _anonymous,
                    onChanged: (v) => setState(() => _anonymous = v),
                    title: Text('Post anonymously',
                        style: AppTextStyles.bodyMedium),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: AppColors.primary,
                    value: _recommend,
                    onChanged: (v) => setState(() => _recommend = v),
                    title: Text('Would you recommend this?',
                        style: AppTextStyles.bodyMedium),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Submit
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: (_canSubmit && !_submitting) ? _submit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  disabledBackgroundColor: AppColors.grey300,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Submit Review',
                        style: AppTextStyles.buttonLarge
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }

  Widget _buildProductCard(order_model.OrderItem item, int index) {
    return _buildSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 60,
                  height: 60,
                  color: AppColors.grey100,
                  child: item.productImage.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: item.productImage,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) => const Icon(
                            Icons.image_not_supported,
                            color: AppColors.grey400,
                          ),
                        )
                      : const Icon(Icons.image_not_supported,
                          color: AppColors.grey400),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.productName,
                      style: AppTextStyles.bodyMedium
                          .copyWith(fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.variationName != null &&
                        item.variationName!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.variationName!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.onSurface.withValues(alpha: 0.6),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24, color: AppColors.grey200),
          _buildRatingRow(
            'Rate Product',
            _productRatings[index],
            (v) => setState(() => _productRatings[index] = v),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingRow(String label, int value, ValueChanged<int> onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style:
                AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w500),
          ),
        ),
        _StarRating(value: value, onChanged: onChanged),
      ],
    );
  }

  Widget _buildPhotoRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < _photoUrls.length; i++) ...[
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: _photoUrls[i],
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: () => setState(() => _photoUrls.removeAt(i)),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(2),
                      child: const Icon(Icons.close,
                          size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
          ],
          if (_photoUrls.length < _maxPhotos)
            GestureDetector(
              onTap: _uploadingPhoto ? null : _addPhoto,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.grey100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.grey300),
                ),
                child: _uploadingPhoto
                    ? const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    : const Icon(Icons.add_a_photo_outlined,
                        color: AppColors.grey400),
              ),
            ),
        ],
      ),
    );
  }
}

class _StarRating extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _StarRating({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final starValue = index + 1;
        return GestureDetector(
          onTap: () => onChanged(starValue),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Icon(
              starValue <= value ? Icons.star : Icons.star_border,
              color: Colors.amber,
              size: 32,
            ),
          ),
        );
      }),
    );
  }
}
