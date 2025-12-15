import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/app_theme/app_colors.dart';
import '../../core/app_theme/app_text_styles.dart';
import 'package:dentpal/utils/app_logger.dart';

class AddressMapWidget extends StatefulWidget {
  final String address;
  final Function(double lat, double lng) onLocationSelected;
  final Function(Map<String, String> addressData)? onAddressFound;
  final double? initialLatitude;
  final double? initialLongitude;
  final bool preventAutoRepositioning; // Flag to prevent auto-repositioning during auto-fill

  const AddressMapWidget({
    super.key,
    required this.address,
    required this.onLocationSelected,
    this.onAddressFound,
    this.initialLatitude,
    this.initialLongitude,
    this.preventAutoRepositioning = false,
  });

  @override
  State<AddressMapWidget> createState() => _AddressMapWidgetState();
}

class _AddressMapWidgetState extends State<AddressMapWidget> {
  GoogleMapController? _mapController;
  LatLng? _selectedLocation;
  bool _isLoading = false;
  String? _error;
  bool _userHasManuallySetLocation = false; // Track if user has manually placed pin

  // Default to Manila, Philippines
  static const LatLng _defaultLocation = LatLng(14.5995, 120.9842);

  @override
  void initState() {
    super.initState();
    _initializeLocation();
  }

  @override
  void didUpdateWidget(AddressMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Only reposition map if user hasn't manually set a location
    // AND if auto-fill is not in progress
    // This prevents auto-fill from moving the user's chosen pin location
    if (oldWidget.address != widget.address && 
        widget.address.isNotEmpty && 
        !_userHasManuallySetLocation &&
        !widget.preventAutoRepositioning) {
      _geocodeAddressForMapPosition();
    }
  }

