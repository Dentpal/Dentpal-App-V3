import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:dentpal/utils/app_logger.dart';

/// Offline Philippine locations dataset used to power the cascading
/// Location → Province → City dropdowns (and postal-code auto-fill) on the
/// address form.
///
/// The bundled asset is derived from the official PSGC hierarchy plus PhLPost
/// ZIP codes, shaped as: `island group → province → { city: zipCode }`.
/// The four island groups match the address form's Location field:
/// `NCR`, `Luzon`, `Visayas`, `Mindanao` (NCR is split out of Luzon, so Luzon
/// intentionally excludes Metro Manila).
///
/// ZIP coverage is best-effort (~86% of cities/municipalities); cities without
/// a known ZIP map to an empty string, and the postal field stays editable.
class PhLocationsService {
  PhLocationsService._();

  static const String _assetPath = 'lib/assets/data/ph_locations.json';

  /// island group -> province -> city -> zip
  static Map<String, Map<String, Map<String, String>>>? _data;

  /// Loads and caches the dataset. Safe to call repeatedly. Returns false if
  /// the asset can't be read/parsed (the form then falls back to free text).
  static Future<bool> ensureLoaded() async {
    if (_data != null) return true;
    try {
      final raw = await rootBundle.loadString(_assetPath);
      final decoded = json.decode(raw) as Map<String, dynamic>;
      _data = decoded.map((island, provinces) => MapEntry(
            island,
            (provinces as Map<String, dynamic>).map((province, cities) => MapEntry(
                  province,
                  (cities as Map<String, dynamic>)
                      .map((city, zip) => MapEntry(city, (zip ?? '').toString())),
                )),
          ));
      return true;
    } catch (e) {
      AppLogger.d('Failed to load PH locations dataset: $e');
      return false;
    }
  }

  static bool get isLoaded => _data != null;

  /// Island-group / Location values, in the order the form presents them.
  static const List<String> locations = ['NCR', 'Luzon', 'Visayas', 'Mindanao'];

  /// Provinces within a Location, alphabetically. Empty if not loaded/unknown.
  static List<String> provincesFor(String? location) {
    if (location == null) return const [];
    final provinces = _data?[location];
    if (provinces == null) return const [];
    return provinces.keys.toList();
  }

  /// Cities/municipalities within a Location + Province, alphabetically.
  static List<String> citiesFor(String? location, String? province) {
    if (location == null || province == null) return const [];
    final cities = _data?[location]?[province];
    if (cities == null) return const [];
    return cities.keys.toList();
  }

  /// Representative postal code for a city, or null when unknown (field stays
  /// blank/editable). Returns null for empty-string placeholders too.
  static String? zipFor(String? location, String? province, String? city) {
    if (location == null || province == null || city == null) return null;
    final zip = _data?[location]?[province]?[city];
    return (zip == null || zip.isEmpty) ? null : zip;
  }

  /// Whether the dataset contains this exact province under the Location.
  static bool hasProvince(String? location, String? province) =>
      province != null && provincesFor(location).contains(province);

  /// Whether the dataset contains this exact city under the Location+Province.
  static bool hasCity(String? location, String? province, String? city) =>
      city != null && citiesFor(location, province).contains(city);
}
