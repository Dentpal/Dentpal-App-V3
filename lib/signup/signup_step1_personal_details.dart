// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'signup_controller.dart';

class SignupStep1PersonalDetails extends StatefulWidget {
  final SignupController controller;
  final VoidCallback onNext;

  const SignupStep1PersonalDetails({
    super.key,
    required this.controller,
    required this.onNext,
  });

  @override
  State<SignupStep1PersonalDetails> createState() => _SignupStep1PersonalDetailsState();
}

class _SignupStep1PersonalDetailsState extends State<SignupStep1PersonalDetails> {
  // Quick access to controller
  SignupController get _controller => widget.controller;
  
  @override
  Widget build(BuildContext context) {
    return Form(
      key: _controller.formKeyStep1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Personal Details',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _controller.firstNameController,
                      cursorColor: Colors.black,
                      decoration: InputDecoration(
                        labelText: 'First Name',
                        hintText: 'Juan',
                        floatingLabelStyle: const TextStyle(color: Colors.black),
                        border: OutlineInputBorder(
                          borderSide: const BorderSide(color: Colors.black),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Colors.black),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Colors.blue, width: 2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'First name is required';
                        }
                        if (value.trim().length < 3) {
                          return 'First name must be at least 3 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _controller.lastNameController,
                      cursorColor: Colors.black,
                      decoration: InputDecoration(
                        labelText: 'Last Name',
                        hintText: 'Dela Cruz',
                        floatingLabelStyle: const TextStyle(color: Colors.black),
                        border: OutlineInputBorder(
                          borderSide: const BorderSide(color: Colors.black),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Colors.black),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Colors.blue, width: 2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Last name is required';
                        }
                        if (value.trim().length < 3) {
                          return 'Last name must be at least 3 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _controller.contactNumberController,
                            cursorColor: Colors.black,
                            keyboardType: TextInputType.phone,
                            onChanged: (value) {
                              // Remove all non-digit characters and update the field
                              final digitsOnly = value.replaceAll(RegExp(r'[^0-9]'), '');
                              if (digitsOnly != value) {
                                _controller.contactNumberController.value = TextEditingValue(
                                  text: digitsOnly,
                                  selection: TextSelection.collapsed(offset: digitsOnly.length),
                                );
                              }
                              
                              // Check if contact number is valid for verify button
                              setState(() {
                                _controller.isVerifyButtonEnabled = digitsOnly.length == 11 && digitsOnly.startsWith('09');
                              });
                            },
                            decoration: InputDecoration(
                              labelText: 'Contact Number',
                              hintText: '09123456789',
                              floatingLabelStyle: const TextStyle(color: Colors.black),
                              border: OutlineInputBorder(
                                borderSide: const BorderSide(color: Colors.black),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide: const BorderSide(color: Colors.black),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: const BorderSide(color: Colors.blue, width: 2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              suffixIcon: _controller.isContactNumberVerified 
                                ? const Icon(Icons.check_circle, color: Colors.green)
                                : null,
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Contact number is required';
                              }
                              // Value should already be digits only due to onChanged
                              if (value.length != 11) {
                                return 'Contact number must be 11 digits';
                              }
                              if (!value.startsWith('09')) {
                                return 'Contact number must start with 09';
                              }
                              if (!_controller.isContactNumberVerified) {
                                return 'Please verify your contact number';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _controller.isVerifyButtonEnabled && !_controller.isContactNumberVerified ? _initiatePhoneVerification : null,
                          style: TextButton.styleFrom(
                            foregroundColor: _controller.isVerifyButtonEnabled && !_controller.isContactNumberVerified ? Colors.blue : Colors.grey,
                            textStyle: const TextStyle(fontWeight: FontWeight.w500),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                          child: _controller.isVerificationInProgress 
                            ? const SizedBox(
                                width: 16, 
                                height: 16, 
                                child: CircularProgressIndicator(strokeWidth: 2)
                              )
                            : Text(_controller.isContactNumberVerified ? 'Verified' : 'Verify'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Gender',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: RadioListTile<String>(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Male'),
                            value: 'Male',
                            groupValue: _controller.selectedGender,
                            activeColor: Colors.blue,
                            onChanged: (value) {
                              setState(() {
                                _controller.selectedGender = value;
                              });
                            },
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<String>(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Female'),
                            value: 'Female',
                            groupValue: _controller.selectedGender,
                            activeColor: Colors.blue,
                            onChanged: (value) {
                              setState(() {
                                _controller.selectedGender = value;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    if (_controller.step1GenderError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0, left: 8.0),
                        child: Text(
                          _controller.step1GenderError!,
                          style: const TextStyle(color: Colors.red, fontSize: 13),
                        ),
                      ),
                    const SizedBox(height: 16),
                    const Text(
                      'Birthdate',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () async {
                        final now = DateTime.now();
                        final initialDate = _controller.selectedBirthdate ?? DateTime(now.year - 18, now.month, now.day);
                        final picked = await showModalBottomSheet<DateTime>(
                          context: context,
                          backgroundColor: Colors.transparent,
                          builder: (context) {
                            DateTime tempPicked = initialDate;
                            return Container(
                              height: 270,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(16),
                                  topRight: Radius.circular(16),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Expanded(
                                    child: CupertinoTheme(
                                      data: const CupertinoThemeData(
                                        brightness: Brightness.dark,
                                        textTheme: CupertinoTextThemeData(
                                          dateTimePickerTextStyle: TextStyle(color: Colors.black, fontSize: 22),
                                        ),
                                      ),
                                      child: CupertinoDatePicker(
                                        mode: CupertinoDatePickerMode.date,
                                        initialDateTime: initialDate,
                                        maximumDate: now,
                                        onDateTimeChanged: (date) {
                                          tempPicked = date;
                                        },
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 16.0),
                                    child: SizedBox(
                                      width: 180,
                                      child: TextButton(
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.green,
                                          textStyle: const TextStyle(fontWeight: FontWeight.bold),
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          shadowColor: Colors.transparent,
                                          backgroundColor: Colors.transparent,
                                        ),
                                        onPressed: () {
                                          Navigator.of(context).pop(tempPicked);
                                        },
                                        child: const Text('Select', style: TextStyle(color: Colors.green)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                        if (picked != null) {
                          setState(() {
                            _controller.selectedBirthdate = picked;
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.black, width: 1),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.white,
                        ),
                        child: Text(
                          _controller.selectedBirthdate == null
                              ? 'Select your birthdate'
                              : '${_controller.selectedBirthdate!.month.toString().padLeft(2, '0')}/'
                                '${_controller.selectedBirthdate!.day.toString().padLeft(2, '0')}/'
                                '${_controller.selectedBirthdate!.year}',
                          style: const TextStyle(fontSize: 16, color: Colors.black),
                        ),
                      ),
                    ),
                    if (_controller.step1BirthdateError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0, left: 8.0),
                        child: Text(
                          _controller.step1BirthdateError!,
                          style: const TextStyle(color: Colors.red, fontSize: 13),
                        ),
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _validateAndProceed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF43A047),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Proceed'),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  void _validateAndProceed() {
    final valid = _controller.formKeyStep1.currentState?.validate() ?? false;
    String? genderError;
    String? birthdateError;
    
    if (_controller.selectedGender == null) {
      genderError = 'Please select a gender';
    }
    if (_controller.selectedBirthdate == null) {
      birthdateError = 'Please select your birthdate';
    }
    
    setState(() {
      _controller.step1GenderError = genderError;
      _controller.step1BirthdateError = birthdateError;
    });
    
    if (valid && genderError == null && birthdateError == null) {
      _controller.step1GenderError = null;
      _controller.step1BirthdateError = null;
      widget.onNext();
    }
  }

  // Initiate Firebase phone verification
  Future<void> _initiatePhoneVerification() async {
    if (_controller.isVerificationInProgress) return;
    
    setState(() {
      _controller.isVerificationInProgress = true;
    });

    final formattedNumber = _controller.formattedPhoneNumber;

    try {
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
          
          String errorMessage = 'Verification failed. Please try again.';
          if (e.code == 'invalid-phone-number') {
            errorMessage = 'The phone number entered is invalid.';
          } else if (e.code == 'too-many-requests') {
            errorMessage = 'Too many attempts. Please try again later.';
          }
          
          _showVerificationResult(false, errorMessage);
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _controller.verificationId = verificationId;
            _controller.isVerificationInProgress = false;
          });
          _showOtpModal();
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _controller.verificationId = verificationId;
        },
        timeout: const Duration(seconds: 120),
      );
    } catch (e) {
      setState(() {
        _controller.isVerificationInProgress = false;
      });
      _showVerificationResult(false, 'An error occurred. Please try again.');
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
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        maxLength: 1,
                        decoration: InputDecoration(
                          counterText: '',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.black),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.black),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.blue, width: 2),
                          ),
                        ),
                        onChanged: (value) {
                          if (value.isNotEmpty) {
                            // Move to next field
                            if (index < 5) {
                              _controller.otpFocusNodes[index + 1].requestFocus();
                            }
                          } else {
                            // Move to previous field
                            if (index > 0) {
                              _controller.otpFocusNodes[index - 1].requestFocus();
                            }
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

  void _verifyOtp() async {
    final otp = _controller.otpControllers.map((controller) => controller.text).join();
    
    if (otp.length != 6) {
      _showVerificationResult(false, 'Please enter all 6 digits');
      return;
    }

    if (_controller.verificationId == null) {
      _showVerificationResult(false, 'Verification ID not found. Please try again.');
      return;
    }

    try {
      // Create a PhoneAuthCredential with the code
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _controller.verificationId!,
        smsCode: otp,
      );

      // Verify the credential (we won't sign in, just verify the phone number)
      final authResult = await FirebaseAuth.instance.signInWithCredential(credential);
      
      // Sign out immediately since we only want to verify the phone number
      await FirebaseAuth.instance.signOut();
      
      if (authResult.user != null) {
        Navigator.of(context).pop(); // Close OTP modal
        setState(() {
          _controller.isContactNumberVerified = true;
        });
        _showVerificationResult(true, 'Your phone number has been successfully verified!');
      } else {
        _showVerificationResult(false, 'Verification failed. Please try again.');
      }
    } on FirebaseAuthException catch (e) {
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
                      if (!isSuccess) {
                        // Wait for the dialog to close before showing the modal again
                        await Future.delayed(const Duration(milliseconds: 200));
                        if (mounted) {
                          _showOtpModal();
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSuccess ? Colors.green : Colors.red,
                      foregroundColor: Colors.white,
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
