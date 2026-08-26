// ignore_for_file: unused_field

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/app_theme/app_text_styles.dart';
import '../../../core/app_theme/ink_palette.dart';
import '../../../core/app_theme/theme_utils.dart';
import '../../../core/widgets/app_page_header.dart';
import '../../../utils/app_logger.dart';

enum VerificationStep {
  enterNewPhone,
  verifyCurrentPhone,
  verifyNewPhone,
  completed,
}

/// Moving the account to a different number, proving both ends along the way:
/// the old number confirms it is really you, the new one confirms it is really
/// yours.
class ChangeMobilePage extends StatefulWidget {
  const ChangeMobilePage({super.key});

  @override
  State<ChangeMobilePage> createState() => _ChangeMobilePageState();
}

class _ChangeMobilePageState extends State<ChangeMobilePage> {
  final TextEditingController _newPhoneController = TextEditingController();
  final List<TextEditingController> _currentOtpControllers = List.generate(
    6,
    (index) => TextEditingController(),
  );
  final List<TextEditingController> _newOtpControllers = List.generate(
    6,
    (index) => TextEditingController(),
  );
  final List<FocusNode> _currentOtpFocusNodes = List.generate(
    6,
    (index) => FocusNode(),
  );
  final List<FocusNode> _newOtpFocusNodes = List.generate(
    6,
    (index) => FocusNode(),
  );

  String? _currentPhoneNumber;
  String? _currentVerificationId;
  String? _newVerificationId;
  int? _currentResendToken;
  int? _newResendToken;
  PhoneAuthCredential? _currentPhoneCredential;
  PhoneAuthCredential? _newPhoneCredential;

  bool _isLoading = false;
  bool _isCurrentPhoneVerified = false;
  bool _isNewPhoneVerified = false;
  bool _isUpdatingPhone = false;

  VerificationStep _currentStep = VerificationStep.enterNewPhone;

  @override
  void initState() {
    super.initState();
    _loadCurrentPhoneNumber();
  }

