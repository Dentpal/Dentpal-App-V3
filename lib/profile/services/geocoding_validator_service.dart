import 'package:geocoding/geocoding.dart';
import 'package:dentpal/utils/app_logger.dart';

/// Service for validating addresses using Google Maps Geocoding API
class GeocodingValidatorService {
  /// Validates if a city exists in the Philippines
  static Future<bool> validateCity(String city) async {
    if (city.trim().isEmpty) return false;

    try {
      final locations = await locationFromAddress('$city, Philippines');
      return locations.isNotEmpty;
    } catch (e) {
      AppLogger.d('City validation failed for "$city": $e');
      return false;
    }
  }

  /// Validates if a state/province exists in the Philippines
  static Future<bool> validateState(String state) async {
    if (state.trim().isEmpty) return false;

    try {
      final locations = await locationFromAddress('$state, Philippines');
      return locations.isNotEmpty;
    } catch (e) {
      AppLogger.d('State validation failed for "$state": $e');
      return false;
    }
  }

  /// Validates if a postal code exists in the Philippines
  static Future<bool> validatePostalCode(String postalCode) async {
    if (postalCode.trim().isEmpty) return false;

    try {
      final locations = await locationFromAddress('$postalCode, Philippines');
      return locations.isNotEmpty;
    } catch (e) {
      AppLogger.d('Postal code validation failed for "$postalCode": $e');
      return false;
    }
  }

  /// Validates if city, state, and postal code form a valid address in the Philippines
  /// Returns a map with validation results and suggestions
  static Future<Map<String, dynamic>> validateAddress({
    required String city,
    required String state,
    required String postalCode,
  }) async {
    try {
      // Validate inputs are not empty
      if (city.trim().isEmpty ||
          state.trim().isEmpty ||
          postalCode.trim().isEmpty) {
        return {
          'isValid': false,
          'message': 'City, state, and postal code are required.',
        };
      }

      // Try to geocode the complete address
      final fullAddress = '$city, $state, $postalCode, Philippines';
      AppLogger.d('Attempting to validate address: $fullAddress');

      List<Location> locations;
      try {
        locations = await locationFromAddress(fullAddress);
      } catch (geocodeError) {
        AppLogger.d('Geocoding failed for "$fullAddress": $geocodeError');
        return {
          'isValid': false,
          'message':
              'Unable to find this address. Please check your city, state, and postal code.',
        };
      }

      if (locations.isEmpty) {
        return {
          'isValid': false,
          'message':
              'Unable to verify this address. Please check your city, state, and postal code.',
        };
      }

      // Reverse geocode to verify the components
      final location = locations.first;
      List<Placemark> placemarks;

      try {
        placemarks = await placemarkFromCoordinates(
          location.latitude,
          location.longitude,
        );
      } catch (reverseGeocodeError) {
        AppLogger.d('Reverse geocoding failed: $reverseGeocodeError');
        // If reverse geocoding fails but we got coordinates, consider it valid
        return {
          'isValid': true,
          'message': 'Address verified successfully',
          'latitude': location.latitude,
          'longitude': location.longitude,
        };
      }

      if (placemarks.isEmpty) {
        // If no placemarks but we have coordinates, consider it valid
        return {
          'isValid': true,
          'message': 'Address verified successfully',
          'latitude': location.latitude,
          'longitude': location.longitude,
        };
      }

      final placemark = placemarks.first;

      // Check if the resolved location matches the input reasonably well
      final resolvedCity =
          placemark.locality ?? placemark.subAdministrativeArea ?? '';
      final resolvedState = placemark.administrativeArea ?? '';
      final resolvedPostal = placemark.postalCode ?? '';

      // Flexible matching (case-insensitive partial match)
      final cityMatch =
          resolvedCity.isNotEmpty &&
          (resolvedCity.toLowerCase().contains(city.toLowerCase()) ||
              city.toLowerCase().contains(resolvedCity.toLowerCase()));
      final stateMatch =
          resolvedState.isNotEmpty &&
          (resolvedState.toLowerCase().contains(state.toLowerCase()) ||
              state.toLowerCase().contains(resolvedState.toLowerCase()));

      if (!cityMatch &&
          !stateMatch &&
          resolvedCity.isNotEmpty &&
          resolvedState.isNotEmpty) {
        return {
          'isValid': false,
          'message':
              'The address components don\'t match a valid location in the Philippines.',
          'suggestion': 'Did you mean: $resolvedCity, $resolvedState?',
          'resolvedCity': resolvedCity,
          'resolvedState': resolvedState,
          'resolvedPostal': resolvedPostal.isNotEmpty ? resolvedPostal : null,
        };
      }

      return {
        'isValid': true,
        'message': 'Address verified successfully',
        'latitude': location.latitude,
        'longitude': location.longitude,
        'resolvedCity': resolvedCity.isNotEmpty ? resolvedCity : null,
        'resolvedState': resolvedState.isNotEmpty ? resolvedState : null,
        'resolvedPostal': resolvedPostal.isNotEmpty ? resolvedPostal : null,
      };
    } catch (e, stackTrace) {
      AppLogger.e('Address validation error', e, stackTrace);
      return {
        'isValid': false,
        'message':
            'Unable to verify address. Please ensure city, state, and postal code are correct.',
      };
    }
  }

  /// Gets suggestions for cities in a given state/province
  static Future<List<String>> getCitySuggestions(String state) async {
    // This is a basic implementation - you might want to use a more comprehensive
    // Philippine cities/municipalities database for better suggestions
    final commonCities = <String>[];

    try {
      // Try to get location for the state
      final locations = await locationFromAddress('$state, Philippines');
      if (locations.isNotEmpty) {
        // Return common cities based on state (this is a simplified approach)
        // In production, you'd want a proper database of Philippine cities
        return commonCities;
      }
    } catch (e) {
      AppLogger.d('Failed to get city suggestions: $e');
    }

    return commonCities;
  }

  /// Validates if the country is Philippines (since we only support PH for now)
  static bool validateCountry(String country) {
    final validCountries = [
      'Philippines',
      'philippines',
      'PHILIPPINES',
      'PH',
      'ph',
    ];
    return validCountries.contains(country.trim());
  }

  /// Formats a validated address suggestion
  static String formatAddressSuggestion(Map<String, dynamic> validationResult) {
    if (validationResult['resolvedCity'] != null &&
        validationResult['resolvedState'] != null) {
      return '${validationResult['resolvedCity']}, ${validationResult['resolvedState']}';
    }
    return '';
  }
}