  Future<void> _initializeLocation() async {
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _selectedLocation = LatLng(widget.initialLatitude!, widget.initialLongitude!);
      _userHasManuallySetLocation = true; // User has existing coordinates
    } else if (widget.address.isNotEmpty) {
      // Just set map position based on address, but don't trigger auto-fill
      await _geocodeAddressForMapPosition();
    } else {
      _selectedLocation = _defaultLocation;
    }
    
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _geocodeAddressForMapPosition() async {
    // This method only positions the map, doesn't trigger auto-fill
    if (widget.address.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      String addressToGeocode = widget.address.trim();
      
      // Parse the address to extract city and state for better geocoding
      List<String> addressParts = addressToGeocode.split(',').map((e) => e.trim()).toList();
      
      String? cityPart;
      String? statePart;
      
      // Try to identify city and state from the address parts
      if (addressParts.length >= 3) {
        // Format: "Street, City, State" 
        cityPart = addressParts[1];
        statePart = addressParts[2];
      } else if (addressParts.length == 2) {
        // Format: "City, State" or "Street, City"
        cityPart = addressParts[0];
        statePart = addressParts[1];
      }

      // Try multiple geocoding strategies in order of preference
      List<String> geocodingAttempts = [];
      
      // 1. Try full address with Philippines
      if (!addressToGeocode.toLowerCase().contains('philippines') && 
          !addressToGeocode.toLowerCase().contains('ph')) {
        geocodingAttempts.add('$addressToGeocode, Philippines');
      } else {
        geocodingAttempts.add(addressToGeocode);
      }
      
      // 2. Try city + state + Philippines (most reliable for getting close to area)
      if (cityPart != null && statePart != null) {
        geocodingAttempts.add('$cityPart, $statePart, Philippines');
      }
      
      // 3. Try just city + Philippines
      if (cityPart != null) {
        geocodingAttempts.add('$cityPart, Philippines');
      }
      
      // 4. Try just state + Philippines
      if (statePart != null) {
        geocodingAttempts.add('$statePart, Philippines');
      }

      Location? foundLocation;

      // Try each geocoding attempt until one succeeds
      for (String attempt in geocodingAttempts) {
        try {
          List<Location> locations = await locationFromAddress(attempt);
          if (locations.isNotEmpty) {
            foundLocation = locations.first;
            break;
          }
        } catch (e) {
          // Continue to next attempt
          continue;
        }
      }

      if (foundLocation != null) {
        _selectedLocation = LatLng(foundLocation.latitude, foundLocation.longitude);
        widget.onLocationSelected(foundLocation.latitude, foundLocation.longitude);
        
        // Note: No auto-fill callback here, just map positioning
        //AppLogger.d('Map positioned to: ${foundLocation.latitude}, ${foundLocation.longitude}');
      } else {
        _selectedLocation = _defaultLocation;
      }
      
    } catch (e) {
      setState(() {
        _error = 'Could not find location for this address. You can tap on the map to set location manually.';
      });
      _selectedLocation = _defaultLocation;
      //AppLogger.d('Map positioning failed: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied');
      }

      Position position = await Geolocator.getCurrentPosition();
      _selectedLocation = LatLng(position.latitude, position.longitude);
      _userHasManuallySetLocation = true; // User used current location button
      widget.onLocationSelected(position.latitude, position.longitude);

      // Perform reverse geocoding to get address
      try {
        await _reverseGeocode(position.latitude, position.longitude);
      } catch (reverseGeocodeError) {
        //AppLogger.d('Error in reverse geocoding: $reverseGeocodeError');
      }

      if (_mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(_selectedLocation!, 16),
        );
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _reverseGeocode(double latitude, double longitude) async {
    //AppLogger.d('_reverseGeocode called with lat: $latitude, lng: $longitude');
    //AppLogger.d('onAddressFound callback is null: ${widget.onAddressFound == null}');
    
    if (widget.onAddressFound == null) return;

    try {
      //AppLogger.d('Starting placemarkFromCoordinates...');
      List<Placemark> placemarks = await placemarkFromCoordinates(latitude, longitude);
      //AppLogger.d('Placemarks found: ${placemarks.length}');
      
      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        //AppLogger.d('First placemark raw data:');
        //AppLogger.d('- street: ${placemark.street}');
        //AppLogger.d('- thoroughfare: ${placemark.thoroughfare}');
        //AppLogger.d('- subThoroughfare: ${placemark.subThoroughfare}');
        //AppLogger.d('- locality: ${placemark.locality}');
        //AppLogger.d('- subAdministrativeArea: ${placemark.subAdministrativeArea}');
        //AppLogger.d('- administrativeArea: ${placemark.administrativeArea}');
        //AppLogger.d('- postalCode: ${placemark.postalCode}');
        //AppLogger.d('- country: ${placemark.country}');
        //AppLogger.d('- name: ${placemark.name}');
        
        // Extract address components with null safety
        String street = '';
        String city = '';
        String state = '';
        String postalCode = '';
        String country = '';

        // Build street address from available components
        try {
          if (placemark.street?.isNotEmpty == true) {
            street = placemark.street!;
          } else if (placemark.thoroughfare?.isNotEmpty == true) {
            street = placemark.thoroughfare!;
            if (placemark.subThoroughfare?.isNotEmpty == true) {
              street = '${placemark.subThoroughfare} $street';
            }
          } else if (placemark.name?.isNotEmpty == true) {
            // Use name as fallback for street
            street = placemark.name!;
          }
        } catch (e) {
          //AppLogger.d('Error extracting street: $e');
        }

        // Get city (try multiple fields)
        try {
          city = placemark.locality ?? 
                 placemark.subAdministrativeArea ?? 
                 placemark.administrativeArea ?? 
                 '';
        } catch (e) {
          //AppLogger.d('Error extracting city: $e');
        }

        // Get state/province
        try {
          state = placemark.administrativeArea ?? '';
        } catch (e) {
          //AppLogger.d('Error extracting state: $e');
        }

        // Get postal code
        try {
          postalCode = placemark.postalCode ?? '';
        } catch (e) {
          //AppLogger.d('Error extracting postalCode: $e');
        }

        // Get country
        try {
          country = placemark.country ?? 'Philippines';
        } catch (e) {
          //AppLogger.d('Error extracting country: $e');
          country = 'Philippines';
        }

        //AppLogger.d('Extracted components:');
        //AppLogger.d('- street: "$street"');
        //AppLogger.d('- city: "$city"');
        //AppLogger.d('- state: "$state"');
        //AppLogger.d('- postalCode: "$postalCode"');
        //AppLogger.d('- country: "$country"');

        // Create address data map - ensure no null values
        Map<String, String> addressData = {
          'street': street,
          'city': city,
          'state': state,
          'postalCode': postalCode,
          'country': country,
        };

        //AppLogger.d('Address data prepared: $addressData');

        // Call the callback with the address data
        widget.onAddressFound!(addressData);
        
        //AppLogger.d('onAddressFound callback completed successfully');
      } else {
        //AppLogger.d('No placemarks found for coordinates');
        // Provide fallback data with coordinates
        _provideFallbackAddress(latitude, longitude);
      }
    } catch (e, stackTrace) {
      //AppLogger.d('Reverse geocoding failed: $e');
      //AppLogger.d('Stack trace: $stackTrace');
      // Provide fallback data with coordinates
      _provideFallbackAddress(latitude, longitude);
    }
  }

