import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dentpal/utils/app_logger.dart';

class BannedSellerService {
  BannedSellerService._();
  static final BannedSellerService instance = BannedSellerService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Set<String> _bannedSellerIds = <String>{};
  bool _loaded = false;

  Set<String> get bannedSellerIds => Set.unmodifiable(_bannedSellerIds);
  bool get isLoaded => _loaded;

  Future<Set<String>> loadForCurrentUser() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      clear();
      return _bannedSellerIds;
    }

    try {
      final snapshot = await _firestore
          .collectionGroup('bannedBuyers')
          .where('bannedBy.buyerId', isEqualTo: uid)
          .get();

      final ids = <String>{};
      for (final doc in snapshot.docs) {
        final sellerId = doc.reference.parent.parent?.id;
        if (sellerId != null && sellerId.isNotEmpty) {
          ids.add(sellerId);
        }
      }

      _bannedSellerIds = ids;
      _loaded = true;
      AppLogger.d(
        'BannedSellerService: loaded ${ids.length} banned sellers for $uid',
      );
    } catch (e) {
      AppLogger.d('BannedSellerService: load error: $e');
    }
    return _bannedSellerIds;
  }

  bool isBanned(String sellerId) {
    if (!_loaded) return false;
    return _bannedSellerIds.contains(sellerId);
  }

  // Direct per-seller existence checks. Use this when the
  // collection-group query in [loadForCurrentUser] failed (e.g. the
  // composite index has not been created yet) or as an extra burst after
  // loading a product page. Each call is a tiny doc-get on
  // Seller/{sellerId}/bannedBuyers/{currentUid} — no index required.
  Future<void> checkSellers(Iterable<String> sellerIds) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final unique = sellerIds
        .where((id) => id.isNotEmpty)
        .toSet()
      ..removeAll(_bannedSellerIds);
    if (unique.isEmpty) {
      // Even with nothing to check, mark the cache as authoritative for
      // the ids we've already confirmed.
      _loaded = true;
      return;
    }
    final futures = unique.map((sid) => _firestore
        .collection('Seller')
        .doc(sid)
        .collection('bannedBuyers')
        .doc(uid)
        .get()
        .then((snap) {
      if (snap.exists) _bannedSellerIds.add(sid);
    }).catchError((e) {
      AppLogger.d('BannedSellerService.checkSellers $sid: $e');
    }));
    await Future.wait(futures);
    _loaded = true;
  }

  Future<bool> refreshAndCheck(String sellerId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    try {
      final doc = await _firestore
          .collection('Seller')
          .doc(sellerId)
          .collection('bannedBuyers')
          .doc(uid)
          .get();
      final banned = doc.exists;
      if (banned) {
        _bannedSellerIds.add(sellerId);
      } else {
        _bannedSellerIds.remove(sellerId);
      }
      return banned;
    } catch (e) {
      AppLogger.d('BannedSellerService: refreshAndCheck error: $e');
      return _bannedSellerIds.contains(sellerId);
    }
  }

  void clear() {
    _bannedSellerIds = <String>{};
    _loaded = false;
  }
}
