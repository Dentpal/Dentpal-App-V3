import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // Added for web detection
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocoding/geocoding.dart' as geo;
import '../models/shipping_address.dart';
import '../services/address_service.dart';
import '../services/ph_locations_service.dart';
import '../../core/app_theme/app_colors.dart';
import '../../core/app_theme/app_text_styles.dart';
import 'package:dentpal/utils/app_logger.dart';
import '../../core/services/sub_account_service.dart';

class ShippingAddressesPage extends StatefulWidget {
  const ShippingAddressesPage({super.key});

  @override
  State<ShippingAddressesPage> createState() => _ShippingAddressesPageState();
}

class _ShippingAddressesPageState extends State<ShippingAddressesPage> {
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAddresses();
  }

  Future<void> _loadAddresses() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });
      // The stream will handle loading data
      await Future.delayed(const Duration(milliseconds: 500));
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _setAsDefault(String addressId) async {
    try {
      await AddressService.setAsDefault(addressId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Default address updated'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _deleteAddress(ShippingAddress address) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.delete_outline,
                color: AppColors.error,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Delete Address',
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete this address?',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.onSurface.withValues(alpha: 0.8),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.onSurface.withValues(alpha: 0.6),
            ),
            child: Text('Cancel', style: AppTextStyles.buttonMedium),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.onPrimary,
              elevation: 0,
            ),
            child: Text('Delete', style: AppTextStyles.buttonMedium),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      try {
        await AddressService.deleteAddress(address.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Address deleted successfully'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting address: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Shipping Addresses',
          style: AppTextStyles.titleLarge.copyWith(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.add, color: AppColors.primary),
            onPressed: () => _showAddAddressDialog(),
            tooltip: 'Add Address',
          ),
        ],
      ),
      // Responsive wrapper
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWideWeb = kIsWeb && constraints.maxWidth > 800; // BREAKPOINT
          final content = _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? _buildErrorState()
              : StreamBuilder<List<ShippingAddress>>(
                  stream: AddressService.getAddressesStream(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return _buildErrorState(snapshot.error.toString());
                    }

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final addresses = snapshot.data ?? [];

                    if (addresses.isEmpty) {
                      return _buildEmptyState();
                    }

                    return _buildAddressList(addresses);
                  },
                );
          if (isWideWeb) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640), // MAX_WIDTH
                child: Material(color: Colors.transparent, child: content),
              ),
            );
          }
          return content; // mobile & narrow web full width
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddAddressDialog(),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildErrorState([String? errorMessage]) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage ?? _error ?? 'Please try again later',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadAddresses,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.location_off_outlined,
              size: 64,
              color: AppColors.onSurface.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'No addresses yet',
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add your first shipping address to get started',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showAddAddressDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Add Address'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressList(List<ShippingAddress> addresses) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: addresses.length,
      itemBuilder: (context, index) {
        final address = addresses[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildAddressCard(address),
        );
      },
    );
  }

  Widget _buildAddressCard(ShippingAddress address) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: address.isDefault
            ? Border.all(color: AppColors.primary, width: 2)
            : null,
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with default badge and actions
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        address.fullName,
                        style: AppTextStyles.titleMedium.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (address.isDefault) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'DEFAULT',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.onPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        _showAddAddressDialog(address: address);
                        break;
                      case 'default':
                        _setAsDefault(address.id);
                        break;
                      case 'delete':
                        _deleteAddress(address);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    if (!address.isDefault)
                      const PopupMenuItem(
                        value: 'default',
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_outline, size: 18),
                            SizedBox(width: 8),
                            Text('Set as Default'),
                          ],
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: Colors.red,
                          ),
                          SizedBox(width: 8),
                          Text('Delete', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                  child: Icon(
                    Icons.more_vert,
                    color: AppColors.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),

          // Address details
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(address.addressLine1, style: AppTextStyles.bodyMedium),
                if (address.addressLine2 != null &&
                    address.addressLine2!.isNotEmpty)
                  Text(address.addressLine2!, style: AppTextStyles.bodyMedium),
                Text(
                  '${address.city}, ${address.state} ${address.postalCode}',
                  style: AppTextStyles.bodyMedium,
                ),
                Text(address.country, style: AppTextStyles.bodyMedium),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.phone_outlined,
                      size: 16,
                      color: AppColors.onSurface.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      address.phoneNumber, // Display the full +63 format
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
                // Show notes if available
                if (address.notes != null && address.notes!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.note_outlined,
                        size: 16,
                        color: AppColors.onSurface.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          address.notes!,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.onSurface.withValues(alpha: 0.7),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                // Show location pin if available
                if (address.latitude != null && address.longitude != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Location pinned',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showAddAddressDialog({ShippingAddress? address}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AddEditAddressPage(address: address),
        fullscreenDialog: true,
      ),
    );
  }
}

