/// Display-ready vendor fields pulled out of a raw `Seller` document.
///
/// Seller documents nest the interesting parts several levels down
/// (`vendor.company.address…`) and any level may be missing, so this does the
/// digging once for every screen that shows a store. Both the listing page's
/// trader cards and the browse page's store list read from here — parsing this
/// shape in two places is how the two drift apart.
class SellerDisplay {
  const SellerDisplay({
    required this.storeName,
    required this.province,
    required this.coverImageUrl,
    required this.categories,
  });

  final String storeName;
  final String province;
  final String coverImageUrl;

  /// Comma-separated category names, for the one line a card can spare.
  final String categories;

  /// Reads [raw], falling back at every level so a card always renders.
  ///
  /// The fallbacks come from the products themselves, which is why the caller
  /// supplies them: a store with a half-filled profile still shows its brand
  /// name and one of its product photos rather than an empty frame.
  factory SellerDisplay.fromSellerData(
    Map<String, dynamic>? raw, {
    required String fallbackName,
    required String fallbackCategories,
    required String fallbackImageUrl,
  }) {
    if (raw == null) {
      return SellerDisplay(
        storeName: fallbackName,
        province: 'Metro Manila',
        coverImageUrl: fallbackImageUrl,
        categories: fallbackCategories,
      );
    }

    final vendor = raw['vendor'] is Map
        ? raw['vendor'] as Map<String, dynamic>
        : <String, dynamic>{};
    final company = vendor['company'] is Map
        ? vendor['company'] as Map<String, dynamic>
        : <String, dynamic>{};
    final address = company['address'] is Map
        ? company['address'] as Map<String, dynamic>
        : <String, dynamic>{};

    // Cover image: url → storage path → a product photo.
    var coverUrl = fallbackImageUrl;
    final coverImg = vendor['coverImage'];
    if (coverImg is Map) {
      final url = coverImg['url'] as String?;
      final path = coverImg['path'] as String?;
      if (url != null && url.isNotEmpty) {
        coverUrl = url;
      } else if (path != null && path.isNotEmpty) {
        coverUrl = path;
      }
    }

    final storeName = (company['storeName'] as String?)?.isNotEmpty == true
        ? company['storeName'] as String
        : ((raw['storeName'] as String?) ?? fallbackName);

    final province = (address['province'] as String?)?.isNotEmpty == true
        ? address['province'] as String
        : 'Metro Manila';

    // vendor.categories is an array of names.
    var categories = fallbackCategories;
    final rawCategories = vendor['categories'];
    if (rawCategories is List && rawCategories.isNotEmpty) {
      final joined = rawCategories.whereType<String>().take(2).join(', ');
      if (joined.isNotEmpty) categories = joined;
    }

    return SellerDisplay(
      storeName: storeName,
      province: province,
      coverImageUrl: coverUrl,
      categories: categories,
    );
  }

  /// The region a seller ships from, as free-form text for classification.
  static String? locationOf(Map<String, dynamic>? raw) {
    if (raw == null) return null;
    final vendor = raw['vendor'] is Map
        ? raw['vendor'] as Map<String, dynamic>
        : <String, dynamic>{};
    final company = vendor['company'] is Map
        ? vendor['company'] as Map<String, dynamic>
        : <String, dynamic>{};
    final address = company['address'] is Map
        ? company['address'] as Map<String, dynamic>
        : <String, dynamic>{};
    return (address['location'] as String?) ?? (address['province'] as String?);
  }
}
