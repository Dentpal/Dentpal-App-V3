// ignore_for_file: deprecated_member_use

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'signup_controller.dart';
import 'package:dentpal/login_page.dart';
import 'package:dentpal/core/app_theme/index.dart';
import 'package:dentpal/utils/app_logger.dart';
import 'package:dentpal/utils/signup_state.dart';

class SignupStep5PhoneVerification extends StatefulWidget {
  final SignupController controller;
  final VoidCallback onBack;

  const SignupStep5PhoneVerification({
    super.key,
    required this.controller,
    required this.onBack,
  });

  @override
  State<SignupStep5PhoneVerification> createState() => _SignupStep5PhoneVerificationState();
}

class _SignupStep5PhoneVerificationState extends State<SignupStep5PhoneVerification> {
  // Quick access to controller
  SignupController get _controller => widget.controller;
  
  // UI state management
  bool _showOtpInput = false;
  bool _verificationFailed = false;
  String _errorMessage = '';
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _otpFocusNode = FocusNode();
  
  @override
  void dispose() {
    _otpController.dispose();
    _otpFocusNode.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    AppLogger.d('SignupStep5PhoneVerification build called');
    return SingleChildScrollView(
      padding: const EdgeInsets.only(
        left: 30.0,
        right: 30.0,
        top: 30.0
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Phone verification section
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.grey50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.grey200),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.phone_android,
                  size: 48,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 16),
                
                // Conditional rendering based on state
                if (_controller.isContactNumberVerified) ...[
                  // Success state
                  Text(
                    'Phone Verified!',
                    style: AppTextStyles.headlineSmall.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.success,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.success),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: AppColors.success,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Phone number verified',
                          style: AppTextStyles.labelMedium.copyWith(
                            color: AppColors.success,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (_showOtpInput) ...[
                  // OTP Input state
                  Text(
                    'Enter Verification Code',
                    style: AppTextStyles.headlineSmall.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter the 6-digit code sent to ${_controller.formattedPhoneNumber}',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.grey600,
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Single OTP text field with letter spacing
                  TextField(
                    controller: _otpController,
                    focusNode: _otpFocusNode,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.headlineMedium.copyWith(
                      letterSpacing: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '000000',
                      hintStyle: AppTextStyles.headlineMedium.copyWith(
                        letterSpacing: 16,
                        color: AppColors.grey300,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.grey300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.grey300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.primary, width: 2),
                      ),
                      filled: true,
                      fillColor: AppColors.surface,
                    ),
                    onChanged: (value) {
                      if (value.length == 6) {
                        // Auto-verify when 6 digits entered
                        _verifyOtp();
                      }
                    },
                  ),
                  
                  if (_verificationFailed) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.error),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: AppColors.error, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _resendCode,
                    child: Text(
                      'Resend Code',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ] else ...[
                  // Initial state
                  Text(
                    'Phone Verification',
                    style: AppTextStyles.headlineSmall.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'We\'ll send a verification code to your phone number to ensure account security.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.grey600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          const SizedBox(height: 200), // Spacer for content
          
          // Action buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: widget.onBack,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.grey200,
                    foregroundColor: AppColors.grey700,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Back',
                    style: AppTextStyles.buttonLarge,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: _showOtpInput ? _verifyOtp : _processSubmission,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _controller.isVerificationInProgress
                    ? SizedBox(
                        width: 20, 
                        height: 20, 
                        child: CircularProgressIndicator(
                          color: AppColors.onPrimary, 
                          strokeWidth: 2.5
                        )
                      )
                    : Text(
                        _showOtpInput 
                          ? 'Verify Code' 
                          : (_controller.isContactNumberVerified ? 'Submit' : 'Verify Phone'),
                        style: AppTextStyles.buttonLarge,
                      ),
                ),
              ),
            ],
          ),
          // Add extra space at the bottom to account for home indicator
          SizedBox(height: MediaQuery.of(context).padding.bottom > 0 ? 40 : 20),
        ],
      ),
    );
  }

  // Process form submission - verify phone if not verified, otherwise submit form
  Future<void> _processSubmission() async {
    AppLogger.d('_processSubmission called - isContactNumberVerified: ${_controller.isContactNumberVerified}');
    
    if (_controller.isContactNumberVerified) {
      // Phone already verified, show loading overlay and start account creation
      _showLoadingOverlay(context, 'Completing registration...');
      
      try {
        User? user;
        
        if (_controller.phoneCredential != null) {
          // ── SINGLE-ACCOUNT FLOW ──
          // 1) Sign in with the phone credential (creates one auth account)
          AppLogger.d('Signing in with phone credential...');
          final UserCredential phoneUserCredential =
              await FirebaseAuth.instance.signInWithCredential(_controller.phoneCredential!);
          user = phoneUserCredential.user;
          
          if (user == null) {
            throw Exception('Phone sign-in returned null user');
          }
          AppLogger.d('Signed in with phone - uid: ${user.uid}');
          
          // 2) Link email/password to the same account
          AppLogger.d('Linking email/password to phone account...');
          final emailCredential = EmailAuthProvider.credential(
            email: _controller.email,
            password: _controller.password,
          );
          await user.linkWithCredential(emailCredential);
          AppLogger.d('Email/password linked successfully');
        } else {
          // ── FALLBACK: no phone credential (e.g. test flow) ──
          // Create with email/password directly
          AppLogger.d('No phone credential - creating email/password account');
          final UserCredential userCredential =
              await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: _controller.email,
            password: _controller.password,
          );
          user = userCredential.user;
          
          if (user == null) {
            throw Exception('User creation failed');
          }
        }
        
        // Send email verification
        await user.sendEmailVerification();
        AppLogger.d('Email verification sent');
        
        // Save user data to Firestore
        await _saveUserDataToFirestore(user);
        
        // Sign out the user so they have to verify email before logging in
        await FirebaseAuth.instance.signOut();
        AppLogger.d('Signed out after registration');
        
        // Remove loading overlay
        if (mounted) {
          Navigator.of(context).pop();
        }
        
        // Navigate to login page
        if (mounted) {
          // Clear signup flag before navigating away - signup is complete
          SignupState.isInSignupFlow = false;
          AppLogger.d('Registration complete, cleared isInSignupFlow flag');
          
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginPage()),
            (route) => false,  // Remove all previous routes
          );
          
          // Show email verification dialog after navigation
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showEmailVerificationDialog();
          });
        }
      } catch (e) {
        // Remove loading overlay
        if (mounted) {
          Navigator.of(context).pop();
        }
        
        AppLogger.d('Registration error: $e');
        
        // Show error dialog
        String errorMessage = 'Registration failed. Please try again.';
        if (e is FirebaseAuthException) {
          switch (e.code) {
            case 'email-already-in-use':
              errorMessage = 'An account already exists for this email address.';
              break;
            case 'invalid-email':
              errorMessage = 'The email address is invalid.';
              break;
            case 'weak-password':
              errorMessage = 'The password is too weak.';
              break;
            case 'operation-not-allowed':
              errorMessage = 'Email/password accounts are not enabled.';
              break;
            case 'provider-already-linked':
              errorMessage = 'This email is already linked to another account.';
              break;
            case 'credential-already-in-use':
              errorMessage = 'This phone number is already linked to another account.';
              break;
            case 'invalid-verification-code':
              errorMessage = 'The verification code was invalid. Please go back and verify your phone again.';
              break;
            case 'invalid-verification-id':
              errorMessage = 'Verification session expired. Please go back and verify your phone again.';
              break;
            default:
              errorMessage = e.message ?? 'Authentication failed.';
          }
        }
        
        _showVerificationResult(false, errorMessage);
      }
    } else {
      // Need to verify phone first
      await _initiatePhoneVerification();
    }
  }
  
  // Upload face verification selfie as profile picture to Firebase Storage
  Future<String?> _uploadProfileImage(String uid, Uint8List imageBytes) async {
    try {
      AppLogger.d('Uploading profile image to UserImages/$uid/displayimage.jpg');
      
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('UserImages')
          .child(uid)
          .child('displayimage.jpg');
      
      // Upload the image bytes with JPEG content type
      final uploadTask = await storageRef.putData(
        imageBytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      
      // Get the download URL
      final downloadURL = await uploadTask.ref.getDownloadURL();
      AppLogger.d('Profile image uploaded successfully: $downloadURL');
      
      return downloadURL;
    } catch (e) {
      AppLogger.d('Error uploading profile image: $e');
      // Don't fail registration if image upload fails
      return null;
    }
  }
  
  // Save user data to Firestore
  Future<void> _saveUserDataToFirestore(User user) async {
    try {
      // Get the final ID number from the text controller (user may have edited it)
      final String? registrationNo = _controller.idNumberController.text.trim().isNotEmpty 
          ? _controller.idNumberController.text.trim() 
          : _controller.idNumber;
      
      // Upload face verification selfie as profile picture
      String? photoURL;
      if (_controller.selfieImage != null) {
        photoURL = await _uploadProfileImage(user.uid, _controller.selfieImage!);
      }
      
      // Update Firebase Auth profile with display name and photo URL
      await user.updateDisplayName('${_controller.firstName} ${_controller.lastName}');
      if (photoURL != null) {
        await user.updatePhotoURL(photoURL);
        AppLogger.d('Firebase Auth profile updated with photoURL');
      }
      
      // Create the user document with user details from controller
      await FirebaseFirestore.instance.collection('User').doc(user.uid).set({
        'displayName': '${_controller.firstName} ${_controller.lastName}',
        'photoURL': photoURL, // Profile picture from face verification selfie
        'fullName': '${_controller.firstName} ${_controller.lastName}',
        'firstName': _controller.firstName,
        'middleName': '', // No middle name in signup flow
        'lastName': _controller.lastName,
        'contactNumber': _controller.formattedPhoneNumber,
        'email': _controller.email,
        'gender': _controller.gender,
        'birthdate': _controller.birthdate != null ? Timestamp.fromDate(_controller.birthdate!) : null,
        'RegistrationNo': registrationNo, // PRC Registration Number (from OCR or manually edited)
        'specialty': _controller.selectedSpecialties, // List of selected specialties
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'role': 'buyer', // Default role
      });
      
      // Create UserLookup document for fast phone/email lookup during login
      await FirebaseFirestore.instance.collection('UserLookup').doc(user.uid).set({
        'contactNumber': _controller.formattedPhoneNumber,
        'email': _controller.email,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      AppLogger.d('User and UserLookup documents created successfully');
    } catch (e) {
      AppLogger.d('Error saving user data: $e');
      rethrow; // Re-throw to handle in the calling function
    }
  }
  
  // Show email verification dialog
  void _showEmailVerificationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: AppColors.surface,
          child: Padding(
            padding: const EdgeInsets.all(30.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: Icon(
                    Icons.email_outlined,
                    size: 40,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Email Verification Sent!',
                  style: AppTextStyles.headlineSmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Please check your inbox and verify your email address before logging in.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.grey600,
                  ),
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Got it',
                      style: AppTextStyles.buttonLarge,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Verify OTP code entered by user
  // This does NOT sign in — it only creates and stores the credential.
  // The actual sign-in happens in _processSubmission() to avoid creating
  // a separate phone-only account.
  Future<void> _verifyOtp() async {
    final String otpCode = _otpController.text.trim();
    
    if (otpCode.length != 6) {
      setState(() {
        _verificationFailed = true;
        _errorMessage = 'Please enter a 6-digit code';
      });
      return;
    }
    
    // Check verification ID
    if (_controller.verificationId == null || _controller.verificationId!.isEmpty) {
      setState(() {
        _verificationFailed = true;
        _errorMessage = 'Verification session expired. Please resend code.';
      });
      return;
    }
    
    // Show loading state
    setState(() {
      _controller.isVerificationInProgress = true;
      _verificationFailed = false;
      _errorMessage = '';
    });
    
    try {
      AppLogger.d('Creating phone credential from OTP code...');
      
      // Check if this is a test verification (simulated flow)
      final bool isTestVerification =
          _controller.verificationId!.startsWith('test_verification_id_');

      if (isTestVerification) {
        // For test phone numbers, skip credential creation.
        // _processSubmission() will use the email-only fallback path.
        _controller.phoneCredential = null;
        AppLogger.d('Test verification detected - skipping credential creation');
      } else {
        // Create phone auth credential with verification ID and SMS code.
        // We do NOT call signInWithCredential here to avoid creating a
        // phone-only auth account. The credential will be used during
        // account creation to sign in and then link email/password.
        final PhoneAuthCredential credential = PhoneAuthProvider.credential(
          verificationId: _controller.verificationId!,
          smsCode: otpCode,
        );

        // Store the credential for use during final account creation
        _controller.phoneCredential = credential;
        AppLogger.d('Phone credential created and stored - ready for account creation');
      }
      
      // Update verification status
      if (mounted) {
        setState(() {
          _controller.isContactNumberVerified = true;
          _controller.isVerificationInProgress = false;
          _showOtpInput = false; // Hide OTP input
        });
      }
    } catch (e) {
      AppLogger.d('Unexpected error creating phone credential: $e');
      if (mounted) {
        setState(() {
          _controller.isVerificationInProgress = false;
          _verificationFailed = true;
          _errorMessage = 'An error occurred. Please try again.';
        });
      }
    }
  }
  
  // Resend verification code
  Future<void> _resendCode() async {
    AppLogger.d('Resending verification code...');
    
    // Reset state
    setState(() {
      _otpController.clear();
      _verificationFailed = false;
      _errorMessage = '';
      _showOtpInput = false; // Go back to initial state
    });
    
    // Restart verification process
    await _initiatePhoneVerification();
  }

  // Initiate Firebase phone verification
  Future<void> _initiatePhoneVerification() async {
    if (_controller.isVerificationInProgress) return;
    
    if (mounted) {
      setState(() {
        _controller.isVerificationInProgress = true;
      });
    }

    final formattedNumber = _controller.formattedPhoneNumber;

    try {
      // First check if the phone number format is valid
      if (!formattedNumber.startsWith('+')) {
        if (mounted) {
          setState(() {
            _controller.isVerificationInProgress = false;
          });
          _showVerificationResult(false, 'Invalid phone number format. Phone number must include country code.');
        }
        return;
      }
      
      AppLogger.d('Starting Firebase phone verification for: $formattedNumber');
      
      // Check if this is a test phone number for development
      if (_isTestPhoneNumber(formattedNumber)) {
        AppLogger.d('Using test phone number - simulating verification');
        await _simulateTestVerification();
        return;
      }
      
      // Add a small delay to ensure proper network connectivity
      await Future.delayed(const Duration(milliseconds: 500));
      
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: formattedNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-verification completed (usually happens on Android)
          AppLogger.d('verificationCompleted callback triggered!');
          AppLogger.d('Credential received: ${credential.toString()}');
          if (mounted) {
            setState(() {
              _controller.isContactNumberVerified = true;
              _controller.isVerificationInProgress = false;
              _controller.phoneCredential = credential;
            });
            
            // Show success message but don't automatically complete registration
            _showVerificationResult(true, 'Your phone number has been automatically verified! You can now complete your registration.');
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          AppLogger.d('verificationFailed callback triggered!');
          AppLogger.d('Phone verification failed: ${e.code} - ${e.message}');
          if (mounted) {
            setState(() {
              _controller.isVerificationInProgress = false;
            });
            
            AppLogger.d('Firebase phone verification failed: ${e.code} - ${e.message}');
            
            String errorMessage = 'Verification failed. Please try again.';
            
            // Handle specific reCAPTCHA errors
            if (e.code == 'web-internal-error' && e.message != null && e.message!.contains('reCAPTCHA')) {
              errorMessage = 'reCAPTCHA service is temporarily unavailable. Please check your internet connection and try again.';
            } else if (e.code == 'invalid-phone-number') {
              errorMessage = 'The phone number entered is invalid.';
            } else if (e.code == 'too-many-requests') {
              errorMessage = 'Too many attempts. Please try again later.';
            } else if (e.code == 'app-not-authorized') {
              errorMessage = 'App not authorized for phone authentication. Please check Firebase configuration.';
            } else if (e.code == 'web-internal-error') {
              errorMessage = 'Service temporarily unavailable. Please check your internet connection and try again.';
            } else {
              // Include error code in message to help diagnose the issue
              errorMessage = 'Verification failed (${e.code}). Please try again or contact support.';
            }
            
            _showVerificationResult(false, errorMessage);
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          AppLogger.d('codeSent callback triggered!');
          AppLogger.d('SMS code sent to $formattedNumber. verificationId: ${verificationId.substring(0, 5)}...');
          
          if (verificationId.isNotEmpty) {
            if (mounted) {
              setState(() {
                _controller.verificationId = verificationId;
                _controller.resendToken = resendToken; // Store for potential resend
                _controller.isVerificationInProgress = false;
                _showOtpInput = true; // Show OTP input section
                _verificationFailed = false; // Reset error state
                _errorMessage = '';
              });
              AppLogger.d('Showing OTP input section...');
              // Focus on the OTP text field after a short delay
              Future.delayed(const Duration(milliseconds: 300), () {
                if (mounted) {
                  _otpFocusNode.requestFocus();
                }
              });
            }
          } else {
            AppLogger.d('Empty verification ID received');
            if (mounted) {
              setState(() {
                _controller.isVerificationInProgress = false;
              });
              _showVerificationResult(false, 'Failed to send verification code. Please try again.');
            }
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          AppLogger.d('codeAutoRetrievalTimeout callback triggered!');
          AppLogger.d('Auto-retrieval timeout for verificationId: ${verificationId.substring(0, 5)}...');
          // Only update if not null/empty
          if (verificationId.isNotEmpty) {
            _controller.verificationId = verificationId;
          }
        },
        timeout: const Duration(seconds: 120),
      );
    } catch (e) {
      AppLogger.d('Unexpected error during phone verification: $e');
      if (mounted) {
        setState(() {
          _controller.isVerificationInProgress = false;
        });
        _showVerificationResult(false, 'An error occurred: $e. Please try again.');
      }
    }
  }

  // Check if phone number is a test number for development
  bool _isTestPhoneNumber(String phoneNumber) {
    // Test phone numbers for development (including your actual number)
    final testNumbers = [
      '+1555123456', // US test number
      '+639999999999', // Philippines test number
      '+639123456789', // Philippines test number
      '+639000000000', // Philippines test number
      '+639226537982', // Your actual number for testing
    ];
    
    return testNumbers.contains(phoneNumber);
  }

  // Simulate test phone verification for development
  Future<void> _simulateTestVerification() async {
    AppLogger.d('Simulating test phone verification');
    
    // Simulate loading time
    await Future.delayed(const Duration(seconds: 2));
    
    if (mounted) {
      setState(() {
        _controller.isVerificationInProgress = false;
        _controller.verificationId = 'test_verification_id_${DateTime.now().millisecondsSinceEpoch}';
        _showOtpInput = true; // Show OTP input section
        _verificationFailed = false;
        _errorMessage = '';
      });
      
      AppLogger.d('Test verification simulated, showing OTP input section');
      // Focus on the OTP text field
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          _otpFocusNode.requestFocus();
        }
      });
    }
  }

  // Show loading overlay during registration completion
  void _showLoadingOverlay(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                  strokeWidth: 3,
                ),
                const SizedBox(height: 24),
                Text(
                  message,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showVerificationResult(bool isSuccess, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: AppColors.surface,
          child: Padding(
            padding: const EdgeInsets.all(30.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: (isSuccess ? AppColors.success : AppColors.error).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: Icon(
                    isSuccess ? Icons.check_circle : Icons.error,
                    size: 40,
                    color: isSuccess ? AppColors.success : AppColors.error,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  isSuccess ? 'Verified!' : 'Verification Failed',
                  style: AppTextStyles.headlineSmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.grey600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      // Don't automatically proceed with account creation here
                      // The verification result dialog is just for showing status
                      // Account creation only happens when user clicks "Complete Registration" button
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSuccess ? AppColors.success : AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      isSuccess ? 'Continue' : 'Retry Verification',
                      style: AppTextStyles.buttonLarge,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}