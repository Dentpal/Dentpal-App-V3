import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocoding/geocoding.dart' as geo;
import '../models/shipping_address.dart';
import '../services/address_service.dart';
import '../services/ph_locations_service.dart';
import '../../core/app_theme/app_text_styles.dart';
import '../../core/app_theme/ink_palette.dart';
import '../../core/app_theme/theme_utils.dart';
import '../../core/widgets/app_page_header.dart';
import '../../core/widgets/skeleton.dart';
import 'package:dentpal/utils/app_logger.dart';
import '../../core/services/sub_account_service.dart';

/// Where this account's orders get delivered.
class ShippingAddressesPage extends StatefulWidget {
  const ShippingAddressesPage({super.key});

  @override
  State<ShippingAddressesPage> createState() => _ShippingAddressesPageState();
}

class _ShippingAddressesPageState extends State<ShippingAddressesPage> {
  /// Held in a field rather than built inside `build()`, so a rebuild does not
  /// re-open the query — and so [_retry] has something to actually replace.
  late Stream<List<ShippingAddress>> _addressesStream =
      AddressService.getAddressesStream();

  void _retry() => setState(
    () => _addressesStream = AddressService.getAddressesStream(),
  );

  // ── Palette ──────────────────────────────────────────────────────────────

  InkPalette get ink => InkPalette.of(context);

