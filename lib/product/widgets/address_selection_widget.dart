import 'package:flutter/material.dart';
import '../../profile/models/shipping_address.dart';
import '../../profile/services/address_service.dart';
import '../../profile/pages/shipping_addresses_page.dart';
import '../../core/app_theme/app_colors.dart';
import '../../core/app_theme/app_text_styles.dart';

class AddressSelectionWidget extends StatefulWidget {
  final ShippingAddress? selectedAddress;
  final Function(ShippingAddress) onAddressSelected;
  final VoidCallback? onAddNewAddress;
  final bool showAddButton;
  final String title;

  const AddressSelectionWidget({
    super.key,
    this.selectedAddress,
    required this.onAddressSelected,
    this.onAddNewAddress,
    this.showAddButton = true,
    this.title = 'Shipping Address',
  });

  @override
  State<AddressSelectionWidget> createState() => _AddressSelectionWidgetState();
}

class _AddressSelectionWidgetState extends State<AddressSelectionWidget> {
  ShippingAddress? _selectedAddress;
  List<ShippingAddress> _addresses = [];
  bool _isLoading = true;
  bool _showAllAddresses = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedAddress = widget.selectedAddress;
    _loadAddresses();
  }

  Future<void> _loadAddresses() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final addresses = await AddressService.getAllAddresses();
      
      setState(() {
        _addresses = addresses;
        _isLoading = false;
      });

      // Always check for and use the current default address
      if (addresses.isNotEmpty) {
        final currentDefault = addresses.firstWhere(
          (addr) => addr.isDefault,
          orElse: () => addresses.first,
        );
        
        // Update selected address if:
        // 1. No address is currently selected, OR
        // 2. The currently selected address no longer exists in the updated list, OR
        // 3. There's a new default address that's different from current selection
        final shouldUpdateSelection = _selectedAddress == null ||
            !addresses.any((addr) => addr.id == _selectedAddress?.id) ||
            (currentDefault.isDefault && currentDefault.id != _selectedAddress?.id);
        
        if (shouldUpdateSelection) {
          setState(() {
            _selectedAddress = currentDefault;
          });
          
          widget.onAddressSelected(currentDefault);
        }
      }

    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  void _selectAddress(ShippingAddress address) {
    setState(() {
      _selectedAddress = address;
      _showAllAddresses = false;
    });
    widget.onAddressSelected(address);
  }

  void _toggleShowAllAddresses() {
    setState(() {
      _showAllAddresses = !_showAllAddresses;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.onSurface.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.location_on,
                  color: AppColors.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title,
                    style: AppTextStyles.titleMedium.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (widget.showAddButton)
                  TextButton.icon(
                    onPressed: widget.onAddNewAddress ?? _showAddAddressDialog,
                    icon: Icon(
                      Icons.add,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    label: Text(
                      'Add',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(
            color: AppColors.primary,
          ),
        ),
      );
    }

    if (_error != null) {
      return _buildErrorState();
    }

    if (_addresses.isEmpty) {
      return _buildEmptyState();
    }

    if (_showAllAddresses) {
      return _buildAllAddressesList();
    }

    return _buildSelectedAddressCard();
  }

  Widget _buildSelectedAddressCard() {
    if (_selectedAddress == null) {
      return _buildEmptyState();
    }

    return Column(
      children: [
        _buildAddressCard(_selectedAddress!, isSelected: true),
        
        if (_addresses.length > 1) ...[
          const SizedBox(height: 12),
          InkWell(
            onTap: _toggleShowAllAddresses,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.grey50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.onSurface.withValues(alpha: 0.1),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Choose different address (${_addresses.length - 1} more)',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.keyboard_arrow_down,
                    color: AppColors.primary,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAllAddressesList() {
    return Column(
      children: [
        // Header for address list
        Row(
          children: [
            Text(
              'Select Address',
              style: AppTextStyles.titleSmall.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: _toggleShowAllAddresses,
              child: Text(
                'Close',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        // Addresses list
        ...List.generate(_addresses.length, (index) {
          final address = _addresses[index];
          final isSelected = _selectedAddress?.id == address.id;
          
          return Padding(
            padding: EdgeInsets.only(bottom: index < _addresses.length - 1 ? 12 : 0),
            child: _buildAddressCard(
              address,
              isSelected: isSelected,
              onTap: () => _selectAddress(address),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildAddressCard(
    ShippingAddress address, {
    bool isSelected = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected 
              ? AppColors.primary.withValues(alpha: 0.05)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected 
                ? AppColors.primary
                : AppColors.onSurface.withValues(alpha: 0.1),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Name and default badge
            Row(
              children: [
                Expanded(
                  child: Text(
                    address.fullName,
                    style: AppTextStyles.titleSmall.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isSelected ? AppColors.primary : AppColors.onSurface,
                    ),
                  ),
                ),
                if (address.isDefault)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Default',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (isSelected && !_showAllAddresses)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Selected',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            
            // Address
            Text(
              address.formattedAddress,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.8),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            
            // Phone number
            Row(
              children: [
                Icon(
                  Icons.phone,
                  size: 14,
                  color: AppColors.onSurface.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 4),
                Text(
                  address.phoneNumber,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
            
            // Delivery notes (if any)
            if (address.notes?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.note_outlined,
                      size: 14,
                      color: AppColors.info,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        address.notes!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.info,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(
            Icons.location_off_outlined,
            size: 48,
            color: AppColors.onSurface.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'No addresses available',
            style: AppTextStyles.titleSmall.copyWith(
              color: AppColors.onSurface.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add a shipping address to continue',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: widget.onAddNewAddress ?? _showAddAddressDialog,
            icon: const Icon(Icons.add),
            label: const Text('Add Address'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: AppColors.error,
          ),
          const SizedBox(height: 16),
          Text(
            'Error loading addresses',
            style: AppTextStyles.titleSmall.copyWith(
              color: AppColors.error,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _error ?? 'Unknown error occurred',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.onSurface.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
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
    );
  }

  void _showAddAddressDialog() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const ShippingAddressesPage(),
      ),
    ).then((_) {
      // Reload addresses when returning from the addresses page
      // This ensures any new addresses added or changes made are reflected
      _loadAddresses();
    });
  }
}

// Compact version of address selection for smaller spaces
class CompactAddressSelector extends StatelessWidget {
  final ShippingAddress? selectedAddress;
  final Function(ShippingAddress) onAddressSelected;
  final VoidCallback? onAddNewAddress;

  const CompactAddressSelector({
    super.key,
    this.selectedAddress,
    required this.onAddressSelected,
    this.onAddNewAddress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.onSurface.withValues(alpha: 0.1),
        ),
      ),
      child: InkWell(
        onTap: () => _showAddressSelectionModal(context),
        borderRadius: BorderRadius.circular(8),
        child: Row(
          children: [
            Icon(
              Icons.location_on,
              color: AppColors.primary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: selectedAddress != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selectedAddress!.fullName,
                          style: AppTextStyles.titleSmall.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          selectedAddress!.formattedAddress,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.onSurface.withValues(alpha: 0.7),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    )
                  : Text(
                      'Select shipping address',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
            ),
            Icon(
              Icons.keyboard_arrow_right,
              color: AppColors.onSurface.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddressSelectionModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: AddressSelectionWidget(
            selectedAddress: selectedAddress,
            onAddressSelected: (address) {
              onAddressSelected(address);
              Navigator.pop(context);
            },
            onAddNewAddress: onAddNewAddress,
            title: 'Select Shipping Address',
          ),
        ),
      ),
    );
  }
}
