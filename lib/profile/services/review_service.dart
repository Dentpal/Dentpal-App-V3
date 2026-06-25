import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/review_model.dart';
import '../../utils/app_logger.dart';

class ReviewService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Whether the current user has already reviewed [orderId].
  static Future<bool> hasReviewed(String orderId) async {
    final user = _auth.currentUser;
    if (user == null) return false;
    try {
      final snapshot = await _firestore
          .collectionGroup('review')
          .where('OrderID', isEqualTo: orderId)
          .where('userId', isEqualTo: user.uid)
          .limit(1)
          .get();
      return snapshot.docs.isNotEmpty;
    } catch (e) {
      AppLogger.d('Error checking existing review: $e');
      return false;
    }
  }

  /// All order IDs the current user has reviewed (across all sellers), in a
  /// single collection-group query.
  static Future<Set<String>> getReviewedOrderIds() async {
    final user = _auth.currentUser;
    if (user == null) return {};
    try {
      final snapshot = await _firestore
          .collectionGroup('review')
          .where('userId', isEqualTo: user.uid)
          .get();
      return snapshot.docs
          .map((d) => (d.data()['OrderID'] as String?) ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (e) {
      AppLogger.d('Error fetching reviewed order ids: $e');
      return {};
    }
  }

  /// All reviews for a seller, newest first.
  static Future<List<Review>> getSellerReviews(String sellerId) async {
    try {
      final snapshot = await _firestore
          .collection('Seller')
          .doc(sellerId)
          .collection('review')
          .orderBy('createdAt', descending: true)
          .get();
      return snapshot.docs.map((d) => Review.fromDoc(d)).toList();
    } catch (e) {
      AppLogger.d('Error fetching seller reviews: $e');
      return [];
    }
  }

  /// Review count and product-rating average for a seller.
  static Future<({int count, double average})> getSellerRatingSummary(
      String sellerId) async {
    final reviews = await getSellerReviews(sellerId);
    if (reviews.isEmpty) return (count: 0, average: 0.0);
    final sum = reviews.fold<double>(0, (t, r) => t + r.productRatingAverage);
    return (count: reviews.length, average: sum / reviews.length);
  }

  /// Persist a review to `Seller/{sellerId}/review`.
  static Future<void> submitReview(Review review) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }
    await _firestore
        .collection('Seller')
        .doc(review.sellerId)
        .collection('review')
        .add(review.toMap());
    AppLogger.d(
        'Review submitted for order ${review.orderId} → seller ${review.sellerId}');
  }
}
