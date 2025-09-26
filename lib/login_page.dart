import 'package:dentpal/signup/signup_flow.dart';
import 'package:dentpal/forgot_password.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dentpal/home_page.dart';
import 'package:dentpal/core/app_theme/index.dart';
import 'package:dentpal/utils/credential_manager.dart';
import 'dart:ui' as ui;

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _rememberMe = false;
  String? _errorMessage;
  String? _emailError;
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCredentials() async {
    final credentials = await CredentialManager.loadCredentials();
    final savedEmail = credentials['email'];
    final savedPassword = credentials['password'];
    
    if (savedEmail != null && savedPassword != null) {
      setState(() {
        _emailController.text = savedEmail;
        _passwordController.text = savedPassword;
        _rememberMe = true;
      });
    }
  }

  Future<void> _saveCredentials() async {
    if (_rememberMe) {
      // Save credentials when remember me is checked
      await CredentialManager.saveCredentials(_emailController.text.trim(), _passwordController.text);
    } else {
      // Clear saved credentials when remember me is unchecked
      await CredentialManager.clearCredentials();
    }
  }

  Future<void> _login() async {
    setState(() {
      _emailError = null;
      _passwordError = null;
      _errorMessage = null;
    });

    await _saveCredentials();

    final emailOrPhone = _emailController.text.trim();
    final password = _passwordController.text;
    bool hasError = false;
    if (emailOrPhone.isEmpty) {
      setState(() {
        _emailError = 'Please enter your email address or phone number.';
      });
      hasError = true;
    }
    if (password.isEmpty) {
      setState(() {
        _passwordError = 'Please enter your password.';
      });
      hasError = true;
    }
    if (hasError) return;

    setState(() {
      _isLoading = true;
    });
    try {
      // Determine if input is email or phone number
      final bool isEmail = emailOrPhone.contains('@');

      // Determine login type and authenticate
      UserCredential userCredential;

      if (isEmail) {
        // Login with email directly
        userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: emailOrPhone,
          password: password,
        );
      } else {
        // Format Philippine phone number (09XXXXXXXXX to +639XXXXXXXXX)
        String formattedPhone = emailOrPhone;

        // Check if phone number starts with '09' (Philippine format)
        if (formattedPhone.startsWith('09') && formattedPhone.length == 11) {
          // Convert 09XXXXXXXXX to +639XXXXXXXXX
          formattedPhone = '+63${formattedPhone.substring(1)}';
        }
        // If it doesn't start with + already, add it (for other formats)
        else if (!formattedPhone.startsWith('+')) {
          formattedPhone = '+$formattedPhone';
        }

        // Show specific loading state for phone lookup
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Verifying phone number...'),
              duration: Duration(seconds: 1),
            ),
          );
        }

        // Query UserLookup to find the user with this phone number
        final QuerySnapshot userLookupQuery = await FirebaseFirestore.instance
            .collection('UserLookup')
            .where('contactNumber', isEqualTo: formattedPhone)
            .limit(1)
            .get();

        // Check if we found a user with this phone number
        if (userLookupQuery.docs.isEmpty) {
          setState(() {
            _isLoading = false;
            _errorMessage =
                "Account not found. Try logging in with your email.";
          });
          return;
        }

        // Try to extract the email from the found UserLookup document
        String? userEmail;
        try {
          final userLookupData = userLookupQuery.docs.first.data() as Map<String, dynamic>;
          userEmail = userLookupData['email'] as String?;
        } catch (e) {
          // Handle case where email field doesn't exist or isn't a string
        }

        // Check if we successfully retrieved an email
        if (userEmail == null || userEmail.isEmpty) {
          setState(() {
            _isLoading = false;
            _errorMessage =
                "Error accessing account details. Please contact support.";
          });
          return;
        }

        // Login with the associated email
        userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: userEmail,
          password: password,
        );
      }

      // Check if email is verified
      if (userCredential.user != null && !userCredential.user!.emailVerified) {
        // Sign out the user if email is not verified
        await FirebaseAuth.instance.signOut();

        if (mounted) {
          setState(() {
            _errorMessage =
                'Please verify your email before logging in. Check your inbox for a verification link.';
          });

          // Offer to resend verification email
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Email Not Verified'),
              content: const Text(
                'You need to verify your email address before logging in. Would you like us to resend the verification email?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'CANCEL',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    try {
                      // Sign in temporarily to send verification email
                      final tempCredential = await FirebaseAuth.instance
                          .signInWithEmailAndPassword(
                            email: emailOrPhone,
                            password: password,
                          );
                      await tempCredential.user?.sendEmailVerification();
                      await FirebaseAuth.instance.signOut();

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Verification email has been sent!'),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Failed to send verification email. Please try again.',
                            ),
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('RESEND'),
                ),
              ],
            ),
          );
        }
        return;
      }

      if (mounted) {
        // Check current auth state
        final currentUser = FirebaseAuth.instance.currentUser;

        if (currentUser != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Login successful! User ID: ${currentUser.uid.substring(0, 5)}...',
              ),
              duration: const Duration(seconds: 2),
            ),
          );

          // Navigate to the home page after successful login
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomePage()),
          );
        } else {
          // This shouldn't happen, but adding for debugging
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Authentication successful but user is null! Please try again.',
              ),
              duration: Duration(seconds: 3),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } on FirebaseAuthException catch (e) {
      String message;
      bool isPhoneLogin = !emailOrPhone.contains('@');

      switch (e.code) {
        case 'invalid-email':
          message = 'Invalid email address.';
          break;
        case 'user-not-found':
          message = isPhoneLogin
              ? 'No account found with this phone number. Try using your email instead.'
              : 'Account does not exist.';
          break;
        case 'wrong-password':
          message = 'Wrong password.';
          break;
        case 'invalid-credential':
          message = isPhoneLogin
              ? 'Invalid login details. Please check your phone number and password.'
              : 'Invalid email or password.';
          break;
        case 'user-disabled':
          message = 'This account has been disabled.';
          break;
        case 'too-many-requests':
          message = 'Too many login attempts. Please try again later.';
          break;
        case 'network-request-failed':
          message = 'Network error. Please check your connection.';
          break;
        default:
          message = e.message ?? 'Authentication failed.';
      }
      setState(() {
        _errorMessage = message;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'An unexpected error occurred.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Set background color to match the form's color for a seamless look
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          // Background gradient covering full screen
          Container(
            decoration: const BoxDecoration(gradient: AppGradients.teal),
            height: MediaQuery.of(context).size.height,
          ),
          // Content with SafeArea
          SafeArea(
            // Don't apply bottom padding to allow content to extend fully
            bottom: false,
            child: Column(
              children: [
              // Top section with logo and powered by text
              Expanded(
                flex: 3,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo with shadow
                    Container(
                      width: 220,
                      height: 160,
                      child: Stack(
                        children: [
                          // Shadow
                          ImageFiltered(
                            imageFilter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                            child: ColorFiltered(
                              colorFilter: ColorFilter.mode(
                              Colors.white.withValues(alpha: 0.4),
                                BlendMode.srcATop,
                              ),
                              child: Image.asset(
                                'lib/assets/icons/dentpal_vertical.png',
                                width: 220,
                                height: 160,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          // Actual image on top
                          Image.asset(
                            'lib/assets/icons/dentpal_vertical.png',
                            width: 220,
                            height: 160,
                            fit: BoxFit.cover,
                          ),
                        ],
                      ),
                    ),

                  ],
                ),
              ),
              // Bottom section with login form
              Expanded(
                flex: 7,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(30),
                      topRight: Radius.circular(30),
                      bottomLeft: Radius.zero,
                      bottomRight: Radius.zero,
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(
                      left: 30.0,
                      right: 30.0,
                      top: 30.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 10),
                        // Error message
                        if (_errorMessage != null) ...[
                          Container(
                            padding: context.paddingAll16,
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: .1),
                              borderRadius: context.borderRadius8,
                              border: Border.all(
                                color: AppColors.error.withValues(alpha: .3),
                              ),
                            ),
                            child: Text(
                              _errorMessage!,
                              style: context.textTheme.bodyMedium?.copyWith(
                                color: AppColors.error,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        // Email or Phone Number field
                        Text(
                          'Email or Phone Number',
                          style: context.textTheme.labelLarge?.copyWith(
                            color: AppColors.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: AppTextStyles.inputText,
                          decoration: InputDecoration(
                            hintText: 'example@domain.com',
                            hintStyle: AppTextStyles.inputHint,
                            filled: true,
                            fillColor: AppColors.surfaceVariant,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: const BorderSide(
                                color: AppColors.primary,
                                width: 2,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 18,
                            ),
                          ),
                        ),
                        if (_emailError != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _emailError!,
                            style: context.textTheme.bodySmall?.copyWith(
                              color: AppColors.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        // Password field
                        Text(
                          'Password',
                          style: context.textTheme.labelLarge?.copyWith(
                            color: AppColors.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: AppTextStyles.inputText,
                          decoration: InputDecoration(
                            hintText: '●●●●●●●●',
                            hintStyle: AppTextStyles.inputHint,
                            filled: true,
                            fillColor: AppColors.surfaceVariant,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: const BorderSide(
                                color: AppColors.primary,
                                width: 2,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 18,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: AppColors.grey400,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                        ),
                        if (_passwordError != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _passwordError!,
                            style: context.textTheme.bodySmall?.copyWith(
                              color: AppColors.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        // Remember Me checkbox
                        Row(
                          children: [
                            Checkbox(
                              value: _rememberMe,
                              onChanged: (value) {
                                setState(() {
                                  _rememberMe = value ?? false;
                                });
                              },
                            ),
                            const Text('Remember me?'),
                          ],
                        ),
                        const SizedBox(height: 14),
                        // Log In button
                        ElevatedButton(
                          onPressed: _isLoading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.onPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            elevation: 0,
                          ),
                          child: _isLoading
                              ? SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    color: AppColors.onPrimary,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : Text(
                                  'Log In',
                                  style: AppTextStyles.buttonLarge.copyWith(
                                    color: AppColors.onPrimary,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 8),
                        // Forgot password link
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                PageRouteBuilder(
                                  transitionDuration: const Duration(milliseconds: 500),
                                  pageBuilder: (context, animation, secondaryAnimation) => const ForgotPasswordPage(),
                                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                    final begin = Offset(0.0, 1.0); // Starts from bottom
                                    final end = Offset.zero; // Ends at original position
                                    final curve = Curves.ease;

                                    final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                                    final offsetAnimation = animation.drive(tween);

                                    return SlideTransition(
                                      position: offsetAnimation,
                                      child: child,
                                    );
                                  },
                                ),
                              );
                            },
                            child: Text(
                              'Forgot password?',
                              style: context.textTheme.bodyMedium?.copyWith(
                                color: AppColors.accent,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Sign in with text
                        Center(
                          child: Text(
                            'Sign in with',
                            style: context.textTheme.bodyMedium?.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Social media buttons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Google button
                            GestureDetector(
                              onTap: () {
                                // TODO: Implement Google Sign In
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Google Sign In - Coming Soon!',
                                    ),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  boxShadow: AppShadows.light,
                                ),
                                child: Image.asset(
                                  'lib/assets/icons/google-logo.png',
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            const SizedBox(width: 30),
                            // Facebook button
                            GestureDetector(
                              onTap: () {
                                // TODO: Implement Facebook Sign In
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Facebook Sign In - Coming Soon!',
                                    ),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  boxShadow: AppShadows.light,
                                ),
                                child: Image.asset(
                                  'lib/assets/icons/facebook-logo.png',
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Sign up link
                        Center(
                          child: TextButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const SignupFlow(),
                                ),
                              );
                            },
                            child: RichText(
                              textAlign: TextAlign.center,
                              text: TextSpan(
                                style: context.textTheme.bodyMedium,
                                children: [
                                  TextSpan(
                                    text: "Don't have an account? ",
                                    style: TextStyle(
                                      color: AppColors.onSurfaceVariant,
                                      fontWeight: FontWeight.normal,
                                    ),
                                  ),
                                  TextSpan(
                                    text: 'Sign up',
                                    style: TextStyle(
                                      color: AppColors.accent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Add extra space at the bottom to account for home indicator
                        SizedBox(height: MediaQuery.of(context).padding.bottom > 0 ? 40 : 20),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    )
  );
  }
}
