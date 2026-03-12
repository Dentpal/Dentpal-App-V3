// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'signup_controller.dart';
import 'package:dentpal/core/app_theme/index.dart';

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
  
  // FocusNodes for field traversal
  final FocusNode _firstNameFocus = FocusNode();
  final FocusNode _lastNameFocus = FocusNode();
  final FocusNode _contactNumberFocus = FocusNode();
  
  // Track if phone number check is in progress
  bool _isCheckingPhoneNumber = false;
  String? _phoneNumberError;
  
  @override
  void dispose() {
    _firstNameFocus.dispose();
    _lastNameFocus.dispose();
    _contactNumberFocus.dispose();
    super.dispose();
  }
  
  // Check if phone number already exists in UserLookup collection
  Future<bool> _checkPhoneNumberExists(String phoneNumber) async {
    if (phoneNumber.isEmpty || !phoneNumber.startsWith('09') || phoneNumber.length != 11) {
      return false;
    }
    
    try {
      // Format phone number to international format for checking
      final formattedNumber = _controller.formatPhoneNumberForFirebase(phoneNumber);
      
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
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      child: Form(
        key: _controller.formKeyStep1,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(
            left: 30.0,
            right: 30.0,
            top: 30.0
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            Text(
              'First Name',
              style: AppTextStyles.labelLarge.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            TextFormField(
              controller: _controller.firstNameController,
              focusNode: _firstNameFocus,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) {
                FocusScope.of(context).requestFocus(_lastNameFocus);
              },
              style: AppTextStyles.inputText,
              decoration: InputDecoration(
                hintText: 'Enter your first name',
                hintStyle: AppTextStyles.inputHint,
                filled: true,
                fillColor: AppColors.grey50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary, width: 2),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.error, width: 2),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.error, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your first name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            // Last Name field
            Text(
              'Last Name',
              style: AppTextStyles.labelLarge.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            TextFormField(
              controller: _controller.lastNameController,
              focusNode: _lastNameFocus,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) {
                FocusScope.of(context).requestFocus(_contactNumberFocus);
              },
              style: AppTextStyles.inputText,
              decoration: InputDecoration(
                hintText: 'Enter your last name',
                hintStyle: AppTextStyles.inputHint,
                filled: true,
                fillColor: AppColors.grey50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary, width: 2),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.error, width: 2),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.error, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your last name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            // Contact Number field
            Text(
              'Contact Number',
              style: AppTextStyles.labelLarge.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            TextFormField(
              controller: _controller.contactNumberController,
              focusNode: _contactNumberFocus,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              style: AppTextStyles.inputText,
              maxLength: 11, // Limit to 11 digits
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly, // Only allow digits
                LengthLimitingTextInputFormatter(11), // Hard limit to 11 characters
              ],
              onChanged: (value) {
                // Enable or disable verification button based on input format
                setState(() {
                  _controller.isVerifyButtonEnabled = value.startsWith('09') && value.length == 11;
                  _phoneNumberError = null; // Clear error when user types
                });
              },
              decoration: InputDecoration(
                hintText: '09XXXXXXXXX',
                hintStyle: AppTextStyles.inputHint,
                filled: true,
                fillColor: AppColors.grey50,
                counterText: '', // Hide the character counter
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary, width: 2),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.error, width: 2),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.error, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
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
            const SizedBox(height: 16),
            
            // Gender field
            Text(
              'Gender',
              style: AppTextStyles.labelLarge.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AppColors.grey50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          title: Text('Male', style: AppTextStyles.bodyMedium),
                          value: 'Male',
                          groupValue: _controller.selectedGender,
                          activeColor: AppColors.primary,
                          onChanged: (value) {
                            setState(() {
                              _controller.selectedGender = value;
                            });
                          },
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          title: Text('Female', style: AppTextStyles.bodyMedium),
                          value: 'Female',
                          groupValue: _controller.selectedGender,
                          activeColor: AppColors.primary,
                          onChanged: (value) {
                            setState(() {
                              _controller.selectedGender = value;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  RadioListTile<String>(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    title: Text('Rather not say', style: AppTextStyles.bodyMedium),
                    value: 'Not Specified',
                    groupValue: _controller.selectedGender,
                    activeColor: AppColors.primary,
                    onChanged: (value) {
                      setState(() {
                        _controller.selectedGender = value;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Birthdate field
            Text(
              'Birthdate',
              style: AppTextStyles.labelLarge.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
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
                        color: AppColors.surface,
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
                                brightness: Brightness.light,
                                textTheme: CupertinoTextThemeData(
                                  dateTimePickerTextStyle: TextStyle(color: AppColors.onSurface, fontSize: 22),
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
                              child: ElevatedButton(
                                onPressed: () {
                                  Navigator.of(context).pop(tempPicked);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: AppColors.onPrimary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text('Select'),
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
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.grey50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _controller.selectedBirthdate == null
                          ? 'Select your birthdate'
                          : '${_controller.selectedBirthdate!.month.toString().padLeft(2, '0')}/'
                            '${_controller.selectedBirthdate!.day.toString().padLeft(2, '0')}/'
                            '${_controller.selectedBirthdate!.year}',
                      style: _controller.selectedBirthdate == null 
                          ? AppTextStyles.inputHint
                          : AppTextStyles.inputText,
                    ),
                    const Icon(Icons.calendar_today, color: AppColors.grey400),
                  ],
                ),
              ),
            ),
            if (_controller.step1BirthdateError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  _controller.step1BirthdateError!,
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
                ),
              ),
            const SizedBox(height: 20),
            
            // Proceed button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isCheckingPhoneNumber ? null : _validateAndProceed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: _isCheckingPhoneNumber
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.onPrimary),
                        ),
                      )
                    : Text(
                        'Proceed',
                        style: AppTextStyles.buttonLarge,
                      ),
              ),
            ),
            const SizedBox(height: 8),
            
            // Login link
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: AppTextStyles.bodyMedium,
                  children: [
                    TextSpan(
                      text: "Already have an account? ",
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.grey600,
                      ),
                    ),
                    TextSpan(
                      text: 'Log In',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.accent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Add extra space at the bottom to account for home indicator
            SizedBox(height: MediaQuery.of(context).padding.bottom > 0 ? 40 : 20),
          ],
        ),
      ),
    ),
    );
  }
  
  void _validateAndProceed() async {
    final valid = _controller.formKeyStep1.currentState?.validate() ?? false;
    String? birthdateError;
    
    if (_controller.selectedBirthdate == null) {
      birthdateError = 'Please select your birthdate';
    }
    
    setState(() {
      _controller.step1GenderError = null;
      _controller.step1BirthdateError = birthdateError;
    });
    
    if (valid && birthdateError == null) {
      // Check if phone number already exists in UserLookup
      setState(() {
        _isCheckingPhoneNumber = true;
        _phoneNumberError = null;
      });
      
      final phoneExists = await _checkPhoneNumberExists(_controller.contactNumber);
      
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
      _controller.step1GenderError = null;
      _controller.step1BirthdateError = null;
      widget.onNext();
    }
  }
}