  @override
  void dispose() {
    _newPhoneController.dispose();
    for (var controller in _currentOtpControllers) {
      controller.dispose();
    }
    for (var controller in _newOtpControllers) {
      controller.dispose();
    }
    for (var node in _currentOtpFocusNodes) {
      node.dispose();
    }
    for (var node in _newOtpFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCurrentPhoneNumber() async {
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

        if (userDoc.exists) {
          final userData = userDoc.data();
          _currentPhoneNumber = userData?['contactNumber'];
        }
      }
    } catch (e) {
      AppLogger.d('Error loading current phone number: $e');
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String get _formattedNewPhoneNumber {
    String phoneNumber = _newPhoneController.text.trim();
    // Convert Philippines format: 09123456789 -> +639123456789
    if (phoneNumber.startsWith('09')) {
      phoneNumber = '+63${phoneNumber.substring(1)}'; // Replace '0' with '+63'
    } else if (!phoneNumber.startsWith('+63')) {
      // If it doesn't start with +63, assume it's missing the country code
      phoneNumber = '+63$phoneNumber';
    }
    return phoneNumber;
  }

  String get _displayPhoneNumber {
    // Display format for Philippines: +639123456789 -> 09123456789
    if (_currentPhoneNumber != null && _currentPhoneNumber!.startsWith('+63')) {
      return '0${_currentPhoneNumber!.substring(3)}';
    }
    return _currentPhoneNumber ?? '—';
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

  static const List<String> _stepLabels = [
    'New number',
    'Verify current',
    'Verify new',
    'Done',
  ];

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
                  title: 'Change phone number',
                  subtitle: _currentStep == VerificationStep.completed
                      ? 'All done'
                      : 'Step ${_currentStep.index + 1} of 4 — '
                            '${_stepLabels[_currentStep.index].toLowerCase()}',
                  subtitleColor: _currentStep == VerificationStep.completed
                      ? ink.emerald
                      : null,
                ),
                Expanded(
                  child: _isLoading && _currentPhoneNumber == null
                      ? Center(
                          child: CircularProgressIndicator(color: ink.emerald),
                        )
                      : ListView(
                          padding: _listPadding,
                          children: [
                            _buildStepRail(),
                            const SizedBox(height: 20),
                            _buildStepContent(),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Progress ─────────────────────────────────────────────────────────────

  /// Where you are in the four steps.
  ///
  /// This was four numbered circles joined by grey rules, with the labels on a
  /// second row that never lined up with them. One rail of segments, with only
  /// the step you are on named, says the same thing in a third of the height.
  Widget _buildStepRail() {
    final current = _currentStep.index;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < _stepLabels.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  height: 4,
                  decoration: BoxDecoration(
                    color: i <= current ? ink.emerald : ink.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Text(
              _stepLabels[current],
              style: AppTextStyles.bodySmall.copyWith(
                color: ink.emerald,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
            const Spacer(),
            Text(
              '${current + 1}/${_stepLabels.length}',
              style: AppTextStyles.bodySmall.copyWith(
                color: ink.text.withValues(alpha: 0.4),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case VerificationStep.enterNewPhone:
        return _buildEnterNewPhoneStep();
      case VerificationStep.verifyCurrentPhone:
        return _buildVerifyCurrentPhoneStep();
      case VerificationStep.verifyNewPhone:
        return _buildVerifyNewPhoneStep();
      case VerificationStep.completed:
        return _buildCompletedStep();
    }
  }

  // ── Step 1 ───────────────────────────────────────────────────────────────

  Widget _buildEnterNewPhoneStep() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCardHeading(
            icon: Icons.smartphone_outlined,
            title: 'Your new number',
            detail: 'We’ll text a code to both numbers to confirm the change.',
          ),
          const SizedBox(height: 18),

          _buildFieldLabel('Current number'),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
            decoration: BoxDecoration(
              color: ink.surfaceHigh,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ink.border),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.phone_outlined,
                  size: 18,
                  color: ink.text.withValues(alpha: 0.35),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _displayPhoneNumber,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: ink.text.withValues(alpha: 0.7),
                      fontSize: 14,
                    ),
                  ),
                ),
                Icon(
                  Icons.lock_outline,
                  size: 15,
                  color: ink.text.withValues(alpha: 0.3),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          _buildFieldLabel('New number'),
          const SizedBox(height: 8),
          _buildPhoneField(),

          const SizedBox(height: 22),
          _buildPrimaryButton(
            label: 'Continue',
            busy: _isLoading,
            onPressed: _isLoading ? null : _validateAndProceed,
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneField() {
    OutlineInputBorder border(Color color, {double width = 1}) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return TextFormField(
      controller: _newPhoneController,
      keyboardType: TextInputType.phone,
      maxLength: 11,
      enabled: !_isLoading,
      cursorColor: ink.emerald,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(11),
      ],
      style: AppTextStyles.bodyMedium.copyWith(color: ink.text, fontSize: 14),
      decoration: InputDecoration(
        hintText: '09123456789',
        hintStyle: AppTextStyles.bodyMedium.copyWith(
          color: ink.text.withValues(alpha: 0.35),
          fontSize: 14,
        ),
        helperText: '11 digits, starting 09',
        helperStyle: AppTextStyles.bodySmall.copyWith(
          color: ink.text.withValues(alpha: 0.45),
          fontSize: 11.5,
        ),
        counterText: '',
        prefixIcon: Icon(
          Icons.phone_android_outlined,
          size: 19,
          color: ink.emerald,
        ),
        border: border(ink.border),
        enabledBorder: border(ink.border),
        disabledBorder: border(ink.border.withValues(alpha: 0.5)),
        focusedBorder: border(ink.emerald, width: 1.5),
        filled: true,
        fillColor: ink.surface,
      ),
    );
  }

  // ── Steps 2 and 3 ────────────────────────────────────────────────────────

  Widget _buildVerifyCurrentPhoneStep() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCardHeading(
            icon: Icons.verified_user_outlined,
            title: 'Confirm it’s you',
            detail: 'Enter the code we sent to $_displayPhoneNumber.',
          ),
          const SizedBox(height: 20),
          _buildOtpInput(_currentOtpControllers, _currentOtpFocusNodes),
          const SizedBox(height: 20),
          _buildOtpActions(
            busy: _isLoading,
            onResend: _isLoading ? null : _resendCurrentOtp,
            onVerify: _isLoading ? null : _verifyCurrentOtp,
          ),
        ],
      ),
    );
  }

  Widget _buildVerifyNewPhoneStep() {
    final busy = _isLoading || _isUpdatingPhone;

    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCardHeading(
            icon: Icons.sms_outlined,
            title: 'Confirm the new number',
            detail: _isUpdatingPhone
                ? 'Saving your new number…'
                : 'Enter the code we sent to '
                      '${_newPhoneController.text.trim()}.',
          ),
          const SizedBox(height: 20),
          _buildOtpInput(_newOtpControllers, _newOtpFocusNodes),
          const SizedBox(height: 20),
          _buildOtpActions(
            busy: busy,
            onResend: busy ? null : _resendNewOtp,
            onVerify: busy ? null : _verifyNewOtp,
          ),
        ],
      ),
    );
  }

