import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io';
import 'dart:typed_data';
import '../../../core/app_theme/app_text_styles.dart';
import '../../../core/app_theme/ink_palette.dart';
import '../../../core/app_theme/theme_utils.dart';
import '../../../core/widgets/app_page_header.dart';
import '../../../utils/app_logger.dart';
import '../../../signup/specialty_selection_widget.dart';
import '../profile_page.dart';
import 'package:intl/intl.dart';

/// Name, photo and personal details, with an explicit diff before anything is
/// written.
class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Controllers
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _middleNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();

  // Current values for comparison
  String _originalDisplayName = '';
  String _originalFirstName = '';
  String _originalMiddleName = '';
  String _originalLastName = '';
  String _originalGender = '';
  DateTime? _originalBirthdate;
  String _originalPhotoURL = '';
  List<String> _originalSpecialties = [];

  // Form state
  String _selectedGender = '';
  DateTime? _selectedBirthdate;
  bool _isLoading = false;
  bool _hasLoadedData = false;
  List<String> _selectedSpecialties = [];

  // Photo state
  File? _selectedImageFile;
  Uint8List? _selectedImageBytes; // For web
  String? _currentPhotoURL;
  bool _isUploadingPhoto = false;
  bool _hasNewPhoto = false; // Track if user has selected/captured a new photo

  @override
  void initState() {
    super.initState();
    _loadUserData();

    // Add listeners to text controllers to detect changes
    _displayNameController.addListener(_onFieldChanged);
    _firstNameController.addListener(_onFieldChanged);
    _middleNameController.addListener(_onFieldChanged);
    _lastNameController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    setState(() {
      // This will trigger a rebuild to update the button state and bottom bar
    });
  }

  @override
  void dispose() {
    // Remove listeners
    _displayNameController.removeListener(_onFieldChanged);
    _firstNameController.removeListener(_onFieldChanged);
    _middleNameController.removeListener(_onFieldChanged);
    _lastNameController.removeListener(_onFieldChanged);

    // Dispose controllers
    _displayNameController.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('User')
            .doc(user.uid)
            .get();

        if (userDoc.exists && mounted) {
          final userData = userDoc.data()!;

          // Load current values
          _originalDisplayName = userData['displayName'] ?? '';
          _displayNameController.text = _originalDisplayName;

          // Load individual name fields first (preferred method)
          // Check if we have individual name fields (even if some are null/empty)
          if (userData.containsKey('firstName') ||
              userData.containsKey('middleName') ||
              userData.containsKey('lastName')) {
            // Use individual name fields if they exist
            _originalFirstName = userData['firstName'] ?? '';
            _originalMiddleName = userData['middleName'] ?? '';
            _originalLastName = userData['lastName'] ?? '';
          } else {
            // Fall back to parsing fullName for backward compatibility
            final fullName = userData['fullName'] ?? '';
            final nameParts = fullName
                .split(' ')
                .where((part) => part.isNotEmpty)
                .toList();

            _originalFirstName = '';
            _originalMiddleName = '';
            _originalLastName = '';

            if (nameParts.isNotEmpty) {
              _originalFirstName = nameParts[0];
            }

            if (nameParts.length > 2) {
              // If more than 2 parts, middle name is everything except first and last
              _originalMiddleName = nameParts
                  .sublist(1, nameParts.length - 1)
                  .join(' ');
              _originalLastName = nameParts.last;
            } else if (nameParts.length == 2) {
              // Only first and last name
              _originalLastName = nameParts[1];
            }
          }

          // Set the controller values
          _firstNameController.text = _originalFirstName;
          _middleNameController.text = _originalMiddleName;
          _lastNameController.text = _originalLastName;

          _originalGender = userData['gender'] ?? '';
          // Normalize to lowercase to match dropdown items
          _selectedGender = _originalGender.toLowerCase();

          // Handle photo URL
          _originalPhotoURL = userData['photoURL'] ?? '';
          _currentPhotoURL = _originalPhotoURL;

          // Handle birthdate
          if (userData['birthdate'] != null) {
            final timestamp = userData['birthdate'] as Timestamp;
            _originalBirthdate = timestamp.toDate();
            _selectedBirthdate = _originalBirthdate;
          }

          // Handle specialties
          if (userData['specialties'] != null) {
            _originalSpecialties = List<String>.from(userData['specialties']);
            _selectedSpecialties = List<String>.from(_originalSpecialties);
          }

          _hasLoadedData = true;
        }
      }
    } catch (e) {
      AppLogger.d('Error loading user data: $e');
      if (mounted) {
        _showSnack('Failed to load profile data', _danger);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _buildFullName() {
    final firstName = _firstNameController.text.trim();
    final middleName = _middleNameController.text.trim();
    final lastName = _lastNameController.text.trim();

    String fullName = firstName;

    if (middleName.isNotEmpty) {
      // Add middle initial(s)
      final middleInitials = middleName
          .split(' ')
          .map((name) => name.isNotEmpty ? '${name[0]}.' : '')
          .where((initial) => initial.isNotEmpty)
          .join(' ');

      if (middleInitials.isNotEmpty) {
        fullName += ' $middleInitials';
      }
    }

    if (lastName.isNotEmpty) {
      fullName += ' $lastName';
    }

    return fullName;
  }

  bool _hasChanges() {
    // If data hasn't been loaded yet, check if user has entered any data
    if (!_hasLoadedData) {
      final currentDisplayName = _displayNameController.text.trim();
      final currentFirstName = _firstNameController.text.trim();
      final currentMiddleName = _middleNameController.text.trim();
      final currentLastName = _lastNameController.text.trim();

      // Return true if user has entered any data
      return currentDisplayName.isNotEmpty ||
          currentFirstName.isNotEmpty ||
          currentMiddleName.isNotEmpty ||
          currentLastName.isNotEmpty ||
          _selectedGender.isNotEmpty ||
          _selectedBirthdate != null ||
          _selectedImageFile != null ||
          _selectedImageBytes != null ||
          _hasNewPhoto ||
          _selectedSpecialties.isNotEmpty;
    }

    final currentDisplayName = _displayNameController.text.trim();
    final currentFirstName = _firstNameController.text.trim();
    final currentMiddleName = _middleNameController.text.trim();
    final currentLastName = _lastNameController.text.trim();

    // Normalize gender for comparison (handle empty strings)
    final originalGenderNormalized = _originalGender.toLowerCase();
    final selectedGenderNormalized = _selectedGender.toLowerCase();

    // Check if specialties have changed
    final specialtiesChanged = !_areListsEqual(
      _selectedSpecialties,
      _originalSpecialties,
    );

    return currentDisplayName != _originalDisplayName ||
        currentFirstName != _originalFirstName ||
        currentMiddleName != _originalMiddleName ||
        currentLastName != _originalLastName ||
        selectedGenderNormalized != originalGenderNormalized ||
        _selectedBirthdate != _originalBirthdate ||
        _selectedImageFile != null ||
        _selectedImageBytes != null ||
        _hasNewPhoto ||
        specialtiesChanged;
  }

  bool _areListsEqual(List<String> list1, List<String> list2) {
    if (list1.length != list2.length) return false;
    final sortedList1 = List<String>.from(list1)..sort();
    final sortedList2 = List<String>.from(list2)..sort();
    for (int i = 0; i < sortedList1.length; i++) {
      if (sortedList1[i] != sortedList2[i]) return false;
    }
    return true;
  }

  // ── Palette ──────────────────────────────────────────────────────────────

  InkPalette get ink => InkPalette.of(context);

  /// Destructive red. [InkPalette] reserves amber for urgency, so danger needs
  /// its own tone that still reads in both themes.
  Color get _danger =>
      ink.isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);

  Color get _muted => ink.text.withValues(alpha: 0.6);

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
    final dirty = _hasChanges();

    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && _hasChanges()) {
          await _showDiscardChangesDialog();
        }
      },
      child: Scaffold(
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
                    title: 'Edit profile',
                    subtitle: dirty && _hasLoadedData
                        ? 'Unsaved changes'
                        : 'Your name, photo and details',
                    subtitleColor: dirty && _hasLoadedData ? ink.amber : null,
                    onBack: _handleBack,
                  ),
                  Expanded(
                    child: _isLoading && !_hasLoadedData
                        ? Center(
                            child: CircularProgressIndicator(
                              color: ink.emerald,
                            ),
                          )
                        : _buildForm(),
                  ),
                  // One bar on every platform. This used to be a web-only
                  // `bottomNavigationBar` plus a second, near-identical pair of
                  // buttons inlined at the end of the form for mobile.
                  if (dirty && _hasLoadedData) _buildActionBar(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleBack() async {
    if (_hasChanges()) {
      await _showDiscardChangesDialog();
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  // ── Form ─────────────────────────────────────────────────────────────────

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: _listPadding,
        children: [
          _buildPhotoCard(),

          const SizedBox(height: 22),
          _buildSectionHeader('Basic information'),
          const SizedBox(height: 10),
          _buildTextField(
            controller: _displayNameController,
            label: 'Display name',
            icon: Icons.badge_outlined,
            validator: (value) => (value == null || value.trim().isEmpty)
                ? 'Display name is required'
                : null,
          ),
          const SizedBox(height: 14),
          _buildTextField(
            controller: _firstNameController,
            label: 'First name',
            icon: Icons.person_outline,
            validator: (value) => (value == null || value.trim().isEmpty)
                ? 'First name is required'
                : null,
          ),
          const SizedBox(height: 14),
          _buildTextField(
            controller: _middleNameController,
            label: 'Middle name (optional)',
            icon: Icons.person_outline,
          ),
          const SizedBox(height: 14),
          _buildTextField(
            controller: _lastNameController,
            label: 'Last name',
            icon: Icons.person_outline,
            validator: (value) => (value == null || value.trim().isEmpty)
                ? 'Last name is required'
                : null,
          ),

          const SizedBox(height: 22),
          _buildSectionHeader('Personal details'),
          const SizedBox(height: 10),
          _buildGenderDropdown(),
          const SizedBox(height: 14),
          _buildBirthdateField(),

          const SizedBox(height: 22),
          _buildSectionHeader('Professional'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ink.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: ink.border),
            ),
            child: SpecialtySelectionWidget(
              selectedSpecialties: _selectedSpecialties,
              onSelectionChanged: (specialties) {
                setState(() {
                  _selectedSpecialties = specialties;
                });
              },
            ),
          ),
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

  // ── Photo ────────────────────────────────────────────────────────────────

  Widget _buildPhotoCard() {
    final hasNewSelection =
        _selectedImageFile != null || _selectedImageBytes != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink.border),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _isUploadingPhoto ? null : _showPhotoSelectionSheet,
            child: SizedBox(
              width: 76,
              height: 76,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ink.emerald.withValues(
                        alpha: ink.isDark ? 0.16 : 0.11,
                      ),
                      border: Border.all(
                        color: ink.emerald.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                    ),
                    child: _buildPhotoContent(),
                  ),
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: ink.emerald,
                        shape: BoxShape.circle,
                        border: Border.all(color: ink.surface, width: 2),
                      ),
                      child: Icon(
                        Icons.photo_camera_outlined,
                        color: ink.onEmerald,
                        size: 14,
                      ),
                    ),
                  ),
                  if (_isUploadingPhoto)
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.55),
                      ),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Profile photo',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: ink.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  hasNewSelection
                      ? 'New photo ready to save'
                      : 'Tap the picture to change it',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: hasNewSelection
                        ? ink.emerald
                        : ink.text.withValues(alpha: 0.5),
                    fontWeight: hasNewSelection
                        ? FontWeight.w600
                        : FontWeight.w400,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 34,
                  child: OutlinedButton.icon(
                    onPressed: _isUploadingPhoto
                        ? null
                        : _showPhotoSelectionSheet,
                    icon: const Icon(Icons.image_outlined, size: 15),
                    label: Text(
                      'Change',
                      style: AppTextStyles.buttonMedium.copyWith(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ink.text,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      side: BorderSide(color: ink.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoContent() {
    if (_selectedImageBytes != null) {
      return Image.memory(_selectedImageBytes!, fit: BoxFit.cover);
    }

    if (_selectedImageFile != null) {
      return Image.file(_selectedImageFile!, fit: BoxFit.cover);
    }

    if (_currentPhotoURL != null && _currentPhotoURL!.isNotEmpty) {
      return Image.network(
        _currentPhotoURL!,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: ink.emerald,
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                    : null,
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => _buildDefaultAvatar(),
      );
    }

    return _buildDefaultAvatar();
  }

  Widget _buildDefaultAvatar() =>
      Icon(Icons.person, size: 38, color: ink.emerald);

  /// "Camera, gallery, or remove?", in the marketplace sheet shape.
  ///
  /// Was an `AlertDialog` of bare `ListTile`s on a hardcoded light surface.
  Future<void> _showPhotoSelectionSheet() async {
    final hasPhoto = _currentPhotoURL != null && _currentPhotoURL!.isNotEmpty;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: ink.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: ink.border),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 14),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: ink.text.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Camera only exists off the web.
              if (!kIsWeb)
                _buildSheetRow(
                  icon: Icons.photo_camera_outlined,
                  tone: ink.emerald,
                  label: 'Take photo',
                  detail: 'Use the camera',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _takePhoto();
                  },
                ),
              _buildSheetRow(
                icon: Icons.photo_library_outlined,
                tone: ink.emerald,
                label: kIsWeb ? 'Upload photo' : 'Choose from gallery',
                detail: 'Pick one you already have',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickImageFromGallery();
                },
              ),
              if (hasPhoto)
                _buildSheetRow(
                  icon: Icons.delete_outline,
                  tone: _danger,
                  label: 'Remove photo',
                  detail: 'Go back to the default avatar',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _removePhoto();
                  },
                ),
              const SizedBox(height: 14),
            ],
          ),
        ),
      ),
    );
  }

  /// One option in a sheet, in the icon-tile row shape the menus use.
  Widget _buildSheetRow({
    required IconData icon,
    required Color tone,
    required String label,
    required String detail,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppLayout.gutter,
            vertical: 12,
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: ink.isDark ? 0.16 : 0.11),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: tone, size: 19),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: tone,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: ink.text.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Personal detail fields ───────────────────────────────────────────────

  Widget _buildGenderDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedGender.isEmpty ? null : _selectedGender,
      isExpanded: true,
      dropdownColor: ink.surface,
      borderRadius: BorderRadius.circular(14),
      icon: Icon(
        Icons.keyboard_arrow_down,
        color: ink.text.withValues(alpha: 0.4),
      ),
      hint: Text(
        'Select gender',
        style: AppTextStyles.bodyMedium.copyWith(
          color: ink.text.withValues(alpha: 0.4),
          fontSize: 14,
        ),
      ),
      items: [
        for (final entry in const {
          'male': 'Male',
          'female': 'Female',
          'rather not say': 'Rather not say',
        }.entries)
          DropdownMenuItem(
            value: entry.key,
            child: Text(
              entry.value,
              style: AppTextStyles.bodyMedium.copyWith(
                color: ink.text,
                fontSize: 14,
              ),
            ),
          ),
      ],
      onChanged: (value) => setState(() => _selectedGender = value ?? ''),
      validator: (value) => (value == null || value.isEmpty)
          ? 'Please select your gender'
          : null,
      decoration: _fieldDecoration(label: 'Gender', icon: Icons.wc_outlined),
    );
  }

  Widget _buildBirthdateField() {
    final hasDate = _selectedBirthdate != null;

    return InkWell(
      onTap: _selectBirthdate,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: ink.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ink.border),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 19,
              color: ink.emerald,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Birthdate',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: hasDate
                          ? ink.text.withValues(alpha: 0.45)
                          : ink.text.withValues(alpha: 0.6),
                      fontSize: hasDate ? 11.5 : 14,
                    ),
                  ),
                  if (hasDate) ...[
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('MMMM d, yyyy').format(_selectedBirthdate!),
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: ink.text,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down,
              color: ink.text.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectBirthdate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedBirthdate ?? DateTime(2000),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      // The Material theme is still the light one, so a date picker left to
      // inherit it opens white over a dark page.
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme:
              (ink.isDark
                      ? const ColorScheme.dark()
                      : const ColorScheme.light())
                  .copyWith(
                    primary: ink.emerald,
                    onPrimary: ink.onEmerald,
                    surface: ink.surface,
                    onSurface: ink.text,
                  ),
          dialogTheme: DialogThemeData(backgroundColor: ink.surface),
        ),
        child: child!,
      ),
    );

    if (picked != null && picked != _selectedBirthdate) {
      setState(() {
        _selectedBirthdate = picked;
      });
    }
  }

  /// The one decoration every field on this form wears.
  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
  }) {
    OutlineInputBorder border(Color color, {double width = 1}) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecoration(
      labelText: label,
      errorMaxLines: 2,
      errorStyle: AppTextStyles.bodySmall.copyWith(
        color: _danger,
        fontSize: 11.5,
      ),
      prefixIcon: Icon(icon, size: 19, color: ink.emerald),
      border: border(ink.border),
      enabledBorder: border(ink.border),
      focusedBorder: border(ink.emerald, width: 1.5),
      errorBorder: border(_danger),
      focusedErrorBorder: border(_danger, width: 1.5),
      filled: true,
      fillColor: ink.surface,
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      enabled: !_isLoading,
      cursorColor: ink.emerald,
      style: AppTextStyles.bodyMedium.copyWith(color: ink.text, fontSize: 14),
      decoration: _fieldDecoration(label: label, icon: icon),
    );
  }

  // ── Action bar ───────────────────────────────────────────────────────────

  Widget _buildActionBar() {
    return Container(
      decoration: BoxDecoration(
        color: ink.surface,
        border: Border(top: BorderSide(color: ink.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppLayout.gutter,
            10,
            AppLayout.gutter,
            10,
          ),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : _showDiscardChangesDialog,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ink.amber,
                      side: BorderSide(color: ink.amber.withValues(alpha: 0.45)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      'Discard',
                      style: AppTextStyles.buttonMedium.copyWith(fontSize: 14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ink.emerald,
                      foregroundColor: ink.onEmerald,
                      disabledBackgroundColor: ink.emerald.withValues(
                        alpha: 0.5,
                      ),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isLoading
                        ? SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: ink.onEmerald,
                            ),
                          )
                        : Text(
                            'Save changes',
                            style: AppTextStyles.buttonMedium.copyWith(
                              fontSize: 14,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Photo capture ────────────────────────────────────────────────────────

  Future<void> _takePhoto() async {
    try {
      // Camera functionality only available on mobile platforms
      if (kIsWeb) {
        _showSnack(
          'Camera is not available on web. Please use the upload option.',
          _danger,
        );
        return;
      }

      final ImagePicker picker = ImagePicker();

      // For iOS, let ImagePicker handle the permission request automatically
      // For Android, we can still do permission checks if needed
      if (Theme.of(context).platform == TargetPlatform.android) {
        // Check current permission status for Android
        PermissionStatus cameraStatus = await Permission.camera.status;

        if (cameraStatus.isDenied) {
          // Request permission if not granted
          cameraStatus = await Permission.camera.request();
        }

        if (cameraStatus.isPermanentlyDenied) {
          // Show dialog to go to settings if permanently denied
          await _showPermissionDeniedDialog(
            icon: Icons.photo_camera_outlined,
            title: 'Camera permission needed',
            what: 'Camera',
          );
          return;
        }

        if (!cameraStatus.isGranted) {
          _showSnack(
            'Camera permission is required to take photos.',
            _danger,
          );
          return;
        }
      }

      final XFile? image = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image != null) {
        await _processSelectedImage(image);
      }
    } catch (e) {
      AppLogger.d('Error taking photo: $e');
      if (!mounted) return;

      // Check if it's a permission error and handle accordingly
      if (e.toString().contains('camera_access_denied') ||
          e.toString().contains('Permission denied') ||
          e.toString().contains('NotAllowedError')) {
        // For iOS, show dialog to go to settings after permission denial
        if (Theme.of(context).platform == TargetPlatform.iOS) {
          await _showPermissionDeniedDialog(
            icon: Icons.photo_camera_outlined,
            title: 'Camera permission needed',
            what: 'Camera',
          );
        } else {
          _showSnack('Camera permission is required to take photos.', _danger);
        }
      } else {
        _showSnack('Failed to take photo. Please try again.', _danger);
      }
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final ImagePicker picker = ImagePicker();

      // For iOS, let ImagePicker handle the permission request automatically
      // For Android, we can still do permission checks if needed
      if (!kIsWeb && Theme.of(context).platform == TargetPlatform.android) {
        // Check photo library permission for Android if needed
        PermissionStatus photosStatus = await Permission.photos.status;

        if (photosStatus.isDenied) {
          photosStatus = await Permission.photos.request();
        }

        if (photosStatus.isPermanentlyDenied) {
          await _showPermissionDeniedDialog(
            icon: Icons.photo_library_outlined,
            title: 'Photo access needed',
            what: 'Photos',
          );
          return;
        }

        if (!photosStatus.isGranted) {
          _showSnack(
            'Photo library access is required to select images.',
            _danger,
          );
          return;
        }
      }

      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image != null) {
        await _processSelectedImage(image);
      }
    } catch (e) {
      AppLogger.d('Error picking image: $e');
      if (!mounted) return;

      // Check if it's a permission error and handle accordingly
      if (e.toString().contains('photo_access_denied') ||
          e.toString().contains('Permission denied') ||
          e.toString().contains('NotAllowedError')) {
        // For iOS, show dialog to go to settings after permission denial
        if (Theme.of(context).platform == TargetPlatform.iOS) {
          await _showPermissionDeniedDialog(
            icon: Icons.photo_library_outlined,
            title: 'Photo access needed',
            what: 'Photos',
          );
        } else {
          _showSnack(
            'Photo library access is required to select images.',
            _danger,
          );
        }
      } else {
        _showSnack('Failed to select image. Please try again.', _danger);
      }
    }
  }

  Future<void> _processSelectedImage(XFile image) async {
    try {
      final int fileSize = await image.length();
      const int maxSizeBytes = 3 * 1024 * 1024; // 3MB

      if (fileSize > maxSizeBytes) {
        _showSnack('Image must be smaller than 3MB', _danger);
        return;
      }

      // Check file extension
      final String extension = image.name.toLowerCase().split('.').last;
      const List<String> allowedExtensions = [
        'jpg',
        'jpeg',
        'png',
        'gif',
        'bmp',
        'webp',
      ];

      if (!allowedExtensions.contains(extension)) {
        _showSnack('Please pick a JPG, PNG, GIF or WebP image', _danger);
        return;
      }

      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        if (!mounted) return;
        setState(() {
          _selectedImageFile = null;
          _selectedImageBytes = bytes;
          _hasNewPhoto = true;
        });
      } else {
        setState(() {
          _selectedImageFile = File(image.path);
          _selectedImageBytes = null;
          _hasNewPhoto = true;
        });
      }

      if (mounted) _showSnack('Photo selected', ink.emerald);
    } catch (e) {
      AppLogger.d('Error processing image: $e');
      if (mounted) _showSnack('Failed to process image', _danger);
    }
  }

  void _removePhoto() {
    setState(() {
      _selectedImageFile = null;
      _selectedImageBytes = null;
      _currentPhotoURL = null;
      _hasNewPhoto = true; // Removing is also a change
    });
    _showSnack('Photo removed', ink.emerald);
  }

  Future<String?> _uploadPhotoToFirebase() async {
    try {
      setState(() {
        _isUploadingPhoto = true;
      });

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

      final FirebaseStorage storage = FirebaseStorage.instance;

      // Determine file extension
      String extension = 'jpg'; // default
      if (_selectedImageFile != null) {
        extension = _selectedImageFile!.path.split('.').last.toLowerCase();
      }

      final String fileName = 'displayimage.$extension';
      final Reference ref = storage.ref().child(
        'UserImages/${user.uid}/$fileName',
      );

      UploadTask uploadTask;

      if (kIsWeb && _selectedImageBytes != null) {
        uploadTask = ref.putData(_selectedImageBytes!);
      } else if (_selectedImageFile != null) {
        uploadTask = ref.putFile(_selectedImageFile!);
      } else {
        return null;
      }

      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();

      return downloadUrl;
    } catch (e) {
      AppLogger.d('Error uploading photo: $e');
      if (mounted) _showSnack('Failed to upload photo', _danger);
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingPhoto = false;
        });
      }
    }
  }

  // ── Save ─────────────────────────────────────────────────────────────────

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_hasChanges()) {
      _showSnack('Nothing to save', ink.amber, onTone: ink.onAmber);
      return;
    }

    // Show confirmation dialog
    final shouldSave = await _showConfirmationDialog();
    if (!shouldSave || !mounted) return;

    setState(() {
      _isLoading = true;
    });

    // Captured before the awaits: on success this page is popped, so reaching
    // for its Navigator or messenger afterwards would be reaching through a
    // context that is on its way out.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final emerald = ink.emerald;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final updates = <String, dynamic>{};

      // Update display name
      final newDisplayName = _displayNameController.text.trim();
      if (newDisplayName != _originalDisplayName) {
        updates['displayName'] = newDisplayName;
      }

      // Update full name
      final newFullName = _buildFullName();
      final originalFullName = _buildOriginalFullName();
      if (newFullName != originalFullName) {
        updates['fullName'] = newFullName;
      }

      // Update individual name fields
      final newFirstName = _firstNameController.text.trim();
      final newMiddleName = _middleNameController.text.trim();
      final newLastName = _lastNameController.text.trim();

      // Check if any name field has changed
      bool nameFieldsChanged =
          newFirstName != _originalFirstName ||
          newMiddleName != _originalMiddleName ||
          newLastName != _originalLastName;

      // If any name field changed, update all name fields to ensure consistency
      if (nameFieldsChanged) {
        updates['firstName'] = newFirstName;
        updates['middleName'] = newMiddleName;
        updates['lastName'] = newLastName;
      }

      // Update gender
      final originalGenderNormalized = _originalGender.toLowerCase();
      final selectedGenderNormalized = _selectedGender.toLowerCase();
      if (selectedGenderNormalized != originalGenderNormalized) {
        updates['gender'] = _selectedGender;
      }

      // Update birthdate
      if (_selectedBirthdate != _originalBirthdate) {
        if (_selectedBirthdate != null) {
          // Set time to 12:00 AM UTC+8 (Philippine time)
          final birthdatePhilippines = DateTime(
            _selectedBirthdate!.year,
            _selectedBirthdate!.month,
            _selectedBirthdate!.day,
            0, // 12:00 AM
            0,
            0,
          ).add(const Duration(hours: 8)); // UTC+8

          updates['birthdate'] = Timestamp.fromDate(birthdatePhilippines);
        } else {
          updates['birthdate'] = null;
        }
      }

      // Upload photo if selected
      if (_selectedImageFile != null || _selectedImageBytes != null) {
        final newPhotoURL = await _uploadPhotoToFirebase();
        if (newPhotoURL != null) {
          updates['photoURL'] = newPhotoURL;
          _currentPhotoURL = newPhotoURL;
        }
      } else if (_currentPhotoURL == null && _originalPhotoURL.isNotEmpty) {
        // Photo was removed
        updates['photoURL'] = null;
      }

      // Update specialties
      if (!_areListsEqual(_selectedSpecialties, _originalSpecialties)) {
        updates['specialties'] = _selectedSpecialties;
      }

      if (updates.isNotEmpty) {
        updates['updatedAt'] = FieldValue.serverTimestamp();

        // If data wasn't loaded, it means the document might not exist or we're
        // creating new data. Use set with merge to handle both cases.
        if (!_hasLoadedData) {
          // For new profiles, add createdAt timestamp
          updates['createdAt'] = FieldValue.serverTimestamp();

          await FirebaseFirestore.instance
              .collection('User')
              .doc(user.uid)
              .set(updates, SetOptions(merge: true));
        } else {
          await FirebaseFirestore.instance
              .collection('User')
              .doc(user.uid)
              .update(updates);
        }

        // Update original values after successful save
        _updateOriginalValues();

        // Mark data as loaded after successful save
        _hasLoadedData = true;

        // The profile tab is kept alive by the app shell, so it will not
        // refetch on its own when this route pops. Drop its cache instead and
        // it re-reads the moment the buyer lands back on it.
        ProfilePage.invalidate();

        if (!mounted) return;
        navigator.pop();
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Profile updated'),
            backgroundColor: emerald,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      AppLogger.d('Error updating profile: $e');
      if (mounted) {
        _showSnack('Failed to update profile', _danger);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _buildOriginalFullName() {
    String fullName = _originalFirstName;

    if (_originalMiddleName.isNotEmpty) {
      final middleInitials = _originalMiddleName
          .split(' ')
          .map((name) => name.isNotEmpty ? '${name[0]}.' : '')
          .where((initial) => initial.isNotEmpty)
          .join(' ');

      if (middleInitials.isNotEmpty) {
        fullName += ' $middleInitials';
      }
    }

    if (_originalLastName.isNotEmpty) {
      fullName += ' $_originalLastName';
    }

    return fullName;
  }

  void _updateOriginalValues() {
    _originalDisplayName = _displayNameController.text.trim();
    _originalFirstName = _firstNameController.text.trim();
    _originalMiddleName = _middleNameController.text.trim();
    _originalLastName = _lastNameController.text.trim();
    _originalGender = _selectedGender;
    _originalBirthdate = _selectedBirthdate;
    _originalPhotoURL = _currentPhotoURL ?? '';
    _originalSpecialties = List<String>.from(_selectedSpecialties);

    // Clear selected image after successful save
    _selectedImageFile = null;
    _selectedImageBytes = null;
    _hasNewPhoto = false; // Reset photo change flag
  }

  // ── Dialogs ──────────────────────────────────────────────────────────────

  Future<bool> _showConfirmationDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: ink.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(Icons.save_outlined, color: ink.emerald),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Save changes?',
                    style: TextStyle(color: ink.text),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _buildChangesList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text('Keep editing', style: TextStyle(color: _muted)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ink.emerald,
                  foregroundColor: ink.onEmerald,
                  elevation: 0,
                ),
                child: const Text('Save'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _showDiscardChangesDialog() async {
    final navigator = Navigator.of(context);

    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: ink.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_outlined, color: ink.amber),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Discard changes?',
                style: TextStyle(color: ink.text),
              ),
            ),
          ],
        ),
        content: Text(
          'You have unsaved changes. Leaving now throws them away.',
          style: AppTextStyles.bodyMedium.copyWith(color: _muted, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Keep editing', style: TextStyle(color: _muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: ink.amber,
              foregroundColor: ink.onAmber,
              elevation: 0,
            ),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    if (shouldDiscard == true && mounted) {
      navigator.pop();
    }
  }

  /// One dialog for both permissions — they only differed in a noun.
  Future<void> _showPermissionDeniedDialog({
    required IconData icon,
    required String title,
    required String what,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: ink.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(icon, color: ink.amber),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: TextStyle(color: ink.text))),
          ],
        ),
        content: Text(
          'Access was permanently denied, so we can’t ask again from here. '
          'Open Settings, find DentPal, and turn $what on.',
          style: AppTextStyles.bodyMedium.copyWith(color: _muted, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Not now', style: TextStyle(color: _muted)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: ink.emerald,
              foregroundColor: ink.onEmerald,
              elevation: 0,
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  // ── The diff ─────────────────────────────────────────────────────────────

  List<Widget> _buildChangesList() {
    final changes = <Widget>[];

    // Display Name changes
    final currentDisplayName = _displayNameController.text.trim();
    if (currentDisplayName != _originalDisplayName) {
      changes.add(
        _buildChangeItem(
          'Display name',
          _originalDisplayName.isEmpty ? '(empty)' : _originalDisplayName,
          currentDisplayName.isEmpty ? '(empty)' : currentDisplayName,
        ),
      );
    }

    // Full Name changes
    final currentFullName = _buildFullName();
    final originalFullName = _buildOriginalFullName();
    if (currentFullName != originalFullName) {
      changes.add(
        _buildChangeItem(
          'Full name',
          originalFullName.isEmpty ? '(empty)' : originalFullName,
          currentFullName.isEmpty ? '(empty)' : currentFullName,
        ),
      );
    }

    // Gender changes
    final originalGenderNormalized = _originalGender.toLowerCase();
    final selectedGenderNormalized = _selectedGender.toLowerCase();
    if (selectedGenderNormalized != originalGenderNormalized) {
      changes.add(
        _buildChangeItem(
          'Gender',
          _originalGender.isEmpty ? '(not set)' : _originalGender,
          _selectedGender.isEmpty ? '(not set)' : _selectedGender,
        ),
      );
    }

    // Birthdate changes
    if (_selectedBirthdate != _originalBirthdate) {
      changes.add(
        _buildChangeItem(
          'Birthdate',
          _originalBirthdate != null
              ? DateFormat('MMMM d, yyyy').format(_originalBirthdate!)
              : '(not set)',
          _selectedBirthdate != null
              ? DateFormat('MMMM d, yyyy').format(_selectedBirthdate!)
              : '(not set)',
        ),
      );
    }

    // Photo changes
    if (_selectedImageFile != null ||
        _selectedImageBytes != null ||
        _hasNewPhoto) {
      changes.add(
        _buildChangeItem(
          'Profile photo',
          _originalPhotoURL.isEmpty ? '(no photo)' : 'Current photo',
          _currentPhotoURL == null && _originalPhotoURL.isNotEmpty
              ? '(removed)'
              : 'New photo',
        ),
      );
    }

    // Specialty changes
    if (!_areListsEqual(_selectedSpecialties, _originalSpecialties)) {
      changes.add(
        _buildChangeItem(
          'Specialties',
          _originalSpecialties.isEmpty
              ? '(not set)'
              : '${_originalSpecialties.length} selected',
          _selectedSpecialties.isEmpty
              ? '(not set)'
              : '${_selectedSpecialties.length} selected',
        ),
      );
    }

    if (changes.isEmpty) {
      changes.add(
        Text(
          'No changes detected',
          style: AppTextStyles.bodyMedium.copyWith(
            color: _muted,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    return changes;
  }

  /// One "was → is" line.
  ///
  /// The label used to be hardcoded `Colors.black` and the arrow `Colors.grey`,
  /// both of which vanish on a dark surface.
  Widget _buildChangeItem(String label, String before, String after) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: ink.text.withValues(alpha: 0.5),
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 3),
          RichText(
            text: TextSpan(
              style: AppTextStyles.bodyMedium.copyWith(
                color: ink.text,
                fontSize: 13.5,
              ),
              children: [
                TextSpan(
                  text: before,
                  style: TextStyle(
                    color: ink.text.withValues(alpha: 0.45),
                    decoration: TextDecoration.lineThrough,
                    decorationColor: ink.text.withValues(alpha: 0.45),
                  ),
                ),
                TextSpan(
                  text: '  →  ',
                  style: TextStyle(color: ink.text.withValues(alpha: 0.3)),
                ),
                TextSpan(
                  text: after,
                  style: TextStyle(
                    color: ink.emerald,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message, Color tone, {Color? onTone}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: onTone ?? Colors.white),
        ),
        backgroundColor: tone,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