class AddEditAddressPage extends StatefulWidget {
  final ShippingAddress? address;

  const AddEditAddressPage({super.key, this.address});

  @override
  State<AddEditAddressPage> createState() => _AddEditAddressPageState();
}

class _AddEditAddressPageState extends State<AddEditAddressPage> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _addressLine1Controller = TextEditingController();
  final _addressLine2Controller = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _postalCodeController = TextEditingController();
  final _countryController = TextEditingController();
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isDefault = false;
  bool _isLoading = false;
  AutovalidateMode _autovalidateMode =
      AutovalidateMode.disabled; // Track validation mode
  String? _selectedLocation;
  // Cascading dropdown selections (province/city). The underlying
  // _stateController / _cityController remain the source of truth for saving;
  // these drive the dropdown UI and postal auto-fill.
  String? _selectedProvince;
  String? _selectedCity;
  // Whether the offline PH locations dataset finished loading.
  bool _locationsLoaded = false;

  static const List<String> _locationOptions = PhLocationsService.locations;

  bool get _isEditing => widget.address != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _populateFields();
    } else {
      _countryController.text = 'Philippines'; // Default country
      _prefillUserName(); // Pre-fill user's name when adding new address
    }
    _loadLocations();
  }

  /// Loads the offline PH locations dataset, then (in edit mode) preselects the
  /// province/city dropdowns from the saved address. Legacy free-text values
  /// that aren't in the dataset are kept as-is (shown as a one-off dropdown
  /// item) so editing an old address never loses or blocks its location.
  Future<void> _loadLocations() async {
    await PhLocationsService.ensureLoaded();
    if (!mounted) return;
    setState(() {
      _locationsLoaded = true;
      if (_isEditing) {
        final state = _stateController.text.trim();
        final city = _cityController.text.trim();
        _selectedProvince = state.isEmpty ? null : state;
        _selectedCity = city.isEmpty ? null : city;
      }
    });
  }

  Future<void> _prefillUserName() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Try to get name from Firebase Auth displayName first
      String? userName = user.displayName;

      // If displayName is empty, try to get from Firestore User collection
      if (userName == null || userName.trim().isEmpty) {
        final effectiveUid = SubAccountSessionManager.getEffectiveUserId();
        final userDoc = await FirebaseFirestore.instance
            .collection('User') // Changed from 'users' to 'User' (capital U)
            .doc(effectiveUid)
            .get();

        if (userDoc.exists) {
          final userData = userDoc.data();
          AppLogger.d('User data from Firestore: $userData');
          
          // Try different possible field names for full name
          userName = userData?['fullName'] ??
              userData?['displayName'] ??
              userData?['name'];
          
          AppLogger.d('Extracted userName: $userName');
        } else {
          AppLogger.d('User document does not exist in Firestore');
        }
      }

      // Set the full name if we found it
      if (userName != null && userName.trim().isNotEmpty && mounted) {
        setState(() {
          _fullNameController.text = userName!;
        });
        AppLogger.d('Pre-filled full name with: $userName');
      } else {
        AppLogger.d('No valid user name found to pre-fill');
      }
    } catch (e) {
      AppLogger.d('Error pre-filling user name: $e');
      // Silently fail - user can still enter name manually
    }
  }

  void _populateFields() {
    final address = widget.address!;
    _fullNameController.text = address.fullName;
    _addressLine1Controller.text = address.addressLine1;
    _addressLine2Controller.text = address.addressLine2 ?? '';
    _cityController.text = address.city;
    _stateController.text = address.state;
    _postalCodeController.text = address.postalCode;
    _countryController.text = address.country;
    _notesController.text = address.notes ?? '';

    // Convert +639XXXXXXXXX back to 09XXXXXXXXX for display/editing
    String displayPhone = address.phoneNumber;
    if (displayPhone.startsWith('+63') && displayPhone.length == 13) {
      displayPhone = '0${displayPhone.substring(3)}';
    }
    _phoneController.text = displayPhone;

    _isDefault = address.isDefault;
    _selectedLocation =
        _locationOptions.contains(address.location) ? address.location : null;
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _addressLine1Controller.dispose();
    _addressLine2Controller.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _postalCodeController.dispose();
    _countryController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _saveAddress() async {
    // Enable autovalidation after first submit attempt
    if (_autovalidateMode != AutovalidateMode.always) {
      setState(() {
        _autovalidateMode = AutovalidateMode.always;
      });
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final now = DateTime.now();

      // Format phone number: convert 09XXXXXXXXX to +639XXXXXXXXX
      String formattedPhone = _phoneController.text.trim();
      // Remove any spaces or special characters
      formattedPhone = formattedPhone.replaceAll(RegExp(r'[^\d]'), '');
      // Convert 09XXXXXXXXX to +639XXXXXXXXX
      if (formattedPhone.startsWith('09')) {
        formattedPhone = '+63${formattedPhone.substring(1)}';
      }

      // Geocode the address up front so Same Day Delivery (Lalamove) has precise
      // coordinates without a server round-trip. Best-effort: if it fails we
      // save with null coords and the backend geocodeHelper resolves them later.
      final coords = await _geocodeAddress(
        line1: _addressLine1Controller.text.trim(),
        line2: _addressLine2Controller.text.trim(),
        city: _cityController.text.trim(),
        state: _stateController.text.trim(),
        postalCode: _postalCodeController.text.trim(),
      );

      final address = ShippingAddress(
        id: _isEditing ? widget.address!.id : '',
        fullName: _fullNameController.text.trim(),
        addressLine1: _addressLine1Controller.text.trim(),
        addressLine2: _addressLine2Controller.text.trim().isEmpty
            ? null
            : _addressLine2Controller.text.trim(),
        city: _cityController.text.trim(),
        state: _stateController.text.trim(),
        postalCode: _postalCodeController.text.trim(),
        country: _countryController.text.trim(),
        phoneNumber: formattedPhone,
        latitude: coords?.latitude ?? (_isEditing ? widget.address!.latitude : null),
        longitude: coords?.longitude ?? (_isEditing ? widget.address!.longitude : null),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        isDefault: _isDefault,
        location: _selectedLocation ?? '',
        createdAt: _isEditing ? widget.address!.createdAt : now,
        updatedAt: now,
      );

      final validationError = AddressService.validateAddress(address);
      if (validationError != null) {
        throw Exception(validationError);
      }

      if (_isEditing) {
        await AddressService.updateAddress(address);
      } else {
        await AddressService.createAddress(address);
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditing
                  ? 'Address updated successfully'
                  : 'Address added successfully',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// NCR cities/municipalities — used only for a non-blocking "no same-day"
  /// hint. Backend (metroManila.ts) remains the authoritative coverage check.
  static const List<String> _ncrCities = [
    'manila', 'quezon city', 'caloocan', 'las pinas', 'las piñas', 'makati',
    'malabon', 'mandaluyong', 'marikina', 'muntinlupa', 'navotas', 'paranaque',
    'parañaque', 'pasay', 'pasig', 'pateros', 'san juan', 'taguig', 'valenzuela',
  ];

  bool _looksMetroManila(String city, String state) {
    final c = city.toLowerCase().trim();
    final s = state.toLowerCase().trim();
    if (s.contains('metro manila') || s.contains('ncr') || c.contains('metro manila')) {
      return true;
    }
    return _ncrCities.any((nc) => c == nc || s == nc || c.contains(nc) || s.contains(nc));
  }

  /// Best-effort geocode of the entered address to coordinates. Returns null on
  /// failure (offline/ambiguous) so saving is never blocked. Shows a hint when
  /// the address resolves outside Metro Manila (no same-day delivery there).
  Future<geo.Location?> _geocodeAddress({
    required String line1,
    required String line2,
    required String city,
    required String state,
    required String postalCode,
  }) async {
    final query = [
      if (line1.isNotEmpty) line1,
      if (line2.isNotEmpty) line2,
      if (city.isNotEmpty) city,
      if (state.isNotEmpty) state,
      if (postalCode.isNotEmpty) postalCode,
      'Philippines',
    ].join(', ');

    if (!_looksMetroManila(city, state) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Heads up: Same Day Delivery is only available within Metro Manila.',
          ),
          backgroundColor: AppColors.info,
          duration: const Duration(seconds: 4),
        ),
      );
    }

    try {
      final results = await geo.locationFromAddress(query);
      if (results.isNotEmpty) return results.first;
    } catch (e) {
      AppLogger.d('Geocoding failed for "$query": $e');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: AppColors.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _isEditing ? 'Edit Address' : 'Add Address',
          style: AppTextStyles.titleLarge.copyWith(fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _saveAddress,
            child: Text(
              'Save',
              style: AppTextStyles.buttonMedium.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWideWeb = kIsWeb && constraints.maxWidth > 800; // BREAKPOINT
          final formContent = Form(
            key: _formKey,
            autovalidateMode: _autovalidateMode,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Info banner about address validation
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: AppColors.primary,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Pick your Location, Province, and City from the lists. The postal code is filled in for you — you can edit it if needed.',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.onSurface.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _buildTextField(
                  controller: _fullNameController,
                  label: 'Full Name',
                  icon: Icons.person_outline,
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Full name is required'
                      : null,
                ),
                const SizedBox(height: 16),
                _buildLocationDropdown(),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _countryController,
                  label: 'Country',
                  icon: Icons.public_outlined,
                  enabled: false,
                  helperText: 'Currently only Philippines is supported',
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Country is required'
                      : null,
                ),
                const SizedBox(height: 16),
                _buildProvinceDropdown(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _buildCityDropdown(),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 1,
                      child: _buildTextField(
                        controller: _postalCodeController,
                        label: 'Postal Code',
                        icon: Icons.markunread_mailbox_outlined,
                        keyboardType: TextInputType.number,
                        enabled: _selectedLocation != null,
                        helperText: 'Auto-filled from city; edit if needed',
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                            ? 'Postal code is required'
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _addressLine1Controller,
                  label: 'Address Line 1',
                  icon: Icons.home_outlined,
                  enabled: _selectedLocation != null,
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Address line 1 is required'
                      : null,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _addressLine2Controller,
                  label: 'Address Line 2 (Optional)',
                  icon: Icons.home_outlined,
                  enabled: _selectedLocation != null,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _phoneController,
                  label: 'Phone Number (09123456789)',
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  enabled: _selectedLocation != null,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty)
                      return 'Phone number is required';
                    final clean = value.replaceAll(RegExp(r'[^\d]'), '');
                    if (clean.length != 11)
                      return 'Phone number must be 11 digits';
                    if (!clean.startsWith('09'))
                      return 'Phone number must start with 09';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _notesController,
                  label: 'Delivery Notes (Optional)',
                  icon: Icons.note_outlined,
                  maxLines: 3,
                  enabled: _selectedLocation != null,
                ),
                const SizedBox(height: 24),

                // Default address toggle
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.onSurface.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        color: AppColors.primary,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Set as Default Address',
                              style: AppTextStyles.bodyLarge.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Use this address as your default shipping address',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.onSurface.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _isDefault,
                        onChanged: _selectedLocation == null
                            ? null
                            : (value) {
                                setState(() {
                                  _isDefault = value;
                                });
                              },
                        activeThumbColor: AppColors.primary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Save button
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveAddress,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isLoading
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.onPrimary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Saving...',
                                style: AppTextStyles.buttonLarge,
                              ),
                            ],
                          )
                        : Text(
                            _isEditing ? 'Update Address' : 'Add Address',
                            style: AppTextStyles.buttonLarge,
                          ),
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          );
          if (isWideWeb) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640), // MAX_WIDTH
                child: Material(color: Colors.transparent, child: formContent),
              ),
            );
          }
          return formContent; // mobile & narrow web
        },
      ),
    );
  }

  Widget _buildLocationDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedLocation,
      isExpanded: true,
      items: _locationOptions
          .map(
            (loc) => DropdownMenuItem<String>(
              value: loc,
              child: Text(loc, style: AppTextStyles.bodyMedium),
            ),
          )
          .toList(),
      onChanged: (value) {
        setState(() {
          _selectedLocation = value;
          // Changing region invalidates the province/city/postal selections.
          _selectedProvince = null;
          _selectedCity = null;
          _stateController.clear();
          _cityController.clear();
          _postalCodeController.clear();
        });
      },
      validator: (value) =>
          (value == null || value.isEmpty) ? 'Location is required' : null,
      decoration: InputDecoration(
        labelText: 'Location',
        helperText: _selectedLocation == null
            ? 'Select your location to continue'
            : 'NCR, Luzon, Visayas, or Mindanao',
        helperMaxLines: 2,
        errorMaxLines: 2,
        helperStyle: AppTextStyles.bodySmall.copyWith(
          color: AppColors.primary.withValues(alpha: 0.7),
        ),
        errorStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
        prefixIcon: const Icon(
          Icons.location_on_outlined,
          color: AppColors.primary,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: AppColors.onSurface.withValues(alpha: 0.2),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: AppColors.onSurface.withValues(alpha: 0.2),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        filled: true,
        fillColor: AppColors.surface,
        labelStyle: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.onSurface.withValues(alpha: 0.7),
        ),
      ),
    );
  }

  /// Shared decoration for the cascading location dropdowns (matches the
  /// text-field / location-dropdown styling).
  InputDecoration _dropdownDecoration({
    required String label,
    required String helperText,
    required IconData icon,
    required bool enabled,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      helperMaxLines: 2,
      errorMaxLines: 2,
      helperStyle: AppTextStyles.bodySmall.copyWith(
        color: AppColors.primary.withValues(alpha: 0.7),
      ),
      errorStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
      prefixIcon: Icon(
        icon,
        color: enabled
            ? AppColors.primary
            : AppColors.onSurface.withValues(alpha: 0.3),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.onSurface.withValues(alpha: 0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.onSurface.withValues(alpha: 0.2)),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.onSurface.withValues(alpha: 0.1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error, width: 2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error, width: 2),
      ),
      filled: true,
      fillColor: enabled
          ? AppColors.surface
          : AppColors.surface.withValues(alpha: 0.5),
      labelStyle: AppTextStyles.bodyMedium.copyWith(
        color: AppColors.onSurface.withValues(alpha: 0.7),
      ),
    );
  }

  /// State/Province dropdown, populated with the provinces of the selected
  /// Location. A saved value that isn't in the dataset (legacy free text) is
  /// added as a one-off item so it still displays and validates.
  Widget _buildProvinceDropdown() {
    final enabled = _selectedLocation != null && _locationsLoaded;
    final options = PhLocationsService.provincesFor(_selectedLocation);
    final values = <String>[...options];
    if (_selectedProvince != null && !values.contains(_selectedProvince)) {
      values.insert(0, _selectedProvince!);
    }
    return DropdownButtonFormField<String>(
      // Rebuild (and re-seed initialValue) when the Location changes or the
      // dataset finishes loading, so cascade resets / edit-mode preselect show.
      key: ValueKey('province-${_selectedLocation ?? ''}-$_locationsLoaded'),
      initialValue: _selectedProvince,
      isExpanded: true,
      items: values
          .map((p) => DropdownMenuItem<String>(
                value: p,
                child: Text(p, style: AppTextStyles.bodyMedium, overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: enabled
          ? (value) {
              setState(() {
                _selectedProvince = value;
                _stateController.text = value ?? '';
                // Province change invalidates the city + postal.
                _selectedCity = null;
                _cityController.clear();
                _postalCodeController.clear();
              });
            }
          : null,
      validator: (value) =>
          (value == null || value.isEmpty) ? 'State/Province is required' : null,
      decoration: _dropdownDecoration(
        label: 'State/Province',
        helperText: _selectedLocation == null
            ? 'Select a Location first'
            : (_locationsLoaded ? 'Select your province' : 'Loading provinces…'),
        icon: Icons.map_outlined,
        enabled: enabled,
      ),
    );
  }

  /// City dropdown, populated with the cities/municipalities of the selected
  /// province. Selecting a city auto-fills the postal code (still editable).
  Widget _buildCityDropdown() {
    final enabled = _selectedProvince != null && _locationsLoaded;
    final options =
        PhLocationsService.citiesFor(_selectedLocation, _selectedProvince);
    final values = <String>[...options];
    if (_selectedCity != null && !values.contains(_selectedCity)) {
      values.insert(0, _selectedCity!);
    }
    return DropdownButtonFormField<String>(
      // Rebuild when the parent Location/Province changes (or data loads) so the
      // city resets on province change and edit-mode preselect displays.
      key: ValueKey(
          'city-${_selectedLocation ?? ''}-${_selectedProvince ?? ''}-$_locationsLoaded'),
      initialValue: _selectedCity,
      isExpanded: true,
      items: values
          .map((c) => DropdownMenuItem<String>(
                value: c,
                child: Text(c, style: AppTextStyles.bodyMedium, overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: enabled
          ? (value) {
              setState(() {
                _selectedCity = value;
                _cityController.text = value ?? '';
                // Auto-fill a representative ZIP when we have one; otherwise
                // clear so a stale ZIP from the previous city isn't kept.
                final zip = PhLocationsService.zipFor(
                    _selectedLocation, _selectedProvince, value);
                _postalCodeController.text = zip ?? '';
              });
            }
          : null,
      validator: (value) =>
          (value == null || value.isEmpty) ? 'City is required' : null,
      decoration: _dropdownDecoration(
        label: 'City',
        helperText: _selectedProvince == null
            ? 'Select a province first'
            : 'Select your city',
        icon: Icons.location_city_outlined,
        enabled: enabled,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    int? maxLines,
    String? helperText,
    bool enabled = true,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      maxLines: maxLines ?? 1,
      enabled: enabled,
      style: AppTextStyles.bodyMedium.copyWith(
        color: enabled ? null : AppColors.onSurface.withValues(alpha: 0.5),
      ),
      inputFormatters: label.contains('Phone')
          ? [
              // Only allow digits and basic formatting for phone
              FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
              LengthLimitingTextInputFormatter(11),
            ]
          : null,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        helperMaxLines: 2,
        errorMaxLines: 2,
        helperStyle: AppTextStyles.bodySmall.copyWith(
          color: AppColors.primary.withValues(alpha: 0.7),
        ),
        errorStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
        prefixIcon: Icon(
          icon,
          color: enabled
              ? AppColors.primary
              : AppColors.onSurface.withValues(alpha: 0.3),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: AppColors.onSurface.withValues(alpha: 0.2),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: AppColors.onSurface.withValues(alpha: 0.2),
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: AppColors.onSurface.withValues(alpha: 0.1),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.error, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.error, width: 2),
        ),
        filled: true,
        fillColor: enabled
            ? AppColors.surface
            : AppColors.surface.withValues(alpha: 0.5),
        labelStyle: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.onSurface.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}
