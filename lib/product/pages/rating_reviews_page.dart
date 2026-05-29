import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/app_theme/app_colors.dart';
import '../../core/app_theme/app_text_styles.dart';
import '../../profile/models/review_model.dart';
import '../../profile/services/review_service.dart';
import 'product_detail_page.dart';

enum _ReviewSort { top, newest, highest, lowest }

class RatingReviewsPage extends StatefulWidget {
  final String sellerId;

  const RatingReviewsPage({super.key, required this.sellerId});

  @override
  State<RatingReviewsPage> createState() => _RatingReviewsPageState();
}

class _RatingReviewsPageState extends State<RatingReviewsPage> {
  bool _loading = true;
  List<Review> _reviews = [];
  final Map<String, String> _names = {};
  final Map<String, ({String name, String image})> _products = {};
  _ReviewSort _sort = _ReviewSort.top;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final reviews = await ReviewService.getSellerReviews(widget.sellerId);

    // Batch-load reviewer names for non-anonymous reviews.
    final uids = reviews
        .where((r) => !r.anonymous && r.userId.isNotEmpty)
        .map((r) => r.userId)
        .toSet();
    for (final uid in uids) {
      try {
        final doc =
            await FirebaseFirestore.instance.collection('User').doc(uid).get();
        final data = doc.data();
        if (data != null) {
          final first = (data['firstName'] as String?)?.trim();
          final full = (data['fullName'] as String?)?.trim();
          if (first != null && first.isNotEmpty) {
            _names[uid] = first;
          } else if (full != null && full.isNotEmpty) {
            _names[uid] = full.split(' ').first;
          }
        }
      } catch (_) {
        // ignore; falls back to "User"
      }
    }

