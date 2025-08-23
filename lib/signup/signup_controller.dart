import 'package:flutter/material.dart';

class SignupController {
  // Personal details (Step 1)
  final TextEditingController firstNameController = TextEditingController();
  final TextEditingController lastNameController = TextEditingController();
  final TextEditingController contactNumberController = TextEditingController();
  String? selectedGender;
  DateTime? selectedBirthdate;
  
  // OTP verification state for contact number
  bool isContactNumberVerified = false;
  bool isVerifyButtonEnabled = false;
  final List<TextEditingController> otpControllers = List.generate(6, (index) => TextEditingController());
  final List<FocusNode> otpFocusNodes = List.generate(6, (index) => FocusNode());
  
  // Firebase verification state
  String? verificationId;
  bool isVerificationInProgress = false;
  
  // Account credentials (Step 2)
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();
  
  // Form keys for validation
  final formKeyStep1 = GlobalKey<FormState>();
  final formKeyStep2 = GlobalKey<FormState>();
  final formKeyStep3 = GlobalKey<FormState>();
  
  // Form validation errors
  String? step1GenderError;
  String? step1BirthdateError;
  
  // Password validation
  bool hasUppercase = false;
  bool hasLowercase = false;
  bool hasNumber = false;
  bool hasSpecialCharacter = false;
  bool hasMinLength = false;
  
  // Helper method to convert Philippine mobile number to international format
  String formatPhoneNumberForFirebase(String phoneNumber) {
    if (phoneNumber.startsWith('09') && phoneNumber.length == 11) {
      return '+63${phoneNumber.substring(1)}';
    }
    return phoneNumber;
  }
  
  // Getter to access the formatted phone number for Firebase operations
  String get formattedPhoneNumber => formatPhoneNumberForFirebase(contactNumberController.text);
  
  void validatePassword() {
    final password = passwordController.text;
    hasUppercase = password.contains(RegExp(r'[A-Z]'));
    hasLowercase = password.contains(RegExp(r'[a-z]'));
    hasNumber = password.contains(RegExp(r'[0-9]'));
    hasSpecialCharacter = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
    hasMinLength = password.length >= 8;
  }
  
  void dispose() {
    // Dispose all controllers
    firstNameController.dispose();
    lastNameController.dispose();
    contactNumberController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    
    // Dispose OTP controllers and focus nodes
    for (var controller in otpControllers) {
      controller.dispose();
    }
    for (var focusNode in otpFocusNodes) {
      focusNode.dispose();
    }
  }
}
