import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'signup_controller.dart';
import 'id_ocr_service.dart';
import 'id_verification_camera.dart';
import 'specialty_selection_widget.dart';
import 'package:dentpal/core/app_theme/app_text_styles.dart';
import 'package:dentpal/core/app_theme/ink_palette.dart';
import 'package:dentpal/core/widgets/auth_chrome.dart';

/// Step 1: prove the account belongs to a licensed dentist, then say what they
/// practise.
///
/// The page has four faces — nothing scanned yet, a scan that worked, a scan
/// that did not, and the licence number typed in by hand — and only one of them
/// is ever on screen.
class SignupNewStep1IdVerification extends StatefulWidget {
  final SignupController controller;
  final VoidCallback onNext;

  const SignupNewStep1IdVerification({
    super.key,
    required this.controller,
    required this.onNext,
  });

  @override
  State<SignupNewStep1IdVerification> createState() =>
      _SignupNewStep1IdVerificationState();
}

class _SignupNewStep1IdVerificationState
    extends State<SignupNewStep1IdVerification> {
  SignupController get _controller => widget.controller;

  InkPalette get _ink => InkPalette.of(context);

  /// Whether the dentist has asked to type their licence number in instead of
  /// scanning it. Swaps the scanner card for a form; the rest of the step is
  /// unchanged.
  bool _manualEntry = false;
  bool _checkingNumber = false;
  String? _manualNumberError;

  final GlobalKey<FormState> _manualFormKey = GlobalKey<FormState>();
  final TextEditingController _manualNumberController =
      TextEditingController();

  @override
  void dispose() {
    _manualNumberController.dispose();
    super.dispose();
  }

  /// Both halves of the step have to be done before it will let you past: a
  /// verified ID, and at least one specialty.
  bool get _canProceed =>
      _controller.isIdVerified && _controller.selectedSpecialties.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: AuthMetrics.bodyPadding,
      children: [
        if (_controller.isIdVerified)
          _verifiedState()
        else if (_manualEntry)
          _manualEntryForm()
        else if (_controller.idVerificationError != null)
          _failedState()
        else
          _invitation(),

        if (_controller.isIdVerified) ...[
          const SizedBox(height: 24),
          // The picker draws its own heading and expects a card around it —
          // its opener sits on `surfaceHigh` so it reads as nested rather than
          // flush with the surface behind it.
          AuthCard(
            padding: const EdgeInsets.all(18),
            child: SpecialtySelectionWidget(
              selectedSpecialties: _controller.selectedSpecialties,
              onSelectionChanged: (specialties) {
                setState(() {
                  _controller.selectedSpecialties = specialties;
                });
              },
            ),
          ),
        ],

        const SizedBox(height: 28),
        AuthPrimaryButton(
          label: 'Continue',
          onPressed: _canProceed ? widget.onNext : null,
        ),
        if (_controller.isIdVerified &&
            _controller.selectedSpecialties.isEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Pick at least one specialty to continue.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(
              color: _ink.faint,
              fontSize: 12,
            ),
          ),
        ],

        const SizedBox(height: 4),
        AuthFooterPrompt(
          question: 'Already have an account?',
          actionLabel: 'Log in',
          onPressed: () => Navigator.of(context).pop(),
        ),

        SizedBox(height: MediaQuery.of(context).padding.bottom > 0 ? 24 : 8),
      ],
    );
  }

  // ── Nothing scanned yet ──────────────────────────────────────────────────

  Widget _invitation() {
    final ink = _ink;

    return AuthCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: ink.emerald.withValues(alpha: ink.isDark ? 0.16 : 0.1),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              Icons.document_scanner_outlined,
              color: ink.emerald,
              size: 25,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Scan your PRC ID',
            style: AppTextStyles.titleMedium.copyWith(
              color: ink.text,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'DentPal is only open to licensed dentists, so every account starts '
            'here. Hold your PRC ID steady in the frame — the camera detects, '
            'captures and checks it for you.',
            style: AppTextStyles.bodySmall.copyWith(
              color: ink.muted,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          AuthPrimaryButton(label: 'Open camera', onPressed: _captureImage),
          const SizedBox(height: 6),
          Center(
            child: AuthQuietButton(
              label: "I don't have my card with me",
              onPressed: _startManualEntry,
            ),
          ),
        ],
      ),
    );
  }

  // ── Typed in rather than scanned ─────────────────────────────────────────

  void _startManualEntry() {
    setState(() {
      _manualEntry = true;
      _manualNumberError = null;
      _controller.idVerificationError = null;
    });
  }

  Widget _manualEntryForm() {
    final ink = _ink;

    return Form(
      key: _manualFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthBanner(
            icon: Icons.fact_check_outlined,
            tone: ink.amber,
            title: 'We will check this by hand',
            message:
                'Typing your number in gets you into DentPal today, but nothing '
                'about your licence has been proven yet — so your account stays '
                'pending until our team matches it against the PRC register. '
                'Scanning the card clears it right away.',
          ),
          const SizedBox(height: 22),
          const AuthSectionLabel('PRC registration number'),
          const SizedBox(height: 10),
          AuthTextField(
            controller: _manualNumberController,
            label: 'Registration number',
            hint: 'e.g. 0086157',
            prefixIcon: Icons.badge_outlined,
            keyboardType: TextInputType.number,
            enabled: !_checkingNumber,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            helperText: 'The number printed under your name on the card.',
            onChanged: (_) {
              if (_manualNumberError != null) {
                setState(() => _manualNumberError = null);
              }
            },
            validator: (value) {
              final trimmed = value?.trim() ?? '';
              if (trimmed.isEmpty) {
                return 'Please enter your PRC registration number';
              }
              if (trimmed.length < 4) {
                return 'Please enter a valid registration number';
              }
              // Set by the duplicate check, which cannot run inside a validator.
              return _manualNumberError;
            },
          ),
          const SizedBox(height: 20),
          AuthPrimaryButton(
            label: 'Use this number',
            busy: _checkingNumber,
            onPressed: _submitManualNumber,
          ),
          const SizedBox(height: 6),
          Center(
            child: AuthQuietButton(
              label: 'Scan my card instead',
              icon: Icons.camera_alt_outlined,
              onPressed: _checkingNumber
                  ? null
                  : () {
                      setState(() => _manualEntry = false);
                      _captureImage();
                    },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitManualNumber() async {
    if (!(_manualFormKey.currentState?.validate() ?? false)) return;

    final number = _manualNumberController.text.trim();
    setState(() {
      _checkingNumber = true;
      _manualNumberError = null;
    });

    // The same duplicate check the scanner runs. Skipping it here would make
    // typing the number in a way around it.
    final taken = await IdOcrService.checkRegistrationNumberExists(number);

    if (!mounted) return;
    setState(() => _checkingNumber = false);

    if (taken) {
      setState(() {
        _manualNumberError =
            'This PRC number is already registered. Log in instead, or '
            'contact support.';
      });
      _manualFormKey.currentState?.validate();
      return;
    }

    setState(() {
      _controller.isIdVerified = true;
      _controller.idEnteredManually = true;
      _controller.idNumber = number;
      _controller.idNumberController.text = number;
      _controller.idVerificationError = null;
      _controller.isIdAlreadyRegistered = false;
      // No card was read, so there is no face crop and no name to pre-fill —
      // step 2 simply starts empty.
      _controller.idFaceImage = null;
      _manualEntry = false;
    });
  }

  // ── The scan worked ──────────────────────────────────────────────────────

  Widget _verifiedState() {
    final ink = _ink;
    final manual = _controller.idEnteredManually;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Amber, not emerald: a number that has only been typed in has not been
        // verified, and the step should not dress it up as if it had.
        AuthBanner(
          icon: manual
              ? Icons.pending_actions_outlined
              : Icons.verified_user_outlined,
          tone: manual ? ink.amber : ink.emerald,
          title: manual ? 'Pending review' : 'ID verified',
          message: manual
              ? 'We will check this number against the PRC register and get in '
                    'touch if anything does not match.'
              : 'Your licence checks out. Confirm the registration number we '
                    'read below.',
        ),
        const SizedBox(height: 22),
        const AuthSectionLabel('PRC registration number'),
        const SizedBox(height: 10),
        AuthTextField(
          controller: _controller.idNumberController,
          label: 'Registration number',
          prefixIcon: Icons.badge_outlined,
          keyboardType: TextInputType.number,
          helperText: 'Read from your ID — edit it if we got a digit wrong.',
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'PRC registration number is required';
            }
            if (value.trim().length < 4) {
              return 'Please enter a valid registration number';
            }
            return null;
          },
          onChanged: (value) {
            // Keep the controller's own copy in step with the edited field.
            _controller.idNumber = value.trim();
          },
        ),
        const SizedBox(height: 12),
        AuthSecondaryButton(
          label: manual ? 'Scan my card and clear this' : 'Scan a different ID',
          icon: Icons.camera_alt_outlined,
          onPressed: _captureImage,
        ),
      ],
    );
  }

  // ── The scan did not work ────────────────────────────────────────────────

  Widget _failedState() {
    final ink = _ink;
    final message = _controller.idVerificationError!;

    // The iOS camera stack fails face detection in poor light more often than
    // Android's, so that platform gets an extra line of advice.
    final showLightingTip =
        !kIsWeb && Platform.isIOS && message.contains('face');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthBanner(
          icon: _controller.isIdAlreadyRegistered
              ? Icons.person_search_outlined
              : Icons.error_outline,
          tone: ink.danger,
          title: _controller.isIdAlreadyRegistered
              ? 'This ID is already registered'
              : 'We could not verify that',
          message: showLightingTip
              ? '$message\n\nEnsure good lighting and hold the ID steady.'
              : message,
          action: _controller.isIdAlreadyRegistered
              ? AuthSecondaryButton(
                  label: 'Go to login',
                  icon: Icons.login,
                  tone: ink.danger,
                  onPressed: () => Navigator.of(context).pop(),
                )
              : null,
        ),
        const SizedBox(height: 16),
        AuthPrimaryButton(
          label: 'Try again',
          icon: Icons.camera_alt_outlined,
          onPressed: _captureImage,
        ),
        if (!_controller.isIdAlreadyRegistered) ...[
          const SizedBox(height: 6),
          Center(
            child: AuthQuietButton(
              label: 'Enter my number instead',
              onPressed: _startManualEntry,
            ),
          ),
        ],
      ],
    );
  }

  // ── Capture ──────────────────────────────────────────────────────────────

  Future<void> _captureImage() async {
    try {
      // Navigate to the auto-capture ID camera
      // Note: We pass empty strings since names haven't been entered yet in this flow
      // The OCR service will skip name validation when empty strings are provided
      final result = await Navigator.of(context).push<IdVerificationResult>(
        MaterialPageRoute(
          builder: (context) => IdVerificationCamera(
            onIdVerified: (verificationResult) {
              Navigator.of(context).pop(verificationResult);
            },
            onCancel: () {
              Navigator.of(context).pop();
            },
            // Pass empty strings to skip name validation in the new flow
            expectedFirstName: '',
            expectedLastName: '',
          ),
        ),
      );

      if (!mounted) return;

      if (result != null && result.isManualEntryRequest) {
        // Not a failure — the dentist asked for the form instead. Nothing about
        // the previous attempt should be left on screen as an error.
        _startManualEntry();
      } else if (result != null) {
        // ID was auto-captured and verified
        setState(() {
          if (result.isValid) {
            _controller.isIdVerified = true;
            _controller.idNumber = result.registrationNumber;
            // Auto-fill the ID number text field
            _controller.idNumberController.text =
                result.registrationNumber ?? '';
            _controller.idVerificationError = null;
            _controller.idFaceImage = result.faceImage;

            // The scan's reading of the name is deliberately dropped. OCR gets
            // it wrong often enough — hyphens, ñ, middle names run into the
            // first — that a pre-filled field is worse than an empty one: it
            // invites people to accept a misspelling they would have typed
            // correctly, and a wrong legal name is not a small thing on an
            // account tied to a licence. The registration number is a run of
            // digits, so that one is still filled in for them.

            _controller.isIdAlreadyRegistered = false;
            // A successful scan supersedes anything typed in earlier.
            _controller.idEnteredManually = false;
            _manualEntry = false;
          } else {
            _clearVerification(result.errorMessage);
            _controller.isIdAlreadyRegistered = result.isAlreadyRegistered;
          }
        });
      } else {
        // User cancelled the camera - mark as failed
        setState(() {
          _clearVerification(
            'ID verification cancelled. Please try again to complete your '
            'registration.',
          );
        });
      }
    } catch (e) {
      SignupController.logOcrResult('ERROR', 'Failed to capture image: $e');
      if (mounted) {
        const message =
            'Unable to access camera. Please check permissions and try again.';
        setState(() => _clearVerification(message));
        showAuthSnack(context, message, _ink.danger);
      }
    }
  }

  /// Puts the step back into its "not verified" shape, carrying the reason.
  ///
  /// Call inside a [setState] — it only mutates, so the three failure paths do
  /// not each have to remember the full list of fields to reset.
  void _clearVerification(String? error) {
    _controller.isIdVerified = false;
    _controller.idVerificationError = error;
    _controller.isIdAlreadyRegistered = false;
    _controller.idEnteredManually = false;
    _controller.idNumber = null;
    _controller.idNumberController.text = '';
    _controller.idFaceImage = null;
  }
}
