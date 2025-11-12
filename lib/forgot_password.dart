import 'package:dentpal/signup/signup_flow.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dentpal/core/app_theme/index.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final TextEditingController _inputController = TextEditingController();
  bool _isLoading = false;
  String? _inputError;
  bool _isEmailInput = true; // Track if input is email or phone

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  bool _isValidPhoneNumber(String phone) {
    // Basic check for Philippine phone format (09XXXXXXXXX or +639XXXXXXXXX)
    return RegExp(r'^(09|\+639)\d{9}$').hasMatch(phone);
  }

  // Convert phone to international format if needed
  String _formatPhoneNumber(String phone) {
    if (phone.startsWith('09')) {
      return '+639${phone.substring(2)}';
    }
    return phone;
  }

  Future<void> _submitPasswordReset() async {
    setState(() {
      _inputError = null;
      _isLoading = true;
    });

    final input = _inputController.text.trim();

    if (input.isEmpty) {
      setState(() {
        _inputError = 'Please enter your email or phone number.';
        _isLoading = false;
      });
      return;
    }

    // Determine if input is email or phone number
    _isEmailInput = _isValidEmail(input);
    final bool isPhone = !_isEmailInput && _isValidPhoneNumber(input);

    if (!_isEmailInput && !isPhone) {
      setState(() {
        _inputError = 'Please enter a valid email or phone number.';
        _isLoading = false;
      });
      return;
    }

    try {
      String emailToReset;

      if (_isEmailInput) {
        // If it's an email, use it directly
        emailToReset = input;
      } else {
        // If it's a phone number, look up the associated email in Firestore
        final formattedPhone = _formatPhoneNumber(input);
        emailToReset = await _getEmailFromPhone(formattedPhone);
      }

      // Send password reset email
      await FirebaseAuth.instance.sendPasswordResetEmail(email: emailToReset);

      // Always show success popup to prevent email enumeration
      if (mounted) {
        _showSuccessPopup();
      }
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'invalid-email':
          message = 'Please enter a valid email address.';
          break;
        case 'user-not-found':
          // For security, use a generic message
          message = 'If an account exists, we\'ve sent a password reset link.';
          break;
        case 'too-many-requests':
          message = 'Too many requests. Please try again later.';
          break;
        case 'network-request-failed':
          message = 'Network error. Please check your connection.';
          break;
        default:
          message = 'An error occurred. Please try again.';
      }
      setState(() {
        _inputError = message;
      });
    } catch (e) {
      setState(() {
        _inputError = 'An unexpected error occurred.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Look up email from phone number in Firestore
  Future<String> _getEmailFromPhone(String phoneNumber) async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('User')
          .where('contactNumber', isEqualTo: phoneNumber)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        // Don't reveal if the phone exists or not for security
        throw FirebaseAuthException(code: 'user-not-found');
      }

      final email = querySnapshot.docs.first.data()['email'];
      if (email == null || email.toString().isEmpty) {
        throw Exception('No email associated with this phone number');
      }

      return email.toString();
    } catch (e) {
      if (e is FirebaseAuthException) {
        rethrow;
      }
      throw FirebaseAuthException(code: 'user-not-found');
    }
  }

  void _showSuccessPopup() {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
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
                      color: AppColors.primary.withValues(alpha: .1),
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
                    'Password Reset Link Sent!',
                    style: AppTextStyles.headlineSmall.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Please check your inbox (and spam folder) for a link to reset your password.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.grey600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _showFollowUpPopup();
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
                      child: Text('Got it', style: AppTextStyles.buttonLarge),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.8, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
            ),
            child: child,
          ),
        );
      },
    );
  }

  void _showFollowUpPopup() {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
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
                      color: AppColors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(40),
                    ),
                    child: Icon(
                      Icons.info_outline,
                      size: 40,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "Don't see an email?",
                    style: AppTextStyles.headlineSmall.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "If you don't see an email, either check your spam folder or consider signing up — it only takes a minute.",
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.grey600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 30),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => const SignupFlow(),
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: AppColors.accent),
                            foregroundColor: AppColors.accent,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Sign Up',
                            style: AppTextStyles.buttonLarge,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
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
                            'Back to Login',
                            style: AppTextStyles.buttonLarge,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
              .animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWebView = screenWidth > 900;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: isWebView ? const Color(0xFFF5F5F5) : null,
              gradient: isWebView ? null : AppGradients.teal,
            ),
            height: MediaQuery.of(context).size.height,
          ),
          SafeArea(
            bottom: false,
            child: isWebView
                ? Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: Container()),
                        // Center column with heading outside card
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Heading outside card
                              Text(
                                'Forgot Password?',
                                style: AppTextStyles.headlineLarge.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                "Enter your email or phone number and we'll send a password reset link to your email.",
                                style: AppTextStyles.bodyLarge.copyWith(
                                  color: AppColors.grey600,
                                  height: 1.35,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 32),
                              // Card containing form only
                              Card(
                                elevation: 16,
                                shadowColor: Colors.black.withOpacity(.12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(32),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        AppColors.surface,
                                        AppColors.surface.withOpacity(.96),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 46,
                                    vertical: 38,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        'Email or Phone Number',
                                        style: AppTextStyles.labelLarge
                                            .copyWith(
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.onSurface
                                                  .withOpacity(.85),
                                            ),
                                      ),
                                      const SizedBox(height: 6),
                                      TextField(
                                        controller: _inputController,
                                        keyboardType: TextInputType.text,
                                        style: AppTextStyles.inputText,
                                        decoration: InputDecoration(
                                          hintText:
                                              'Enter email or phone (09XXXXXXXXX)',
                                          hintStyle: AppTextStyles.inputHint,
                                          filled: true,
                                          fillColor: AppColors.surfaceVariant,
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              18,
                                            ),
                                            borderSide: BorderSide.none,
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              18,
                                            ),
                                            borderSide: BorderSide.none,
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              18,
                                            ),
                                            borderSide: const BorderSide(
                                              color: AppColors.primary,
                                              width: 2,
                                            ),
                                          ),
                                          errorBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              18,
                                            ),
                                            borderSide: const BorderSide(
                                              color: AppColors.error,
                                              width: 2,
                                            ),
                                          ),
                                          focusedErrorBorder:
                                              OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(18),
                                                borderSide: const BorderSide(
                                                  color: AppColors.error,
                                                  width: 2,
                                                ),
                                              ),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 20,
                                                vertical: 18,
                                              ),
                                        ),
                                      ),
                                      if (_inputError != null) ...[
                                        const SizedBox(height: 8),
                                        RichText(
                                          text: TextSpan(
                                            style: AppTextStyles.bodySmall
                                                .copyWith(
                                                  color: AppColors.error,
                                                ),
                                            children: [
                                              TextSpan(text: _inputError!),
                                              if (_inputError!.contains(
                                                'No account is linked',
                                              )) ...[
                                                const TextSpan(text: ' '),
                                                WidgetSpan(
                                                  child: GestureDetector(
                                                    onTap: () {
                                                      Navigator.of(
                                                        context,
                                                      ).push(
                                                        MaterialPageRoute(
                                                          builder: (context) =>
                                                              const SignupFlow(),
                                                        ),
                                                      );
                                                    },
                                                    child: Text(
                                                      'Want to sign up instead?',
                                                      style: AppTextStyles
                                                          .bodySmall
                                                          .copyWith(
                                                            color: AppColors
                                                                .accent,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            decoration:
                                                                TextDecoration
                                                                    .underline,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 24),
                                      SizedBox(
                                        height: 54,
                                        child: ElevatedButton(
                                          onPressed: _isLoading
                                              ? null
                                              : _submitPasswordReset,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.primary,
                                            foregroundColor:
                                                AppColors.onPrimary,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                            ),
                                            textStyle: AppTextStyles.buttonLarge
                                                .copyWith(fontSize: 18),
                                            elevation: 4,
                                            shadowColor: AppColors.primary
                                                .withOpacity(.35),
                                          ),
                                          child: _isLoading
                                              ? const SizedBox(
                                                  height: 26,
                                                  width: 26,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2.5,
                                                    valueColor:
                                                        AlwaysStoppedAnimation<
                                                          Color
                                                        >(AppColors.onPrimary),
                                                  ),
                                                )
                                              : const Text('Submit'),
                                        ),
                                      ),
                                      const SizedBox(height: 18),
                                      Center(
                                        child: TextButton(
                                          onPressed: () {
                                            Navigator.of(context).pop();
                                          },
                                          child: RichText(
                                            text: TextSpan(
                                              style: AppTextStyles.bodyMedium
                                                  .copyWith(
                                                    color: AppColors.onSurface
                                                        .withOpacity(.7),
                                                  ),
                                              children: const [
                                                TextSpan(
                                                  text:
                                                      'Remember your password? ',
                                                ),
                                                TextSpan(
                                                  text: 'Back to Login',
                                                  style: TextStyle(
                                                    color: AppColors.accent,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(child: Container()),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      // Top section with logo
                      Expanded(
                        flex: 3,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Forgot Password?',
                              style: AppTextStyles.headlineMedium.copyWith(
                                color: AppColors.surface,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            // Subtitle
                            Text(
                              'Enter your email or phone number and we\'ll send a password reset link to your email.',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.surface.withValues(alpha: 0.9),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),

                      // Bottom section with form
                      Expanded(
                        flex: 5,
                        child: Container(
                          width: double.infinity,
                          decoration: const BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(30),
                              topRight: Radius.circular(30),
                            ),
                          ),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.only(
                              left: 30.0,
                              right: 30.0,
                              top: 30.0,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Email/Phone input field
                                Text(
                                  'Email or Phone Number',
                                  style: AppTextStyles.labelLarge.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                TextField(
                                  controller: _inputController,
                                  keyboardType: TextInputType.text,
                                  style: AppTextStyles.inputText,
                                  decoration: InputDecoration(
                                    hintText:
                                        'Enter email or phone (09XXXXXXXXX)',
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
                                      borderSide: const BorderSide(
                                        color: AppColors.primary,
                                        width: 2,
                                      ),
                                    ),
                                    errorBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                        color: AppColors.error,
                                        width: 2,
                                      ),
                                    ),
                                    focusedErrorBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                        color: AppColors.error,
                                        width: 2,
                                      ),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 16,
                                    ),
                                  ),
                                ),
                                // Input error message
                                if (_inputError != null) ...[
                                  const SizedBox(height: 8),
                                  RichText(
                                    text: TextSpan(
                                      style: AppTextStyles.bodySmall.copyWith(
                                        color: AppColors.error,
                                      ),
                                      children: [
                                        TextSpan(text: _inputError!),
                                        if (_inputError!.contains(
                                          'No account is linked',
                                        )) ...[
                                          const TextSpan(text: ' '),
                                          WidgetSpan(
                                            child: GestureDetector(
                                              onTap: () {
                                                Navigator.of(context).push(
                                                  MaterialPageRoute(
                                                    builder: (context) =>
                                                        const SignupFlow(),
                                                  ),
                                                );
                                              },
                                              child: Text(
                                                'Want to sign up instead?',
                                                style: AppTextStyles.bodySmall
                                                    .copyWith(
                                                      color: AppColors.accent,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      decoration: TextDecoration
                                                          .underline,
                                                    ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 20),

                                // Submit button
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: _isLoading
                                        ? null
                                        : _submitPasswordReset,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: AppColors.onPrimary,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 0,
                                    ),
                                    child: _isLoading
                                        ? SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(
                                              color: AppColors.onPrimary,
                                              strokeWidth: 2.5,
                                            ),
                                          )
                                        : Text(
                                            'Submit',
                                            style: AppTextStyles.buttonLarge,
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 8),

                                // Back to Login link
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
                                          text: "Remember your password? ",
                                          style: AppTextStyles.bodyMedium
                                              .copyWith(
                                                color: AppColors.grey600,
                                              ),
                                        ),
                                        TextSpan(
                                          text: 'Back to Login',
                                          style: AppTextStyles.bodyMedium
                                              .copyWith(
                                                color: AppColors.accent,
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                // Add extra space at the bottom to account for home indicator
                                SizedBox(
                                  height:
                                      MediaQuery.of(context).padding.bottom > 0
                                      ? 40
                                      : 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
