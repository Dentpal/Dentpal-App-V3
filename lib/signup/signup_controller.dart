import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logger/logger.dart';
import 'dart:typed_data';

class SignupController {
  // Personal details (Step 1)
  final TextEditingController firstNameController = TextEditingController();
  final TextEditingController lastNameController = TextEditingController();
  final TextEditingController contactNumberController = TextEditingController();
  String? selectedGender;
  DateTime? selectedBirthdate;
  
  // ID verification (Step 3)
  String? idNumber; // Registration number from the scanned ID
  bool isIdVerified = false;
  String? idVerificationError;
  Uint8List? idFaceImage; // Temporarily store face image from ID
  
  // Face verification (Step 4)
  bool isFaceVerified = false;
  Uint8List? selfieImage; // Store the captured selfie
  String? faceVerificationError;
  
  // Logger for OCR debugging
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 5,
      lineLength: 50,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );
  
  // OTP verification state for contact number
  bool isContactNumberVerified = false;
  bool isVerifyButtonEnabled = false;
  final List<TextEditingController> otpControllers = List.generate(6, (index) => TextEditingController());
  final List<FocusNode> otpFocusNodes = List.generate(6, (index) => FocusNode());
  
  // Firebase verification state
  String? verificationId;
  bool isVerificationInProgress = false;
  PhoneAuthCredential? phoneCredential;
  int? resendToken; // Store for potential resend
  
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
    // Clean the input
    final cleanNumber = phoneNumber.trim();
    
    // Philippine mobile format
    if (cleanNumber.startsWith('09') && cleanNumber.length == 11) {
      return '+63${cleanNumber.substring(1)}';
    }
    
    // Already in international format
    if (cleanNumber.startsWith('+')) {
      return cleanNumber;
    }
    
    // Default to Philippine format if it's numeric and 10 digits (without the leading 0)
    if (cleanNumber.length == 10 && RegExp(r'^\d+$').hasMatch(cleanNumber)) {
      return '+63$cleanNumber';
    }
    
    // No conversion possible
    return '+63${cleanNumber.replaceAll(RegExp(r'[^0-9]'), '')}';
  }
  
  // Getters to access the form field values
  String get firstName => firstNameController.text.trim();
  String get lastName => lastNameController.text.trim();
  String get contactNumber => contactNumberController.text.trim();
  String get email => emailController.text.trim();
  String get password => passwordController.text;
  String get gender => selectedGender ?? '';
  DateTime? get birthdate => selectedBirthdate;
  
  // Getter to access the formatted phone number for Firebase operations
  String get formattedPhoneNumber => formatPhoneNumberForFirebase(contactNumberController.text);
  
  // OCR logging helper
  static void logOcrResult(String tag, String message) {
    _logger.i('[OCR_KYC_$tag] $message');
  }
  
  // Static cleanup for OCR service
  static void cleanupOcrService() {
    // This can be called from the main dispose method if needed
    // For now, the OCR service manages its own lifecycle
  }
  
  // Face verification methods
  void setFaceVerification(Uint8List imageBytes) {
    selfieImage = imageBytes;
    isFaceVerified = true;
    faceVerificationError = null;
    logOcrResult('FACE_VERIFICATION', 'Face verification completed successfully');
  }
  
  void clearFaceVerification() {
    selfieImage = null;
    isFaceVerified = false;
    faceVerificationError = null;
  }
  
  void setFaceVerificationError(String error) {
    faceVerificationError = error;
    isFaceVerified = false;
    logOcrResult('FACE_VERIFICATION_ERROR', error);
  }
  
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
    
    // Clear sensitive data
    idFaceImage = null;
    selfieImage = null;
    
    // Dispose OTP controllers and focus nodes
    for (var controller in otpControllers) {
      controller.dispose();
    }
    for (var focusNode in otpFocusNodes) {
      focusNode.dispose();
    }
  }
}