  void _provideFallbackAddress(double latitude, double longitude) {
    //AppLogger.d('Providing fallback address data...');
    
    if (widget.onAddressFound == null) return;
    
    // Create a more realistic fallback address based on coordinates
    // Since we know this is in Metro Manila area, provide reasonable defaults
    String estimatedArea = _getAreaFromCoordinates(latitude, longitude);
    
    Map<String, String> fallbackData = {
      'street': '', // Leave street empty so user can fill it
      'city': estimatedArea,
      'state': 'Metro Manila',
      'postalCode': '',
      'country': 'Philippines',
    };
    
    //AppLogger.d('Fallback address data: $fallbackData');
    
    // Call the callback with fallback data
    widget.onAddressFound!(fallbackData);
    
    //AppLogger.d('Fallback onAddressFound callback completed');
  }

  String _getAreaFromCoordinates(double latitude, double longitude) {
    // Rough approximation of Metro Manila areas based on coordinates
    // These are approximate boundaries for major cities in Metro Manila
    
    // Makati area (where your coordinates seem to be)
    if (latitude >= 14.540 && latitude <= 14.580 && 
        longitude >= 121.010 && longitude <= 121.040) {
      return 'Makati';
    }
    
    // BGC/Taguig area
    if (latitude >= 14.540 && latitude <= 14.560 && 
        longitude >= 121.040 && longitude <= 121.070) {
      return 'Taguig';
    }
    
    // Manila area
    if (latitude >= 14.580 && latitude <= 14.620 && 
        longitude >= 120.970 && longitude <= 121.020) {
      return 'Manila';
    }
    
    // Quezon City area
    if (latitude >= 14.620 && latitude <= 14.680 && 
        longitude >= 121.000 && longitude <= 121.080) {
      return 'Quezon City';
    }
    
    // Pasig area
    if (latitude >= 14.560 && latitude <= 14.600 && 
        longitude >= 121.060 && longitude <= 121.100) {
      return 'Pasig';
    }
    
    // Mandaluyong area
    if (latitude >= 14.570 && latitude <= 14.590 && 
        longitude >= 121.020 && longitude <= 121.050) {
      return 'Mandaluyong';
    }
    
    // Default to Metro Manila if can't determine specific city
    return 'Metro Manila';
  }

  void _onMapTap(LatLng position) {
    setState(() {
      _selectedLocation = position;
      _userHasManuallySetLocation = true; // User manually tapped the map
    });
    widget.onLocationSelected(position.latitude, position.longitude);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 300,
      margin: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.onSurface.withValues(alpha: 0.2),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            // Map
            GoogleMap(
              onMapCreated: (GoogleMapController controller) {
                _mapController = controller;
              },
              initialCameraPosition: CameraPosition(
                target: _selectedLocation ?? _defaultLocation,
                zoom: 14.0,
              ),
              onTap: _onMapTap,
              markers: _selectedLocation != null
                  ? {
                      Marker(
                        markerId: const MarkerId('selected_location'),
                        position: _selectedLocation!,
                        infoWindow: const InfoWindow(
                          title: 'Selected Location',
                        ),
                      ),
                    }
                  : {},
            ),
            
            // Loading overlay
            if (_isLoading)
              Container(
                color: Colors.black.withValues(alpha: 0.3),
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            
            // Error message
            if (_error != null)
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    border: Border.all(color: Colors.red.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.red.shade600,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: Colors.red.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            
            // Controls
            Positioned(
              top: 16,
              right: 16,
              child: Column(
                children: [
                  // Get current location button
                  FloatingActionButton.small(
                    heroTag: 'current_location',
                    onPressed: _getCurrentLocation,
                    backgroundColor: AppColors.primary,
                    child: const Icon(
                      Icons.my_location,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            
            // Instructions
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  'Tap on the map to pin your exact location or use the current location button',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.onSurface.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
