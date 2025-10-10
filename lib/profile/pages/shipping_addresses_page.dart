import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/shipping_address.dart';
import '../services/address_service.dart';
import '../widgets/address_map_widget.dart';
import '../../core/app_theme/app_colors.dart';
import '../../core/app_theme/app_text_styles.dart';
import 'package:dentpal/utils/app_logger.dart';

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
          style: AppTextStyles.titleLarge.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.add, color: AppColors.primary),
            onPressed: () => _showAddAddressDialog(),
            tooltip: 'Add Address',
          ),
        ],
      ),
      body: _isLoading
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
            Icon(
              Icons.error_outline,
              size: 64,
              color: AppColors.error,
            ),
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
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
                          Icon(Icons.delete_outline, size: 18, color: Colors.red),
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
                Text(
                  address.addressLine1,
                  style: AppTextStyles.bodyMedium,
                ),
                if (address.addressLine2 != null && address.addressLine2!.isNotEmpty)
                  Text(
                    address.addressLine2!,
                    style: AppTextStyles.bodyMedium,
                  ),
                Text(
                  '${address.city}, ${address.state} ${address.postalCode}',
                  style: AppTextStyles.bodyMedium,
                ),
                Text(
                  address.country,
                  style: AppTextStyles.bodyMedium,
                ),
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
  bool _isAutoFilling = false; // Track when auto-fill is in progress
  double? _latitude;
  double? _longitude;

  bool get _isEditing => widget.address != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _populateFields();
    } else {
      _countryController.text = 'Philippines'; // Default country
    }
    
    // Add listeners to update map when address fields change
    _addressLine1Controller.addListener(_updateMapAddress);
    _cityController.addListener(_updateMapAddress);
    _stateController.addListener(_updateMapAddress);
  }

  void _updateMapAddress() {
    // Trigger map update when any address field changes
    setState(() {}); // This will rebuild the widget and update the map
  }

  void _autoFillAddress(Map<String, String> addressData) {
    AppLogger.d('_autoFillAddress called with: $addressData');
    
    // Check if we got any meaningful data
    bool hasValidData = addressData['city']?.isNotEmpty == true || 
                        addressData['state']?.isNotEmpty == true ||
                        addressData['street']?.isNotEmpty == true;
    
    if (!hasValidData) {
      AppLogger.d('No valid address data found');
      // Show a different message if no data was found
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Location detected but address details not available. You can enter address manually.'),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }
    
    // Check if this is fallback data (no street address)
    bool isFallbackData = addressData['street']?.isEmpty == true;
    
    // Show a snackbar to confirm auto-fill is happening
    if (isFallbackData) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Location detected in ${addressData['city']}! Auto-filling city and state. Street address needs to be entered manually.'),
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Address detected and auto-filled! City: ${addressData['city']}, State: ${addressData['state']}'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
    
    // Directly auto-fill the address fields without showing a popup
    _fillAddressFields(addressData);
  }

  void _fillAddressFields(Map<String, String> addressData) {
    AppLogger.d('_fillAddressFields called with: $addressData');
    
    setState(() {
      _isAutoFilling = true; // Set flag to prevent map pin movement
      
      // Only fill empty fields and ensure the value is not null or empty
      if (_addressLine1Controller.text.trim().isEmpty && 
          addressData['street']?.isNotEmpty == true) {
        _addressLine1Controller.text = addressData['street']!;
        AppLogger.d('Filled addressLine1: ${addressData['street']}');
      }
      
      if (_cityController.text.trim().isEmpty && 
          addressData['city']?.isNotEmpty == true) {
        _cityController.text = addressData['city']!;
        AppLogger.d('Filled city: ${addressData['city']}');
      }
      
      if (_stateController.text.trim().isEmpty && 
          addressData['state']?.isNotEmpty == true) {
        _stateController.text = addressData['state']!;
        AppLogger.d('Filled state: ${addressData['state']}');
      }
      
      if (_postalCodeController.text.trim().isEmpty && 
          addressData['postalCode']?.isNotEmpty == true) {
        _postalCodeController.text = addressData['postalCode']!;
        AppLogger.d('Filled postalCode: ${addressData['postalCode']}');
      }
      
      if (_countryController.text.trim().isEmpty && 
          addressData['country']?.isNotEmpty == true) {
        _countryController.text = addressData['country']!;
        AppLogger.d('Filled country: ${addressData['country']}');
      }
      
      AppLogger.d('All fields filled successfully');
    });
    
    // Reset the flag after a brief delay to allow the UI to update
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() {
          _isAutoFilling = false;
        });
      }
    });
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
    
    _latitude = address.latitude;
    _longitude = address.longitude;
    _isDefault = address.isDefault;
  }

  @override
  void dispose() {
    // Remove listeners before disposing controllers
    _addressLine1Controller.removeListener(_updateMapAddress);
    _cityController.removeListener(_updateMapAddress);
    _stateController.removeListener(_updateMapAddress);
    
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
        latitude: _latitude,
        longitude: _longitude,
        notes: _notesController.text.trim().isEmpty 
            ? null 
            : _notesController.text.trim(),
        isDefault: _isDefault,
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
            content: Text(_isEditing 
                ? 'Address updated successfully' 
                : 'Address added successfully'),
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
          style: AppTextStyles.titleLarge.copyWith(
            fontWeight: FontWeight.w700,
          ),
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
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildTextField(
              controller: _fullNameController,
              label: 'Full Name',
              icon: Icons.person_outline,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Full name is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            _buildTextField(
              controller: _addressLine1Controller,
              label: 'Address Line 1',
              icon: Icons.home_outlined,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Address line 1 is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            _buildTextField(
              controller: _addressLine2Controller,
              label: 'Address Line 2 (Optional)',
              icon: Icons.home_outlined,
            ),
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _buildTextField(
                    controller: _cityController,
                    label: 'City',
                    icon: Icons.location_city_outlined,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'City is required';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 1,
                  child: _buildTextField(
                    controller: _postalCodeController,
                    label: 'Postal Code',
                    icon: Icons.markunread_mailbox_outlined,
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Postal code is required';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            _buildTextField(
              controller: _stateController,
              label: 'State/Province',
              icon: Icons.map_outlined,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'State/Province is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            _buildTextField(
              controller: _countryController,
              label: 'Country',
              icon: Icons.public_outlined,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Country is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            _buildTextField(
              controller: _phoneController,
              label: 'Phone Number (09123456789)',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Phone number is required';
                }
                
                // Remove any spaces or special characters for validation
                final cleanNumber = value.replaceAll(RegExp(r'[^\d]'), '');
                
                // Check if it's exactly 11 digits
                if (cleanNumber.length != 11) {
                  return 'Phone number must be 11 digits';
                }
                
                // Check if it starts with 09
                if (!cleanNumber.startsWith('09')) {
                  return 'Phone number must start with 09';
                }
                
                return null;
              },
            ),
            const SizedBox(height: 24),
            
            // Map widget for location selection
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Pin your exact location',
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap on the map to pin your exact location for better delivery accuracy',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 12),
                AddressMapWidget(
                  address: '${_addressLine1Controller.text}, ${_cityController.text}, ${_stateController.text}',
                  initialLatitude: _latitude,
                  initialLongitude: _longitude,
                  preventAutoRepositioning: _isAutoFilling, // Prevent repositioning during auto-fill
                  onLocationSelected: (lat, lng) {
                    setState(() {
                      _latitude = lat;
                      _longitude = lng;
                    });
                  },
                  onAddressFound: (addressData) {
                    _autoFillAddress(addressData);
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Notes field
            _buildTextField(
              controller: _notesController,
              label: 'Delivery Notes (Optional)',
              icon: Icons.note_outlined,
              maxLines: 3,
              validator: null,
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
                            color: AppColors.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _isDefault,
                    onChanged: (value) {
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
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.onPrimary,
                        ),
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
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      maxLines: maxLines ?? 1,
      style: AppTextStyles.bodyMedium,
      inputFormatters: label.contains('Phone') ? [
        // Only allow digits and basic formatting for phone
        FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
        LengthLimitingTextInputFormatter(11),
      ] : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.primary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.onSurface.withValues(alpha: 0.2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.onSurface.withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.error, width: 2),
        ),
        filled: true,
        fillColor: AppColors.surface,
        labelStyle: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.onSurface.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}