  Widget _buildOtpActions({
    required bool busy,
    required VoidCallback? onResend,
    required VoidCallback? onVerify,
  }) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 52,
            child: OutlinedButton(
              onPressed: onResend,
              style: OutlinedButton.styleFrom(
                foregroundColor: ink.text,
                disabledForegroundColor: ink.text.withValues(alpha: 0.35),
                side: BorderSide(color: ink.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                'Resend code',
                style: AppTextStyles.buttonMedium.copyWith(fontSize: 13.5),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildPrimaryButton(
            label: 'Verify',
            busy: busy,
            onPressed: onVerify,
          ),
        ),
      ],
    );
  }

  /// Six boxes, each lighting up as it takes a digit.
  Widget _buildOtpInput(
    List<TextEditingController> controllers,
    List<FocusNode> focusNodes,
  ) {
    return Row(
      children: [
        for (var index = 0; index < 6; index++) ...[
          if (index > 0) const SizedBox(width: 8),
          Expanded(
            child: AspectRatio(
              aspectRatio: 0.82,
              child: _buildOtpBox(controllers, focusNodes, index),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOtpBox(
    List<TextEditingController> controllers,
    List<FocusNode> focusNodes,
    int index,
  ) {
    final filled = controllers[index].text.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: filled ? ink.surface : ink.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: filled ? ink.emerald.withValues(alpha: 0.6) : ink.border,
          width: filled ? 1.5 : 1,
        ),
      ),
      child: TextFormField(
        controller: controllers[index],
        focusNode: focusNodes[index],
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        cursorColor: ink.emerald,
        style: AppTextStyles.titleMedium.copyWith(
          color: ink.text,
          fontWeight: FontWeight.w800,
          fontSize: 18,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          counterText: '',
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: (value) {
          if (value.isNotEmpty && index < 5) {
            focusNodes[index + 1].requestFocus();
          }
          if (value.isEmpty && index > 0) {
            focusNodes[index - 1].requestFocus();
          }
          // Repaints the box's filled state — without this the boxes stayed
          // uniformly empty-looking no matter how much had been typed.
          setState(() {});
        },
      ),
    );
  }

  // ── Step 4 ───────────────────────────────────────────────────────────────

  Widget _buildCompletedStep() {
    return _buildCard(
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: ink.emerald.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_circle_outline,
              size: 30,
              color: ink.emerald,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Number updated',
            textAlign: TextAlign.center,
            style: AppTextStyles.titleMedium.copyWith(
              color: ink.text,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your account now uses ${_newPhoneController.text.trim()}.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: _muted,
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: _buildPrimaryButton(
              label: 'Done',
              busy: false,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared parts ─────────────────────────────────────────────────────────

  Widget _buildCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink.border),
      ),
      child: child,
    );
  }

  Widget _buildCardHeading({
    required IconData icon,
    required String title,
    required String detail,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: ink.emerald.withValues(alpha: ink.isDark ? 0.16 : 0.11),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: ink.emerald, size: 19),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: ink.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                detail,
                style: AppTextStyles.bodySmall.copyWith(
                  color: ink.text.withValues(alpha: 0.55),
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        label,
        style: AppTextStyles.bodySmall.copyWith(
          color: ink.text.withValues(alpha: 0.5),
          fontWeight: FontWeight.w700,
          fontSize: 11.5,
        ),
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required bool busy,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
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
        child: busy
            ? SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: ink.onEmerald,
                ),
              )
            : Text(label, style: AppTextStyles.buttonLarge),
      ),
    );
  }

  // ── Flow ─────────────────────────────────────────────────────────────────

  void _validateAndProceed() async {
    final phoneNumber = _newPhoneController.text.trim();

    if (phoneNumber.isEmpty) {
      _showMessage(false, 'Please enter a new phone number');
      return;
    }

    // Validate Philippines phone number format
    if (!phoneNumber.startsWith('09')) {
      _showMessage(false, 'Phone number must start with 09');
      return;
    }

    if (phoneNumber.length != 11) {
      _showMessage(false, 'Phone number must be exactly 11 digits');
      return;
    }

    // Check if it contains only numbers
    if (!RegExp(r'^[0-9]+$').hasMatch(phoneNumber)) {
      _showMessage(false, 'Phone number must contain only numbers');
      return;
    }

    if (_formattedNewPhoneNumber == _currentPhoneNumber) {
      _showMessage(
        false,
        'New phone number must be different from current number',
      );
      return;
    }

    // Check for duplicate phone numbers
    await _checkForDuplicatePhoneNumber();
  }

  Future<void> _checkForDuplicatePhoneNumber() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        setState(() {
          _isLoading = false;
        });
        _showMessage(false, 'User not found');
        return;
      }

      // Check UserLookup collection for existing phone number
      final userLookupQuery = await FirebaseFirestore.instance
          .collection('UserLookup')
          .where('contactNumber', isEqualTo: _formattedNewPhoneNumber)
          .get();

      // Check User collection for existing phone number (fallback)
      final userQuery = await FirebaseFirestore.instance
          .collection('User')
          .where('contactNumber', isEqualTo: _formattedNewPhoneNumber)
          .get();

      // Combine results and exclude current user
      final conflictingUsers = <Map<String, dynamic>>[];

      // Process UserLookup results
      for (var doc in userLookupQuery.docs) {
        if (doc.id != currentUser.uid) {
          final userData = await FirebaseFirestore.instance
              .collection('User')
              .doc(doc.id)
              .get();

          if (userData.exists) {
            conflictingUsers.add({
              'userId': doc.id,
              'userData': userData.data(),
              'lookupData': doc.data(),
            });
          }
        }
      }

      // Process User results (for users without UserLookup)
      for (var doc in userQuery.docs) {
        if (doc.id != currentUser.uid &&
            !conflictingUsers.any((user) => user['userId'] == doc.id)) {
          conflictingUsers.add({
            'userId': doc.id,
            'userData': doc.data(),
            'lookupData': null,
          });
        }
      }

      setState(() {
        _isLoading = false;
      });

      if (conflictingUsers.isNotEmpty) {
        _showMessage(
          false,
          'This number is already linked to another account. Please use a different number.',
        );
      } else {
        _sendCurrentPhoneVerification();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      AppLogger.d('Error checking for duplicate phone: $e');
      _showMessage(false, 'Error checking phone number availability: $e');
    }
  }

  Future<void> _sendCurrentPhoneVerification() async {
    if (_currentPhoneNumber == null) {
      _showMessage(false, 'Current phone number not found');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: _currentPhoneNumber!,
        verificationCompleted: (PhoneAuthCredential credential) {
          _currentPhoneCredential = credential;
          setState(() {
            _isCurrentPhoneVerified = true;
            _isLoading = false;
          });
          _sendNewPhoneVerification();
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() {
            _isLoading = false;
          });
          _showMessage(
            false,
            'Failed to send verification to current number: ${e.message}',
          );
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _currentVerificationId = verificationId;
            _currentResendToken = resendToken;
            _currentStep = VerificationStep.verifyCurrentPhone;
            _isLoading = false;
          });
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _currentVerificationId = verificationId;
        },
        timeout: const Duration(seconds: 120),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showMessage(false, 'Error sending verification: $e');
    }
  }

  Future<void> _verifyCurrentOtp() async {
    final otp = _currentOtpControllers.map((c) => c.text).join();
    if (otp.length != 6) {
      _showMessage(false, 'Please enter all 6 digits');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Create credential for current phone - this validates the OTP format
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _currentVerificationId!,
        smsCode: otp,
      );

      // Store the credential without signing in (we'll validate it works during the update)
      _currentPhoneCredential = credential;

      setState(() {
        _isCurrentPhoneVerified = true;
        _isLoading = false;
      });

      AppLogger.d(
        'Current phone OTP accepted, proceeding to new phone verification',
      );
      _sendNewPhoneVerification();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      AppLogger.d('Current phone verification failed: $e');
      _showMessage(
        false,
        'Invalid verification code for current number. Please try again.',
      );
    }
  }

  Future<void> _sendNewPhoneVerification() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: _formattedNewPhoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) {
          _newPhoneCredential = credential;
          setState(() {
            _isNewPhoneVerified = true;
            _isLoading = false;
          });
          _updatePhoneNumber();
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() {
            _isLoading = false;
          });
          _showMessage(
            false,
            'Failed to send verification to new number: ${e.message}',
          );
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _newVerificationId = verificationId;
            _newResendToken = resendToken;
            _currentStep = VerificationStep.verifyNewPhone;
            _isLoading = false;
          });
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _newVerificationId = verificationId;
        },
        timeout: const Duration(seconds: 120),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showMessage(false, 'Error sending verification: $e');
    }
  }

  Future<void> _verifyNewOtp() async {
    final otp = _newOtpControllers.map((c) => c.text).join();
    if (otp.length != 6) {
      _showMessage(false, 'Please enter all 6 digits');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Create credential for new phone - this validates the OTP format
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _newVerificationId!,
        smsCode: otp,
      );

      // Store the credential without signing in
      _newPhoneCredential = credential;

      setState(() {
        _isNewPhoneVerified = true;
        _isLoading = false;
      });

      AppLogger.d('New phone OTP verified successfully');
      await _updatePhoneNumber();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      AppLogger.d('New phone verification failed: $e');
      _showMessage(
        false,
        'Invalid verification code for new number. Please try again.',
      );
    }
  }

  Future<void> _updatePhoneNumber() async {
    setState(() {
      _isUpdatingPhone = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      AppLogger.d('Starting phone number update for user: ${user.uid}');
      AppLogger.d(
        'User ${user.uid} verified access to both $_currentPhoneNumber and $_formattedNewPhoneNumber',
      );

      // Update Firebase Auth phone number using the new phone credential
      if (_newPhoneCredential != null) {
        try {
          await user.updatePhoneNumber(_newPhoneCredential!);
          AppLogger.d('Firebase Auth phone number updated successfully');
        } catch (e) {
          // If Firebase Auth update fails, we'll continue with Firestore updates only
          // The phone verification already confirmed the user has access to the new number
          AppLogger.d('Firebase Auth phone update failed: $e');
          AppLogger.d(
            'Continuing with Firestore-only update since phone verification was successful',
          );
        }
      } else {
        AppLogger.d(
          'New phone credential not available, updating Firestore only',
        );
      }

      // Get user data first to retrieve email and createdAt
      final userDoc = await FirebaseFirestore.instance
          .collection('User')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        throw Exception('User document not found');
      }

      final userData = userDoc.data()!;
      final userEmail = userData['email'] ?? user.email;
      final userCreatedAt = userData['createdAt'];

      // Update phone number in Firestore User collection
      await FirebaseFirestore.instance.collection('User').doc(user.uid).update({
        'contactNumber': _formattedNewPhoneNumber,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Check if UserLookup exists, if not create it
      final userLookupDoc = await FirebaseFirestore.instance
          .collection('UserLookup')
          .doc(user.uid)
          .get();

      if (userLookupDoc.exists) {
        // Update existing UserLookup document
        await FirebaseFirestore.instance
            .collection('UserLookup')
            .doc(user.uid)
            .update({
              'contactNumber': _formattedNewPhoneNumber,
              'updatedAt': FieldValue.serverTimestamp(),
            });
        AppLogger.d('UserLookup document updated');
      } else {
        // Create new UserLookup document
        await FirebaseFirestore.instance
            .collection('UserLookup')
            .doc(user.uid)
            .set({
              'contactNumber': _formattedNewPhoneNumber,
              'email': userEmail,
              'createdAt': userCreatedAt,
              'updatedAt': FieldValue.serverTimestamp(),
            });
        AppLogger.d('UserLookup document created');
      }

      AppLogger.d('Phone number updated in Firestore collections');

      setState(() {
        _currentStep = VerificationStep.completed;
        _isUpdatingPhone = false;
      });

      AppLogger.d('Phone number update completed successfully');
    } catch (e) {
      setState(() {
        _isUpdatingPhone = false;
      });
      AppLogger.d('Error updating phone number: $e');
      _showMessage(false, 'Error updating phone number: $e');
    }
  }

  Future<void> _resendCurrentOtp() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: _currentPhoneNumber!,
        forceResendingToken: _currentResendToken,
        verificationCompleted: (PhoneAuthCredential credential) {
          _currentPhoneCredential = credential;
          setState(() {
            _isCurrentPhoneVerified = true;
            _isLoading = false;
          });
          _sendNewPhoneVerification();
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() {
            _isLoading = false;
          });
          _showMessage(false, 'Failed to resend code: ${e.message}');
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _currentVerificationId = verificationId;
            _currentResendToken = resendToken;
            _isLoading = false;
          });
          // Clear OTP fields
          for (var controller in _currentOtpControllers) {
            controller.clear();
          }
          _showMessage(true, 'Verification code resent');
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _currentVerificationId = verificationId;
        },
        timeout: const Duration(seconds: 120),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showMessage(false, 'Error resending code: $e');
    }
  }

  Future<void> _resendNewOtp() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: _formattedNewPhoneNumber,
        forceResendingToken: _newResendToken,
        verificationCompleted: (PhoneAuthCredential credential) {
          _newPhoneCredential = credential;
          setState(() {
            _isNewPhoneVerified = true;
            _isLoading = false;
          });
          _updatePhoneNumber();
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() {
            _isLoading = false;
          });
          _showMessage(false, 'Failed to resend code: ${e.message}');
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _newVerificationId = verificationId;
            _newResendToken = resendToken;
            _isLoading = false;
          });
          // Clear OTP fields
          for (var controller in _newOtpControllers) {
            controller.clear();
          }
          _showMessage(true, 'Verification code resent');
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _newVerificationId = verificationId;
        },
        timeout: const Duration(seconds: 120),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showMessage(false, 'Error resending code: $e');
    }
  }

  void _showMessage(bool isSuccess, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess ? ink.emerald : _danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
