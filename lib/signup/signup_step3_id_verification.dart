// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'signup_controller.dart';
import 'package:dentpal/login_page.dart';

class SignupStep3IdVerification extends StatefulWidget {
  final SignupController controller;
  final VoidCallback onBack;

  const SignupStep3IdVerification({
    super.key,
    required this.controller,
    required this.onBack,
  });

  @override
  State<SignupStep3IdVerification> createState() => _SignupStep3IdVerificationState();
}

class _SignupStep3IdVerificationState extends State<SignupStep3IdVerification> {
  // Quick access to controller
  SignupController get _controller => widget.controller;
  
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(child: Text('Step 3: ID Verification', style: TextStyle(fontSize: 24))),
            const SizedBox(height: 20),
            const Center(child: Text('This section will be implemented later')),
            // Add sufficient space before the buttons
            const SizedBox(height: 200), // This gives content space to scroll
            if (_controller.isContactNumberVerified)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Color(0xFF43A047)),
                    const SizedBox(width: 8),
                    const Text(
                      'Verified',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF43A047)
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 40),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: widget.onBack,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _processSubmission,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF43A047),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _controller.isVerificationInProgress
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                      : Text(_controller.isContactNumberVerified ? 'Complete Registration' : 'Submit'),
                  ),
                ),
              ],
            ),
            // Add padding at the bottom to prevent overlap with system UI on smaller screens
            const SizedBox(height: 24),
          ],
        ),
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
            print('Successfully linked phone number to account');
          } catch (linkError) {
            // If linking fails, we'll still continue with the registration
            // but log the error for debugging
            print('Error linking phone credential: $linkError');
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
    } catch (e) {
      print('Error saving user data: $e');
      throw e; // Re-throw to handle in the calling function
    }
  }
  
  // Show email verification dialog
  void _showEmailVerificationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: const Icon(
                    Icons.email_outlined,
                    size: 40,
                    color: Color(0xFF43A047),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Email Verification Sent!',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Please check your inbox and verify your email address before logging in.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF43A047),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('OK'),
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
      
      // Print for debugging
      print('Attempting to verify phone number: $formattedNumber');
      
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
          
          // Print detailed error for debugging
          print('Firebase phone verification failed: ${e.code} - ${e.message}');
          
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
          print('Verification code sent to $formattedNumber. verificationId: ${verificationId.substring(0, 5)}...');
          
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
      print('Unexpected error during phone verification: $e');
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
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                // Placeholder icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: const Icon(
                    Icons.phone_android,
                    size: 40,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Enter your OTP',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please enter the 6-digit code we sent to $formattedNumber to continue.',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(6, (index) {
                    return SizedBox(
                      width: 50,
                      height: 50,
                      child: TextFormField(
                        controller: _controller.otpControllers[index],
                        focusNode: _controller.otpFocusNodes[index],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        maxLength: 1,
                        style: const TextStyle(fontSize: 20),
                        decoration: InputDecoration(
                          counterText: '',
                          contentPadding: EdgeInsets.zero,
                          border: OutlineInputBorder(
                            borderSide: const BorderSide(color: Colors.grey),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: Colors.blue, width: 2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onChanged: (value) {
                          if (value.length == 1 && index < 5) {
                            _controller.otpFocusNodes[index + 1].requestFocus();
                          }
                        },
                      ),
                    );
                  }),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _verifyOtp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF43A047),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Verify'),
                  ),
                ),
                // add margin top
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _resendOtp,
                    child: const Text('Didn\'t receive code? Resend'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFB71C1C),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Cancel'),
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
      print('Attempting to resend OTP to $formattedNumber');
      
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
          print('Resend verification failed: ${e.code} - ${e.message}');
          setState(() {
            _controller.isVerificationInProgress = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to resend code: ${e.message}')),
          );
        },
        codeSent: (String verificationId, int? resendToken) {
          print('Resend successful. New code sent.');
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
      print('Error resending OTP: $e');
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
      _showVerificationResult(true, 'Your phone number has been successfully verified! Click Continue to complete your registration.');
      
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF43A047)),
                  strokeWidth: 3,
                ),
                const SizedBox(height: 24),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 16,
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: (isSuccess ? const Color(0xFF43A047) : const Color(0xFFB71C1C)).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: Icon(
                    isSuccess ? Icons.check_circle : Icons.cancel,
                    size: 40,
                    color: isSuccess ? const Color(0xFF43A047) : const Color(0xFFB71C1C),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  isSuccess ? 'Verified!' : 'Verification Failed',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
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
                      backgroundColor: isSuccess ? const Color(0xFF43A047) : null,
                      foregroundColor: isSuccess ? Colors.white : null,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(isSuccess ? 'Continue' : 'Try Again'),
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
