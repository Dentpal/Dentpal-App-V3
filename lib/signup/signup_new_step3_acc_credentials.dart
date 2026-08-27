// ignore_for_file: deprecated_member_use

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'signup_controller.dart';
import 'package:dentpal/core/app_theme/ink_palette.dart';
import 'package:dentpal/core/widgets/auth_chrome.dart';
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

  InkPalette get _ink => InkPalette.of(context);

  bool get _passwordsMatch =>
      _controller.passwordController.text.isNotEmpty &&
      _controller.confirmPasswordController.text.isNotEmpty &&
      _controller.passwordController.text.trim() ==
          _controller.confirmPasswordController.text.trim();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Form(
        key: _controller.formKeyStep2,
        child: ListView(
          padding: AuthMetrics.bodyPadding,
          children: [
            AuthBanner(
              icon: Icons.mark_email_read_outlined,
              tone: _ink.emerald,
              message:
                  'We will send a confirmation link to this address. Your '
                  'account opens once you follow it.',
            ),

            const SizedBox(height: 22),
            const AuthSectionLabel('Sign-in email'),
            const SizedBox(height: 10),
            AuthTextField(
              controller: _controller.emailController,
              focusNode: _emailFocus,
              label: 'Email address',
              hint: 'you@clinic.com',
              prefixIcon: Icons.alternate_email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              enabled: !_isCheckingEmail,
              autofillHints: const [AutofillHints.newUsername],
              onFieldSubmitted: (_) =>
                  FocusScope.of(context).requestFocus(_passwordFocus),
              onChanged: (value) {
                // Clear error when user types
                setState(() {
                  _emailError = null;
                });
              },
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

            const SizedBox(height: 24),
            const AuthSectionLabel('Password'),
            const SizedBox(height: 10),
            AuthTextField(
              controller: _controller.passwordController,
              focusNode: _passwordFocus,
              label: 'Password',
              prefixIcon: Icons.lock_outline,
              obscureText: !_isPasswordVisible,
              textInputAction: TextInputAction.next,
              enabled: !_isCheckingEmail,
              autofillHints: const [AutofillHints.newPassword],
              onFieldSubmitted: (_) =>
                  FocusScope.of(context).requestFocus(_confirmPasswordFocus),
              suffixIcon: AuthPasswordToggle(
                visible: _isPasswordVisible,
                onToggle: () =>
                    setState(() => _isPasswordVisible = !_isPasswordVisible),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a password';
                }
                if (!_controller.hasUppercase ||
                    !_controller.hasLowercase ||
                    !_controller.hasNumber ||
                    !_controller.hasSpecialCharacter ||
                    !_controller.hasMinLength) {
                  return 'Password does not meet the requirements below';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            AuthTextField(
              controller: _controller.confirmPasswordController,
              focusNode: _confirmPasswordFocus,
              label: 'Confirm password',
              prefixIcon: Icons.lock_outline,
              obscureText: !_isConfirmPasswordVisible,
              textInputAction: TextInputAction.done,
              enabled: !_isCheckingEmail,
              autofillHints: const [AutofillHints.newPassword],
              suffixIcon: AuthPasswordToggle(
                visible: _isConfirmPasswordVisible,
                onToggle: () => setState(
                  () => _isConfirmPasswordVisible = !_isConfirmPasswordVisible,
                ),
              ),
              validator: (value) => value != _controller.passwordController.text
                  ? 'Passwords do not match'
                  : null,
            ),

            const SizedBox(height: 16),
            AuthChecklistCard(
              title: 'Requirements',
              rows: [
                AuthCheckRow(
                  label: 'At least 8 characters',
                  met: _controller.hasMinLength,
                ),
                AuthCheckRow(
                  label: 'An uppercase letter',
                  met: _controller.hasUppercase,
                ),
                AuthCheckRow(
                  label: 'A lowercase letter',
                  met: _controller.hasLowercase,
                ),
                AuthCheckRow(label: 'A number', met: _controller.hasNumber),
                AuthCheckRow(
                  label: 'A special character',
                  met: _controller.hasSpecialCharacter,
                ),
                AuthCheckRow(label: 'Both entries match', met: _passwordsMatch),
              ],
            ),

            const SizedBox(height: 28),
            AuthPrimaryButton(
              label: 'Create account',
              busy: _isCheckingEmail,
              onPressed: _processSubmission,
            ),
            const SizedBox(height: 6),
            Center(
              child: AuthQuietButton(
                label: 'Back',
                onPressed: _isCheckingEmail ? null : widget.onBack,
              ),
            ),

            SizedBox(
              height: MediaQuery.of(context).padding.bottom > 0 ? 24 : 8,
            ),
          ],
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

    if (!mounted) return;

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
    showAuthLoadingOverlay(context, 'Completing registration…');
    
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
        
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/login', (route) => false);
        
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
        showAuthDialog<void>(
          context: context,
          icon: Icons.error_outline,
          tone: _ink.danger,
          title: 'Registration failed',
          message: errorMessage,
          barrierDismissible: true,
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
      
      // A licence that was typed in has not been checked against anything, so
      // the record says so rather than looking identical to a scanned one. Staff
      // filter on `idVerification.status` to find the ones needing a look.
      final idVerification = {
        'method': _controller.idEnteredManually ? 'manual' : 'scan',
        'status': _controller.idEnteredManually ? 'pending_review' : 'verified',
        'registrationNo': registrationNo,
        'recordedAt': FieldValue.serverTimestamp(),
      };

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
        'idVerification': idVerification,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'role': 'buyer',
      });
      
      await FirebaseFirestore.instance.collection('UserLookup').doc(user.uid).set({
        'contactNumber': _controller.formattedPhoneNumber,
        'email': _controller.email,
        'RegistrationNo': registrationNo, // PRC Registration Number for duplicate check
        'idVerificationStatus': idVerification['status'],
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
    showAuthDialog<void>(
      context: context,
      icon: Icons.mark_email_read_outlined,
      tone: _ink.emerald,
      title: 'Check your inbox',
      message:
          'We have sent a confirmation link to ${_controller.email}. Follow it, '
          'then sign in.',
    );
  }
}
