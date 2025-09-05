
import 'package:dentpal/signup/signup_flow.dart';
import 'package:dentpal/forgot_password.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
  String? _errorMessage;
  String? _emailError;
  String? _passwordError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _emailError = null;
      _passwordError = null;
      _errorMessage = null;
    });

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
            
        // Query Firestore to find the user with this phone number
        final QuerySnapshot userQuery = await FirebaseFirestore.instance
            .collection('Users')
            .where('contactNumber', isEqualTo: formattedPhone)
            .limit(1)
            .get();
            
        // Check if we found a user with this phone number
        if (userQuery.docs.isEmpty) {
          setState(() {
            _isLoading = false;
            _errorMessage = "Account not found. Try logging in with your email.";
          });
          return;
        }
        
        // Try to extract the email from the found user document
        String? userEmail;
        try {
          final userData = userQuery.docs.first.data() as Map<String, dynamic>;
          userEmail = userData['email'] as String?;
        } catch (e) {
          // Handle case where email field doesn't exist or isn't a string
        }
        
        // Check if we successfully retrieved an email
        if (userEmail == null || userEmail.isEmpty) {
          setState(() {
            _isLoading = false;
            _errorMessage = "Error accessing account details. Please contact support.";
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
            _errorMessage = 'Please verify your email before logging in. Check your inbox for a verification link.';
          });
          
          // Offer to resend verification email
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Email Not Verified'),
              content: const Text('You need to verify your email address before logging in. Would you like us to resend the verification email?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('CANCEL'),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    try {
                      // Sign in temporarily to send verification email
                      final tempCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
                        email: emailOrPhone,
                        password: password,
                      );
                      await tempCredential.user?.sendEmailVerification();
                      await FirebaseAuth.instance.signOut();
                      
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Verification email has been sent!')),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Failed to send verification email. Please try again.')),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Login successful!')),
        );
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
                          'lib/assets/icons/dentpal_vertical.png',
                          width: 180,
                          height: 180,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(height: 48),
                        // Error message
                        if (_errorMessage != null) ...[
                          Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.red, fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                        ],
                        // Login form
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          cursorColor: Colors.black,
                          decoration: InputDecoration(
                            labelText: 'Email or Phone Number',
                            hintText: 'example@email.com or +63912456789',
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
                        if (_emailError != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            _emailError!,
                            style: const TextStyle(color: Colors.red, fontSize: 14),
                          ),
                        ],
                        const SizedBox(height: 16),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          cursorColor: Colors.black,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            hintText: '●●●●●●●●',
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
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                color: Colors.grey,
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
                          const SizedBox(height: 6),
                          Text(
                            _passwordError!,
                            style: const TextStyle(color: Colors.red, fontSize: 14),
                          ),
                        ],
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _isLoading ? null : _login,
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
                                  'Login',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                        ),
                        const SizedBox(height: 16),
                        // Forgot password link
                        Align(
                          alignment: Alignment.bottomRight,
                          child: TextButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (context) => const ForgotPasswordPage()),
                              );
                            },
                            child: RichText(
                              text: const TextSpan(
                                style: TextStyle(fontSize: 16, color: Colors.black87),
                                children: [
                                  TextSpan(
                                    text: 'Forgot password?',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontWeight: FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const SignupFlow()),
                  );
                },
                child: RichText(
                  textAlign: TextAlign.center,
                  text: const TextSpan(
                    style: TextStyle(fontSize: 16, color: Colors.black87),
                    children: [
                      TextSpan(
                        text: "Don't have an account? ",
                        style: TextStyle(color: Colors.grey, 
                        fontWeight: FontWeight.normal
                        ),
                      ),
                      TextSpan(
                        text: 'Sign Up',
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
