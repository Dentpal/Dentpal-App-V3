import 'package:flutter/material.dart';
import '../../profile/models/shipping_address.dart';
import '../../profile/services/address_service.dart';
import '../../core/app_theme/app_text_styles.dart';
import '../../core/app_theme/ink_palette.dart';

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
    this.title = 'Shipping address',
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

        // Refresh the widget's selected address with the latest data from the
        // server for the address that is currently selected (same ID but
        // potentially edited content like a new city or province).
        final freshSelected = _selectedAddress != null
            ? addresses.firstWhere(
                (addr) => addr.id == _selectedAddress!.id,
                orElse: () => currentDefault,
              )
            : currentDefault;

        // Notify parent (and trigger shipping recalculation) when:
        // 1. No address is currently selected, OR
        // 2. The currently selected address no longer exists in the updated list, OR
        // 3. A different address is now the default, OR
        // 4. The selected address still exists but its shipping-relevant content
        //    has changed (e.g. city/province edited while keeping the same ID).
        final selectedGone =
            !addresses.any((addr) => addr.id == _selectedAddress?.id);
        final defaultSwitched =
            currentDefault.isDefault &&
            currentDefault.id != _selectedAddress?.id;
        final contentChanged =
            _selectedAddress != null &&
            !selectedGone &&
            freshSelected.formattedAddress != _selectedAddress!.formattedAddress;

        final shouldUpdateSelection = _selectedAddress == null ||
            selectedGone ||
            defaultSwitched ||
            contentChanged;

        if (shouldUpdateSelection) {
          final nextAddress = defaultSwitched || _selectedAddress == null
              ? currentDefault
              : freshSelected;
          setState(() {
            _selectedAddress = nextAddress;
          });
          widget.onAddressSelected(nextAddress);
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

  InkPalette get ink => InkPalette.of(context);

  Color get _danger =>
      ink.isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);

  @override
  Widget build(BuildContext context) {
    // Same card as every other checkout section: one hairline border, one
    // radius, a plain heading rather than a tinted brand-green band.
    return Container(
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on_outlined, size: 18, color: ink.emerald),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.title,
                  style: AppTextStyles.titleMedium.copyWith(
                    color: ink.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              if (widget.showAddButton)
                TextButton.icon(
                  onPressed: widget.onAddNewAddress ?? _showAddAddressDialog,
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(
                    'Add',
                    style: AppTextStyles.bodySmall.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: ink.emerald,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _buildContent(),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: ink.emerald,
            ),
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
          const SizedBox(height: 10),
          InkWell(
            onTap: _toggleShowAllAddresses,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                color: ink.surfaceHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ink.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Choose a different address '
                    '(${_addresses.length - 1} more)',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: ink.emerald,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.keyboard_arrow_down,
                    color: ink.emerald,
                    size: 17,
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
              'Select an address',
              style: AppTextStyles.titleSmall.copyWith(
                color: ink.text.withValues(alpha: 0.7),
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: _toggleShowAllAddresses,
              style: TextButton.styleFrom(
                foregroundColor: ink.emerald,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Close',
                style: AppTextStyles.bodySmall.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Addresses list
        ...List.generate(_addresses.length, (index) {
          final address = _addresses[index];
          final isSelected = _selectedAddress?.id == address.id;

          return Padding(
            padding: EdgeInsets.only(
              bottom: index < _addresses.length - 1 ? 8 : 0,
            ),
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
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? ink.emerald.withValues(alpha: ink.isDark ? 0.14 : 0.08)
              : ink.surfaceHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? ink.emerald : ink.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Name and badges
            Row(
              children: [
                Expanded(
                  child: Text(
                    address.fullName,
                    style: AppTextStyles.titleSmall.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                      color: isSelected ? ink.emerald : ink.text,
                    ),
                  ),
                ),
                if (address.isDefault) _badge('Default'),
                if (isSelected && !_showAllAddresses) ...[
                  if (address.isDefault) const SizedBox(width: 6),
                  _badge('Selected'),
                ],
              ],
            ),
            const SizedBox(height: 7),

            // Address
            Text(
              address.formattedAddress,
              style: AppTextStyles.bodyMedium.copyWith(
                color: ink.text.withValues(alpha: 0.75),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 7),

            // Phone number
            Row(
              children: [
                Icon(
                  Icons.phone_outlined,
                  size: 14,
                  color: ink.text.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 5),
                Text(
                  address.phoneNumber,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: ink.text.withValues(alpha: 0.55),
                    fontSize: 12,
                  ),
                ),
              ],
            ),

            // Delivery notes (if any)
            if (address.notes?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: ink.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: ink.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.sticky_note_2_outlined,
                      size: 14,
                      color: ink.text.withValues(alpha: 0.45),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        address.notes!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: ink.text.withValues(alpha: 0.65),
                          fontSize: 12,
                          height: 1.35,
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

  Widget _badge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: ink.emerald.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          color: ink.emerald,
          fontWeight: FontWeight.w700,
          fontSize: 10.5,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: ink.surfaceHigh,
              shape: BoxShape.circle,
              border: Border.all(color: ink.border),
            ),
            child: Icon(
              Icons.location_off_outlined,
              size: 26,
              color: ink.text.withValues(alpha: 0.35),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'No addresses yet',
            style: AppTextStyles.bodyMedium.copyWith(
              color: ink.text.withValues(alpha: 0.8),
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Add a shipping address to continue.',
            style: AppTextStyles.bodySmall.copyWith(
              color: ink.text.withValues(alpha: 0.5),
              fontSize: 12.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          _primaryButton(
            icon: Icons.add,
            label: 'Add address',
            onPressed: widget.onAddNewAddress ?? _showAddAddressDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 34, color: _danger),
          const SizedBox(height: 12),
          Text(
            'Couldn\'t load your addresses',
            style: AppTextStyles.bodyMedium.copyWith(
              color: _danger,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            _error ?? 'Unknown error occurred',
            style: AppTextStyles.bodySmall.copyWith(
              color: ink.text.withValues(alpha: 0.5),
              fontSize: 12.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          _primaryButton(
            icon: Icons.refresh,
            label: 'Retry',
            onPressed: _loadAddresses,
          ),
        ],
      ),
    );
  }

  Widget _primaryButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      label: Text(
        label,
        style: AppTextStyles.buttonMedium.copyWith(fontWeight: FontWeight.w700),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: ink.emerald,
        foregroundColor: ink.onEmerald,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  void _showAddAddressDialog() {
    Navigator.of(context).pushNamed('/profile/address').then((_) {
      // Reload addresses when returning from the addresses page
      // This ensures any new addresses added or changes made are reflected
      _loadAddresses();
    });
  }
}

/// Compact version of address selection for smaller spaces.
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
    final ink = InkPalette.of(context);

    return InkWell(
      onTap: () => _showAddressSelectionModal(context),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ink.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ink.border),
        ),
        child: Row(
          children: [
            Icon(Icons.location_on_outlined, color: ink.emerald, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: selectedAddress != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selectedAddress!.fullName,
                          style: AppTextStyles.titleSmall.copyWith(
                            color: ink.text,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          selectedAddress!.formattedAddress,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: ink.text.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    )
                  : Text(
                      'Select a shipping address',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: ink.text.withValues(alpha: 0.55),
                        fontSize: 13.5,
                      ),
                    ),
            ),
            Icon(
              Icons.chevron_right,
              color: ink.text.withValues(alpha: 0.4),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  void _showAddressSelectionModal(BuildContext context) {
    final ink = InkPalette.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: ink.bg,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: AddressSelectionWidget(
            selectedAddress: selectedAddress,
            onAddressSelected: (address) {
              onAddressSelected(address);
              Navigator.pop(context);
            },
            onAddNewAddress: onAddNewAddress,
            title: 'Select a shipping address',
          ),
        ),
      ),
    );
  }
}