    // Batch-load product name/image for every rated product.
    final productIds = <String>{
      for (final r in reviews)
        for (final pr in r.productRatings)
          if (pr.productId.isNotEmpty) pr.productId,
    };
    for (final pid in productIds) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('Product')
            .doc(pid)
            .get();
        final data = doc.data();
        if (data != null) {
          _products[pid] = (
            name: (data['name'] as String?)?.trim().isNotEmpty == true
                ? data['name'] as String
                : 'Product',
            image: (data['imageURL'] as String?) ?? '',
          );
        }
      } catch (_) {
        // ignore; falls back to placeholder
      }
    }

    if (mounted) {
      setState(() {
        _reviews = reviews;
        _loading = false;
      });
    }
  }

  double get _average {
    if (_reviews.isEmpty) return 0.0;
    final sum = _reviews.fold<double>(0, (t, r) => t + r.productRatingAverage);
    return sum / _reviews.length;
  }

  /// Counts of reviews per rounded star level (1..5).
  Map<int, int> get _breakdown {
    final map = {for (var i = 1; i <= 5; i++) i: 0};
    for (final r in _reviews) {
      map[r.productRatingRounded] = (map[r.productRatingRounded] ?? 0) + 1;
    }
    return map;
  }

  List<Review> get _sortedReviews {
    final list = [..._reviews];
    int byDateDesc(Review a, Review b) {
      final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    }

    switch (_sort) {
      case _ReviewSort.top:
        list.sort((a, b) {
          final ar = a.hasPhotos && a.hasComment ? 1 : 0;
          final br = b.hasPhotos && b.hasComment ? 1 : 0;
          if (ar != br) return br - ar;
          return byDateDesc(a, b);
        });
        break;
      case _ReviewSort.newest:
        list.sort(byDateDesc);
        break;
      case _ReviewSort.highest:
        list.sort((a, b) {
          final c = b.productRatingAverage.compareTo(a.productRatingAverage);
          return c != 0 ? c : byDateDesc(a, b);
        });
        break;
      case _ReviewSort.lowest:
        list.sort((a, b) {
          final c = a.productRatingAverage.compareTo(b.productRatingAverage);
          return c != 0 ? c : byDateDesc(a, b);
        });
        break;
    }
    return list;
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
          'Rating and Review',
          style: AppTextStyles.titleLarge.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSummaryCard(),
                  const SizedBox(height: 20),
                  Text(
                    'Reviews',
                    style: AppTextStyles.titleMedium
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  _buildSortChips(),
                  const SizedBox(height: 12),
                  if (_reviews.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text(
                          'No reviews yet',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    )
                  else
                    for (final review in _sortedReviews) ...[
                      _buildReviewCard(review),
                      const SizedBox(height: 12),
                    ],
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryCard() {
    final breakdown = _breakdown;
    final total = _reviews.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: average + stars + count
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _average.toStringAsFixed(1),
                style: AppTextStyles.headlineMedium.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Roboto',
                ),
              ),
              const SizedBox(height: 4),
              _StarsDisplay(value: _average, size: 18),
              const SizedBox(height: 6),
              Text(
                'All ratings ($total+)',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          const SizedBox(width: 20),
          // Right: 5..1 breakdown
          Expanded(
            child: Column(
              children: [
                for (var star = 5; star >= 1; star--)
                  _buildBreakdownRow(
                    star,
                    breakdown[star] ?? 0,
                    total == 0 ? 0 : (breakdown[star] ?? 0) / total,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownRow(int star, int count, double fraction) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 12,
            child: Text(
              '$star',
              style: AppTextStyles.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.star, size: 12, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 6,
                backgroundColor: AppColors.grey200,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Colors.amber),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 22,
            child: Text(
              '$count',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortChips() {
    const labels = {
      _ReviewSort.top: 'Top Review',
      _ReviewSort.newest: 'Newest',
      _ReviewSort.highest: 'Highest Rating',
      _ReviewSort.lowest: 'Lowest Rating',
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final entry in labels.entries) ...[
            ChoiceChip(
              label: Text(entry.value),
              selected: _sort == entry.key,
              onSelected: (_) => setState(() => _sort = entry.key),
              selectedColor: AppColors.primary,
              backgroundColor: AppColors.surface,
              labelStyle: AppTextStyles.bodySmall.copyWith(
                color: _sort == entry.key
                    ? AppColors.onPrimary
                    : AppColors.onSurface.withValues(alpha: 0.7),
                fontWeight: FontWeight.w600,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: _sort == entry.key
                      ? AppColors.primary
                      : AppColors.grey300,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildReviewCard(Review review) {
    final name = review.anonymous
        ? 'Anonymous'
        : (_names[review.userId] ?? 'User');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: AppTextStyles.bodyMedium
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                _relativeDate(review.createdAt),
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final pr in review.productRatings) ...[
            _buildItemRow(pr),
            const SizedBox(height: 8),
          ],
          if (review.recommend) ...[
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.thumb_up,
                      size: 14, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Recommends this product',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (review.hasComment) ...[
            const SizedBox(height: 8),
            Text(review.comment, style: AppTextStyles.bodyMedium),
          ],
          if (review.hasPhotos) ...[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < review.photoUrls.length; i++) ...[
                    GestureDetector(
                      onTap: () => _openPhotos(review.photoUrls, i),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: CachedNetworkImage(
                          imageUrl: review.photoUrls[i],
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemRow(ProductRating pr) {
    final info = _products[pr.productId];
    final image = info?.image ?? '';
    final name = info?.name ?? 'Product';
    final exists = pr.productId.isNotEmpty && _products.containsKey(pr.productId);

    return InkWell(
      onTap: exists
          ? () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProductDetailPage(productId: pr.productId),
                ),
              );
            }
          : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 44,
                height: 44,
                color: AppColors.grey100,
                child: image.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: image,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) => const Icon(
                          Icons.image_not_supported,
                          size: 18,
                          color: AppColors.grey400,
                        ),
                      )
                    : const Icon(Icons.image_not_supported,
                        size: 18, color: AppColors.grey400),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: AppTextStyles.bodySmall
                        .copyWith(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  _StarsDisplay(value: pr.rating.toDouble(), size: 14),
                ],
              ),
            ),
            if (exists) ...[
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right,
                  size: 18, color: AppColors.grey400),
            ],
          ],
        ),
      ),
    );
  }

  void _openPhotos(List<String> photos, int initialIndex) {
    if (photos.isEmpty) return;
    final controller = PageController(initialPage: initialIndex);
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.7,
              child: PageView.builder(
                controller: controller,
                itemCount: photos.length,
                itemBuilder: (_, i) => InteractiveViewer(
                  child: Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: photos[i],
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (photos.length > 1)
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: AnimatedBuilder(
                    animation: controller,
                    builder: (context, child) {
                      final page = controller.hasClients &&
                              controller.page != null
                          ? controller.page!.round()
                          : initialIndex;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${page + 1} / ${photos.length}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                        ),
                      );
                    },
                  ),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    );
  }

  String _relativeDate(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

class _StarsDisplay extends StatelessWidget {
  final double value;
  final double size;

  const _StarsDisplay({required this.value, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = value >= i + 1;
        final half = !filled && value > i;
        return Icon(
          half ? Icons.star_half : (filled ? Icons.star : Icons.star_border),
          color: Colors.amber,
          size: size,
        );
      }),
    );
  }
}
