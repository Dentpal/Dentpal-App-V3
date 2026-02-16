import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'signup_controller.dart';
import 'package:dentpal/core/app_theme/index.dart';

class SignupStep2AccCredentials extends StatefulWidget {
  final SignupController controller;
  final VoidCallback onNext;
  final VoidCallback onBack;

  const SignupStep2AccCredentials({
    super.key,
    required this.controller,
    required this.onNext,
    required this.onBack,
  });

  @override
  State<SignupStep2AccCredentials> createState() => _SignupStep2AccCredentialsState();
}

class _SignupStep2AccCredentialsState extends State<SignupStep2AccCredentials> {
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
    'gov', 'edu', 'mil', 'ac', 'sch', 'org', 'net', 'health', 'pharmacy',
    'med', 'legal', 'law', 'bank', 'insurance', 'cpa', 'attorney', 'dentist',
    'doctor', 'vet',
    
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
    'today', 'news', 'press', 'report', 'media', 'tv', 'radio', 'live', 'events',
    'tickets', 'show', 'theater', 'movie', 'film', 'game', 'games', 'casino',
    'poker', 'bet', 'sport', 'sports', 'football', 'soccer', 'golf', 'tennis',
    'education', 'training', 'courses', 'school', 'university', 'college',
    'academy', 'institute', 'learning', 'study', 'guide', 'tips', 'how',
    'business', 'company', 'enterprise', 'ventures', 'capital', 'holdings',
    'management', 'marketing', 'sales', 'support', 'help', 'contact', 'community',
    'social', 'network', 'group', 'club', 'team', 'family', 'life', 'love',
    'wedding', 'baby', 'kids', 'toys', 'pet', 'dog', 'cat', 'vet', 'church',
    'faith', 'bible', 'zone', 'space', 'land', 'city', 'town', 'place', 'directory',
    'page', 'works', 'center', 'plus', 'pro', 'xyz', 'one', 'top', 'best',
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
          Text(
            text,
            style: AppTextStyles.bodySmall.copyWith(
              color: met ? AppColors.success : AppColors.grey600,
            ),
          ),
        ],
      ),
    );
  }
  
  void _validateAndProceed() async {
    if (_controller.formKeyStep2.currentState!.validate()) {
      // Check if email already exists in UserLookup
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
        // Trigger validation to show the error
        _controller.formKeyStep2.currentState?.validate();
        return;
      }
      
      // All validations passed
      widget.onNext();
    }
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
                      onPressed: _isCheckingEmail ? null : _validateAndProceed,
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
                              'Proceed',
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
      )
    );
  }
}
