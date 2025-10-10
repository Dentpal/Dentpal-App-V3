// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'signup_controller.dart';
import 'package:dentpal/login_page.dart';
import 'package:dentpal/core/app_theme/index.dart';
import 'package:dentpal/utils/app_logger.dart';

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
  
  @override
  Widget build(BuildContext context) {
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
                const SizedBox(height: 16),
                if (_controller.isContactNumberVerified)
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
                  onPressed: _processSubmission,
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
                        _controller.isContactNumberVerified ? 'Complete Registration' : 'Verify Phone',
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
    if (_controller.isContactNumberVerified) {
      // Phone already verified, show loading overlay and start account creation
      _showLoadingOverlay(context, 'Completing registration...');
      
      try {
        // Create the Firebase auth user account with email and password
        final UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _controller.email,
          password: _controller.password,
        );
        
        // Get the created user
        final User? user = userCredential.user;
        if (user == null) {
          throw Exception('User creation failed');
        }
        
        // Link phone credential to the email account if we have verified a phone
        if (_controller.phoneCredential != null) {
          try {
            // Link phone authentication to this account
            await user.linkWithCredential(_controller.phoneCredential!);
            AppLogger.d('Successfully linked phone number to account');
          } catch (linkError) {
            // If linking fails, we'll still continue with the registration
            // but log the error for debugging
            AppLogger.d('Error linking phone credential: $linkError');
            // We won't throw here to allow the registration to complete
          }
        }
        
        // Send email verification
        await user.sendEmailVerification();
        
        // Save user data to Firestore
        await _saveUserDataToFirestore(user);
        
        // Sign out the user so they have to verify email before logging in
        await FirebaseAuth.instance.signOut();
        
        // Remove loading overlay
        if (mounted) {
          Navigator.of(context).pop();
        }
        
        // Navigate to login page
        if (mounted) {
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
  
  // Save user data to Firestore
  Future<void> _saveUserDataToFirestore(User user) async {
    try {
      // Create the user document with user details from controller
      await FirebaseFirestore.instance.collection('User').doc(user.uid).set({
        'displayName': '${_controller.firstName} ${_controller.lastName}',
        'photoURL': null, // Will be updated when the user adds a profile photo
        'fullName': '${_controller.firstName} ${_controller.lastName}',
        'contactNumber': _controller.formattedPhoneNumber,
        'email': _controller.email,
        'gender': _controller.gender,
        'birthdate': _controller.birthdate != null ? Timestamp.fromDate(_controller.birthdate!) : null,
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

  // Initiate Firebase phone verification
  Future<void> _initiatePhoneVerification() async {
    if (_controller.isVerificationInProgress) return;
    
    setState(() {
      _controller.isVerificationInProgress = true;
    });

    final formattedNumber = _controller.formattedPhoneNumber;

    try {
      // First check if the phone number format is valid
      if (!formattedNumber.startsWith('+')) {
        setState(() {
          _controller.isVerificationInProgress = false;
        });
        _showVerificationResult(false, 'Invalid phone number format. Phone number must include country code.');
        return;
      }
      
      AppLogger.d('Attempting to verify phone number: $formattedNumber');
      
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: formattedNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-verification completed (usually happens on Android)
          setState(() {
            _controller.isContactNumberVerified = true;
            _controller.isVerificationInProgress = false;
          });
          _showVerificationResult(true, 'Your phone number has been automatically verified!');
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() {
            _controller.isVerificationInProgress = false;
          });
          
          AppLogger.d('Firebase phone verification failed: ${e.code} - ${e.message}');
          
          String errorMessage = 'Verification failed. Please try again.';
          if (e.code == 'invalid-phone-number') {
            errorMessage = 'The phone number entered is invalid.';
          } else if (e.code == 'too-many-requests') {
            errorMessage = 'Too many attempts. Please try again later.';
          } else if (e.code == 'app-not-authorized') {
            errorMessage = 'App not authorized for phone authentication. Please check Firebase configuration.';
          } else {
            // Include error code in message to help diagnose the issue
            errorMessage = 'Verification failed (${e.code}). Please try again or contact support.';
          }
          
          _showVerificationResult(false, errorMessage);
        },
        codeSent: (String verificationId, int? resendToken) {
          AppLogger.d('Verification code sent to $formattedNumber. verificationId: ${verificationId.substring(0, 5)}...');
          
          if (verificationId.isNotEmpty) {
            setState(() {
              _controller.verificationId = verificationId;
              _controller.resendToken = resendToken; // Store for potential resend
              _controller.isVerificationInProgress = false;
            });
            _showOtpModal();
          } else {
            setState(() {
              _controller.isVerificationInProgress = false;
            });
            _showVerificationResult(false, 'Failed to send verification code. Please try again.');
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          // Only update if not null/empty
          if (verificationId.isNotEmpty) {
            _controller.verificationId = verificationId;
          }
        },
        timeout: const Duration(seconds: 120),
      );
    } catch (e) {
      AppLogger.d('Unexpected error during phone verification: $e');
      setState(() {
        _controller.isVerificationInProgress = false;
      });
      _showVerificationResult(false, 'An error occurred: $e. Please try again.');
    }
  }

  void _showOtpModal() {
    // Prevent multiple OTP modals from stacking
    if (ModalRoute.of(context)?.isCurrent != true) return;

    // Clear previous OTP entries
    for (var controller in _controller.otpControllers) {
      controller.clear();
    }

    final formattedNumber = _controller.formattedPhoneNumber;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.6,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(30.0),
            child: Column(
              children: [
                // Handle bar
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.grey300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                
                // Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: Icon(
                    Icons.sms,
                    size: 40,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 24),
                
                Text(
                  'Enter Verification Code',
                  style: AppTextStyles.headlineSmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please enter the 6-digit code we sent to\n$formattedNumber',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.grey600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                
                // OTP Input fields
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(6, (index) {
                    return Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: AppColors.grey50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.grey200),
                      ),
                      child: TextFormField(
                        controller: _controller.otpControllers[index],
                        focusNode: _controller.otpFocusNodes[index],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        maxLength: 1,
                        style: AppTextStyles.headlineSmall.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          counterText: '',
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (value) {
                          if (value.isNotEmpty && index < 5) {
                            _controller.otpFocusNodes[index + 1].requestFocus();
                          }
                          if (value.isEmpty && index > 0) {
                            _controller.otpFocusNodes[index - 1].requestFocus();
                          }
                        },
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 32),
                
                // Verify button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _controller.isVerificationInProgress ? null : _verifyOtp,
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
                            strokeWidth: 2.5,
                          ),
                        )
                      : Text(
                          'Verify Code',
                          style: AppTextStyles.buttonLarge,
                        ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Resend button
                TextButton(
                  onPressed: _controller.isVerificationInProgress ? null : _resendOtp,
                  child: RichText(
                    text: TextSpan(
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                      children: [
                        TextSpan(
                          text: "Didn't receive the code? ",
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        TextSpan(
                          text: 'Resend',
                          style: TextStyle(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
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

  // Resend OTP method
  Future<void> _resendOtp() async {
    setState(() {
      _controller.isVerificationInProgress = true;
    });

    final formattedNumber = _controller.formattedPhoneNumber;

    try {
      AppLogger.d('Attempting to resend OTP to $formattedNumber');
      
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: formattedNumber,
        forceResendingToken: _controller.resendToken,
        verificationCompleted: (PhoneAuthCredential credential) async {
          setState(() {
            _controller.isContactNumberVerified = true;
            _controller.isVerificationInProgress = false;
            _controller.phoneCredential = credential;
          });
          Navigator.of(context).pop(); // Close OTP modal
          _showVerificationResult(true, 'Your phone number has been automatically verified!');
        },
        verificationFailed: (FirebaseAuthException e) {
          AppLogger.d('Resend verification failed: ${e.code} - ${e.message}');
          setState(() {
            _controller.isVerificationInProgress = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to resend code: ${e.message}')),
          );
        },
        codeSent: (String verificationId, int? resendToken) {
          AppLogger.d('Resend successful. New code sent.');
          setState(() {
            _controller.verificationId = verificationId;
            _controller.resendToken = resendToken;
            _controller.isVerificationInProgress = false;
          });
          
          // Clear existing OTP inputs
          for (var controller in _controller.otpControllers) {
            controller.clear();
          }
          
          // Focus on first OTP field
          if (_controller.otpFocusNodes.isNotEmpty) {
            _controller.otpFocusNodes.first.requestFocus();
          }
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Verification code resent')),
          );
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _controller.verificationId = verificationId;
        },
        timeout: const Duration(seconds: 120),
      );
    } catch (e) {
      AppLogger.d('Error resending OTP: $e');
      setState(() {
        _controller.isVerificationInProgress = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error resending code: $e')),
      );
    }
  }

  void _verifyOtp() async {
    final otp = _controller.otpControllers.map((controller) => controller.text).join();
    
    if (otp.length != 6) {
      _showVerificationResult(false, 'Please enter all 6 digits');
      return;
    }

    if (_controller.verificationId == null || _controller.verificationId!.isEmpty) {
      _showVerificationResult(false, 'Verification ID not found. Please try again.');
      return;
    }

    setState(() {
      _controller.isVerificationInProgress = true;
    });

    try {
      // Create a PhoneAuthCredential with the code
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _controller.verificationId!,
        smsCode: otp,
      );

      // Just store the credential for later use rather than signing in now
      _controller.phoneCredential = credential;
      
      setState(() {
        _controller.isVerificationInProgress = false;
        _controller.isContactNumberVerified = true;
      });
      
      // Close OTP modal and show success message
      Navigator.of(context).pop();
      _showVerificationResult(true, 'Your phone number has been successfully verified! Click Complete Registration to finish your account setup.');
      
    } on FirebaseAuthException catch (e) {
      setState(() {
        _controller.isVerificationInProgress = false;
      });
      String errorMessage = 'The OTP you entered is incorrect. Please try again.';
      if (e.code == 'invalid-verification-code') {
        errorMessage = 'The OTP you entered is incorrect. Please try again.';
      } else if (e.code == 'session-expired') {
        errorMessage = 'The OTP has expired. Please request a new one.';
      }
      _showVerificationResult(false, errorMessage);
    } catch (e) {
      _showVerificationResult(false, 'An error occurred. Please try again.');
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
                      if (isSuccess && _controller.isContactNumberVerified) {
                        // If verification was successful, automatically proceed with account creation
                        _processSubmission();
                      }
                      // If verification failed, just close dialog and allow retry
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
                      isSuccess ? 'Complete' : 'Try Again',
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
