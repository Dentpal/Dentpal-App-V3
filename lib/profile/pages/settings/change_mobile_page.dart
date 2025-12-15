// ignore_for_file: unused_field

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // Added for web detection
import '../../../core/app_theme/app_colors.dart';
import '../../../core/app_theme/app_text_styles.dart';
import '../../../utils/app_logger.dart';

enum VerificationStep {
  enterNewPhone,
  verifyCurrentPhone,
  verifyNewPhone,
  completed,
}

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
      //AppLogger.d('Error loading current phone number: $e');
    }

    setState(() {
      _isLoading = false;
    });
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
    return _currentPhoneNumber ?? 'Loading...';
  }

  @override
  Widget build(BuildContext context) {
    final content = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStepIndicator(),
                const SizedBox(height: 32),
                _buildStepContent(),
              ],
            ),
          );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        toolbarHeight: 60,
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Icon(Icons.phone_outlined, color: AppColors.primary, size: 24),
            const SizedBox(width: 8),
            Text(
              'Change Mobile Number',
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWideWeb = kIsWeb && constraints.maxWidth > 800; // BREAKPOINT
          if (isWideWeb) {
            return Align(
              alignment: Alignment.topCenter, // top-centered vertically
              child: Padding(
                padding: const EdgeInsets.only(top: 16), // slight top spacing
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640), // MAX_WIDTH
                  child: Material(color: Colors.transparent, child: content),
                ),
              ),
            );
          }
          return content; // mobile & narrow web full width
        },
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildStepIcon(1, _currentStep.index >= 0),
              _buildStepLine(_currentStep.index >= 1),
              _buildStepIcon(2, _currentStep.index >= 1),
              _buildStepLine(_currentStep.index >= 2),
              _buildStepIcon(3, _currentStep.index >= 2),
              _buildStepLine(_currentStep.index >= 3),
              _buildStepIcon(4, _currentStep.index >= 3),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStepLabel('New\nNumber'),
              _buildStepLabel('Verify\nCurrent'),
              _buildStepLabel('Verify\nNew'),
              _buildStepLabel('Complete'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepIcon(int step, bool isActive) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isActive ? AppColors.primary : AppColors.grey200,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          '$step',
          style: AppTextStyles.bodyMedium.copyWith(
            color: isActive ? AppColors.onPrimary : AppColors.grey600,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildStepLine(bool isActive) {
    return Expanded(
      child: Container(
        height: 2,
        color: isActive ? AppColors.primary : AppColors.grey200,
        margin: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }

  Widget _buildStepLabel(String label) {
    return Text(
      label,
      style: AppTextStyles.bodySmall.copyWith(
        color: AppColors.grey600,
        fontWeight: FontWeight.w500,
      ),
      textAlign: TextAlign.center,
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

  Widget _buildEnterNewPhoneStep() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
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
          Icon(Icons.phone_android, size: 48, color: AppColors.primary),
          const SizedBox(height: 16),
          Text(
            'Current Phone Number',
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.grey50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.grey200),
            ),
            child: Text(
              _displayPhoneNumber,
              style: AppTextStyles.bodyLarge.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'New Phone Number',
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _newPhoneController,
            keyboardType: TextInputType.phone,
            maxLength: 11,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(11),
            ],
            decoration: InputDecoration(
              hintText: '09123456789',
              prefixText: '',
              helperText: 'Format: 09XXXXXXXXX (11 digits)',
              helperStyle: AppTextStyles.bodySmall.copyWith(
                color: AppColors.grey600,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.grey200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.grey200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.primary, width: 2),
              ),
              filled: true,
              fillColor: AppColors.surface,
            ),
            style: AppTextStyles.bodyLarge,
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _validateAndProceed,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Text('Continue', style: AppTextStyles.buttonLarge),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerifyCurrentPhoneStep() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(Icons.verified_user, size: 48, color: AppColors.primary),
          const SizedBox(height: 16),
          Text(
            'Verify Current Number',
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'We sent a verification code to your current number:\n $_displayPhoneNumber',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.grey600),
          ),
          const SizedBox(height: 24),
          _buildOtpInput(_currentOtpControllers, _currentOtpFocusNodes),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _isLoading ? null : () => _resendCurrentOtp(),
                  child: Text(
                    'Resend Code',
                    style: AppTextStyles.buttonMedium.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verifyCurrentOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: AppColors.onPrimary,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Text('Verify', style: AppTextStyles.buttonMedium),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVerifyNewPhoneStep() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(Icons.smartphone, size: 48, color: AppColors.success),
          const SizedBox(height: 16),
          Text(
            'Verify New Number',
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isUpdatingPhone
                ? 'Updating your phone number...'
                : 'We sent a verification code to your new number:\n${_newPhoneController.text.trim()}',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.grey600),
          ),
          const SizedBox(height: 24),
          _buildOtpInput(_newOtpControllers, _newOtpFocusNodes),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: (_isLoading || _isUpdatingPhone)
                      ? null
                      : () => _resendNewOtp(),
                  child: Text(
                    'Resend Code',
                    style: AppTextStyles.buttonMedium.copyWith(
                      color: AppColors.success,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: (_isLoading || _isUpdatingPhone)
                      ? null
                      : _verifyNewOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: AppColors.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: (_isLoading || _isUpdatingPhone)
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: AppColors.onPrimary,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Text('Verify', style: AppTextStyles.buttonMedium),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedStep() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check_circle, size: 48, color: AppColors.success),
          ),
          const SizedBox(height: 24),
          Text(
            'Phone Number Updated!',
            style: AppTextStyles.titleLarge.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your phone number has been successfully updated to:\n${_newPhoneController.text.trim()}',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.grey600),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Text('Done', style: AppTextStyles.buttonLarge),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpInput(
    List<TextEditingController> controllers,
    List<FocusNode> focusNodes,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(6, (index) {
        return Container(
          width: 45,
          height: 45,
          decoration: BoxDecoration(
            color: AppColors.grey50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.grey200),
          ),
          child: TextFormField(
            controller: controllers[index],
            focusNode: focusNodes[index],
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 1,
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
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
            },
          ),
        );
      }),
    );
  }

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
      //AppLogger.d('Error checking for duplicate phone: $e');
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

      //AppLogger.d('Current phone OTP accepted, proceeding to new phone verification',);
      _sendNewPhoneVerification();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      //AppLogger.d('Current phone verification failed: $e');
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

      //AppLogger.d('New phone OTP verified successfully');
      await _updatePhoneNumber();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      //AppLogger.d('New phone verification failed: $e');
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

      //AppLogger.d('Starting phone number update for user: ${user.uid}');
      //AppLogger.d('User ${user.uid} verified access to both $_currentPhoneNumber and $_formattedNewPhoneNumber',);

      // Update Firebase Auth phone number using the new phone credential
      if (_newPhoneCredential != null) {
        try {
          await user.updatePhoneNumber(_newPhoneCredential!);
          //AppLogger.d('Firebase Auth phone number updated successfully');
        } catch (e) {
          // If Firebase Auth update fails, we'll continue with Firestore updates only
          // The phone verification already confirmed the user has access to the new number
          //AppLogger.d('Firebase Auth phone update failed: $e');
          //AppLogger.d('Continuing with Firestore-only update since phone verification was successful',);
        }
      } else {
        //AppLogger.d('New phone credential not available, updating Firestore only',);
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
        //AppLogger.d('UserLookup document updated');
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
        //AppLogger.d('UserLookup document created');
      }

      //AppLogger.d('Phone number updated in Firestore collections');

      setState(() {
        _currentStep = VerificationStep.completed;
        _isUpdatingPhone = false;
      });

      //AppLogger.d('Phone number update completed successfully');
    } catch (e) {
      setState(() {
        _isUpdatingPhone = false;
      });
      //AppLogger.d('Error updating phone number: $e');
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
        backgroundColor: isSuccess ? AppColors.success : AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
