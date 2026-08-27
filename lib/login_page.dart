import 'package:dentpal/signup/signup_page_new.dart';
import 'package:dentpal/forgot_password.dart';
import 'package:dentpal/utils/app_logger.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dentpal/core/app_theme/app_text_styles.dart';
import 'package:dentpal/core/app_theme/ink_palette.dart';
import 'package:dentpal/core/app_theme/theme_utils.dart';
import 'package:dentpal/core/widgets/auth_chrome.dart';
import 'package:dentpal/utils/credential_manager.dart';
import 'package:dentpal/product/services/user_service.dart';
import 'package:dentpal/core/services/sub_account_service.dart';
import 'package:url_launcher/url_launcher.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _rememberMe = false;
  String? _errorMessage;

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
      await CredentialManager.saveCredentials(
        _emailController.text.trim(),
        _passwordController.text,
      );
    } else {
      // Clear saved credentials when remember me is unchecked
      await CredentialManager.clearCredentials();
    }
  }

  /// Quick check if a UID belongs to a sub account by checking SubAccountLookup.
  Future<bool> _isSubAccountEmail(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('SubAccountLookup')
          .doc(uid)
          .get();
      return doc.exists;
    } catch (e) {
      return false;
    }
  }

  Future<void> _login() async {
    // The empty-field checks live in the fields' own validators now, so a
    // missing email marks the email box rather than printing a line of red
    // under the whole form.
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _errorMessage = null;
    });

    await _saveCredentials();

    final emailOrPhone = _emailController.text.trim();
    final password = _passwordController.text;

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
          showAuthSnack(context, 'Verifying phone number…', _ink.emerald);
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
          final userLookupData =
              userLookupQuery.docs.first.data() as Map<String, dynamic>;
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

      // Check if email is verified (skip for sub accounts — they use password reset flow)
      final isSubAccount = await _isSubAccountEmail(userCredential.user!.uid);
      if (!isSubAccount &&
          userCredential.user != null &&
          !userCredential.user!.emailVerified) {
        // Sign out the user if email is not verified
        await FirebaseAuth.instance.signOut();

        if (mounted) {
          setState(() {
            _errorMessage =
                'Please verify your email before logging in. Check your inbox for a verification link.';
          });

          // Offer to resend verification email
          _showVerificationPrompt(emailOrPhone, password);
        }
        return;
      }

      if (mounted) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          // Clear any cached user role data before navigating
          try {
            UserService.clearCache();
          } catch (e) {
            AppLogger.d('Failed to clear cache: $e');
          }

          // Resolve sub account status before navigating to HomePage.
          try {
            final subAccountResult = await SubAccountService.lookupSubAccount(
              uid,
            );
            if (subAccountResult != null) {
              // This is a sub account - set up the session
              SubAccountSessionManager.setSubAccountSession(
                subAccount: subAccountResult.subAccount,
                parentUserId: subAccountResult.parentUserId,
              );
              AppLogger.d(
                'Logged in as sub account: ${subAccountResult.subAccount.email} '
                '(parent: ${subAccountResult.parentUserId})',
              );
            } else {
              // This is a main account
              SubAccountSessionManager.setMainAccountSession();
              AppLogger.d('Logged in as main account: $uid');
            }
          } catch (e) {
            // Sub account lookup failed — do NOT default to main account
            // (that would silently grant unintended privileges to a sub-account
            // user if lookup fails transiently).  Sign out and surface the error
            // so the user can retry.
            AppLogger.d('Sub account lookup failed during login: $e');
            await FirebaseAuth.instance.signOut();
            if (mounted) {
              showAuthSnack(
                context,
                'Unable to verify your account type. '
                'Please check your connection and try again.',
                _ink.danger,
              );
            }
            return;
          }

          // Navigate to HomePage (LoginPage may be pushed on top of the
          // navigation stack, so we must navigate explicitly).
          if (mounted) {
            Navigator.of(context).pushReplacementNamed('/');
          }
        } else {
          // If uid is null, force sign out and ask user to try again
          await FirebaseAuth.instance.signOut();
          if (mounted) {
            showAuthSnack(
              context,
              'Something went wrong! Please log in again.',
              _ink.amber,
            );
          }
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
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Offers to send the verification email again, for an account that was
  /// created but never confirmed.
  void _showVerificationPrompt(String emailOrPhone, String password) {
    showAuthDialog<void>(
      context: context,
      icon: Icons.mark_email_unread_outlined,
      tone: _ink.amber,
      title: 'Email not verified',
      message:
          'You need to verify your email address before logging in. Would you '
          'like us to send the verification email again?',
      barrierDismissible: true,
      actions: (dialogContext) => [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          style: TextButton.styleFrom(foregroundColor: _ink.muted),
          child: const Text('Not now'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            _resendVerificationEmail(emailOrPhone, password);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: _ink.emerald,
            foregroundColor: _ink.onEmerald,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('Resend'),
        ),
      ],
    );
  }

  Future<void> _resendVerificationEmail(
    String emailOrPhone,
    String password,
  ) async {
    try {
      // Sign in temporarily to send verification email
      final tempCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: emailOrPhone, password: password);
      await tempCredential.user?.sendEmailVerification();
      await FirebaseAuth.instance.signOut();

      if (mounted) {
        showAuthSnack(
          context,
          'Verification email has been sent!',
          _ink.emerald,
        );
      }
    } catch (e) {
      if (mounted) {
        showAuthSnack(
          context,
          'Failed to send verification email. Please try again.',
          _ink.danger,
        );
      }
    }
  }

  // ── Palette ──────────────────────────────────────────────────────────────

  InkPalette get _ink => InkPalette.of(context);

  // ── Layout ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // The brand pane is a browser-window luxury; below it the form takes the
    // whole screen. Same test the buyer shell uses for its side rail, so login
    // and the app behind it change shape at the same width.
    final wide = context.isWideLayout;

    return wide ? _buildWideLayout() : _buildNarrowLayout();
  }

  /// Phone, tablet in portrait, narrow browser window.
  ///
  /// Centred rather than pinned to the top: the form is short enough that a
  /// tall phone screen — or a mobile browser, which is taller still — left a
  /// third of the page as empty ground beneath it.
  Widget _buildNarrowLayout() {
    return AuthScaffold.centered(header: _header(), children: _formChildren());
  }

  /// Wide window: the brand holds the left half, the form sits in a card on
  /// the right. The card carries the *same* [AuthHeader] as the narrow layout,
  /// so the title and its margins do not move between the two.
  Widget _buildWideLayout() {
    final ink = _ink;

    return Scaffold(
      backgroundColor: ink.bg,
      body: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Expanded(flex: 6, child: _brandPane()),
            Expanded(
              flex: 5,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 32,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AuthMetrics.columnWidth + 32,
                    ),
                    child: AuthCard(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _header(),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AuthMetrics.gutter,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: _formChildren(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  AuthHeader _header() {
    return AuthHeader(
      title: 'Welcome back',
      subtitle: 'Sign in to your DentPal account.',
      onBrandTap: _browseAsGuest,
    );
  }

  /// Tapping the logo has always been the way into the marketplace without an
  /// account; keeping it means the guest route survives the redesign.
  void _browseAsGuest() {
    // Named, and clearing the stack: the address bar has to come off '/login'
    // with the page, and pushing the shell *on top* of login would leave two
    // AppShells fighting over the one `AppShell.instance`.
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  /// The emerald half of the wide layout.
  Widget _brandPane() {
    return Container(
      // The hero gradient is dark in both appearances, so white type sits on it
      // either way and this pane does not need to flip.
      decoration: const BoxDecoration(gradient: InkPalette.heroGradient),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(48),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The logo artwork is drawn on white, so it gets a plate of its
                // own rather than a scrubbed-looking square of it on emerald.
                Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _browseAsGuest,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 20,
                      ),
                      child: Image.asset(
                        'lib/assets/icons/dentpal_vertical.png',
                        width: 220,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                Text(
                  'The marketplace built for\nPhilippine dental practices.',
                  style: AppTextStyles.headlineMedium.copyWith(
                    color: Colors.white,
                    fontSize: 30,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Source from verified sellers, track every order in one '
                  'place, and get same-day delivery where it is offered.',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 14.5,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── The form ─────────────────────────────────────────────────────────────

  /// The body of both layouts, so there is exactly one description of the form.
  List<Widget> _formChildren() {
    final ink = _ink;

    return [
      if (_errorMessage != null) ...[
        AuthBanner(
          icon: Icons.error_outline,
          tone: ink.danger,
          message: _errorMessage!,
          onClose: () => setState(() => _errorMessage = null),
        ),
        const SizedBox(height: 20),
      ],

      Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthTextField(
              controller: _emailController,
              label: 'Email or phone number',
              hint: 'you@clinic.com or 09XXXXXXXXX',
              prefixIcon: Icons.person_outline,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              enabled: !_isLoading,
              autofillHints: const [AutofillHints.username],
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Please enter your email address or phone number.'
                  : null,
            ),
            const SizedBox(height: 14),
            AuthTextField(
              controller: _passwordController,
              label: 'Password',
              prefixIcon: Icons.lock_outline,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              enabled: !_isLoading,
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) {
                if (!_isLoading) _login();
              },
              suffixIcon: AuthPasswordToggle(
                visible: !_obscurePassword,
                onToggle: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
              validator: (value) => (value == null || value.isEmpty)
                  ? 'Please enter your password.'
                  : null,
            ),
          ],
        ),
      ),

      const SizedBox(height: 6),
      _rememberRow(),
      const SizedBox(height: 16),

      AuthPrimaryButton(
        label: 'Log in',
        busy: _isLoading,
        onPressed: _login,
      ),

      const SizedBox(height: 24),
      // On the web there is no signup to offer — ID verification needs a phone
      // camera — so the page points at the app stores instead.
      if (kIsWeb) _downloadAppCard() else _createAccountPrompt(),

      SizedBox(height: MediaQuery.of(context).padding.bottom > 0 ? 24 : 8),
    ];
  }

  Widget _rememberRow() {
    final ink = _ink;

    return Row(
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: _rememberMe,
            onChanged: _isLoading
                ? null
                : (value) => setState(() => _rememberMe = value ?? false),
            activeColor: ink.emerald,
            checkColor: ink.onEmerald,
            side: BorderSide(color: ink.border, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: _isLoading
                ? null
                : () => setState(() => _rememberMe = !_rememberMe),
            child: Text(
              'Remember me',
              style: AppTextStyles.bodySmall.copyWith(
                color: ink.muted,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
        ),
        TextButton(
          onPressed: _isLoading
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ForgotPasswordPage()),
                ),
          style: TextButton.styleFrom(
            foregroundColor: ink.emerald,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            'Forgot password?',
            style: AppTextStyles.bodySmall.copyWith(
              color: ink.emerald,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _createAccountPrompt() {
    return AuthFooterPrompt(
      question: "Don't have an account?",
      actionLabel: 'Create one',
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => const SignUpPageNew()),
      ),
    );
  }

  Widget _downloadAppCard() {
    final ink = _ink;

    return AuthCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'New to DentPal?',
            style: AppTextStyles.bodyMedium.copyWith(
              color: ink.text,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Accounts are created in the app — verifying your PRC ID needs '
            'your phone camera.',
            style: AppTextStyles.bodySmall.copyWith(
              color: ink.muted,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _storeButton(
                  label: 'App Store',
                  icon: const Icon(Icons.apple, size: 20),
                  url: 'https://apps.apple.com/app/dentpal/id6758815697',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _storeButton(
                  label: 'Google Play',
                  icon: Image.asset(
                    'lib/assets/icons/google-logo.png',
                    width: 17,
                    height: 17,
                  ),
                  url:
                      'https://play.google.com/store/apps/details?id=com.rrnewtech.dentpal',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _storeButton({
    required String label,
    required Widget icon,
    required String url,
  }) {
    final ink = _ink;

    return SizedBox(
      height: 46,
      child: OutlinedButton.icon(
        onPressed: () async {
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        icon: icon,
        label: Text(
          label,
          style: AppTextStyles.buttonMedium.copyWith(fontSize: 13),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: ink.text,
          side: BorderSide(color: ink.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AuthMetrics.fieldRadius),
          ),
        ),
      ),
    );
  }
}
