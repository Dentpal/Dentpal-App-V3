import 'package:cloud_firestore/cloud_firestore.dart';

/// A single product's star rating within a review.
class ProductRating {
  final String productId;
  final String? variationId;
  final int rating; // 1..5

  ProductRating({
    required this.productId,
    this.variationId,
    required this.rating,
  });

  Map<String, dynamic> toMap() => {
        'productId': productId,
        if (variationId != null) 'variationId': variationId,
        'rating': rating,
      };
}

/// A buyer's review for one seller within a completed order. Persisted to
/// `Seller/{sellerId}/review`. Field names match the agreed Firestore schema.
class Review {
  final String orderId;
  final String userId;
  final String sellerId;
  final List<ProductRating> productRatings;
  final int deliveryService; // renamed from "Seller Service"
  final int? deliverySpeed; // null for pickup orders
  final int? driverService; // null for pickup orders
  final String comment;
  final List<String> photoUrls;
  final bool anonymous;
  final bool recommend;
  final DateTime? createdAt;

  Review({
    this.id = '',
    required this.orderId,
    required this.userId,
    required this.sellerId,
    required this.productRatings,
    required this.deliveryService,
    this.deliverySpeed,
    this.driverService,
    this.comment = '',
    this.photoUrls = const [],
    this.anonymous = false,
    this.recommend = true,
    this.createdAt,
  });

  final String id;

  /// Mean of this review's product star ratings (0 if none).
  double get productRatingAverage {
    if (productRatings.isEmpty) return 0.0;
    final sum = productRatings.fold<int>(0, (t, r) => t + r.rating);
    return sum / productRatings.length;
  }

  int get productRatingRounded => productRatingAverage.round().clamp(1, 5);

  bool get hasPhotos => photoUrls.isNotEmpty;
  bool get hasComment => comment.trim().isNotEmpty;

  factory Review.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    final ratings = <ProductRating>[];
    final rawRatings = data['rateProduct'];
    if (rawRatings is List) {
      for (final entry in rawRatings) {
        if (entry is Map) {
          ratings.add(ProductRating(
            productId: entry['productId']?.toString() ?? '',
            variationId: entry['variationId']?.toString(),
            rating: (entry['rating'] as num?)?.toInt() ?? 0,
          ));
        }
      }
    }

    final photos = <String>[];
    final rawPhotos = data['Photos'];
    if (rawPhotos is List) {
      for (final p in rawPhotos) {
        if (p is String && p.isNotEmpty) photos.add(p);
      }
    }

    DateTime? createdAt;
    final rawCreated = data['createdAt'];
    if (rawCreated is Timestamp) createdAt = rawCreated.toDate();

    return Review(
      id: doc.id,
      orderId: data['OrderID']?.toString() ?? '',
      userId: data['userId']?.toString() ?? '',
      sellerId: doc.reference.parent.parent?.id ?? '',
      productRatings: ratings,
      deliveryService: (data['deliveryService'] as num?)?.toInt() ?? 0,
      deliverySpeed: (data['deliverySpeed'] as num?)?.toInt(),
      driverService: (data['driverService'] as num?)?.toInt(),
      comment: data['Review']?.toString() ?? '',
      photoUrls: photos,
      anonymous: data['postAnonymously'] == true,
      recommend: data['wouldYouRecommendThis'] == true,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'OrderID': orderId,
        'userId': userId,
        'rateProduct': productRatings.map((r) => r.toMap()).toList(),
        'deliveryService': deliveryService,
        if (deliverySpeed != null) 'deliverySpeed': deliverySpeed,
        if (driverService != null) 'driverService': driverService,
        'Review': comment,
        'Photos': photoUrls,
        'postAnonymously': anonymous,
        'wouldYouRecommendThis': recommend,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
