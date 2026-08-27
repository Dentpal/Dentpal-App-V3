import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'signup_controller.dart';
import 'package:dentpal/core/app_theme/app_text_styles.dart';
import 'package:dentpal/core/app_theme/ink_palette.dart';
import 'package:dentpal/core/widgets/auth_chrome.dart';

/// Step 2: who you are, and where.
///
/// The name fields usually arrive pre-filled from the ID scanned in step 1;
/// everything else is asked for here.
class SignupNewStep2PersonalDetails extends StatefulWidget {
  final SignupController controller;
  final VoidCallback onNext;
  final VoidCallback onBack;

  const SignupNewStep2PersonalDetails({
    super.key,
    required this.controller,
    required this.onNext,
    required this.onBack,
  });

  @override
  State<SignupNewStep2PersonalDetails> createState() =>
      _SignupNewStep2PersonalDetailsState();
}

class _SignupNewStep2PersonalDetailsState
    extends State<SignupNewStep2PersonalDetails> {
  // Quick access to controller
  SignupController get _controller => widget.controller;

  InkPalette get _ink => InkPalette.of(context);

  // FocusNodes for field traversal
  final FocusNode _firstNameFocus = FocusNode();
  final FocusNode _lastNameFocus = FocusNode();
  final FocusNode _contactNumberFocus = FocusNode();

  // Track if phone number check is in progress
  bool _isCheckingPhoneNumber = false;
  String? _phoneNumberError;

  static const List<String> _locations = ['NCR', 'Luzon', 'Visayas', 'Mindanao'];

  @override
  void dispose() {
    _firstNameFocus.dispose();
    _lastNameFocus.dispose();
    _contactNumberFocus.dispose();
    super.dispose();
  }

  // Check if phone number already exists in UserLookup collection
  Future<bool> _checkPhoneNumberExists(String phoneNumber) async {
    if (phoneNumber.isEmpty ||
        !phoneNumber.startsWith('09') ||
        phoneNumber.length != 11) {
      return false;
    }

    try {
      // Format phone number to international format for checking
      final formattedNumber = _controller.formatPhoneNumberForFirebase(
        phoneNumber,
      );

      // Query UserLookup collection for existing phone number
      final querySnapshot = await FirebaseFirestore.instance
          .collection('UserLookup')
          .where('contactNumber', isEqualTo: formattedNumber)
          .limit(1)
          .get();

      return querySnapshot.docs.isNotEmpty;
    } catch (e) {
      // If there's an error checking, return false to allow user to proceed
      // The error will be caught during actual registration
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Form(
        key: _controller.formKeyStep1,
        child: ListView(
          padding: AuthMetrics.bodyPadding,
          children: [
            // Nothing is filled in from the ID scan any more, so there is no
            // "we read this off your card, check it" banner to show: the name
            // below is whatever the dentist typed.
            const AuthSectionLabel('Your name'),
            const SizedBox(height: 10),
            AuthTextField(
              controller: _controller.firstNameController,
              focusNode: _firstNameFocus,
              label: 'First name',
              prefixIcon: Icons.person_outline,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              enabled: !_isCheckingPhoneNumber,
              onFieldSubmitted: (_) =>
                  FocusScope.of(context).requestFocus(_lastNameFocus),
              validator: (value) => (value == null || value.isEmpty)
                  ? 'Please enter your first name'
                  : null,
            ),
            const SizedBox(height: 14),
            AuthTextField(
              controller: _controller.lastNameController,
              focusNode: _lastNameFocus,
              label: 'Last name',
              prefixIcon: Icons.person_outline,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              enabled: !_isCheckingPhoneNumber,
              onFieldSubmitted: (_) =>
                  FocusScope.of(context).requestFocus(_contactNumberFocus),
              validator: (value) => (value == null || value.isEmpty)
                  ? 'Please enter your last name'
                  : null,
            ),

            const SizedBox(height: 24),
            const AuthSectionLabel('How we reach you'),
            const SizedBox(height: 10),
            AuthTextField(
              controller: _controller.contactNumberController,
              focusNode: _contactNumberFocus,
              label: 'Mobile number',
              hint: '09XXXXXXXXX',
              prefixIcon: Icons.phone_iphone_outlined,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              enabled: !_isCheckingPhoneNumber,
              maxLength: 11,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
              helperText: 'Sellers use this to reach you about your orders.',
              onChanged: (value) {
                setState(() {
                  _controller.isVerifyButtonEnabled =
                      value.startsWith('09') && value.length == 11;
                  _phoneNumberError = null; // Clear error when user types
                });
              },
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your contact number';
                }
                if (!value.startsWith('09') || value.length != 11) {
                  return 'Contact number must start with 09';
                }
                // Show cached error if phone number already exists
                if (_phoneNumberError != null) {
                  return _phoneNumberError;
                }
                return null;
              },
            ),

            const SizedBox(height: 24),
            _optionalLabel('About you'),
            const SizedBox(height: 10),
            _genderPicker(),
            const SizedBox(height: 14),
            _birthdateField(),

            const SizedBox(height: 24),
            const AuthSectionLabel('Where you practise'),
            const SizedBox(height: 10),
            _locationField(),

            const SizedBox(height: 28),
            AuthPrimaryButton(
              label: 'Continue',
              busy: _isCheckingPhoneNumber,
              onPressed: _validateAndProceed,
            ),
            const SizedBox(height: 6),
            Center(
              child: AuthQuietButton(
                label: 'Back',
                onPressed: _isCheckingPhoneNumber ? null : widget.onBack,
              ),
            ),

            SizedBox(
              height: MediaQuery.of(context).padding.bottom > 0 ? 24 : 8,
            ),
          ],
        ),
      ),
    );
  }

  /// A section heading whose fields can all be skipped.
  Widget _optionalLabel(String title) {
    final ink = _ink;

    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            title,
            style: AppTextStyles.titleMedium.copyWith(
              color: ink.text,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'optional',
            style: AppTextStyles.bodySmall.copyWith(
              color: ink.faint,
              fontWeight: FontWeight.w600,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  /// Three choices, so they fit on one row of chips rather than three rows of
  /// radio tiles.
  Widget _genderPicker() {
    const options = ['Male', 'Female', 'Not Specified'];
    const labels = ['Male', 'Female', 'Rather not say'];

    return Row(
      children: List.generate(options.length, (index) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index == options.length - 1 ? 0 : 8),
            child: _choiceChip(
              label: labels[index],
              selected: _controller.selectedGender == options[index],
              onTap: () => setState(() {
                // Tapping the current choice clears it — the field is optional,
                // and a radio group with no way back is a trap.
                _controller.selectedGender =
                    _controller.selectedGender == options[index]
                    ? null
                    : options[index];
              }),
            ),
          ),
        );
      }),
    );
  }

  Widget _choiceChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final ink = _ink;

    return Material(
      color: selected
          ? ink.emerald.withValues(alpha: ink.isDark ? 0.18 : 0.1)
          : ink.surface,
      borderRadius: BorderRadius.circular(AuthMetrics.fieldRadius),
      child: InkWell(
        onTap: _isCheckingPhoneNumber ? null : onTap,
        borderRadius: BorderRadius.circular(AuthMetrics.fieldRadius),
        child: Container(
          height: 46,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AuthMetrics.fieldRadius),
            border: Border.all(
              color: selected ? ink.emerald : ink.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall.copyWith(
              color: selected ? ink.emerald : ink.muted,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 12.5,
            ),
          ),
        ),
      ),
    );
  }

  /// A tap target wearing the same outline as the text fields, so the row of
  /// inputs stays one column of identical shapes.
  Widget _birthdateField() {
    final ink = _ink;
    final picked = _controller.selectedBirthdate;

    return InkWell(
      onTap: _isCheckingPhoneNumber ? null : _pickBirthdate,
      borderRadius: BorderRadius.circular(AuthMetrics.fieldRadius),
      child: InputDecorator(
        decoration: authInputDecoration(
          context,
          label: 'Birthdate',
          prefixIcon: Icon(
            Icons.cake_outlined,
            size: 19,
            color: ink.emerald,
          ),
          suffixIcon: Icon(
            Icons.calendar_today_outlined,
            size: 17,
            color: ink.faint,
          ),
        ).copyWith(
          // Only float the label once there is a date under it; an empty field
          // should read as a prompt, not as a labelled blank.
          floatingLabelBehavior: picked == null
              ? FloatingLabelBehavior.never
              : FloatingLabelBehavior.always,
          errorText: _controller.step1BirthdateError,
        ),
        child: Text(
          picked == null
              ? 'Select your birthdate'
              : DateFormat('MMMM d, yyyy').format(picked),
          style: AppTextStyles.bodyMedium.copyWith(
            color: picked == null ? ink.faint : ink.text,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Future<void> _pickBirthdate() async {
    final ink = _ink;
    final now = DateTime.now();
    final initialDate =
        _controller.selectedBirthdate ??
        DateTime(now.year - 18, now.month, now.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900, 1, 1),
      lastDate: now,
      initialEntryMode: DatePickerEntryMode.calendar,
      helpText: 'Select your birthdate',
      builder: (context, child) {
        // The picker is a Material surface, so it needs the appearance handed
        // to it explicitly — the app's own ThemeData is still light-only.
        return Theme(
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
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _controller.selectedBirthdate = picked;
        _controller.step1BirthdateError = null;
      });
    }
  }

  Widget _locationField() {
    final ink = _ink;

    return DropdownButtonFormField<String>(
      initialValue: _controller.selectedLocation,
      isExpanded: true,
      decoration: authInputDecoration(
        context,
        label: 'Location',
        prefixIcon: Icon(
          Icons.location_on_outlined,
          size: 19,
          color: ink.emerald,
        ),
      ).copyWith(errorText: _controller.step1LocationError),
      style: AppTextStyles.bodyMedium.copyWith(color: ink.text, fontSize: 14),
      dropdownColor: ink.surface,
      borderRadius: BorderRadius.circular(AuthMetrics.fieldRadius),
      icon: Icon(Icons.expand_more, color: ink.faint),
      items: _locations
          .map(
            (location) =>
                DropdownMenuItem<String>(value: location, child: Text(location)),
          )
          .toList(),
      onChanged: _isCheckingPhoneNumber
          ? null
          : (String? newValue) {
              setState(() {
                _controller.selectedLocation = newValue;
                _controller.step1LocationError = null;
              });
            },
      validator: (value) => (value == null || value.isEmpty)
          ? 'Please select your location'
          : null,
    );
  }

  void _validateAndProceed() async {
    final valid = _controller.formKeyStep1.currentState?.validate() ?? false;

    setState(() {
      _controller.step1GenderError = null;
      _controller.step1BirthdateError = null;
      _controller.step1LocationError = null;
    });

    if (!valid) return;

    // Check if phone number already exists in UserLookup
    setState(() {
      _isCheckingPhoneNumber = true;
      _phoneNumberError = null;
    });

    final phoneExists = await _checkPhoneNumberExists(_controller.contactNumber);

    if (!mounted) return;

    setState(() {
      _isCheckingPhoneNumber = false;
    });

    if (phoneExists) {
      setState(() {
        _phoneNumberError = 'This phone number is already registered';
      });
      // Trigger validation to show the error
      _controller.formKeyStep1.currentState?.validate();
      return;
    }

    // All validations passed
    widget.onNext();
  }
}
