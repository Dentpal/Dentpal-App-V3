import 'package:dentpal/signup/signup_flow.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final TextEditingController _emailController = TextEditingController();
  bool _isLoading = false;
  String? _emailError;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  Future<void> _submitPasswordReset() async {
    setState(() {
      _emailError = null;
    });

    final email = _emailController.text.trim();

    // Client-side email validation
    if (email.isEmpty) {
      setState(() {
        _emailError = 'Please enter your email address.';
      });
      return;
    }

    if (!_isValidEmail(email)) {
      setState(() {
        _emailError = 'Please enter a valid email address.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // With email enumeration protection, we send the email regardless.
      // Firebase will not indicate if the email exists or not.
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      // Always show success popup to prevent email enumeration.
      if (mounted) {
        _showSuccessPopup();
      }
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'invalid-email':
          message = 'Please enter a valid email address.';
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
        _emailError = message;
      });
    } catch (e) {
      setState(() {
        _emailError = 'An unexpected error occurred.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showSuccessPopup() {
    showGeneralDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      barrierColor: Colors.black54, // Dimmed background
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            backgroundColor: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                // Placeholder icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFF43A047).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.email_outlined,
                    size: 40,
                    color: Color(0xFF43A047),
                  ),
                ),
                const SizedBox(height: 24),
                // Title
                const Text(
                  'Password Reset Link Sent!',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                // Description
                const Text(
                  'Please check your inbox (and spam folder) for a link to reset your password.',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                // Continue button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop(); // Close first popup
                      _showFollowUpPopup(); // Show second popup
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF43A047),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Got it',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ));
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(
              begin: 0.8,
              end: 1.0,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutBack,
            )),
            child: child,
          ),
        );
      },
    );
  }

  void _showFollowUpPopup() {
    showGeneralDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      barrierColor: Colors.black54, // Dimmed background
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            backgroundColor: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                // Info icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(222, 140, 60, 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.info_outline,
                    size: 40,
                    color: Color.fromRGBO(222, 140, 60, 1),
                  ),
                ),
                const SizedBox(height: 24),
                // Title
                const Text(
                  'Don\'t see an email?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                // Description
                const Text(
                  'If you don\'t see an email, either check your spam folder or consider signing up — it only takes a minute.',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).pop(); // Close popup
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const SignupFlow(),
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color.fromRGBO(222, 140, 60, 1)),
                          foregroundColor: const Color.fromRGBO(222, 140, 60, 1),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Sign Up',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop(); // Close popup
                          Navigator.of(context).pop(); // Go back to login
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF43A047),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Back to Login',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        )
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.3),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Logo image
                        Image.asset(
                          'lib/assets/dentpal_vertical.png',
                          width: 180,
                          height: 180,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(height: 48),
                        // Title
                        const Text(
                          'Forgot Password?',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        // Subtitle
                        const Text(
                          'Enter your email address and we\'ll send you a link to reset your password.',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        // Email input
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          cursorColor: Colors.black,
                          decoration: InputDecoration(
                            labelText: 'Email',
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
                        ),
                        // Email error message
                        if (_emailError != null) ...[
                          const SizedBox(height: 6),
                          RichText(
                            text: TextSpan(
                              style: const TextStyle(color: Colors.red, fontSize: 13),
                              children: [
                                TextSpan(text: _emailError!),
                                if (_emailError!.contains('No account is linked')) ...[
                                  const TextSpan(text: ' '),
                                  WidgetSpan(
                                    child: GestureDetector(
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (context) => const SignupFlow(),
                                          ),
                                        );
                                      },
                                      child: const Text(
                                        'Want to sign up instead?',
                                        style: TextStyle(
                                          color: Color.fromRGBO(222, 140, 60, 1),
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          decoration: TextDecoration.underline,
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
                        // Submit button
                        ElevatedButton(
                          onPressed: _isLoading ? null : _submitPasswordReset,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF43A047),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text(
                                  'Submit',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Back to Login link
            Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: RichText(
                  textAlign: TextAlign.center,
                  text: const TextSpan(
                    style: TextStyle(fontSize: 16, color: Colors.black87),
                    children: [
                      TextSpan(
                        text: "Remember your password? ",
                        style: TextStyle(color: Colors.grey),
                      ),
                      TextSpan(
                        text: 'Back to Login',
                        style: TextStyle(
                          color: Color.fromRGBO(222, 140, 60, 1),
                          fontWeight: FontWeight.bold,
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
    );
  }
}
