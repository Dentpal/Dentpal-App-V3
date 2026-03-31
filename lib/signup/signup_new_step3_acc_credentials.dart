// ignore_for_file: deprecated_member_use

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'signup_controller.dart';
import 'package:dentpal/login_page.dart';
import 'package:dentpal/core/app_theme/index.dart';
import 'package:dentpal/utils/app_logger.dart';
import 'package:dentpal/utils/signup_state.dart';

class SignupNewStep3AccCredentials extends StatefulWidget {
  final SignupController controller;
  final VoidCallback onBack;

  const SignupNewStep3AccCredentials({
    super.key,
    required this.controller,
    required this.onBack,
  });

  @override
  State<SignupNewStep3AccCredentials> createState() => _SignupNewStep3AccCredentialsState();
}

class _SignupNewStep3AccCredentialsState extends State<SignupNewStep3AccCredentials> {
  // Quick access to controller
  SignupController get _controller => widget.controller;
  
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  
  // Track if email check is in progress
  bool _isCheckingEmail = false;
  String? _emailError;
  
  // FocusNodes for field traversal
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _confirmPasswordFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.passwordController.addListener(_validatePassword);
    _controller.confirmPasswordController.addListener(() {
      setState(() {});
    });
  }
  
  @override
  void dispose() {
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
    super.dispose();
  }

  void _validatePassword() {
    _controller.validatePassword();
    setState(() {});
  }
  
  // Comprehensive list of valid TLDs
  static const List<String> _validTlds = [
    // Generic Top-Level Domains (gTLDs)
    'com', 'net', 'org', 'edu', 'gov', 'mil', 'int', 'info', 'biz', 'name',
    'pro', 'aero', 'coop', 'museum', 'mobi', 'tel', 'asia', 'cat', 'jobs',
    'travel', 'xxx', 'post',
    
    // Country-Code Top-Level Domains (ccTLDs) - Major ones
    'us', 'uk', 'ca', 'au', 'de', 'fr', 'jp', 'cn', 'in', 'br', 'ru', 'it',
    'es', 'nl', 'se', 'no', 'dk', 'fi', 'be', 'ch', 'at', 'pl', 'cz', 'gr',
    'pt', 'hu', 'ro', 'bg', 'hr', 'sk', 'si', 'ee', 'lv', 'lt', 'ie', 'nz',
    'sg', 'my', 'th', 'vn', 'ph', 'id', 'kr', 'tw', 'hk', 'mx', 'ar', 'cl',
    'co', 'pe', 've', 'za', 'ng', 'ke', 'eg', 'ma', 'ae', 'sa', 'il', 'tr',
    
    // Sponsored / Specialized Domains
    'ac', 'sch', 'health', 'pharmacy', 'med', 'legal', 'law', 'bank', 
    'insurance', 'cpa', 'attorney', 'dentist', 'doctor', 'vet',
    
    // New Generic TLDs (modern extensions)
    'app', 'dev', 'web', 'site', 'blog', 'shop', 'store', 'online', 'tech',
    'digital', 'email', 'cloud', 'io', 'ai', 'ml', 'data', 'software', 'systems',
    'solutions', 'services', 'consulting', 'agency', 'studio', 'design', 'media',
    'photography', 'video', 'music', 'art', 'gallery', 'fashion', 'style',
    'beauty', 'fitness', 'health', 'care', 'clinic', 'hospital', 'dental',
    'medical', 'pharmacy', 'doctor', 'surgery', 'nutrition', 'wellness',
    'finance', 'money', 'cash', 'credit', 'loan', 'banking', 'insurance',
    'investment', 'trading', 'forex', 'crypto', 'bitcoin', 'property', 'estate',
    'realestate', 'house', 'homes', 'rent', 'lease', 'hotel', 'restaurant',
    'cafe', 'bar', 'pizza', 'food', 'cooking', 'recipes', 'kitchen', 'catering',
    'delivery', 'express', 'logistics', 'transport', 'taxi', 'auto', 'car',
    'bike', 'motorcycles', 'parts', 'repair', 'tools', 'equipment', 'supplies',
    'energy', 'solar', 'green', 'eco', 'earth', 'world', 'global', 'international',
    'today', 'news', 'press', 'report', 'tv', 'radio', 'live', 'events',
    'tickets', 'show', 'theater', 'movie', 'film', 'game', 'games', 'casino',
    'poker', 'bet', 'sport', 'sports', 'football', 'soccer', 'golf', 'tennis',
    'education', 'training', 'courses', 'school', 'university', 'college',
    'academy', 'institute', 'learning', 'study', 'guide', 'tips', 'how',
    'business', 'company', 'enterprise', 'ventures', 'capital', 'holdings',
    'management', 'marketing', 'sales', 'support', 'help', 'contact', 'community',
    'social', 'network', 'group', 'club', 'team', 'family', 'life', 'love',
    'wedding', 'baby', 'kids', 'toys', 'pet', 'dog', 'cat', 'church',
    'faith', 'bible', 'zone', 'space', 'land', 'city', 'town', 'place', 'directory',
    'page', 'works', 'center', 'plus', 'xyz', 'one', 'top', 'best',
    'cool', 'fun', 'lol', 'wtf', 'ninja', 'guru', 'expert', 'rocks', 'link',
    'click', 'download', 'now', 'new', 'free', 'cheap', 'sale', 'deals',
    'wiki', 'reviews', 'rating', 'vote', 'host', 'domains', 'website', 'hosting',
  ];
  
  // Validate email format with comprehensive TLD checking
  bool _isValidEmailFormat(String email) {
    // Basic format check
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    
    if (!emailRegex.hasMatch(email)) {
      return false;
    }
    
    // Extract and validate TLD
    final parts = email.toLowerCase().split('@');
    if (parts.length != 2) return false;
    
    final domainParts = parts[1].split('.');
    if (domainParts.length < 2) return false;
    
    // Get the TLD (last part of domain)
    final tld = domainParts.last;
    
    // Check if TLD is in the valid list
    return _validTlds.contains(tld);
  }
  
  // Check if email already exists in UserLookup collection
  Future<bool> _checkEmailExists(String email) async {
    if (email.isEmpty || !_isValidEmailFormat(email)) {
      return false;
    }
    
    try {
      // Query UserLookup collection for existing email
      final querySnapshot = await FirebaseFirestore.instance
          .collection('UserLookup')
          .where('email', isEqualTo: email.trim().toLowerCase())
          .limit(1)
          .get();
      
      return querySnapshot.docs.isNotEmpty;
    } catch (e) {
      // If there's an error checking, return false to allow user to proceed
      // The error will be caught during actual registration
      return false;
    }
  }

  Widget _buildPasswordRequirement(String text, bool met) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle : Icons.radio_button_unchecked,
            color: met ? AppColors.success : AppColors.grey400,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodySmall.copyWith(
                color: met ? AppColors.success : AppColors.grey600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      child: Form(
        key: _controller.formKeyStep2,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(
            left: 30.0,
            right: 30.0,
            top: 30.0
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Email field
              Text(
                'Email Address',
                style: AppTextStyles.labelLarge.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              TextFormField(
                controller: _controller.emailController,
                focusNode: _emailFocus,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) {
                  FocusScope.of(context).requestFocus(_passwordFocus);
                },
                onChanged: (value) {
                  // Clear error when user types
                  setState(() {
                    _emailError = null;
                  });
                },
                style: AppTextStyles.inputText,
                decoration: InputDecoration(
                  hintText: 'Enter your email address',
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
                    return 'Please enter your email address';
                  }
                  if (!_isValidEmailFormat(value.trim())) {
                    return 'Please enter a valid email address';
                  }
                  // Show cached error if email already exists
                  if (_emailError != null) {
                    return _emailError;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              
              // Password field
              Text(
                'Password',
                style: AppTextStyles.labelLarge.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              TextFormField(
                controller: _controller.passwordController,
                focusNode: _passwordFocus,
                obscureText: !_isPasswordVisible,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) {
                  FocusScope.of(context).requestFocus(_confirmPasswordFocus);
                },
                style: AppTextStyles.inputText,
                decoration: InputDecoration(
                  hintText: 'Create a strong password',
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
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                      color: AppColors.grey400,
                    ),
                    onPressed: () {
                      setState(() {
                        _isPasswordVisible = !_isPasswordVisible;
                      });
                    },
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a password';
                  }
                  if (!_controller.hasUppercase || !_controller.hasLowercase || !_controller.hasNumber || 
                      !_controller.hasSpecialCharacter || !_controller.hasMinLength) {
                    return 'Password does not meet requirements';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              
              // Confirm Password field
              Text(
                'Confirm Password',
                style: AppTextStyles.labelLarge.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              TextFormField(
                controller: _controller.confirmPasswordController,
                focusNode: _confirmPasswordFocus,
                obscureText: !_isConfirmPasswordVisible,
                textInputAction: TextInputAction.done,
                style: AppTextStyles.inputText,
                decoration: InputDecoration(
                  hintText: 'Re-enter your password',
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
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isConfirmPasswordVisible ? Icons.visibility : Icons.visibility_off,
                      color: AppColors.grey400,
                    ),
                    onPressed: () {
                      setState(() {
                        _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
                      });
                    },
                  ),
                ),
                validator: (value) {
                  if (value != _controller.passwordController.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              
              // Password requirements section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.grey50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.grey200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Password Requirements:',
                      style: AppTextStyles.labelMedium.copyWith(
                        fontWeight: FontWeight.w500,
                        color: AppColors.grey700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildPasswordRequirement('At least 8 characters', _controller.hasMinLength),
                    _buildPasswordRequirement('At least 1 uppercase letter', _controller.hasUppercase),
                    _buildPasswordRequirement('At least 1 lowercase letter', _controller.hasLowercase),
                    _buildPasswordRequirement('At least 1 number', _controller.hasNumber),
                    _buildPasswordRequirement('At least 1 special character', _controller.hasSpecialCharacter),
                    _buildPasswordRequirement(
                      'Passwords must match',
                      _controller.passwordController.text.isNotEmpty &&
                      _controller.confirmPasswordController.text.isNotEmpty &&
                      _controller.passwordController.text.trim() == _controller.confirmPasswordController.text.trim()
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              
              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isCheckingEmail ? null : widget.onBack,
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
                      onPressed: _isCheckingEmail ? null : _processSubmission,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: _isCheckingEmail
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(AppColors.onPrimary),
                              ),
                            )
                          : Text(
                              'Complete Signup',
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
        ),
      ),
    );
  }

  // Process form submission
  Future<void> _processSubmission() async {
    AppLogger.d('_processSubmission called');
    
    // First validate the form
    if (!(_controller.formKeyStep2.currentState?.validate() ?? false)) {
      return;
    }
    
    // Check if email exists
    setState(() {
      _isCheckingEmail = true;
      _emailError = null;
    });
    
    final emailExists = await _checkEmailExists(_controller.email);
    
    setState(() {
      _isCheckingEmail = false;
    });
    
    if (emailExists) {
      setState(() {
        _emailError = 'This email address is already registered';
      });
      _controller.formKeyStep2.currentState?.validate();
      return;
    }
    
    // Create account directly without phone and face verification
    _showLoadingOverlay(context, 'Completing registration...');
    
    try {
      // Create with email/password
      AppLogger.d('Creating email/password account');
      final UserCredential userCredential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _controller.email,
        password: _controller.password,
      );
      final User? user = userCredential.user;
      
      if (user == null) {
        throw Exception('User creation failed');
      }
      
      // Send email verification
      await user.sendEmailVerification();
      AppLogger.d('Email verification sent');
      
      // Save user data
      await _saveUserDataToFirestore(user);
      
      // Sign out
      await FirebaseAuth.instance.signOut();
      AppLogger.d('Signed out after registration');
      
      // Remove loading overlay
      if (mounted) {
        Navigator.of(context).pop();
      }
      
      // Navigate to login
      if (mounted) {
        SignupState.isInSignupFlow = false;
        AppLogger.d('Registration complete, cleared isInSignupFlow flag');
        
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginPage()),
          (route) => false,
        );
        
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
            errorMessage = 'The verification code was invalid. Please verify your phone again.';
            break;
          case 'invalid-verification-id':
            errorMessage = 'Verification session expired. Please verify your phone again.';
            break;
          default:
            errorMessage = e.message ?? 'Authentication failed.';
        }
      }
      
      // Show error dialog
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Registration Failed'),
            content: Text(errorMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  // Upload profile image
  Future<String?> _uploadProfileImage(String uid, Uint8List imageBytes) async {
    try {
      AppLogger.d('Uploading profile image to UserImages/$uid/displayimage.jpg');
      
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('UserImages')
          .child(uid)
          .child('displayimage.jpg');
      
      final uploadTask = await storageRef.putData(
        imageBytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      
      final downloadURL = await uploadTask.ref.getDownloadURL();
      AppLogger.d('Profile image uploaded successfully: $downloadURL');
      
      return downloadURL;
    } catch (e) {
      AppLogger.d('Error uploading profile image: $e');
      return null;
    }
  }

  // Save user data to Firestore
  Future<void> _saveUserDataToFirestore(User user) async {
    try {
      final String? registrationNo = _controller.idNumberController.text.trim().isNotEmpty 
          ? _controller.idNumberController.text.trim() 
          : _controller.idNumber;
      
      String? photoURL;
      if (_controller.selfieImage != null) {
        photoURL = await _uploadProfileImage(user.uid, _controller.selfieImage!);
      }
      
      await user.updateDisplayName('${_controller.firstName} ${_controller.lastName}');
      if (photoURL != null) {
        await user.updatePhotoURL(photoURL);
        AppLogger.d('Firebase Auth profile updated with photoURL');
      }
      
      await FirebaseFirestore.instance.collection('User').doc(user.uid).set({
        'displayName': '${_controller.firstName} ${_controller.lastName}',
        'photoURL': photoURL,
        'fullName': '${_controller.firstName} ${_controller.lastName}',
        'firstName': _controller.firstName,
        'middleName': '',
        'lastName': _controller.lastName,
        'contactNumber': _controller.formattedPhoneNumber,
        'email': _controller.email,
        'gender': _controller.gender,
        'birthdate': _controller.birthdate != null ? Timestamp.fromDate(_controller.birthdate!) : null,
        'location': _controller.location,
        'RegistrationNo': registrationNo,
        'specialty': _controller.selectedSpecialties,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'role': 'buyer',
      });
      
      await FirebaseFirestore.instance.collection('UserLookup').doc(user.uid).set({
        'contactNumber': _controller.formattedPhoneNumber,
        'email': _controller.email,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      AppLogger.d('User and UserLookup documents created successfully');
    } catch (e) {
      AppLogger.d('Error saving user data: $e');
      rethrow;
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
}