  /// Destructive red. [InkPalette] reserves amber for urgency, so danger needs
  /// its own tone that still reads in both themes.
  Color get _danger =>
      ink.isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);

  Color get _muted => ink.text.withValues(alpha: 0.6);

  static const EdgeInsets _listPadding = EdgeInsets.fromLTRB(
    AppLayout.gutter,
    4,
    AppLayout.gutter,
    28,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ink.bg,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppLayout.maxContentWidth,
            ),
            child: StreamBuilder<List<ShippingAddress>>(
              stream: _addressesStream,
              builder: (context, snapshot) {
                final addresses = snapshot.data ?? const <ShippingAddress>[];

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(snapshot, addresses),
                    Expanded(child: _buildBody(snapshot, addresses)),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────

  Widget _buildHeader(
    AsyncSnapshot<List<ShippingAddress>> snapshot,
    List<ShippingAddress> addresses,
  ) {
    final String subtitle;
    if (snapshot.hasError) {
      subtitle = 'Couldn’t load your addresses';
    } else if (snapshot.connectionState == ConnectionState.waiting) {
      subtitle = 'Loading your addresses…';
    } else if (addresses.isEmpty) {
      subtitle = 'No addresses yet';
    } else {
      subtitle =
          '${addresses.length} address${addresses.length == 1 ? '' : 'es'} saved';
    }

    return AppPageHeader(
      title: 'Shipping addresses',
      subtitle: subtitle,
      subtitleColor: snapshot.hasError ? _danger : null,
      // Below ~430px the labelled button and the title fight over the same
      // row, so the action collapses to its icon.
      trailing: _buildAddButton(
        compact: MediaQuery.sizeOf(context).width < 430,
      ),
    );
  }

  Widget _buildAddButton({bool compact = false}) {
    if (compact) {
      return Tooltip(
        message: 'Add address',
        child: IconButton(
          onPressed: () => _openEditor(),
          icon: Icon(Icons.add, size: 20, color: ink.onEmerald),
          style: IconButton.styleFrom(
            backgroundColor: ink.emerald,
            shape: const CircleBorder(),
          ),
        ),
      );
    }

    return SizedBox(
      height: 38,
      child: ElevatedButton.icon(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add, size: 16),
        label: Text(
          'Add address',
          style: AppTextStyles.buttonMedium.copyWith(fontSize: 12.5),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: ink.emerald,
          foregroundColor: ink.onEmerald,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }

  // ── Body ─────────────────────────────────────────────────────────────────

  Widget _buildBody(
    AsyncSnapshot<List<ShippingAddress>> snapshot,
    List<ShippingAddress> addresses,
  ) {
    if (snapshot.hasError) {
      return _buildStateMessage(
        icon: Icons.cloud_off,
        tone: _danger,
        title: 'Couldn’t load addresses',
        detail:
            'Check your connection and try again — nothing has been lost.',
        action: _buildStateAction(
          label: 'Retry',
          icon: Icons.refresh,
          onTap: _retry,
        ),
      );
    }

    if (snapshot.connectionState == ConnectionState.waiting) {
      return const _AddressesSkeleton(padding: _listPadding);
    }

    if (addresses.isEmpty) {
      return _buildStateMessage(
        icon: Icons.location_on_outlined,
        tone: ink.emerald,
        title: 'No addresses yet',
        detail:
            'Add where your orders should be delivered — you can save more '
            'than one and pick at checkout.',
        action: _buildStateAction(
          label: 'Add address',
          icon: Icons.add,
          onTap: () => _openEditor(),
        ),
      );
    }

    return ListView.builder(
      padding: _listPadding,
      itemCount: addresses.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _buildAddressCard(addresses[index]),
      ),
    );
  }

  /// One saved address, with the default one outlined in emerald so it can be
  /// picked out without reading a badge.
  Widget _buildAddressCard(ShippingAddress address) {
    final isDefault = address.isDefault;
    final hasNotes = address.notes != null && address.notes!.isNotEmpty;
    final hasPin = address.latitude != null && address.longitude != null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDefault ? ink.emerald.withValues(alpha: 0.55) : ink.border,
          width: isDefault ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: ink.emerald.withValues(
                    alpha: ink.isDark ? 0.16 : 0.11,
                  ),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.location_on_outlined,
                  color: ink.emerald,
                  size: 19,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      address.fullName,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: ink.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (isDefault) ...[
                      const SizedBox(height: 6),
                      _buildBadge(
                        label: 'Default',
                        icon: Icons.check_circle_outline,
                        tone: ink.emerald,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Delete used to hide inside a three-dot menu alongside Edit and
              // Set as default; those two now have their own buttons below, so
              // this is all the menu had left.
              Tooltip(
                message: 'Delete address',
                child: IconButton(
                  onPressed: () => _deleteAddress(address),
                  icon: Icon(Icons.delete_outline, size: 19, color: _danger),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // The place itself, laid out by the model so this card and every
          // other reader of an address agree on the shape.
          for (final line in address.addressLines)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                line,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: ink.text.withValues(alpha: 0.75),
                  fontSize: 13.5,
                  height: 1.35,
                ),
              ),
            ),

          const SizedBox(height: 8),
          _buildDetailRow(Icons.phone_outlined, address.phoneNumber),

          if (hasNotes) ...[
            const SizedBox(height: 6),
            _buildDetailRow(Icons.note_outlined, address.notes!, italic: true),
          ],

          if (hasPin) ...[
            const SizedBox(height: 10),
            _buildBadge(
              label: 'Location pinned',
              icon: Icons.my_location,
              tone: ink.emeraldSoft,
            ),
          ],

          const SizedBox(height: 12),
          Divider(height: 1, color: ink.border),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _buildOutlinedButton(
                  label: 'Edit',
                  icon: Icons.edit_outlined,
                  onTap: () => _openEditor(address: address),
                ),
              ),
              if (!isDefault) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: _buildFilledButton(
                    label: 'Set as default',
                    icon: Icons.check_circle_outline,
                    onTap: () => _setAsDefault(address.id),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String text, {bool italic = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 14, color: ink.text.withValues(alpha: 0.45)),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.bodySmall.copyWith(
              color: ink.text.withValues(alpha: 0.55),
              fontSize: 12.5,
              fontStyle: italic ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ),
      ],
    );
  }

  // ── Small parts ──────────────────────────────────────────────────────────

  Widget _buildBadge({
    required String label,
    required IconData icon,
    required Color tone,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: ink.isDark ? 0.16 : 0.11),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tone.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: tone),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: tone,
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilledButton({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 40,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.buttonMedium.copyWith(fontSize: 13),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: ink.emerald,
          foregroundColor: ink.onEmerald,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildOutlinedButton({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
    Color? tone,
  }) {
    final foreground = tone ?? ink.text;
    return SizedBox(
      height: 40,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.buttonMedium.copyWith(fontSize: 13),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          backgroundColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          side: BorderSide(
            color: tone == null ? ink.border : tone.withValues(alpha: 0.45),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildStateAction({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 46,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label, style: AppTextStyles.buttonMedium),
        style: ElevatedButton.styleFrom(
          backgroundColor: ink.emerald,
          foregroundColor: ink.onEmerald,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Widget _buildStateMessage({
    required IconData icon,
    required Color tone,
    required String title,
    required String detail,
    Widget? action,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 40, 32, 60),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: tone.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 30, color: tone),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.titleMedium.copyWith(
                        color: ink.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      detail,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: _muted,
                        fontSize: 13.5,
                        height: 1.45,
                      ),
                    ),
                    if (action != null) ...[
                      const SizedBox(height: 24),
                      action,
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _setAsDefault(String addressId) async {
    try {
      await AddressService.setAsDefault(addressId);
      if (mounted) {
        _showSnack('Default address updated', ink.emerald);
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Error: $e', _danger);
      }
    }
  }

  Future<void> _deleteAddress(ShippingAddress address) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ink.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.delete_outline, color: _danger),
            const SizedBox(width: 8),
            Text('Delete address?', style: TextStyle(color: ink.text)),
          ],
        ),
        content: Text(
          'This address will be permanently removed from your account.',
          style: AppTextStyles.bodyMedium.copyWith(color: _muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Keep', style: TextStyle(color: _muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _danger,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete != true) return;

    try {
      await AddressService.deleteAddress(address.id);
      if (mounted) {
        _showSnack('Address deleted', ink.emerald);
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Error deleting address: $e', _danger);
      }
    }
  }

  void _showSnack(String message, Color tone) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: tone,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// Named routes, so the address bar reads `/profile/address/add` or
  /// `/profile/address/edit`. The path deliberately carries no address id, so
  /// which one to edit travels in arguments.
  void _openEditor({ShippingAddress? address}) {
    final navigator = Navigator.of(context);
    if (address == null) {
      navigator.pushNamed('/profile/address/add');
    } else {
      navigator.pushNamed('/profile/address/edit', arguments: address);
    }
  }
}

/// Placeholder cards in the shape the real list settles into, so the page does
/// not jump when the stream arrives.
class _AddressesSkeleton extends StatelessWidget {
  const _AddressesSkeleton({this.padding = EdgeInsets.zero});

  final EdgeInsetsGeometry padding;

  /// Enough cards to fill a phone screen; the real list replaces them before a
  /// reader could count.
  static const int _itemCount = 3;

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);

    return SkeletonShimmer(
      child: ListView.builder(
        padding: padding,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _itemCount,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ink.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: ink.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    SkeletonBox(width: 38, height: 38, radius: 11),
                    SizedBox(width: 14),
                    Expanded(child: SkeletonLine(width: 140, height: 13)),
                  ],
                ),
                const SizedBox(height: 14),
                const SkeletonLine(widthFactor: 0.9, height: 11),
                const SizedBox(height: 7),
                const SkeletonLine(widthFactor: 0.7, height: 11),
                const SizedBox(height: 7),
                const SkeletonLine(widthFactor: 0.5, height: 11),
                const SizedBox(height: 16),
                const SkeletonBox(height: 40, radius: 12),
              ],
            ),
          ),
        ),
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
          userName =
              userData?['fullName'] ??
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
    _selectedLocation = _locationOptions.contains(address.location)
        ? address.location
        : null;
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

    // Captured before the awaits: on success this page is popped, so reaching
    // for its Navigator or messenger afterwards would be reaching through a
    // context that is on its way out.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

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
        latitude:
            coords?.latitude ?? (_isEditing ? widget.address!.latitude : null),
        longitude:
            coords?.longitude ?? (_isEditing ? widget.address!.longitude : null),
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

      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(_isEditing ? 'Address updated' : 'Address added'),
          backgroundColor: ink.emerald,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        _showSnack('Error: $e', _danger);
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
    'manila',
    'quezon city',
    'caloocan',
    'las pinas',
    'las piñas',
    'makati',
    'malabon',
    'mandaluyong',
    'marikina',
    'muntinlupa',
    'navotas',
    'paranaque',
    'parañaque',
    'pasay',
    'pasig',
    'pateros',
    'san juan',
    'taguig',
    'valenzuela',
  ];

  bool _looksMetroManila(String city, String state) {
    final c = city.toLowerCase().trim();
    final s = state.toLowerCase().trim();
    if (s.contains('metro manila') ||
        s.contains('ncr') ||
        c.contains('metro manila')) {
      return true;
    }
    return _ncrCities.any(
      (nc) => c == nc || s == nc || c.contains(nc) || s.contains(nc),
    );
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
      _showSnack(
        'Heads up: Same Day Delivery is only available within Metro Manila.',
        ink.amber,
        onTone: ink.onAmber,
        seconds: 4,
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

  // ── Palette ──────────────────────────────────────────────────────────────

  InkPalette get ink => InkPalette.of(context);

  Color get _danger =>
      ink.isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);

  /// A form reads best in a narrower column than a browse grid, so the fields
  /// stop short of the page's full width — but it still centres inside the same
  /// frame every other buyer surface uses.
  static const double _formMaxWidth = 640;

  static const EdgeInsets _listPadding = EdgeInsets.fromLTRB(
    AppLayout.gutter,
    4,
    AppLayout.gutter,
    32,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ink.bg,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _formMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppPageHeader(
                  title: _isEditing ? 'Edit address' : 'New address',
                  subtitle: 'Where your orders are delivered',
                ),
                Expanded(child: _buildForm()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      autovalidateMode: _autovalidateMode,
      child: ListView(
        padding: _listPadding,
        children: [
          _buildInfoBanner(),
          const SizedBox(height: 18),

          _buildSectionHeader('Recipient'),
          const SizedBox(height: 10),
          _buildTextField(
            controller: _fullNameController,
            label: 'Full name',
            icon: Icons.person_outline,
            validator: (value) => (value == null || value.trim().isEmpty)
                ? 'Full name is required'
                : null,
          ),
          const SizedBox(height: 14),
          _buildTextField(
            controller: _phoneController,
            label: 'Phone number (09123456789)',
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            enabled: _selectedLocation != null,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Phone number is required';
              }
              final clean = value.replaceAll(RegExp(r'[^\d]'), '');
              if (clean.length != 11) {
                return 'Phone number must be 11 digits';
              }
              if (!clean.startsWith('09')) {
                return 'Phone number must start with 09';
              }
              return null;
            },
          ),

          const SizedBox(height: 22),
          _buildSectionHeader('Location'),
          const SizedBox(height: 10),
          _buildLocationDropdown(),
          const SizedBox(height: 14),
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
          const SizedBox(height: 14),
          _buildProvinceDropdown(),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: _buildCityDropdown()),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTextField(
                  controller: _postalCodeController,
                  label: 'Postal code',
                  icon: Icons.markunread_mailbox_outlined,
                  keyboardType: TextInputType.number,
                  enabled: _selectedLocation != null,
                  helperText: 'Auto-filled; edit if needed',
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Postal code is required'
                      : null,
                ),
              ),
            ],
          ),

          const SizedBox(height: 22),
          _buildSectionHeader('Street'),
          const SizedBox(height: 10),
          _buildTextField(
            controller: _addressLine1Controller,
            label: 'Address line 1',
            icon: Icons.home_outlined,
            enabled: _selectedLocation != null,
            validator: (value) => (value == null || value.trim().isEmpty)
                ? 'Address line 1 is required'
                : null,
          ),
          const SizedBox(height: 14),
          _buildTextField(
            controller: _addressLine2Controller,
            label: 'Address line 2 (optional)',
            icon: Icons.home_outlined,
            enabled: _selectedLocation != null,
          ),
          const SizedBox(height: 14),
          _buildTextField(
            controller: _notesController,
            label: 'Delivery notes (optional)',
            icon: Icons.note_outlined,
            maxLines: 3,
            enabled: _selectedLocation != null,
          ),

          const SizedBox(height: 22),
          _buildDefaultToggle(),

          const SizedBox(height: 24),
          _buildSaveButton(),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        title,
        style: AppTextStyles.titleMedium.copyWith(
          color: ink.text,
          fontWeight: FontWeight.w800,
          fontSize: 15,
        ),
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ink.emerald.withValues(alpha: ink.isDark ? 0.14 : 0.09),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ink.emerald.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: ink.emerald, size: 19),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Pick your location, province and city from the lists. The '
              'postal code is filled in for you — edit it if needed.',
              style: AppTextStyles.bodySmall.copyWith(
                color: ink.text.withValues(alpha: 0.75),
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultToggle() {
    final enabled = _selectedLocation != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: ink.emerald.withValues(
                alpha: enabled ? (ink.isDark ? 0.16 : 0.11) : 0.06,
              ),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              Icons.check_circle_outline,
              color: ink.emerald.withValues(alpha: enabled ? 1 : 0.4),
              size: 19,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Set as default',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: ink.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Pre-selected at checkout',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: ink.text.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _isDefault,
            onChanged: enabled
                ? (value) => setState(() => _isDefault = value)
                : null,
            activeThumbColor: ink.onEmerald,
            activeTrackColor: ink.emerald,
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _saveAddress,
        style: ElevatedButton.styleFrom(
          backgroundColor: ink.emerald,
          foregroundColor: ink.onEmerald,
          disabledBackgroundColor: ink.emerald.withValues(alpha: 0.5),
          disabledForegroundColor: ink.onEmerald.withValues(alpha: 0.8),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: _isLoading
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: ink.onEmerald,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('Saving…', style: AppTextStyles.buttonLarge),
                ],
              )
            : Text(
                _isEditing ? 'Update address' : 'Save address',
                style: AppTextStyles.buttonLarge,
              ),
      ),
    );
  }

  // ── Fields ───────────────────────────────────────────────────────────────

  /// The one decoration every field and dropdown on this form wears.
  ///
  /// Text fields and the three dropdowns each carried their own copy of eight
  /// `OutlineInputBorder`s; they now share this, so a disabled dropdown and a
  /// disabled text field cannot look like different controls.
  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    required bool enabled,
    String? helperText,
  }) {
    OutlineInputBorder border(Color color, {double width = 1}) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecoration(
      labelText: label,
      helperText: helperText,
      helperMaxLines: 2,
      errorMaxLines: 2,
      helperStyle: AppTextStyles.bodySmall.copyWith(
        color: ink.text.withValues(alpha: 0.45),
        fontSize: 11.5,
      ),
      errorStyle: AppTextStyles.bodySmall.copyWith(
        color: _danger,
        fontSize: 11.5,
      ),
      prefixIcon: Icon(
        icon,
        size: 19,
        color: enabled ? ink.emerald : ink.text.withValues(alpha: 0.25),
      ),
      border: border(ink.border),
      enabledBorder: border(ink.border),
      disabledBorder: border(ink.border.withValues(alpha: 0.5)),
      focusedBorder: border(ink.emerald, width: 1.5),
      errorBorder: border(_danger),
      focusedErrorBorder: border(_danger, width: 1.5),
      filled: true,
      fillColor: enabled ? ink.surface : ink.surfaceHigh,
      labelStyle: AppTextStyles.bodyMedium.copyWith(
        color: ink.text.withValues(alpha: 0.6),
        fontSize: 14,
      ),
      floatingLabelStyle: AppTextStyles.bodyMedium.copyWith(
        color: ink.emerald,
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
    );
  }

  /// Menu entry styling, shared by all three cascading dropdowns.
  DropdownMenuItem<String> _dropdownItem(String value) {
    return DropdownMenuItem<String>(
      value: value,
      child: Text(
        value,
        style: AppTextStyles.bodyMedium.copyWith(color: ink.text, fontSize: 14),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildLocationDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedLocation,
      isExpanded: true,
      dropdownColor: ink.surface,
      borderRadius: BorderRadius.circular(14),
      icon: Icon(
        Icons.keyboard_arrow_down,
        color: ink.text.withValues(alpha: 0.4),
      ),
      items: _locationOptions.map(_dropdownItem).toList(),
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
      decoration: _fieldDecoration(
        label: 'Location',
        icon: Icons.location_on_outlined,
        enabled: true,
        helperText: _selectedLocation == null
            ? 'Select your location to continue'
            : 'NCR, Luzon, Visayas, or Mindanao',
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
      dropdownColor: ink.surface,
      borderRadius: BorderRadius.circular(14),
      icon: Icon(
        Icons.keyboard_arrow_down,
        color: ink.text.withValues(alpha: enabled ? 0.4 : 0.2),
      ),
      items: values.map(_dropdownItem).toList(),
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
      validator: (value) => (value == null || value.isEmpty)
          ? 'State/Province is required'
          : null,
      decoration: _fieldDecoration(
        label: 'State/Province',
        icon: Icons.map_outlined,
        enabled: enabled,
        helperText: _selectedLocation == null
            ? 'Select a location first'
            : (_locationsLoaded ? 'Select your province' : 'Loading provinces…'),
      ),
    );
  }

  /// City dropdown, populated with the cities/municipalities of the selected
  /// province. Selecting a city auto-fills the postal code (still editable).
  Widget _buildCityDropdown() {
    final enabled = _selectedProvince != null && _locationsLoaded;
    final options = PhLocationsService.citiesFor(
      _selectedLocation,
      _selectedProvince,
    );
    final values = <String>[...options];
    if (_selectedCity != null && !values.contains(_selectedCity)) {
      values.insert(0, _selectedCity!);
    }
    return DropdownButtonFormField<String>(
      // Rebuild when the parent Location/Province changes (or data loads) so the
      // city resets on province change and edit-mode preselect displays.
      key: ValueKey(
        'city-${_selectedLocation ?? ''}-${_selectedProvince ?? ''}-$_locationsLoaded',
      ),
      initialValue: _selectedCity,
      isExpanded: true,
      dropdownColor: ink.surface,
      borderRadius: BorderRadius.circular(14),
      icon: Icon(
        Icons.keyboard_arrow_down,
        color: ink.text.withValues(alpha: enabled ? 0.4 : 0.2),
      ),
      items: values.map(_dropdownItem).toList(),
      onChanged: enabled
          ? (value) {
              setState(() {
                _selectedCity = value;
                _cityController.text = value ?? '';
                // Auto-fill a representative ZIP when we have one; otherwise
                // clear so a stale ZIP from the previous city isn't kept.
                final zip = PhLocationsService.zipFor(
                  _selectedLocation,
                  _selectedProvince,
                  value,
                );
                _postalCodeController.text = zip ?? '';
              });
            }
          : null,
      validator: (value) =>
          (value == null || value.isEmpty) ? 'City is required' : null,
      decoration: _fieldDecoration(
        label: 'City',
        icon: Icons.location_city_outlined,
        enabled: enabled,
        helperText: _selectedProvince == null
            ? 'Select a province first'
            : 'Select your city',
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
      cursorColor: ink.emerald,
      style: AppTextStyles.bodyMedium.copyWith(
        color: enabled ? ink.text : ink.text.withValues(alpha: 0.45),
        fontSize: 14,
      ),
      inputFormatters: label.toLowerCase().contains('phone')
          ? [
              // Only allow digits and basic formatting for phone
              FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
              LengthLimitingTextInputFormatter(11),
            ]
          : null,
      decoration: _fieldDecoration(
        label: label,
        icon: icon,
        enabled: enabled,
        helperText: helperText,
      ),
    );
  }

  void _showSnack(
    String message,
    Color tone, {
    Color? onTone,
    int seconds = 3,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: onTone ?? Colors.white),
        ),
        backgroundColor: tone,
        duration: Duration(seconds: seconds),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
